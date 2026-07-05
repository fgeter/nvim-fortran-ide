-- ============================================================
-- plugins/dap.lua — Debug Adapter Protocol core
--
-- Owns:
--   • dapui layout (setup called once here, not in language files)
--   • auto open/close listeners (registered once, work for all languages)
--   • all language-agnostic <leader>d* keymaps + F-key aliases
--
-- Language-specific adapters and <leader>ds live in:
--   plugins/fortran-tools.lua — gdb adapter + custom exe/workdata picker
--   plugins/python.lua        — debugpy adapter
--
-- LAZY: Yes — nothing is installed or configured until the first
--       <leader>d*/F-key press, or until a language file calls
--       require('plugins.dap').activate() before registering its
--       adapter. The keymaps below are permanent thin closures that
--       run activate() (idempotent, cheap after the first call) and
--       then dispatch, so the very first keypress already works.
-- ============================================================

local utils = require('core.utils')
local gh    = utils.gh

local activated = false

local function activate()
  if activated then return end
  activated = true

  vim.pack.add {
    { src = gh 'mfussenegger/nvim-dap',  version = vim.version.range '*' },
    { src = gh 'rcarriga/nvim-dap-ui',   version = vim.version.range '4.*' },
    { src = gh 'nvim-neotest/nvim-nio',  version = vim.version.range '1.*' },  -- required async library for dap-ui
    gh 'theHamsta/nvim-dap-virtual-text',  -- inline variable values; no tagged releases
  }

  local dap   = require('dap')
  local dapui = require('dapui')

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

  -- Virtual text: show variable values inline next to their declarations while stepping.
  require('nvim-dap-virtual-text').setup {
    commented = true, -- render as a comment so it is visually distinct
  }

  -- Clear any pending follow_current_file debounce. Neo-tree queues follows
  -- with a 100ms debounce (utils.debounce('neo-tree-follow',…) in its
  -- filesystem/init.lua) on focus/buffer events. Around DAP session start
  -- and end we open, close, and refocus windows in quick succession, and a
  -- follow firing against that half-settled state crashes inside nui.tree
  -- ("Invalid 'win'"). Registering a no-op as the last-one-wins function
  -- drops whatever is queued. (A no-op, NOT nil: a nil fn leaves the
  -- debounce's tracked entry behind in a state where the next real call
  -- executes immediately instead of being deferred 100ms — the no-op runs
  -- through the normal path and cleans the entry up.)
  local function cancel_pending_follow()
    utils.try('Neo-tree follow-debounce cancel (its internals may have changed)',
      function()
        local nt_utils = require('neo-tree.utils')
        nt_utils.debounce('neo-tree-follow', function() end, 100,
          nt_utils.debounce_strategy.CALL_LAST_ONLY)
      end)
  end

  -- Follow suspension for the session-end sidebar reopen. `Neotree show`
  -- populates the new window with an ASYNC filesystem scan; until its
  -- first render replaces state.tree, the state still holds the previous
  -- sidebar's tree whose buffer no longer exists — any follow in that gap
  -- (late BufEnter from dap terminal teardown, the second end-listener,
  -- user movement) crashes in nui.tree get_node ("Invalid 'win'").
  -- Cancelling queued follows can't cover follows queued *later in the
  -- gap*, so instead follows are switched off entirely and switched back
  -- on by neo-tree's own AFTER_RENDER event — the moment state.tree is
  -- guaranteed fresh.
  local follow_suspended = false
  utils.try('neo-tree follow suspend hook (fs.follow may have changed)',
    function()
      local fs = require('neo-tree.sources.filesystem')
      local orig_follow = fs.follow
      fs.follow = function(...)
        if follow_suspended then return false end
        return orig_follow(...)
      end
    end)
  local function resume_follow() follow_suspended = false end

  -- Auto open/close the UI panels with the debug session.
  -- Registered once here so they work for all languages without
  -- duplication in each language file.
  dap.listeners.after.event_initialized['dapui_config']  = function()
    dapui.open()
    -- Starting a session focuses the source file, queuing a follow; cancel
    -- it before closing the sidebar so it can't act on the closed window.
    -- Any follow queued *after* the close bails out early in
    -- follow_internal (window no longer exists).
    cancel_pending_follow()
    utils.try('Neo-tree close', 'Neotree close')
    vim.notify('DAP session started — <leader>dF for key reference', vim.log.levels.INFO)
  end

  local function is_neotree_open()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'neo-tree' then
        return true
      end
    end
    return false
  end

  -- Move focus to the first ordinary editor window (utils.find_editor_win
  -- skips neo-tree, terminals, and dap panels), since closing the dapui
  -- layout can otherwise leave focus in whatever window Neovim fell back to.
  local function focus_file_window()
    local win = utils.find_editor_win()
    if win then vim.api.nvim_set_current_win(win) end
  end

  -- dapui.close() closed the neo-tree window at session start (see above),
  -- and never reopened it — leaving the sidebar gone after every debug
  -- session. Reopen it (without stealing focus, matching the convention used
  -- at startup/DirChanged in neo-tree.lua) and land the cursor back on the
  -- file buffer rather than wherever dapui's closing left it.
  local function on_dap_end()
    dapui.close()
    focus_file_window()
    if not is_neotree_open() then
      -- See follow_suspended above: no follow may run between this show
      -- and the fresh tree's first render. Suspend, drop anything already
      -- queued by the refocus, reopen, and let AFTER_RENDER resume.
      follow_suspended = true
      cancel_pending_follow()
      utils.try('neo-tree AFTER_RENDER subscribe', function()
        local nt_events = require('neo-tree.events')
        nt_events.subscribe {
          id      = 'dap-follow-resume',
          event   = nt_events.AFTER_RENDER,
          once    = true,
          handler = resume_follow,
        }
      end)
      utils.try('Neo-tree open', 'Neotree show filesystem left')
      -- Safety net only (not sequencing): if the render never happens
      -- (show failed, empty dir edge case), follows must not stay off
      -- forever. resume_follow is idempotent.
      vim.defer_fn(resume_follow, 3000)
    end
  end
  dap.listeners.before.event_terminated['dapui_config']  = on_dap_end
  dap.listeners.before.event_exited['dapui_config']      = on_dap_end
  -- F10/<leader>dq call dap.terminate(). When the adapter doesn't support
  -- the terminate request (gdb's DAP interpreter, notably), nvim-dap falls
  -- back to a *disconnect* request instead — which fires neither
  -- event_terminated nor event_exited, leaving dapui open and the sidebar
  -- gone. Hook the disconnect request too so every session-ending path
  -- closes the panels, reopens neo-tree, and refocuses the file window.
  -- (If an adapter fires both a terminated event and a disconnect, running
  -- on_dap_end twice is harmless: close is idempotent and the reopen is
  -- guarded by is_neotree_open.)
  dap.listeners.before.disconnect['dapui_config']         = on_dap_end
end

-- Wrap an action so the first keypress activates the DAP stack (install,
-- setup, listeners) and then dispatches. After the first call activate()
-- is a no-op boolean check, so there is no per-press overhead to speak of.
local function with_dap(fn)
  return function()
    activate()
    return fn(require('dap'), require('dapui'))
  end
end

vim.keymap.set('n', '<F1>',  with_dap(function(d) d.step_into() end),         { desc = 'DAP: step into' })
vim.keymap.set('n', '<F2>',  with_dap(function(d) d.step_over() end),         { desc = 'DAP: step over' })
vim.keymap.set('n', '<F3>',  with_dap(function(d) d.step_out() end),          { desc = 'DAP: step out' })
vim.keymap.set('n', '<F4>',  with_dap(function(d) d.toggle_breakpoint() end), { desc = 'DAP: toggle breakpoint' })
-- Kitty (and most terminals) report Shift+F4 as the legacy vt220 keycode
-- F16, not a modified F4 — see doc/native_nvim_keymaps.md for the F13-F24
-- shifted-function-key convention.
vim.keymap.set('n', '<F16>', with_dap(function(d) d.clear_breakpoints() end), { desc = 'DAP: clear all breakpoints' })
-- F5: start if no session, continue if one is active.
-- For Fortran, fortran-tools.lua overrides this with the exe/workdata picker.
-- For Python, dap.continue() already shows the config picker when no session is active.
vim.keymap.set('n', '<F5>',  with_dap(function(d) d.continue() end),          { desc = 'DAP: start / continue' })
vim.keymap.set('n', '<F6>',  with_dap(function(d) d.run_to_cursor() end),     { desc = 'DAP: run to cursor' })
vim.keymap.set('n', '<F7>',  with_dap(function(_, ui) ui.toggle() end),       { desc = 'DAP: toggle UI' })
vim.keymap.set('n', '<F8>',  with_dap(function(d)
  d.set_breakpoint(vim.fn.input('Breakpoint condition: '))
end), { desc = 'DAP: conditional breakpoint' })
vim.keymap.set('n', '<F10>', with_dap(function(d) d.terminate() end),         { desc = 'DAP: terminate session' })

-- ── Language-agnostic DAP keymaps ────────────────────────────
-- <leader>ds (start) is intentionally absent here — the launch logic
-- differs per language (Fortran needs an exe/workdata picker; Python
-- uses dap.continue() which shows the config picker automatically).
-- <leader>ds is defined in fortran-tools.lua and python.lua.

vim.keymap.set('n', '<leader>dq', with_dap(function(d) d.terminate() end),     { desc = 'DAP: terminate - F10' })
vim.keymap.set('n', '<leader>dr', with_dap(function(d) d.restart() end),       { desc = 'DAP: restart' })
vim.keymap.set('n', '<leader>dn', with_dap(function(d) d.step_over() end),     { desc = 'DAP: step over - F2' })
vim.keymap.set('n', '<leader>di', with_dap(function(d) d.step_into() end),     { desc = 'DAP: step into - F1' })
vim.keymap.set('n', '<leader>do', with_dap(function(d) d.step_out() end),      { desc = 'DAP: step out - F3' })
vim.keymap.set('n', '<leader>dc', with_dap(function(d) d.run_to_cursor() end), { desc = 'DAP: run to cursor - F6' })

vim.keymap.set('n', '<leader>db', with_dap(function(d) d.toggle_breakpoint() end),
  { desc = 'DAP: toggle breakpoint - F4' })
vim.keymap.set('n', '<leader>dB', with_dap(function(d)
  d.set_breakpoint(vim.fn.input('Breakpoint condition: '))
end), { desc = 'DAP: conditional breakpoint - F8' })
vim.keymap.set('n', '<leader>dL', with_dap(function(d)
  d.set_breakpoint(nil, nil, vim.fn.input('Log point message: '))
end), { desc = 'DAP: log point' })
vim.keymap.set('n', '<leader>dx', with_dap(function(d) d.clear_breakpoints() end),
  { desc = 'DAP: clear all breakpoints - Shift-F4 (F16)' })

vim.keymap.set('n', '<leader>dw', with_dap(function(_, ui)
  local word = vim.fn.expand('<cword>')
  vim.ui.input({ prompt = 'Add to watches: ', default = word }, function(input)
    if input and input ~= '' then
      ui.elements['watches'].add(input)
      vim.notify('Watching: ' .. input, vim.log.levels.INFO)
    end
  end)
end), { desc = 'DAP: add to watches' })

vim.keymap.set('n', '<leader>dU', with_dap(function(_, ui) ui.toggle() end), { desc = 'DAP: toggle UI - F7' })
vim.keymap.set('n', '<leader>dC', with_dap(function(_, ui)
  local before = vim.api.nvim_list_wins()
  ui.float_element('console', { enter = true })
  utils.raise_new_floats(before)
end), { desc = 'DAP: open console float' })
vim.keymap.set({ 'n', 'v' }, '<leader>de', with_dap(function(_, ui)
  local before = vim.api.nvim_list_wins()
  ui.eval(nil, { enter = true })
  utils.raise_new_floats(before)
end), { desc = 'DAP: eval expression / selection' })
vim.keymap.set('n', '<leader>dR', with_dap(function(d) d.repl.open() end), { desc = 'DAP: open REPL' })

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

vim.keymap.set('n', '<leader>dh', with_dap(function()
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
end), { desc = 'DAP: toggle hover' })

-- Pure UI popup (reads keymap descriptions, touches no dap module) —
-- no activation needed.
vim.keymap.set('n', '<leader>dF', function()
  -- Build popup lines from the actual keymap descriptions so the popup
  -- stays accurate automatically when F-key bindings change.
  local fkeys = {
    { '<F1>',  'F1'  }, { '<F2>',  'F2'  }, { '<F3>',  'F3'  },
    { '<F4>',  'F4'  }, { '<F16>', 'S-F4' }, { '<F5>',  'F5'  }, { '<F6>',  'F6'  },
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

-- Language files (fortran-tools, python, c-tools, web-tools, java-tools)
-- call require('plugins.dap').activate() before require('dap') so the
-- stack is installed and configured regardless of which entry point
-- (keypress or FileType activation) comes first.
return { activate = activate }
