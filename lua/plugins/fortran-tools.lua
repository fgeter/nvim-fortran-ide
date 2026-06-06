-- ============================================================
-- plugins/fortran-tools.lua — Fortran LSP + DAP configuration
--
-- Configures:
--   fortls    — Fortran language server (LSP hover, go-to-def, etc.)
--   gdb       — Debug adapter via nvim-dap
--   nvim-dap-ui — Debug UI panels (scopes, breakpoints, watches, REPL)
--
-- LAZY: Yes — everything inside activate() runs only on the first
--       FileType fortran event. This means:
--         • fortls is not started until a Fortran file is opened
--         • dapui.setup() runs exactly once (no race with dap.lua)
--         • require('dap') and require('dapui') are safe because
--           dap.lua (which installs both plugins) loads first
--
-- Project paths (repo_root, src_dir, work_root) are defined once
-- at the top of activate() and referenced throughout.
-- ============================================================

if vim.g.loaded_fortran_tools then return end
vim.g.loaded_fortran_tools = true

-- ── Paths ────────────────────────────────────────────────────
-- Centralised here so they are easy to update if the project moves
local REPO_ROOT = '/home/fgeter/code/swatplus_repos/swatplus_fg_fork'
local SRC_DIR   = REPO_ROOT .. '/src'
local WORK_ROOT = REPO_ROOT .. '/workdata'
local BUILD_ROOT = REPO_ROOT .. '/build'

