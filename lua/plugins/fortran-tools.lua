-- ============================================================
-- plugins/fortran-tools.lua — Fortran LSP + DAP configuration
--
-- Configures:
--   fortls    — Fortran language server (LSP hover, go-to-def, etc.)
--   gdb       — Debug adapter via nvim-dap
--
-- dapui.setup(), auto open/close listeners, and all language-
-- agnostic <leader>d* keymaps live in plugins/dap.lua.
-- This file only adds what is Fortran-specific:
--   • fortls LSP config
--   • <leader>ds — custom executable/workdata picker
--
-- LAZY: Yes — everything inside activate() runs only on the first
--       FileType fortran event.
-- ============================================================

if vim.g.loaded_fortran_tools then return end
vim.g.loaded_fortran_tools = true

local function activate()
  if vim.g.fortran_tools_active then return end
  vim.g.fortran_tools_active = true

  -- Read paths at activation time so :cd before opening a Fortran file
  -- gives the right root. vim.g overrides let a .nvim.lua pin these.
  local REPO_ROOT  = vim.g.project_repo_root  or vim.fn.getcwd()
  local SRC_DIR    = vim.g.project_src_dir    or (REPO_ROOT .. '/src')
  local WORK_ROOT  = vim.g.project_work_root  or (REPO_ROOT .. '/workdata')
  local BUILD_ROOT = vim.g.project_build_root or (REPO_ROOT .. '/build')

  local dap = require('dap')

  ---------------------------------------------------------------------------
  -- LSP: fortls
  ---------------------------------------------------------------------------
  vim.lsp.config('fortls', {
    cmd          = { 'fortls', '--lowercase_intrinsics' },
    filetypes    = { 'fortran' },
    root_markers = { '.fortls', '.git' },
    settings     = {
      fortran_ls = { lowercase_intrinsics = true },
    },
  })
  vim.lsp.enable('fortls')

  ---------------------------------------------------------------------------
  -- DAP: gdb adapter + custom launchers
  ---------------------------------------------------------------------------
  dap.adapters.gdb = {
    type    = 'executable',
    command = 'gdb',
    args    = { '--interpreter=dap', '--eval-command', 'set print pretty on' },
  }

  -- Only debug builds are offered — release builds strip debug symbols
  -- so gdb cannot map instructions back to source lines meaningfully.
  local function get_executables()
    local debug_dir = BUILD_ROOT .. '/debug'

    if vim.fn.isdirectory(debug_dir) == 0 then
      vim.notify(
        'No debug build found — ' .. debug_dir .. ' does not exist.\n' ..
        'Build a debug version first: <leader>cb → select Debug.',
        vim.log.levels.WARN)
      return {}
    end

    local execs = {}
    for _, path in ipairs(vim.fn.glob(debug_dir .. '/swatplus*', false, true)) do
      if vim.fn.executable(path) == 1 then
        table.insert(execs, path)
      end
    end

    if #execs == 0 then
      vim.notify(
        'Debug directory exists but no executable found in ' .. debug_dir .. '.\n' ..
        'Build a debug version first: <leader>cb → select Debug.',
        vim.log.levels.WARN)
    end
    return execs
  end

  local function launch(program, cwd)
    dap.run({
      name         = 'Launch swatplus',
      type         = 'gdb',
      request      = 'launch',
      program      = program,
      cwd          = cwd,
      initCommands = { 'set directories ' .. SRC_DIR },
    })
  end

  local utils = require('core.utils')

  local function pick_cwd_and_launch(program)
    local dirs = utils.get_workdirs(WORK_ROOT)
    if #dirs == 0 then
      vim.notify('No workdata directories found in ' .. WORK_ROOT, vim.log.levels.ERROR)
      return
    end
    if #dirs == 1 then
      launch(program, dirs[1])
      return
    end
    vim.ui.select(dirs, {
      prompt      = 'Select workdata directory:',
      format_item = utils.basename,
    }, function(choice)
      if choice then launch(program, choice) end
    end)
  end

  local function pick_and_launch()
    local execs = get_executables()
    if #execs == 0 then return end
    if #execs == 1 then
      pick_cwd_and_launch(execs[1])
      return
    end
    vim.ui.select(execs, {
      prompt      = 'Select debug executable:',
      format_item = function(item)
        return item:gsub(BUILD_ROOT .. '/', '')
      end,
    }, function(choice)
      if choice then pick_cwd_and_launch(choice) end
    end)
  end

  ---------------------------------------------------------------------------
  -- <leader>ds — Fortran-specific start/continue
  ---------------------------------------------------------------------------
  local _start = function()
    if dap.session() then dap.continue() else pick_and_launch() end
  end
  vim.keymap.set('n', '<leader>ds', _start, { desc = 'DAP: start / continue' })
  vim.keymap.set('n', '<F9>',       _start, { desc = 'DAP: start / continue' })

  vim.notify('✅ Fortran tools loaded (LSP + DAP)', vim.log.levels.INFO)
end

-- ── Trigger ──────────────────────────────────────────────────
vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'fortran',
  once     = true,
  callback = activate,
})

vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'fortran',
  callback = function() vim.opt_local.textwidth = 80 end,
})
