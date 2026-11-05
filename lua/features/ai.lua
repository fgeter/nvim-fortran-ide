-- ============================================================
-- features/ai.lua — the AI menu: Claude Code inside the IDE
--
-- Starts Claude Code (`claude` or `claude-personal`, i.e. the two
-- CLAUDE_CONFIG_DIRs, which may be signed in to different accounts) in a
-- split on the right, connected to Neovim through claudecode.nvim
-- (plugins/claudecode.lua):
--   • Claude sees the current file and selection, open files and
--     diagnostics; its edits arrive as diffs to accept / reject;
--   • Claude can drive this Neovim — list and run keymaps, run commands,
--     read the build terminal — with the `nvim-ide` script (bin/nvim-ide,
--     features/ai-bridge.lua). A line appended to Claude's system prompt
--     points it at `nvim-ide help` (ai/claude-in-nvim.md). Each call is
--     a Bash command, so Claude Code asks permission for it like any other.
--
-- One session at a time. Starting the other account offers to stop the
-- running one first (the IDE connection's lock file lives in the
-- account's own config dir, so the server restarts with it).
--
-- The AI menu shows ✓ beside the running session's account (M.state).
--
-- Keymaps (<leader>i…, menu AI / Alt+A):
--   <leader>ic   Claude: continue (claude -c)
--   <leader>iC   Claude: new session (claude)
--   <leader>ip   Claude personal: continue (claude-personal -c)
--   <leader>iP   Claude personal: new session (claude-personal)
--   <leader>it   show / hide the Claude panel           (also <F9>)
--   <leader>if   add the current file to Claude's context
--   <leader>is   send the selection (visual) to Claude
--   <leader>ia   accept Claude's proposed diff
--   <leader>id   reject Claude's proposed diff
--   <leader>iq   stop the Claude session
-- ============================================================

if vim.g.loaded_ai_menu then return end
vim.g.loaded_ai_menu = true

local M = {}

local HOME   = vim.env.HOME
local CONFIG = vim.fn.stdpath('config')
-- Appended to Claude's system prompt; `nvim-ide help` prints the full
-- guide (ai/claude-in-nvim.md). Single-quoted for the plugin's shell-style
-- split, so it must not contain a single quote.
local PROMPT = 'You are running inside the user Neovim IDE, in a terminal split.'
  .. ' The IDE connection shows you the file and selection the user is on.'
  .. ' To inspect or drive this Neovim (list and run its keymaps and menu'
  .. ' features, run Ex commands or Lua, read the build terminal) use the'
  .. ' nvim-ide command; run nvim-ide help once before first use.'

-- `dir` is the account's CLAUDE_CONFIG_DIR; `unset` means run with the
-- variable removed (plain `claude` keeps its global state in ~/.claude.json,
-- which setting CLAUDE_CONFIG_DIR=~/.claude would move).
M.accounts = {
  { id = 'claude',          cmd = 'claude',          dir = HOME .. '/.claude',          unset = true },
  { id = 'claude-personal', cmd = 'claude-personal', dir = HOME .. '/.claude-personal' },
}

local current = nil   -- the account of the running session

-- The email the account is signed in as (shown in the menu), or nil.
local function email(acct)
  local file = acct.unset and (HOME .. '/.claude.json') or (acct.dir .. '/.claude.json')
  local fd = io.open(file, 'r')
  if not fd then return nil end
  local ok, data = pcall(vim.json.decode, fd:read('*a'))
  fd:close()
  return ok and type(data) == 'table' and data.oauthAccount and data.oauthAccount.emailAddress or nil
end

local function running()
  local ok, term = pcall(require, 'claudecode.terminal')
  return ok and term.get_active_terminal_bufnr() ~= nil
end

local function command(acct, args)
  local parts = { 'env' }
  if acct.unset then
    vim.list_extend(parts, { '-u', 'CLAUDE_CONFIG_DIR' })
  else
    parts[#parts + 1] = 'CLAUDE_CONFIG_DIR=' .. acct.dir
  end
  parts[#parts + 1] = 'claude'
  if args and args ~= '' then parts[#parts + 1] = args end
  parts[#parts + 1] = "--append-system-prompt '" .. PROMPT .. "'"
  return table.concat(parts, ' ')
end

-- Does `acct` have a saved conversation for the current folder? Claude
-- keeps them in <config dir>/projects/<cwd with every non-alphanumeric
-- character (/ . _ and so on) turned into ->/. Matching only / and . missed
-- folders with an underscore (swatplus_fg_fork), so -c was always dropped.
-- `-c` with none just prints "No conversation found" and exits.
local function has_conversation(acct)
  local key = vim.fn.getcwd():gsub('[^%w]', '-')
  return #vim.fn.glob(acct.dir .. '/projects/' .. key .. '/*.jsonl', false, true) > 0
end

local claude_buf = nil   -- the running session's terminal buffer

local function start(acct, args)
  if args == '-c' and not has_conversation(acct) then
    vim.notify(('No %s conversation to continue in %s; starting a new one.')
      :format(acct.cmd, vim.fn.fnamemodify(vim.fn.getcwd(), ':~')), vim.log.levels.INFO)
    args = nil
  end
  local cc   = require('claudecode')
  local term = require('claudecode.terminal')
  if current ~= acct.id or not cc.state.server then
    if cc.state.server then cc.stop() end
    require('claudecode.lockfile').lock_dir = acct.dir .. '/ide'
    local ok, err = cc.start(false)
    if not ok then
      vim.notify('Claude IDE connection did not start: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end
  end
  current = acct.id
  term.setup({
    provider = 'native', split_side = 'right', split_width_percentage = 0.40, auto_close = false,
  }, command(acct, nil), {
    PATH         = CONFIG .. '/bin:' .. (vim.env.PATH or ''),
    NVIM_IDE_EXE = vim.v.progpath,
  })
  term.open({}, args)
  claude_buf = term.get_active_terminal_bufnr()
  -- The plugin's :startinsert is a pending request. When the launch came
  -- from a menu-bar click (the menu acts on the press), the mouse release
  -- lands after it and cancels it, leaving the new panel in Terminal-Normal
  -- ("nt"): the first key typed runs as a Neovim command. The release can
  -- come any time the button is held, so a single check at a fixed delay
  -- misses it. Watch the panel for a while instead: whenever it is focused
  -- and in "nt", re-enter Terminal mode. A ModeChanged autocmd is not
  -- enough: entering the split straight into "nt" fires no mode change.
  local buf = claude_buf
  if not buf then return end
  local timer = vim.uv.new_timer()
  local ticks = 0
  timer:start(50, 50, vim.schedule_wrap(function()
    ticks = ticks + 1
    if ticks > 40 or not vim.api.nvim_buf_is_valid(buf) then   -- 2 s
      if not timer:is_closing() then timer:stop() timer:close() end
      return
    end
    if vim.api.nvim_get_current_buf() == buf
      and vim.api.nvim_get_mode().mode == 'nt' then
      vim.api.nvim_feedkeys('i', 'n', false)
    end
  end))
end

-- The session ended. A clean exit closes the panel. An error keeps it, so
-- the message can be read, until q. Done here rather than by the plugin
-- (auto_close = false): closing a window from inside the job's exit
-- callback can trip other WinEnter autocmds (E1312).
vim.api.nvim_create_autocmd('TermClose', {
  group = vim.api.nvim_create_augroup('ai-menu-term', { clear = true }),
  callback = function(ev)
    if ev.buf ~= claude_buf then return end
    claude_buf = nil
    local status = vim.v.event and vim.v.event.status or 0
    local buf = ev.buf
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if status == 0 then
        for _, w in ipairs(vim.fn.win_findbuf(buf)) do
          if #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(w)) > 1 then
            pcall(vim.api.nvim_win_close, w, true)
          end
        end
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        return
      end
      for _, w in ipairs(vim.fn.win_findbuf(buf)) do
        vim.wo[w].winbar = (' Claude exited (code %d) · q: close'):format(status)
      end
      vim.keymap.set('n', 'q', function()
        for _, w in ipairs(vim.fn.win_findbuf(buf)) do pcall(vim.api.nvim_win_close, w, true) end
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end, { buffer = buf, nowait = true, desc = 'Close the ended Claude panel' })
      vim.cmd('stopinsert')
    end)
  end,
})

function M.launch(id, args)
  local acct
  for _, a in ipairs(M.accounts) do if a.id == id then acct = a end end
  if not acct then return end
  if running() then
    if current == id then
      require('claudecode.terminal').open()   -- already running: show / focus it
      return
    end
    vim.ui.select({ 'Yes', 'No' }, {
      prompt = ('Stop the running %s session and start %s?'):format(current or 'Claude', id),
    }, function(choice)
      if choice ~= 'Yes' then return end
      require('claudecode.terminal').close()
      vim.schedule(function() start(acct, args) end)
    end)
    return
  end
  start(acct, args)
end

function M.toggle()
  if running() then
    require('claudecode.terminal').simple_toggle({})
  else
    M.launch('claude', '-c')
  end
end

function M.stop()
  if running() then require('claudecode.terminal').close() end
  local cc = require('claudecode')
  if cc.state.server then cc.stop() end
  current = nil
end

-- Menu bar state column (features/topbar.lua): a check mark beside the
-- running session's account, both its continue and new-session items.
local ACCOUNT_KEYS = { ic = 'claude', iC = 'claude', ip = 'claude-personal', iP = 'claude-personal' }

function M.state(key)
  local id = ACCOUNT_KEYS[key]
  if not id or not running() then return nil end
  return current == id and '✓' or ''
end

local function need_session(fn)
  return function()
    if not running() then
      vim.notify('No Claude session running — start one from the AI menu.', vim.log.levels.WARN)
      return
    end
    fn()
  end
end

local function map(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { desc = desc }) end

local function label(acct, what)
  local e = email(acct)
  return ('Claude: %s (%s%s)%s'):format(what, acct.cmd, what == 'continue' and ' -c' or '',
    e and ('  ' .. e) or '')
end

local A, P = M.accounts[1], M.accounts[2]
map('n', '<leader>ic', function() M.launch('claude', '-c') end,          label(A, 'continue'))
map('n', '<leader>iC', function() M.launch('claude') end,                label(A, 'new session'))
map('n', '<leader>ip', function() M.launch('claude-personal', '-c') end, label(P, 'continue'))
map('n', '<leader>iP', function() M.launch('claude-personal') end,       label(P, 'new session'))
map('n', '<leader>it', M.toggle, 'Claude: show / hide panel - F9')
map({ 'n', 't' }, '<F9>', M.toggle, 'Claude: show / hide panel')
map('n', '<leader>if', need_session(function() vim.cmd('ClaudeCodeAdd %') end),
  'Claude: add current file to context')
map('x', '<leader>is', '<Cmd>ClaudeCodeSend<CR>', 'Claude: send selection')
map('n', '<leader>is', need_session(function()
  vim.notify('Select some lines first (visual mode), then <leader>is.', vim.log.levels.INFO)
end), 'Claude: send selection (visual mode)')
map('n', '<leader>ia', '<Cmd>ClaudeCodeDiffAccept<CR>', 'Claude: accept proposed diff')
map('n', '<leader>id', '<Cmd>ClaudeCodeDiffDeny<CR>',   'Claude: reject proposed diff')
map('n', '<leader>iq', M.stop, 'Claude: stop session')

-- Remember the last real editor window, so features/ai-bridge.lua can run
-- keymaps there rather than in the Claude terminal.
local utils = require('core.utils')
local ai_group = vim.api.nvim_create_augroup('ai-menu', { clear = true })
vim.api.nvim_create_autocmd('WinEnter', {
  group = ai_group,
  callback = function()
    local w = vim.api.nvim_get_current_win()
    if utils.is_editor_buf(vim.api.nvim_win_get_buf(w)) then vim.g.ai_last_editor_win = w end
  end,
})

-- Coming back into the Claude panel (Ctrl+Alt+arrow, <C-w>, a mouse
-- click) lands in Terminal-Normal mode ("nt"), where typed keys run as
-- Neovim commands instead of reaching Claude. Re-enter Terminal mode.
-- Scheduled so it runs after the move (and the click) has finished.
local function is_claude_buf(buf)
  local ok, term = pcall(require, 'claudecode.terminal')
  return ok and buf ~= nil and term.get_active_terminal_bufnr() == buf
end
vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter' }, {
  group = ai_group,
  callback = function(ev)
    if not is_claude_buf(ev.buf) then return end
    vim.schedule(function()
      if is_claude_buf(vim.api.nvim_get_current_buf())
        and vim.api.nvim_get_mode().mode == 'nt' then
        vim.cmd('startinsert')
      end
    end)
  end,
})

-- A click inside the panel while it is already focused: Claude Code does
-- not turn on terminal mouse reporting, so Neovim handles the click itself
-- and drops to Terminal-Normal ("nt"). No WinEnter fires, so the autocmd
-- above never sees it. Watch for the release with on_key (observe only)
-- rather than a <LeftRelease> map: features/hscrollbar.lua maps that key
-- globally to end a scrollbar drag, and a buffer-local map here would
-- shadow it. A drag-select ends in Visual mode, so the "nt" check leaves it
-- alone. Fed keys, not :startinsert, so nothing still queued cancels it.
local K_RELEASE = vim.keycode('<LeftRelease>')
vim.on_key(function(key)
  if key ~= K_RELEASE then return end
  vim.schedule(function()
    if vim.g.hscroll_dragging then return end
    if is_claude_buf(vim.api.nvim_get_current_buf())
      and vim.api.nvim_get_mode().mode == 'nt' then
      vim.api.nvim_feedkeys('i', 'n', false)
    end
  end)
end, vim.api.nvim_create_namespace('ai-menu-click'))

package.loaded['features.ai'] = M
return M
