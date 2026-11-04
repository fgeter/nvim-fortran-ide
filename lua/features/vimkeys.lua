-- ============================================================
-- features/vimkeys.lua — Vim keybindings on / off (Edit › Vim keybindings,
-- <leader>Em)
--
-- Off makes file windows behave like an ordinary editor: always typing
-- (insert mode), Shift+arrows / mouse drag select, typing replaces a
-- selection, and the usual Ctrl keys:
--
--   Ctrl+S save        Ctrl+Z undo        Ctrl+Y redo
--   Ctrl+X cut         Ctrl+C copy        Ctrl+V paste
--   Ctrl+A select all  Ctrl+F find        Ctrl+H replace
--   Ctrl+G go to line  Ctrl+/ comment     Tab / Shift+Tab indent a selection
--   Ctrl+N new file    Ctrl+O open…       Ctrl+P find file
--   Ctrl+W close file  Ctrl+Q quit
--   Ctrl+Alt+arrows    move to the window in that direction (always on)
--   F1–F10             debugger keys work while typing
--   Alt+letter         the menus (features/topbar.lua)
--   right-click        Cut / Copy / Paste / Delete / Select All
--
-- Everything else is in the menus. Only file windows change: the file
-- tree, terminals, pickers, debugger panels and other plugin windows keep
-- their own keys. Cut / copy without a selection take the whole line, as
-- the Edit menu does — each Ctrl key runs the same <leader> keymap as its
-- menu entry, so the two can't drift apart.
--
-- How "always typing" works: whenever Neovim is idle (SafeState) in a
-- file window in normal mode, insert mode starts again, at the spot
-- where typing stopped if the cursor is still there. A selection made
-- in visual mode (Select all, a menu action) becomes a select-mode one,
-- so typing replaces it. Pausing while typing (CursorHoldI) starts a new
-- undo step, so Ctrl+Z undoes a burst of typing, not the whole session.
--
-- The choice is remembered in stdpath('state')/vim-keys ("off"); on is
-- the default. M.state('Em') gives on / off for the Edit drop-down.
-- Added 2026-11-03.
-- ============================================================

local M = {}

local utils = require('core.utils')
local SAVE  = vim.fn.stdpath('state') .. '/vim-keys'

local enabled = true            -- Vim keybindings on?
local saved_opts = nil          -- option values to put back when turned on

local function t(k) return vim.api.nvim_replace_termcodes(k, true, false, true) end
local function feed(k, remap) vim.api.nvim_feedkeys(t(k), remap and 'm' or 'n', false) end

