-- ============================================================
-- features/view.lua — <leader>v: View (layout and display toggles)
--
-- The keymaps behind the menu bar's View drop-down (features/topbar.lua),
-- which lists these plus the existing <leader>t display toggles. Like
-- every other menu, the drop-down only feeds these keymaps, so they work
-- the same from the keyboard.
--
--   ve  file explorer (Neo-tree) on/off      vt  terminal at the bottom
--   vv  split side by side (vertical)        vT  terminal on the right
--   vs  split stacked (horizontal)           vf  floating terminal
--   vq  close this split                     vn  line numbers on/off
--   vo  close the other editor splits        vw  soft line wrap on/off
--   v=  make splits equal size               vi  show whitespace on/off
--   vz  zoom this split (again to restore)   vd  inline diagnostics on/off
--   vh  Neovim help window on/off            vc  cursor line/column guide
--   vC  theme… (features/theme.lua)
--
-- M.state(key, win, buf) reports whether a toggle is on, for the on/off
-- column in the drop-down (nil = not a toggle).
-- Added 2026-11-02; help toggle and on/off states 2026-11-03.
-- ============================================================

local M = {}

local function map(lhs, rhs, desc)
  vim.keymap.set('n', '<leader>' .. lhs, rhs, { desc = 'View: ' .. desc, silent = true })
end

-- Windows that are part of the layout but not "editor splits": the menu
-- bar's carrier, the file explorer, terminals, floats. Closing or zooming
-- splits must leave these alone.
local function is_editor_win(win)
  if vim.api.nvim_win_get_config(win).relative ~= '' then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  local ft, bt = vim.bo[buf].filetype, vim.bo[buf].buftype
  if ft == 'topbar' or ft == 'neo-tree' then return false end
  return bt == '' or bt == 'acwrite' or bt == 'help'
end

