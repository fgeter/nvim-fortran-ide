-- ============================================================
-- plugins/dap.lua — Debug Adapter Protocol core
--
-- Installs nvim-dap, nvim-dap-ui, and nvim-nio. Owns:
--   • dapui layout (setup called once here, not in language files)
--   • auto open/close listeners (registered once, work for all languages)
--   • all language-agnostic <leader>d* keymaps + F-key aliases
--
-- Language-specific adapters and <leader>ds live in:
--   plugins/fortran-tools.lua — gdb adapter + custom exe/workdata picker
--   plugins/python.lua        — debugpy adapter
--
-- LAZY: No — DAP must be installed before fortran-tools.lua
--       calls require('dap') on first FileType fortran.
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

vim.pack.add {
  gh 'mfussenegger/nvim-dap',
  gh 'rcarriga/nvim-dap-ui',
  gh 'nvim-neotest/nvim-nio',  -- required async library for dap-ui
}

local dap   = require('dap')
local dapui = require('dapui')

-- ── DAP UI layout ────────────────────────────────────────────
-- Called once here so the layout is consistent across all languages
-- and listeners register exactly once, regardless of which language
-- activates first.
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

-- Auto open/close the UI panels with the debug session.
-- Registered once here so they work for all languages without
-- duplication in each language file.
dap.listeners.after.event_initialized['dapui_config']  = function() dapui.open()  end
dap.listeners.before.event_terminated['dapui_config']  = function() dapui.close() end
dap.listeners.before.event_exited['dapui_config']      = function() dapui.close() end

-- ── F-key aliases ────────────────────────────────────────────
vim.keymap.set('n', '<F5>', function() dap.continue()   end, { desc = 'DAP: continue' })
vim.keymap.set('n', '<F1>', function() dap.step_into()  end, { desc = 'DAP: step into' })
vim.keymap.set('n', '<F2>', function() dap.step_over()  end, { desc = 'DAP: step over' })
vim.keymap.set('n', '<F3>', function() dap.step_out()   end, { desc = 'DAP: step out' })
vim.keymap.set('n', '<F7>', function() dapui.toggle()   end, { desc = 'DAP: toggle UI' })

-- ── Language-agnostic DAP keymaps ────────────────────────────
-- <leader>ds (start) is intentionally absent here — the launch logic
-- differs per language (Fortran needs an exe/workdata picker; Python
-- uses dap.continue() which shows the config picker automatically).
-- <leader>ds is defined in fortran-tools.lua and python.lua.

vim.keymap.set('n', '<leader>dq', function() dap.terminate()     end, { desc = 'DAP: terminate' })
vim.keymap.set('n', '<leader>dr', function() dap.restart()       end, { desc = 'DAP: restart' })
vim.keymap.set('n', '<leader>dn', function() dap.step_over()     end, { desc = 'DAP: step over' })
vim.keymap.set('n', '<leader>di', function() dap.step_into()     end, { desc = 'DAP: step into' })
vim.keymap.set('n', '<leader>do', function() dap.step_out()      end, { desc = 'DAP: step out' })
vim.keymap.set('n', '<leader>dc', function() dap.run_to_cursor() end, { desc = 'DAP: run to cursor' })

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

vim.keymap.set('n', '<leader>dw', function()
  local word = vim.fn.expand('<cword>')
  vim.ui.input({ prompt = 'Add to watches: ', default = word }, function(input)
    if input and input ~= '' then
      dapui.elements['watches'].add(input)
      vim.notify('Watching: ' .. input, vim.log.levels.INFO)
    end
  end)
end, { desc = 'DAP: add to watches' })

vim.keymap.set('n', '<leader>dU', function() dapui.toggle()  end, { desc = 'DAP: toggle UI' })
vim.keymap.set('n', '<leader>de', function() dapui.eval()    end, { desc = 'DAP: eval expression' })
vim.keymap.set('v', '<leader>de', function() dapui.eval()    end, { desc = 'DAP: eval selection' })
vim.keymap.set('n', '<leader>dR', function() dap.repl.open() end, { desc = 'DAP: open REPL' })