-- A window this module manages: a real file (or new, unnamed) buffer,
-- not a float or a plugin panel.
local function managed(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then return false end
  if vim.api.nvim_win_get_config(win).relative ~= '' then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  return utils.is_editor_buf(buf) and vim.bo[buf].modifiable
end

local function active() return not enabled and managed() end

-- ── Ctrl+Alt+arrows: move between windows (any mode) ─────────
-- Leaving typing first, so landing in the file tree is not insert mode
-- there; a file window starts typing again by itself (SafeState below).
for key, dir in pairs({ Left = 'h', Down = 'j', Up = 'k', Right = 'l' }) do
  vim.keymap.set({ 'n', 'i', 'x', 's', 't' }, '<C-M-' .. key .. '>', function()
    local mode = vim.fn.mode()
    if mode == 't' then
      vim.api.nvim_feedkeys(t('<C-\\><C-n>'), 'n', false)
      vim.schedule(function() vim.cmd.wincmd(dir) end)
      return
    end
    if mode:match('^[ivVsS\22\19]') then
      vim.api.nvim_feedkeys(t('<Esc>'), 'n', false)
    end
    vim.schedule(function() vim.cmd.wincmd(dir) end)
  end, { desc = 'Window: move ' .. key:lower(), silent = true })
end

-- ── Ctrl keys (only while off, only in file windows) ─────────
-- Each runs the <leader> keymap behind the menu entry: from typing,
-- leave insert mode first; from a selection, switch select mode to
-- visual so the keymap's visual-mode version gets the selection.
local CTRL = {
  ['<C-s>'] = 'Fs', ['<C-z>'] = 'Ez', ['<C-y>'] = 'EZ',
  ['<C-x>'] = 'Ek', ['<C-c>'] = 'Ey', ['<C-v>'] = 'EV',
  ['<C-a>'] = 'Ea', ['<C-f>'] = 'Es', ['<C-h>'] = 'Er', ['<C-g>'] = 'Eg',
  ['<C-n>'] = 'Fn', ['<C-o>'] = 'Fo', ['<C-p>'] = 'Ff',
  ['<C-w>'] = 'bd', ['<C-q>'] = 'Fq',
  ['<C-/>'] = 'E/', ['<C-_>'] = 'E/',   -- terminals send Ctrl+/ as Ctrl+_
}

local function leader() return vim.g.mapleader or '\\' end

local function run_leader(key)
  local mode = vim.fn.mode()
  local selecting = mode:match('^[sS\19]') ~= nil
  -- Copy keeps the selection, as in other editors: copy, reselect, and
  -- back to select mode in one go.
  if selecting and key == 'Ey' then
    vim.api.nvim_feedkeys(t('<C-g>"+ygv<C-g>'), 'n', false)
    return
  end
  local prefix = ''
  if mode:match('^i') then prefix = t('<Esc>')
  elseif selecting then prefix = t('<C-g>') end
  if prefix ~= '' then vim.api.nvim_feedkeys(prefix, 'n', false) end
  vim.api.nvim_feedkeys(t(leader() .. key), 'm', false)
end

-- Where the key does its normal job (another window, Vim keys on).
local function passthrough(lhs) vim.api.nvim_feedkeys(t(lhs), 'n', false) end

-- { mode, lhs, previous } of the mappings made while off; previous is
-- the global mapping that was there (normal-mode Ctrl+S save, …), put
-- back when Vim keys come back on.
local installed = {}

local function add(modes, lhs, fn, desc)
  for _, m in ipairs(type(modes) == 'table' and modes or { modes }) do
    local seen = false
    for _, e in ipairs(installed) do
      if e[1] == m and e[2] == lhs then seen = true break end
    end
    if not seen then
      local prev = vim.fn.maparg(lhs, m, false, true)
      if vim.tbl_isempty(prev) or prev.buffer == 1 then prev = nil end
      installed[#installed + 1] = { m, lhs, prev }
    end
  end
  vim.keymap.set(modes, lhs, function()
    if active() then return fn() end
    -- Elsewhere: whatever this key did before (a mapping, or Neovim's own).
    local mode = vim.fn.mode():sub(1, 1)
    mode = (mode == 'S' or mode == '\19') and 's' or mode
    for _, e in ipairs(installed) do
      if e[1] == mode and e[2] == lhs and e[3] then
        local p = e[3]
        if p.callback then return p.callback() end
        if p.expr == 1 then return passthrough(lhs) end
        return vim.api.nvim_feedkeys(t(p.rhs), p.noremap == 1 and 'n' or 'm', false)
      end
    end
    passthrough(lhs)
  end, { desc = desc, silent = true })
end

local function install()
  for lhs, key in pairs(CTRL) do
    add({ 'n', 'i', 's' }, lhs, function() run_leader(key) end, 'Vim keys off: <leader>' .. key)
  end
  -- Paste while typing: straight from the clipboard at the cursor ("+P
  -- after leaving insert mode would land one character early).
  add('i', '<C-v>', function()
    vim.api.nvim_feedkeys(t('<C-g>u<C-r><C-o>+'), 'n', false)
  end, 'Vim keys off: paste')
  -- Undo / redo while typing: close the current typing step first.
  add('i', '<C-z>', function() vim.api.nvim_feedkeys(t('<C-g>u<C-o>u'), 'n', false) end, 'Vim keys off: undo')
  add('i', '<C-y>', function() vim.api.nvim_feedkeys(t('<C-o><C-r>'), 'n', false) end, 'Vim keys off: redo')

  -- Esc while typing: close the completion menu, clear search highlight;
  -- there is no normal mode to go to.
  add('i', '<Esc>', function()
    if vim.fn.pumvisible() == 1 then
      vim.api.nvim_feedkeys(t('<C-e>'), 'n', false)
    else
      vim.cmd('nohlsearch')
    end
  end, 'Vim keys off: Esc')

  -- Tab / Shift+Tab on a selection indent it, and keep it selected.
  -- Done as a command on the lines, not with keys: a selection started
  -- while typing drops back to typing after > / <, and the rest of a key
  -- sequence would be typed as text.
  local function shift(dir)
    return function()
      local a, b = vim.fn.line('v'), vim.fn.line('.')
      if a > b then a, b = b, a end
      vim.cmd(('silent keepjumps %d,%d%s'):format(a, b, dir))
      -- The command ends the selection; select the same lines again (whole
      -- lines: the columns moved with the indent).
      vim.schedule(function()
        if vim.fn.mode() ~= 'n' then return end
        vim.api.nvim_win_set_cursor(0, { a, 0 })
        vim.api.nvim_feedkeys(t(('V%s<C-g>'):format(b > a and (b - a) .. 'j' or '')), 'n', false)
      end)
    end
  end
  add('s', '<Tab>',   shift('>'), 'Vim keys off: indent')
  add('s', '<S-Tab>', shift('<'), 'Vim keys off: outdent')

  -- Right-click on a selection made while typing ("(insert) select"):
  -- Neovim runs menu entries there through Ctrl+\ Ctrl+O, which drops the
  -- selection before the entry runs, so Cut / Copy did nothing. Turn it
  -- into a plain selection of the same text first, then open the menu.
  -- Outside the selection: end it, put the cursor there, open the menu.
  add('s', '<RightMouse>', function()
    local mp = vim.fn.getmousepos()
    if mp.winid ~= vim.api.nvim_get_current_win() or mp.line == 0 then
      return passthrough('<RightMouse>')
    end
    local v, c = vim.fn.getpos('v'), vim.fn.getpos('.')
    local a, b = { v[2], v[3] }, { c[2], c[3] }
    if a[1] > b[1] or (a[1] == b[1] and a[2] > b[2]) then a, b = b, a end
    local m = { mp.line, mp.column }
    local inside
    if vim.fn.mode() == 'S' then
      inside = m[1] >= a[1] and m[1] <= b[1]
    else
      inside = (m[1] > a[1] or (m[1] == a[1] and m[2] >= a[2]))
        and (m[1] < b[1] or (m[1] == b[1] and m[2] <= b[2]))
    end
    if inside then
      feed('<C-\\><C-n>gv<C-g><Cmd>popup PopUp<CR>')
    else
      feed('<C-\\><C-n>')
      vim.schedule(function()
        pcall(vim.api.nvim_win_set_cursor, 0, { mp.line, math.max(0, mp.column - 1) })
        feed('<Cmd>popup PopUp<CR>')
      end)
    end
  end, 'Vim keys off: right-click menu on a selection')

  -- Debugger and other F-keys: whatever they do in normal mode (including
  -- buffer-local ones, like Fortran's F5), also while typing / selecting.
  for i = 1, 24 do
    local k = '<F' .. i .. '>'
    add({ 'i', 's' }, k, function()
      if vim.fn.maparg(k, 'n') == '' then passthrough(k) return end
      local mode = vim.fn.mode()
      vim.api.nvim_feedkeys(t(mode:match('^i') and '<Esc>' or '<C-g><Esc>'), 'n', false)
      vim.api.nvim_feedkeys(t(k), 'm', false)
    end, 'Vim keys off: ' .. k .. ' as in normal mode')
  end
end

local function uninstall()
  for _, m in ipairs(installed) do
    pcall(vim.keymap.del, m[1], m[2])
    if m[3] then pcall(vim.fn.mapset, m[3]) end
  end
  installed = {}
end

-- ── Options ──────────────────────────────────────────────────
-- Shift+arrows (and Shift+Home/End, Ctrl+Shift+arrows) start a
-- selection, plain arrows end it; mouse and keyboard selections are
-- select mode (typing replaces them); arrows wrap across lines.
local OPTS = {
  keymodel   = 'startsel,stopsel',
  selectmode = 'mouse,key',
  whichwrap  = 'b,s,<,>,[,]',
  selection  = 'exclusive',   -- Shift+End selects up to, not including, the line break
}

local function set_opts(off)
  if off then
    saved_opts = {}
    for k, v in pairs(OPTS) do saved_opts[k] = vim.o[k]; vim.o[k] = v end
  elseif saved_opts then
    for k, v in pairs(saved_opts) do vim.o[k] = v end
    saved_opts = nil
  end
end

-- ── Always typing ────────────────────────────────────────────
local group = vim.api.nvim_create_augroup('vimkeys', { clear = true })

-- Where typing stopped, per window (before Esc moves the cursor left).
vim.api.nvim_create_autocmd('InsertLeavePre', {
  group = group,
  callback = function()
    if enabled then return end
    vim.w.vimkeys_pos = vim.api.nvim_win_get_cursor(0)
  end,
})

vim.api.nvim_create_autocmd('SafeState', {
  group = group,
  callback = function()
    if not active() then return end
    local mode = vim.fn.mode()
    local win = vim.api.nvim_get_current_win()
    if mode == 'n' then
      local pos = vim.w.vimkeys_pos
      vim.w.vimkeys_pos = nil
      _G.___topbar_resume_insert(win, pos)
    elseif mode:match('^[vV\22]$') then
      vim.api.nvim_feedkeys(t('<C-g>'), 'n', false)   -- visual → select
    end
  end,
})

-- Moving into a read-only window (the file tree, a help or plugin
-- panel) while typing: stop typing there. Prompts and terminals keep it.
vim.api.nvim_create_autocmd('WinEnter', {
  group = group,
  callback = function()
    if enabled then return end
    vim.schedule(function()
      local bt = vim.bo.buftype
      if vim.fn.mode():match('^i') and not managed() and bt ~= 'prompt' and bt ~= 'terminal'
        and not vim.bo.modifiable then
        vim.cmd('stopinsert')
      end
    end)
  end,
})

-- A pause in typing ends one undo step.
vim.api.nvim_create_autocmd('CursorHoldI', {
  group = group,
  callback = function()
    if active() then vim.api.nvim_feedkeys(t('<C-g>u'), 'n', false) end
  end,
})

-- ── Right-click menu ─────────────────────────────────────────
-- Neovim's own PopUp Cut / Copy / Delete exist only for Visual mode. A
-- mouse selection made while typing is "(insert) select" mode, where
-- Neovim runs a menu entry's Insert-mode version — none, so E335: Menu not
-- defined for Insert mode, and nothing was cut or copied. Adding an Insert
-- version to those entries does not work either: Neovim makes a second,
-- separate entry. So the edit part of the menu is rebuilt (same order),
-- each entry defined for every mode and running M.popup, which looks at
-- the mode itself and does what the Ctrl keys / Edit menu do.
function M.popup(action)
  local mode = vim.fn.mode(1)
  local sel = mode:match('^[sS\19]') ~= nil
  local vis = mode:match('^[vV\22]') ~= nil
  local ins = mode:match('^i') ~= nil or mode == 'niI'

  if action == 'selectall' then
    if mode ~= 'n' then feed('<C-\\><C-n>') end
    return feed(leader() .. 'Ea', true)
  end
  if action == 'paste' then
    if sel then return run_leader('EV') end
    if vis then return feed(leader() .. 'EV', true) end
    if ins then return feed('<C-g>u<C-r><C-o>+') end
    return feed('"+gP')
  end
  -- cut / copy / delete
  if not (sel or vis) then
    -- No selection: with Vim keys off, cut / copy take the line, like
    -- Ctrl+X / Ctrl+C; otherwise there is nothing to act on.
    if not enabled and action ~= 'delete' then
      return run_leader(action == 'cut' and 'Ek' or 'Ey')
    end
    return vim.notify('Nothing selected', vim.log.levels.INFO)
  end
  if action == 'delete' then return feed((sel and '<C-g>' or '') .. '"_d') end
  local key = action == 'cut' and 'Ek' or 'Ey'
  if sel then return run_leader(key) end
  feed(leader() .. key, true)
end

do
  local items = {
    { 'Cut', 'cut' }, { 'Copy', 'copy' }, { 'Paste', 'paste' },
    { 'Delete', 'delete' }, { 'Select\\ All', 'selectall' },
  }
  local cmds = {}
  -- Remove the old entries and the two after them, then add all back in
  -- order (a re-added entry would otherwise land at the bottom).
  for _, it in ipairs(items) do cmds[#cmds + 1] = 'silent! aunmenu PopUp.' .. it[1] end
  cmds[#cmds + 1] = 'silent! aunmenu PopUp.-2-'
  cmds[#cmds + 1] = 'silent! aunmenu PopUp.How-to\\ disable\\ mouse'
  for _, it in ipairs(items) do
    local rhs = ("<Cmd>lua require('features.vimkeys').popup('%s')<CR>"):format(it[2])
    -- anoremenu makes the one entry for every mode; then plain <Cmd> for
    -- Insert and Visual/Select (anoremenu would add <C-\><C-O> / <C-C>
    -- there, leaving the mode before M.popup can look at it).
    for _, c in ipairs({ 'anoremenu', 'inoremenu', 'vnoremenu' }) do
      cmds[#cmds + 1] = ('%s <silent> PopUp.%s %s'):format(c, it[1], rhs)
    end
  end
  cmds[#cmds + 1] = 'anoremenu PopUp.-2- <Nop>'
  cmds[#cmds + 1] = 'anoremenu PopUp.How-to\\ disable\\ mouse <Cmd>help disable-mouse<CR>'
  vim.cmd(table.concat(cmds, '\n'))
end

-- ── On / off ─────────────────────────────────────────────────
function M.set(on, quiet)
  if on == enabled then return end
  enabled = on
  if on then
    uninstall()
    set_opts(false)
    if vim.fn.mode():match('^[iR]') then vim.cmd('stopinsert') end
    -- Chosen from a menu opened while typing: don't go back to typing.
    vim.g.topbar_skip_resume = true
    vim.defer_fn(function() vim.g.topbar_skip_resume = nil end, 1000)
  else
    install()
    set_opts(true)
  end
  pcall(vim.fn.writefile, { on and 'on' or 'off' }, SAVE)
  if not quiet then
    vim.notify(on and 'Vim keybindings on'
      or ('Vim keybindings off: just type. Ctrl+S save, Ctrl+Z/Y undo/redo, '
        .. 'Ctrl+X/C/V cut/copy/paste, Ctrl+F find, Alt+F/E/V… menus, '
        .. 'Ctrl+Alt+arrows windows. Edit › Vim keybindings turns them back on.'),
      vim.log.levels.INFO)
  end
end

function M.enabled() return enabled end

vim.keymap.set('n', '<leader>Em', function() M.set(not enabled) end,
  { desc = 'Edit: Vim keybindings (toggle)', silent = true })

function M.state(key)
  if key == 'Em' then return enabled end
end

-- Restore the saved choice once every plugin has made its keymaps.
local saved = vim.fn.filereadable(SAVE) == 1 and vim.trim(vim.fn.readfile(SAVE)[1] or '') or ''
if saved == 'off' then
  if vim.v.vim_did_enter == 1 then
    M.set(false, true)
  else
    vim.api.nvim_create_autocmd('VimEnter', {
      group = group, once = true,
      callback = function() M.set(false, true) end,
    })
  end
end

return M