local function editor_wins()
  local out = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor_win(win) then out[#out + 1] = win end
  end
  return out
end

-- ── File explorer ────────────────────────────────────────────
map('ve', '<Cmd>Neotree toggle filesystem left<CR>', 'file explorer (toggle)')

-- ── Terminal ─────────────────────────────────────────────────
-- One terminal (toggleterm #1, the same one <C-\> toggles), shown where
-- asked. Choosing the place it is already in hides it; choosing another
-- place moves it there, keeping its shell and scrollback.
local function terminal(direction)
  local term = require('toggleterm.terminal').get_or_create_term(1)
  local size
  if direction == 'vertical' then size = math.floor(vim.o.columns * 0.4) end
  if term:is_open() then
    local same = term.direction == direction
    term:close()
    if same then return end
  end
  term:open(size, direction)
end

map('vt', function() terminal('horizontal') end, 'terminal at the bottom (toggle)')
map('vT', function() terminal('vertical') end,   'terminal on the right (toggle)')
map('vf', function() terminal('float') end,      'floating terminal (toggle)')

-- ── Splits ───────────────────────────────────────────────────
map('vv', '<Cmd>vsplit<CR>', 'split side by side (vertical)')
map('vs', '<Cmd>split<CR>',  'split stacked (horizontal)')
map('v=', '<Cmd>wincmd =<CR>', 'make splits equal size')

map('vq', function()
  local cur = vim.api.nvim_get_current_win()
  if is_editor_win(cur) and #editor_wins() <= 1 then
    vim.notify('This is the last editor split', vim.log.levels.INFO)
    return
  end
  pcall(vim.api.nvim_win_close, cur, false)
end, 'close this split')

-- Not :only, which would also close the file explorer, terminal and the
-- menu bar's carrier window.
map('vo', function()
  local cur = vim.api.nvim_get_current_win()
  for _, win in ipairs(editor_wins()) do
    if win ~= cur then pcall(vim.api.nvim_win_close, win, false) end
  end
end, 'close the other editor splits')

-- Zoom: give this split the whole width and height; again restores the
-- previous sizes. winrestcmd() also puts the menu bar's zero-height carrier
-- back exactly as it was.
local zoom = {}   -- tabpage → { win, restore }
map('vz', function()
  local tab, cur = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
  if zoom[tab] then
    local restore = zoom[tab].restore
    zoom[tab] = nil
    vim.cmd(restore)
    return
  end
  zoom[tab] = { win = cur, restore = vim.fn.winrestcmd() }
  vim.cmd('wincmd |')
  vim.cmd('wincmd _')
end, 'zoom this split (toggle)')

-- ── Display toggles (current window / buffer) ────────────────
local function toggle(opt, label)
  return function()
    local on = not vim.wo[opt]
    vim.wo[opt] = on
    vim.notify(label .. (on and ' on' or ' off'), vim.log.levels.INFO)
  end
end

map('vn', toggle('number', 'Line numbers'),     'line numbers (toggle)')
map('vw', toggle('wrap', 'Soft wrap'),          'soft line wrap (toggle)')
map('vi', toggle('list', 'Whitespace display'), 'show whitespace (toggle)')

map('vc', function()
  local on = not (vim.wo.cursorline and vim.wo.cursorcolumn)
  vim.wo.cursorline, vim.wo.cursorcolumn = on, on
  vim.notify('Cursor guide' .. (on and ' on' or ' off'), vim.log.levels.INFO)
end, 'cursor line + column guide (toggle)')

map('vd', function()
  local on = not vim.diagnostic.is_enabled()
  vim.diagnostic.enable(on)
  vim.notify('Diagnostics' .. (on and ' on' or ' off'), vim.log.levels.INFO)
end, 'inline diagnostics (toggle)')

-- ── Neovim help ──────────────────────────────────────────────
local function help_wins()
  local out = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == 'help' then out[#out + 1] = win end
  end
  return out
end

map('vh', function()
  local wins = help_wins()
  if #wins == 0 then vim.cmd('help') return end
  for _, win in ipairs(wins) do pcall(vim.api.nvim_win_close, win, false) end
end, 'Neovim help (toggle)')

-- ── On/off state, for the menu bar's View drop-down ──────────
local function tab_has(pred)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if pred(win, vim.api.nvim_win_get_buf(win)) then return true end
  end
  return false
end

local function term_in(direction)
  local ok, t = pcall(require, 'toggleterm.terminal')
  local term = ok and t.get(1) or nil
  return term ~= nil and term:is_open() and term.direction == direction
end

local STATES = {
  ve = function() return tab_has(function(_, b)
         return vim.bo[b].filetype == 'neo-tree' and vim.b[b].neo_tree_source == 'filesystem' end) end,
  vt = function() return term_in('horizontal') end,
  vT = function() return term_in('vertical') end,
  vf = function() return term_in('float') end,
  vz = function() return zoom[vim.api.nvim_get_current_tabpage()] ~= nil end,
  vh = function() return #help_wins() > 0 end,
  vn = function(win) return vim.wo[win].number end,
  tr = function(win) return vim.wo[win].relativenumber end,
  vw = function(win) return vim.wo[win].wrap end,
  tW = function(_, buf) return vim.bo[buf].formatoptions:find('t', 1, true) ~= nil end,
  vi = function(win) return vim.wo[win].list end,
  vc = function(win) return vim.wo[win].cursorline and vim.wo[win].cursorcolumn end,
  vd = function() return vim.diagnostic.is_enabled() end,
  th = function(_, buf) return vim.lsp.inlay_hint.is_enabled({ bufnr = buf }) end,
  ts = function(win) return vim.wo[win].spell end,
  tu = function() return tab_has(function(_, b) return vim.bo[b].filetype == 'undotree' end) end,
}

function M.state(key, win, buf)
  local f = STATES[key]
  if not f then return nil end
  win = (win and vim.api.nvim_win_is_valid(win)) and win or vim.api.nvim_get_current_win()
  buf = (buf and vim.api.nvim_buf_is_valid(buf)) and buf or vim.api.nvim_win_get_buf(win)
  local ok, on = pcall(f, win, buf)
  if not ok then return nil end
  return on and true or false
end

return M
