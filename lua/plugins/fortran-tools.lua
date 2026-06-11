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
--   • fortls LSP config + buffer-local keymaps
--   • gdb DAP adapter + configurations
--   • <leader>ds — custom executable/workdata picker for launching
--   • K override — DAP eval during session, LSP hover otherwise
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

  local dap   = require('dap')
  local dapui = require('dapui')

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

  -- Buffer-local LSP + K keymaps for Fortran files.
  -- K is overridden to show DAP eval during a session, LSP hover otherwise.
  vim.api.nvim_create_autocmd('LspAttach', {
    pattern  = { '*.f90', '*.f95', '*.f03', '*.f08', '*.for', '*.f' },
    group    = vim.api.nvim_create_augroup('fortran-lsp-attach', { clear = true }),
    callback = function(ev)
      local opts = { buffer = ev.buf }
      vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename,
        vim.tbl_extend('force', opts, { desc = 'LSP: rename symbol' }))
      vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action,
        vim.tbl_extend('force', opts, { desc = 'LSP: code action' }))
      vim.keymap.set('n', '<leader>e',  vim.diagnostic.open_float,
        vim.tbl_extend('force', opts, { desc = 'Diagnostics: show float' }))
      vim.keymap.set('n', '[d', function() vim.diagnostic.jump({ count = -1 }) end,
        vim.tbl_extend('force', opts, { desc = 'Diagnostics: prev' }))
      vim.keymap.set('n', ']d', function() vim.diagnostic.jump({ count =  1 }) end,
        vim.tbl_extend('force', opts, { desc = 'Diagnostics: next' }))

      -- K: DAP eval during session, LSP hover otherwise.
      -- CursorMoved closes the eval float immediately so it never gets stuck.
      vim.keymap.set('n', 'K', function()
        if dap.session() then
          dapui.eval(nil, { enter = false })
          vim.api.nvim_create_autocmd('CursorMoved', {
            once     = true,
            callback = function()
              vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
            end,
          })
        else
          vim.lsp.buf.hover()
        end
      end, vim.tbl_extend('force', opts, { desc = 'K: DAP eval / LSP hover' }))
    end,
  })

  ---------------------------------------------------------------------------
  -- DAP: gdb adapter
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

  local function get_workdirs()
    local dirs = {}
    for _, path in ipairs(vim.fn.globpath(WORK_ROOT, '*', false, true)) do
      if vim.fn.isdirectory(path) == 1 then
        table.insert(dirs, path)
      end
    end
    return dirs
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

  local function pick_cwd_and_launch(program)
    local dirs = get_workdirs()
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
      format_item = function(item) return vim.fn.fnamemodify(item, ':t') end,
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
  -- Shows an executable + workdata picker when no session is active.
  -- Common DAP keymaps (<leader>dq, <leader>dn, etc.) are in dap.lua.
  vim.keymap.set('n', '<leader>ds', function()
    if dap.session() then dap.continue() else pick_and_launch() end
  end, { desc = 'DAP: start / continue' })

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
