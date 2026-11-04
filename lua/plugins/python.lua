-- ============================================================
-- plugins/python.lua — Python LSP + DAP
--
-- Configures:
--   basedpyright — Python language server (enabled here, not in lsp.lua,
--                  so venv settings exist before the client starts)
--   debugpy      — Python debug adapter for nvim-dap
--
-- Ruff is the Python formatter; it lives in formatting.lua (conform)
-- and is installed by lsp.lua via Mason. It is not started as an LSP.
--
-- dapui.setup(), auto open/close listeners, and all language-
-- agnostic <leader>d* keymaps live in plugins/dap.lua.
-- This file only adds what is Python-specific:
--   • basedpyright LSP config
--   • debugpy DAP adapter + configurations
--   • buffer-local <leader>ds  — dap.continue() (config picker or resume)
--   • <leader>pr  — run current file in bottom terminal (argument picker
--                   first if the script reads command-line arguments)
--   • <leader>pa  — run current file, always via the argument picker
--
-- LAZY: Yes — activates on FileType python only.
--
-- Installation (run once):
--   :MasonInstall basedpyright debugpy ruff
--
-- Python binary resolution order:
--   1. vim.g.project_python_bin (set in .nvim.lua)
--   2. vim.g.project_venv .. '/bin/python'
--   3. $VIRTUAL_ENV/bin/python (active virtualenv)
--   4. .venv/bin/python in project root
--   5. System python3
-- ============================================================

if vim.g.loaded_python_tools then return end
vim.g.loaded_python_tools = true

-- Resolved at call time so vim.g.project_* from a later .nvim.lua wins.
local function get_python_bin()
  if vim.g.project_python_bin then
    return vim.g.project_python_bin
  end
  if vim.g.project_venv then
    local bin = vim.g.project_venv .. '/bin/python'
    if vim.fn.executable(bin) == 1 then return bin end
  end
  local venv = os.getenv('VIRTUAL_ENV')
  if venv then
    local bin = venv .. '/bin/python'
    if vim.fn.executable(bin) == 1 then return bin end
  end
  if vim.g.project_repo_root then
    local bin = vim.g.project_repo_root .. '/.venv/bin/python'
    if vim.fn.executable(bin) == 1 then return bin end
  end
  local py = vim.fn.exepath('python3')
  return py ~= '' and py or 'python3'
end

-- ── Running a script that takes command-line arguments ───────
-- <leader>pr runs the current file directly, unless the file looks like it
-- reads command-line arguments (argparse, sys.argv, click, …), in which case
-- it opens the argument picker first; <leader>pa always opens it. The picker
-- offers: run again with the last arguments, pick a folder, pick a file,
-- type the arguments, or run with none.
--
-- Arguments are raw shell text, appended after the script path. Picked
-- paths are inserted absolute and shell-quoted, because the terminal that
-- runs the script may already be sitting in some other directory.
--
-- The last arguments for each script are kept per absolute script path in
-- stdpath('state')/python_run_args.json, so they survive a restart. When a
-- new folder/file is picked and the old arguments contained the previously
-- picked path, that path is swapped for the new one and the rest (flags
-- like --repo) is kept — switching datasets is one pick and <CR>.

local ARG_PATTERNS = {
  '^%s*import%s+argparse', '^%s*from%s+argparse%s',
  '^%s*import%s+optparse', '^%s*import%s+getopt',
  '^%s*import%s+click',    '^%s*from%s+click%s',
  '^%s*import%s+typer',    '^%s*from%s+typer%s',
  '^%s*import%s+fire',     'docopt',
  'sys%.argv',
}

local function takes_args(buf)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    for _, pat in ipairs(ARG_PATTERNS) do
      if line:find(pat) then return true end
    end
  end
  return false
end

local ARGS_FILE = vim.fn.stdpath('state') .. '/python_run_args.json'

local function load_args()
  local f = io.open(ARGS_FILE, 'r')
  if not f then return {} end
  local ok, data = pcall(vim.json.decode, f:read('*a'))
  f:close()
  return (ok and type(data) == 'table') and data or {}
end

local function save_args(file, rec)
  local all = load_args()
  all[file] = rec
  local f = io.open(ARGS_FILE, 'w')
  if not f then return end
  f:write(vim.json.encode(all))
  f:close()
end

local function run_in_terminal(file, args)
  local cmd = get_python_bin() .. ' ' .. vim.fn.shellescape(file)
  if args and args ~= '' then cmd = cmd .. ' ' .. args end
  local terms = require('toggleterm.terminal')
  local term, is_new = terms.get_or_create_term(1, vim.fn.fnamemodify(file, ':h'), 'horizontal')
  -- Terminal:open() spawns the shell job synchronously (open → spawn →
  -- termopen sets job_id before returning), so send works immediately —
  -- the PTY buffers the input until the shell reads it.
  if is_new or not term:is_open() then term:open(15) end
  term:send(cmd)
