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

-- Raise zindex of any float that opens asynchronously above the scrollbar.
local function raise_new_floats(before)
  vim.defer_fn(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not vim.tbl_contains(before, win) then
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative ~= '' then
          cfg.zindex = 200
          vim.api.nvim_win_set_config(win, cfg)
        end
      end
    end
  end, 50)
end

-- ── Gutter signs ─────────────────────────────────────────────
vim.fn.sign_define('DapBreakpoint',         { text = '●', texthl = 'DiagnosticError',   linehl = '', numhl = '' })
vim.fn.sign_define('DapBreakpointCondition',{ text = '◆', texthl = 'DiagnosticWarn',    linehl = '', numhl = '' })
vim.fn.sign_define('DapLogPoint',           { text = '◉', texthl = 'DiagnosticInfo',    linehl = '', numhl = '' })
vim.fn.sign_define('DapStopped',            { text = '▶', texthl = 'DiagnosticOk',      linehl = 'CursorLine', numhl = '' })
vim.fn.sign_define('DapBreakpointRejected', { text = '●', texthl = 'DiagnosticHint',    linehl = '', numhl = '' })

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
      size     = 35,
      position = 'left',
    },
    {
      -- Bottom panel: REPL only — console opens on demand via <leader>dC
      elements = {
        { id = 'repl', size = 1.0 },
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
dap.listeners.after.event_initialized['dapui_config']  = function()
  dapui.open()
  vim.cmd('Neotree close')
  vim.notify('DAP session started — <leader>dF for key reference', vim.log.levels.INFO)
end
dap.listeners.before.event_terminated['dapui_config']  = function() dapui.close() end
dap.listeners.before.event_exited['dapui_config']      = function() dapui.close() end

vim.keymap.set('n', '<F1>',  function() dap.step_into()         end, { desc = 'DAP: step into' })
vim.keymap.set('n', '<F2>',  function() dap.step_over()         end, { desc = 'DAP: step over' })
vim.keymap.set('n', '<F3>',  function() dap.step_out()          end, { desc = 'DAP: step out' })
vim.keymap.set('n', '<F4>',  function() dap.toggle_breakpoint() end, { desc = 'DAP: toggle breakpoint' })
-- F5: start if no session, continue if one is active.
-- For Fortran, fortran-tools.lua overrides this with the exe/workdata picker.
-- For Python, dap.continue() already shows the config picker when no session is active.
vim.keymap.set('n', '<F5>',  function() dap.continue()          end, { desc = 'DAP: start / continue' })
vim.keymap.set('n', '<F6>',  function() dap.run_to_cursor()     end, { desc = 'DAP: run to cursor' })
vim.keymap.set('n', '<F7>',  function() dapui.toggle()          end, { desc = 'DAP: toggle UI' })
vim.keymap.set('n', '<F8>',  function() dap.set_breakpoint(vim.fn.input('Breakpoint condition: ')) end,
                                                                  { desc = 'DAP: conditional breakpoint' })
vim.keymap.set('n', '<F10>', function() dap.terminate()         end, { desc = 'DAP: terminate session' })

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
vim.keymap.set('n', '<leader>dC', function()
  local before = vim.api.nvim_list_wins()
  dapui.float_element('console', { enter = true })
  raise_new_floats(before)
end, { desc = 'DAP: open console float' })
vim.keymap.set('n', '<leader>de', function()
  local before = vim.api.nvim_list_wins()
  dapui.eval(nil, { enter = true })
  raise_new_floats(before)
end, { desc = 'DAP: eval expression' })
vim.keymap.set('v', '<leader>de', function()
  local before = vim.api.nvim_list_wins()
  dapui.eval(nil, { enter = true })
  raise_new_floats(before)
end, { desc = 'DAP: eval selection' })
vim.keymap.set('n', '<leader>dR', function() dap.repl.open() end, { desc = 'DAP: open REPL' })

local _hover_view = nil
local _hover_buf  = nil

local function close_hover()
  if _hover_view and _hover_view.win and vim.api.nvim_win_is_valid(_hover_view.win) then
    _hover_view.close()
  end
  _hover_view = nil
  if _hover_buf and vim.api.nvim_buf_is_valid(_hover_buf) then
    pcall(vim.keymap.del, 'n', '<Esc>', { buffer = _hover_buf })
  end
  _hover_buf = nil
end

vim.keymap.set('n', '<leader>dh', function()
  if _hover_view and _hover_view.win and vim.api.nvim_win_is_valid(_hover_view.win) then
    close_hover()
  else
    _hover_view = require('dap.ui.widgets').hover()
    local hcfg = vim.api.nvim_win_get_config(_hover_view.win)
    hcfg.zindex = 200
    vim.api.nvim_win_set_config(_hover_view.win, hcfg)
    _hover_buf  = vim.api.nvim_get_current_buf()
    vim.keymap.set('n', '<Esc>', close_hover, { buffer = _hover_buf, desc = 'DAP: close hover' })
  end
end, { desc = 'DAP: toggle hover' })

vim.keymap.set('n', '<leader>dF', function()
  -- Build popup lines from the actual keymap descriptions so the popup
  -- stays accurate automatically when F-key bindings change.
  local fkeys = {
    { '<F1>',  'F1'  }, { '<F2>',  'F2'  }, { '<F3>',  'F3'  },
    { '<F4>',  'F4'  }, { '<F5>',  'F5'  }, { '<F6>',  'F6'  },
    { '<F7>',  'F7'  }, { '<F8>',  'F8'  }, { '<F10>', 'F10' },
  }
  local rows = {}
  local max_desc = 0
  for _, e in ipairs(fkeys) do
    local info = vim.fn.maparg(e[1], 'n', false, true)
    local desc = (info.desc and info.desc ~= '') and info.desc:gsub('^DAP: ', '') or '—'
    table.insert(rows, { label = e[2], desc = desc })
    if #desc > max_desc then max_desc = #desc end
  end
  local lines = {}
  for _, r in ipairs(rows) do
    table.insert(lines, string.format('  %-3s  %-' .. max_desc .. 's  ', r.label, r.desc))
  end
  table.insert(lines, '')
  local close = '  q / <Esc>  close'
  table.insert(lines, close .. string.rep(' ', math.max(0, #lines[1] - #close)))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width  = #lines[1]
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    row       = math.floor((vim.o.lines   - height) / 2),
    col       = math.floor((vim.o.columns - width)  / 2),
    width     = width,
    height    = height,
    style     = 'minimal',
    border    = 'rounded',
    title     = ' DAP keys ',
    title_pos = 'center',
    zindex    = 200,  -- above scrollbar (zindex 150)
  })
  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
  end
end, { desc = 'DAP: show F-key reference' })