-- ── activate() ───────────────────────────────────────────────
-- All setup is deferred into this function and run once on
-- FileType fortran. Nothing executes at require() time.
local function activate()
  if vim.g.fortran_tools_active then return end
  vim.g.fortran_tools_active = true

  -- DAP and DAP-UI are installed by plugins/dap.lua which loads
  -- before this file (alphabetical order). Safe to require here.
  local dap   = require('dap')
  local dapui = require('dapui')

  ---------------------------------------------------------------------------
  -- LSP: fortls
  ---------------------------------------------------------------------------
  -- fortls is the Fortran Language Server. It provides:
  --   • Hover documentation (K)
  --   • Go-to-definition (grd via telescope)
  --   • Find references (grr via telescope)
  --   • Symbol rename (grn)
  --   • Diagnostics (syntax errors, undefined variables)
  --
  -- root_markers tells Neovim where the project root is. It walks up
  -- from the current file until it finds one of these files/dirs.
  vim.lsp.config('fortls', {
    cmd          = { 'fortls', '--lowercase_intrinsics' },
    filetypes    = { 'fortran' },
    root_markers = { '.fortls', '.git' },
    settings     = {
      fortran_ls = { lowercase_intrinsics = true },
    },
  })
  vim.lsp.enable('fortls')

  -- Buffer-local LSP keymaps for Fortran files.
  -- NOTE: gd/gr are intentionally omitted — grd/grr from telescope.lua
  --       provide the same functionality with a better picker UI.
  --       K is overridden below in the hover section to support DAP eval.
  vim.api.nvim_create_autocmd('LspAttach', {
    pattern  = { '*.f90', '*.f95', '*.f03', '*.f08', '*.for', '*.f' },
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

      -- K: context-aware hover.
      --   • During a DAP session → show variable value in a float
      --   • Otherwise           → show LSP hover documentation
      -- CursorMoved closes the DAP eval float immediately on move
      -- so it never gets stuck open like a CursorHold-based approach.
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
  -- The gdb DAP adapter launches gdb with the --interpreter=dap flag so
  -- gdb speaks the Debug Adapter Protocol that nvim-dap understands.
  -- set print pretty on makes struct/derived-type output readable.
  dap.adapters.gdb = {
    type    = 'executable',
    command = 'gdb',
    args    = { '--interpreter=dap', '--eval-command', 'set print pretty on' },
  }

  -- Scan build/debug/ for swatplus executables.
  -- Only debug builds are offered — release builds strip debug symbols
  -- so gdb cannot map instructions back to source lines meaningfully.
  local function get_executables()
    local execs      = {}
    local debug_dirs = {}

    for _, subdir in ipairs(vim.fn.glob(BUILD_ROOT .. '/*', false, true)) do
      local dirname = vim.fn.fnamemodify(subdir, ':t'):lower()
      if vim.fn.isdirectory(subdir) == 1 and dirname == 'debug' then
        table.insert(debug_dirs, subdir)
      end
    end

    if #debug_dirs == 0 then
      vim.notify(
        'No debug build directories found under ' .. BUILD_ROOT ..
        '\nRun <leader>cp (select preset) then <leader>cb (build).',
        vim.log.levels.WARN)
      return {}
    end

    for _, dir in ipairs(debug_dirs) do
      for _, path in ipairs(vim.fn.glob(dir .. '/swatplus*', false, true)) do
        if vim.fn.executable(path) == 1 then
          table.insert(execs, path)
        end
      end
    end
    return execs
  end

  -- Collect workdata directories (each is a self-contained model run)
  local function get_workdirs()
    local dirs = {}
    for _, path in ipairs(vim.fn.globpath(WORK_ROOT, '*', false, true)) do
      if vim.fn.isdirectory(path) == 1 then
        table.insert(dirs, path)
      end
    end
    return dirs
  end

  -- Start a DAP session with the chosen executable and working directory.
  -- initCommands tells gdb where to find Fortran source files for
  -- source-level stepping.
  -- stopAtBeginningOfMainSubprogram is intentionally omitted so the
  -- debugger runs straight to the first breakpoint you set.
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

  -- Pick a workdata directory then launch
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

  -- Pick a debug executable, then pick a workdata directory, then launch
  local function pick_and_launch()
    local execs = get_executables()
    if #execs == 0 then return end  -- get_executables already notified
    if #execs == 1 then
      pick_cwd_and_launch(execs[1])
      return
    end
    vim.ui.select(execs, {
      prompt      = 'Select debug executable:',
      format_item = function(item)
        return item:gsub(BUILD_ROOT .. '/', '')  -- show relative path
      end,
    }, function(choice)
      if choice then pick_cwd_and_launch(choice) end
    end)
  end

  ---------------------------------------------------------------------------
  -- DAP-UI layout
  ---------------------------------------------------------------------------
  -- dapui.setup() is called exactly once here (not in dap.lua) so the
  -- layout is deterministic. The old kickstart debug.lua called setup()
  -- with a different icon set, causing a race — that file is replaced
  -- by the minimal plugins/dap.lua which does not call setup().
  dapui.setup {
    controls = {
      element = 'repl',
      enabled = true,
      icons = {
        disconnect = '',
        pause      = '',
        play       = '',
        run_last   = '',
        step_back  = '',
        step_into  = '',
        step_out   = '',
        step_over  = '',
        terminate  = '',
      },
    },
    element_mappings = {},
    expand_lines     = true,
    floating = {
      border   = 'single',
      mappings = { close = { 'q', '<Esc>' } },
    },
    force_buffers = true,
    icons = {
      collapsed     = '',
      current_frame = '',
      expanded      = '',
    },
    layouts = {
      {
        -- Left panel: variable scopes, breakpoints, call stack, watches
        elements = {
          { id = 'scopes',      size = 0.35 },
          { id = 'breakpoints', size = 0.20 },
          { id = 'stacks',      size = 0.25 },
          { id = 'watches',     size = 0.20 },
        },
        size     = 50,
        position = 'left',
      },
      {
        -- Bottom panel: REPL for evaluating expressions + console output
        elements = {
          { id = 'repl',    size = 0.5 },
          { id = 'console', size = 0.5 },
        },
        size     = 12,
        position = 'bottom',
      },
    },
    mappings = {
      edit   = 'e',
      expand = { '<CR>', '<2-LeftMouse>' },
      open   = 'o',
      remove = 'd',
      repl   = 'r',
      toggle = 't',
    },
    render = {
      indent          = 1,
      max_type_length = 50,
      max_value_lines = 200,
    },
  }

  -- Auto open/close the UI panels with the debug session
  dap.listeners.after.event_initialized['dapui_config']  = function() dapui.open()  end
  dap.listeners.before.event_terminated['dapui_config']  = function() dapui.close() end
  dap.listeners.before.event_exited['dapui_config']      = function() dapui.close() end

  ---------------------------------------------------------------------------
  -- DAP keymaps
  ---------------------------------------------------------------------------
  -- All DAP keymaps use the <leader>d prefix so they form a logical group
  -- visible in which-key. F1-F5/F7 aliases are in plugins/dap.lua.

  -- Start/continue: launch picker if no session, continue to next
  -- breakpoint if a session is already running
  vim.keymap.set('n', '<leader>ds', function()
    if dap.session() then dap.continue() else pick_and_launch() end
  end, { desc = 'DAP: start / continue' })

  vim.keymap.set('n', '<leader>dq', function() dap.terminate() end, { desc = 'DAP: terminate' })
  vim.keymap.set('n', '<leader>dr', function() dap.restart()   end, { desc = 'DAP: restart' })

  -- Stepping
  vim.keymap.set('n', '<leader>dn', function() dap.step_over()     end, { desc = 'DAP: step over' })
  vim.keymap.set('n', '<leader>di', function() dap.step_into()     end, { desc = 'DAP: step into' })
  vim.keymap.set('n', '<leader>do', function() dap.step_out()      end, { desc = 'DAP: step out' })
  vim.keymap.set('n', '<leader>dc', function() dap.run_to_cursor() end, { desc = 'DAP: run to cursor' })

  -- Breakpoints
  vim.keymap.set('n', '<leader>db', function() dap.toggle_breakpoint() end,
    { desc = 'DAP: toggle breakpoint' })
  vim.keymap.set('n', '<leader>dB', function()
    dap.set_breakpoint(vim.fn.input('Breakpoint condition: '))
  end, { desc = 'DAP: conditional breakpoint' })
  vim.keymap.set('n', '<leader>dL', function()
    dap.set_breakpoint(nil, nil, vim.fn.input('Log point message: '))
  end, { desc = 'DAP: log point' })
  vim.keymap.set('n', '<leader>dx', function() dap.clear_breakpoints() end,
    { desc = 'DAP: clear all breakpoints' })

  -- Watches: add the word under the cursor to the watches panel
  vim.keymap.set('n', '<leader>dw', function()
    local word = vim.fn.expand('<cword>')
    vim.ui.input({ prompt = 'Add to watches: ', default = word }, function(input)
      if input and input ~= '' then
        require('dapui').elements['watches'].add(input)
        vim.notify('Watching: ' .. input, vim.log.levels.INFO)
      end
    end)
  end, { desc = 'DAP: add to watches' })

  -- UI controls
  vim.keymap.set('n', '<leader>dU', function() dapui.toggle() end, { desc = 'DAP: toggle UI' })
  vim.keymap.set('n', '<leader>de', function() dapui.eval()   end, { desc = 'DAP: eval expression' })
  vim.keymap.set('v', '<leader>de', function() dapui.eval()   end, { desc = 'DAP: eval selection' })
  vim.keymap.set('n', '<leader>dR', function() dap.repl.open() end, { desc = 'DAP: open REPL' })

  vim.notify('✅ Fortran tools loaded (LSP + DAP)', vim.log.levels.INFO)
end

-- ── Trigger ──────────────────────────────────────────────────
-- activate() runs once on the first FileType fortran event.
-- `once = true` removes the autocmd after the first fire so it
-- never runs again even if another Fortran buffer is opened.
vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'fortran',
  once     = true,
  callback = activate,
})