end

-- The script's project: the configured repo root when the script lives in
-- it, otherwise the nearest marker above the script, otherwise its folder.
local function project_root(file)
  local repo = vim.g.project_repo_root
  if repo and file:sub(1, #repo + 1) == repo .. '/' then return repo end
  return vim.fs.root(file, { '.git', '.nvim.lua', 'pyproject.toml', 'setup.py' })
      or vim.fn.fnamemodify(file, ':h')
end

-- Prompt for a path with <Tab> completion (snacks.input honours it).
local function browse_path(kind, default, on_path)
  vim.ui.input({
    prompt     = (kind == 'dir' and 'Folder: ' or 'File: '),
    default    = default,
    completion = kind,
  }, function(input)
    if not input or vim.trim(input) == '' then return end
    local path = vim.fn.fnamemodify(vim.fn.expand(vim.trim(input)), ':p'):gsub('/+$', '')
    local ok = kind == 'dir' and vim.fn.isdirectory(path) == 1
                             or  vim.fn.filereadable(path) == 1
    if not ok then
      vim.notify('Not a ' .. (kind == 'dir' and 'folder' or 'file') .. ': ' .. path,
        vim.log.levels.ERROR)
      return
    end
    on_path(path)
  end)
end

local function pick_folder(file, rec, on_path)
  local start = rec.path and vim.fn.fnamemodify(rec.path, ':h') or project_root(file)
  local BROWSE = {}
  local work = vim.g.project_work_root
  local dirs, mtimes = {}, {}
  if work and vim.fn.isdirectory(work) == 1 then
    dirs, mtimes = require('core.utils').get_workdirs(work, 'mtime')
  end
  if #dirs == 0 then return browse_path('dir', start .. '/', on_path) end

  local utils = require('core.utils')
  local width = 0
  for _, d in ipairs(dirs) do width = math.max(width, vim.fn.strdisplaywidth(utils.basename(d))) end
  local items = { BROWSE }
  vim.list_extend(items, dirs)
  vim.ui.select(items, {
    prompt      = 'Folder argument (recent first):',
    format_item = function(item)
      if item == BROWSE then return '󰉋  Browse for another folder…' end
      local name = utils.basename(item)
      return ('%s%s  %s'):format(name, (' '):rep(width - vim.fn.strdisplaywidth(name)),
        utils.relative_time(mtimes[item]))
    end,
  }, function(choice)
    if not choice then return end
    if choice == BROWSE then
      vim.schedule(function() browse_path('dir', start .. '/', on_path) end)
    else
      on_path(choice)
    end
  end)
end

-- Fuzzy-find a file under the project (gitignored files included, since
-- input data usually is), falling back to the path prompt without telescope.
local function pick_file(file, rec, on_path)
  local root = project_root(file)
  local ok, builtin = pcall(require, 'telescope.builtin')
  if not ok then
    local start = rec.path and vim.fn.fnamemodify(rec.path, ':h') or root
    return browse_path('file', start .. '/', on_path)
  end
  local actions = require('telescope.actions')
  local astate  = require('telescope.actions.state')
  builtin.find_files({
    cwd = root, no_ignore = true,
    prompt_title = 'File argument for ' .. vim.fn.fnamemodify(file, ':t'),
    attach_mappings = function(prompt_buf)
      actions.select_default:replace(function()
        local entry = astate.get_selected_entry()
        actions.close(prompt_buf)
        if entry then
          on_path(entry.path or vim.fs.joinpath(root, entry.value or entry[1]))
        end
      end)
      return true
    end,
  })
end

-- Final, editable argument line; <CR> runs and remembers it.
local function edit_and_run(file, default, picked)
  vim.ui.input({
    prompt     = 'Arguments for ' .. vim.fn.fnamemodify(file, ':t') .. ': ',
    default    = default,
    completion = 'file',
  }, function(input)
    if input == nil then return end
    input = vim.trim(input)
    save_args(file, { args = input, path = picked })
    run_in_terminal(file, input)
  end)
end

local function args_picker(file)
  local rec = load_args()[file] or {}
  local function with_path(path)
    local q = vim.fn.shellescape(path)
    local default = q
    if rec.args and rec.path then
      local old = vim.fn.shellescape(rec.path)
      local i = rec.args:find(old, 1, true)
      if i then default = rec.args:sub(1, i - 1) .. q .. rec.args:sub(i + #old) end
    end
    vim.schedule(function() edit_and_run(file, default, path) end)
  end

  local items = {}
  if rec.args and rec.args ~= '' then
    table.insert(items, { id = 'again', label = '  Run again: ' .. rec.args })
  end
  vim.list_extend(items, {
    { id = 'dir',  label = '󰉋  Pick a folder…' },
    { id = 'file', label = '󰈔  Pick a file…' },
    { id = 'type', label = '󰌌  Type arguments…' },
    { id = 'none', label = '   Run with no arguments' },
  })
  vim.ui.select(items, {
    prompt      = 'Run ' .. vim.fn.fnamemodify(file, ':t') .. ' with:',
    format_item = function(item) return item.label end,
  }, function(choice)
    if not choice then return end
    if choice.id == 'again' then
      run_in_terminal(file, rec.args)
    elseif choice.id == 'dir' then
      vim.schedule(function() pick_folder(file, rec, with_path) end)
    elseif choice.id == 'file' then
      vim.schedule(function() pick_file(file, rec, with_path) end)
    elseif choice.id == 'type' then
      vim.schedule(function() edit_and_run(file, rec.args or '', rec.path) end)
    else
      save_args(file, { args = '', path = rec.path })
      run_in_terminal(file, '')
    end
  end)
end

-- The current buffer's file, or nil (with a warning) when it is not a
-- Python file. Both keymaps are reachable from any buffer via the Run menu:
-- never hand a Fortran (or any non-Python) file to the interpreter.
local function current_python_file()
  local file = vim.fn.expand('%:p')
  if file == '' then
    vim.notify('No file in current buffer', vim.log.levels.WARN)
    return nil
  end
  if vim.bo.filetype ~= 'python' then
    vim.notify('Not a Python file: ' .. vim.fn.expand('%:t'), vim.log.levels.WARN)
    return nil
  end
  return file
end

local function activate()
  if vim.g.python_tools_active then return end
  vim.g.python_tools_active = true

  ---------------------------------------------------------------------------
  -- LSP: basedpyright
  ---------------------------------------------------------------------------
  vim.lsp.config('basedpyright', {
    cmd          = { 'basedpyright-langserver', '--stdio' },
    filetypes    = { 'python' },
    root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg',
                     'requirements.txt', '.git' },
    settings     = {
      basedpyright = {
        analysis = {
          typeCheckingMode       = 'standard',
          autoSearchPaths        = true,
          useLibraryCodeForTypes = true,
        },
      },
    },
    -- Client start is after 'exrc'; fill venv/pythonPath from current vim.g.
    before_init = function(_, config)
      local venv = vim.g.project_venv
        or (vim.g.project_repo_root and (vim.g.project_repo_root .. '/.venv'))
        or nil
      config.settings = config.settings or {}
      config.settings.python = { pythonPath = get_python_bin() }
      if venv then
        config.settings.basedpyright = config.settings.basedpyright or {}
        config.settings.basedpyright.analysis =
          config.settings.basedpyright.analysis or {}
        config.settings.basedpyright.analysis.venvPath = venv
      end
    end,
  })
  vim.lsp.enable('basedpyright')

  ---------------------------------------------------------------------------
  -- DAP: debugpy
  ---------------------------------------------------------------------------
  require('plugins.dap').activate()  -- install/configure the DAP stack (lazy since #7)
  local dap = require('dap')

  dap.adapters.python = function(cb)
    cb({
      type    = 'executable',
      command = get_python_bin(),
      args    = { '-m', 'debugpy.adapter' },
    })
  end

  dap.configurations.python = {
    {
      type    = 'python',
      request = 'launch',
      name    = 'Launch current file',
      program = '${file}',
      python  = get_python_bin,
      console = 'integratedTerminal',
    },
    {
      type    = 'python',
      request = 'launch',
      name    = 'Launch module',
      module  = function()
        return vim.fn.input('Module name: ')
      end,
      python  = get_python_bin,
      console = 'integratedTerminal',
    },
    {
      type    = 'python',
      request = 'attach',
      name    = 'Attach to process (localhost:5678)',
      connect = { host = '127.0.0.1', port = 5678 },
    },
  }

  ---------------------------------------------------------------------------
  -- <leader>pr — Run current file in bottom terminal (asks for arguments
  --               first when the script reads any; see args_picker)
  -- <leader>pa — Run current file, always asking for arguments
  ---------------------------------------------------------------------------
  vim.keymap.set('n', '<leader>pr', function()
    local file = current_python_file()
    if not file then return end
    if takes_args(0) then args_picker(file) else run_in_terminal(file, '') end
  end, { desc = 'Python: run current file' })

  vim.keymap.set('n', '<leader>pa', function()
    local file = current_python_file()
    if file then args_picker(file) end
  end, { desc = 'Python: run current file with arguments…' })

  vim.notify('✅ Python tools loaded (LSP + DAP)', vim.log.levels.INFO)
end

-- activate() is idempotent; <leader>ds is buffer-local so a Fortran
-- session cannot leave its picker bound in Python buffers (and vice versa).
vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'python',
  callback = function(ev)
    activate()
    vim.keymap.set('n', '<leader>ds', function()
      require('dap').continue()
    end, { buffer = ev.buf, desc = 'DAP: start / continue - F5' })
  end,
})

return { activate = activate }
