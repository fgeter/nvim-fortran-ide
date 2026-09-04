-- ============================================================
-- plugins/python.lua — Python LSP + DAP + formatting
--
-- Configures:
--   basedpyright — Python language server
--   debugpy      — Python debug adapter for nvim-dap
--   ruff         — Fast Python formatter + linter
--
-- dapui.setup(), auto open/close listeners, and all language-
-- agnostic <leader>d* keymaps live in plugins/dap.lua.
-- This file only adds what is Python-specific:
--   • basedpyright LSP config
--   • debugpy DAP adapter + configurations
--   • buffer-local <leader>ds  — dap.continue() (config picker or resume)
--   • <leader>pr  — run current file in bottom terminal
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
  -- Formatting: ruff via conform.nvim
  ---------------------------------------------------------------------------
  local function register_ruff()
    local ok, conform = pcall(require, 'conform')
    if ok then
      conform.formatters_by_ft = conform.formatters_by_ft or {}
      conform.formatters_by_ft.python = { 'ruff_format', 'ruff_organize_imports' }
    end
  end

  if vim.g.conform_active then
    register_ruff()
  else
    vim.api.nvim_create_autocmd('User', {
      pattern  = 'ConformActivated',
      once     = true,
      callback = register_ruff,
    })
    vim.api.nvim_create_autocmd('BufWritePre', {
      pattern  = '*.py',
      once     = true,
      callback = function()
        vim.schedule(register_ruff)
      end,
    })
  end

  ---------------------------------------------------------------------------
  -- <leader>pr — Run current file in bottom terminal
  ---------------------------------------------------------------------------
  vim.keymap.set('n', '<leader>pr', function()
    local file = vim.fn.expand('%:p')
    if file == '' then
      vim.notify('No file in current buffer', vim.log.levels.WARN)
      return
    end
    local python = get_python_bin()
    local cmd    = python .. ' ' .. vim.fn.shellescape(file)
    local terms  = require('toggleterm.terminal')
    local term, is_new = terms.get_or_create_term(1, vim.fn.expand('%:p:h'), 'horizontal')
    if is_new then
      -- Terminal:open() spawns the shell job synchronously (open → spawn →
      -- termopen sets job_id before returning), so send works immediately —
      -- the PTY buffers the input until the shell reads it.
      term:open(15)
      term:send(cmd)
    else
      if not term:is_open() then term:open(15) end
      term:send(cmd)
    end
  end, { desc = 'Python: run current file' })

  vim.notify('✅ Python tools loaded (LSP + DAP + ruff)', vim.log.levels.INFO)
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
