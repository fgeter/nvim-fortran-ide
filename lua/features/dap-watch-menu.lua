-- ============================================================
-- features/dap-watch-menu.lua — "Add to watches" in the right-click menu
--
-- While a debug session is running, the right-click menu (Neovim's PopUp
-- menu) gets an entry at the top:
--
--     Add to watches: hru(j)%sw
--     ─────────────
--     Cut / Copy / Paste / …
--
-- Choosing it adds the expression to the dap-ui Watches panel, the same as
-- <leader>dw (without the prompt). With no session the entry is not shown.
--
-- What gets watched:
--   • a selection (visual / select mode): exactly the selected text;
--   • otherwise the expression under the click (mousemodel=popup_setpos
--     moves the cursor there first): the identifier, extended through
--     component and index syntax so a click anywhere on `hru(j)%sw` watches
--     all of it, not just `hru` or `sw`:
--       Fortran   a%b, a(i), a(i,j)%b(k)        — '%' members, '(' indexes
--       others    a.b, a[i], a->b               — '.' / '->' members, '[' indexes
--     Fortran parentheses are taken as array indexing; in other languages
--     '(' is a call, so it is never pulled in (watching it would run it).
--
-- In the dap-ui Watches panel itself, right-clicking a watch (its own line
-- or any line of its expanded children) offers instead:
--     Remove watch: <expr>     Edit watch: <expr>     Remove all watches
-- Edit opens a prompt pre-filled with the expression; <CR> replaces it.
--
-- MenuPopup fires just before the menu opens, so the entries (and their
-- labels) are rebuilt on every right-click.
-- ============================================================

if vim.g.loaded_dap_watch_menu then return end
vim.g.loaded_dap_watch_menu = true

local M = {}

local MENU    = 'PopUp.Add\\ to\\ watches'   -- prefix; the label carries the expression
local SEP     = 'PopUp.-dapwatch-'
local defined = {}    -- full menu paths of the entries now defined
local pending = nil   -- the expression the entry will add
local target  = nil   -- Watches panel: { index, expr, header_line, buf }

local function session_running()
  local dap = package.loaded['dap']   -- never load nvim-dap just for a right-click
  return dap ~= nil and dap.session() ~= nil
end

-- Balanced group starting at line[i] == open; returns the index of its close.
local function close_of(line, i, open, close)
  local depth = 0
  for k = i, #line do
    local c = line:sub(k, k)
    if c == open then depth = depth + 1
    elseif c == close then
      depth = depth - 1
      if depth == 0 then return k end
    end
  end
  return nil
end

-- Balanced group ending at line[i] == close; returns the index of its open.
local function open_of(line, i, open, close)
  local depth = 0
  for k = i, 1, -1 do
    local c = line:sub(k, k)
    if c == close then depth = depth + 1
    elseif c == open then
      depth = depth - 1
      if depth == 0 then return k end
    end
  end
  return nil
end

-- The expression around 1-based column `col` of `line`.
function M.expr_at(line, col, fortran)
  local isw = function(c) return c ~= '' and c:match('[%w_]') ~= nil end
  if not isw(line:sub(col, col)) then
    -- On a bracket or member operator next to an identifier: step onto it.
    if isw(line:sub(col - 1, col - 1)) then col = col - 1 else return nil end
  end
  local s, e = col, col
  while isw(line:sub(s - 1, s - 1)) do s = s - 1 end
  while isw(line:sub(e + 1, e + 1)) do e = e + 1 end
  if line:sub(s, e):match('^%d') then return nil end   -- a number literal

  local idx_open, idx_close = '[', ']'
  if fortran then idx_open, idx_close = '(', ')' end
  local function member_before(k)   -- length of the member operator ending at k, or 0
    if fortran then return line:sub(k, k) == '%' and 1 or 0 end
    if line:sub(k, k) == '.' then return 1 end
    if line:sub(k - 1, k) == '->' then return 2 end
    return 0
  end
  local function member_after(k)    -- length of the member operator starting at k, or 0
    if fortran then return line:sub(k, k) == '%' and 1 or 0 end
    if line:sub(k, k) == '.' then return 1 end
    if line:sub(k, k + 1) == '->' then return 2 end
    return 0
  end

  -- Right: index groups and member chains.
  while true do
    local c = line:sub(e + 1, e + 1)
    if c == idx_open then
      local k = close_of(line, e + 1, idx_open, idx_close)
      if not k then break end
      e = k
    else
      local m = member_after(e + 1)
      if m > 0 and isw(line:sub(e + 1 + m, e + 1 + m)) then
        e = e + m
        while isw(line:sub(e + 1, e + 1)) do e = e + 1 end
      else
        break
      end
    end
  end
  -- Left: member chains (through index groups on the way).
  while true do
    local m = member_before(s - 1)
    if m == 0 then break end
    local k = s - 1 - m
    if line:sub(k, k) == idx_close then
      local o = open_of(line, k, idx_open, idx_close)
      if not o then break end
      k = o - 1
    end
    if not isw(line:sub(k, k)) then break end
    while isw(line:sub(k - 1, k - 1)) do k = k - 1 end
    s = k
  end
  return line:sub(s, e)
end

local function selection_text()
  local ok, lines = pcall(vim.fn.getregion, vim.fn.getpos('v'), vim.fn.getpos('.'),
    { type = vim.fn.mode() })
  if not ok or #lines == 0 then return nil end
  return vim.trim(table.concat(lines, ' '))
end

local function remove()
  for _, path in ipairs(defined) do pcall(vim.cmd, 'silent! aunmenu ' .. path) end
  defined = {}
end

local function define(prio, path, rhs)
  for _, c in ipairs({ 'anoremenu', 'inoremenu', 'vnoremenu' }) do
    vim.cmd(('%s <silent> %s %s %s'):format(c, prio, path, rhs))
  end
  defined[#defined + 1] = path
end

-- Menu-path escaping: spaces and dots are separators, & marks an
-- accelerator, and the label is shortened so the menu stays narrow.
local function esc(text)
  local shown = text
  if vim.fn.strchars(shown) > 40 then shown = vim.fn.strcharpart(shown, 0, 39) .. '…' end
  return (shown:gsub('\\', '\\\\'):gsub('&', '&&'):gsub('([ .|"])', '\\%1'))
end

local function label(expr) return MENU .. ':\\ ' .. esc(expr) end

-- Watches panel: which watch does buffer line `row` belong to? A watch's
-- own line starts with dap-ui's expanded/collapsed icon in column 0; its
-- children (and wrapped value lines) are indented. So walk up to the
-- nearest unindented icon line, and its rank among those lines is the
-- watch's index in dapui.elements.watches.get().
local function watch_at(buf, row)
  local ok, dapui = pcall(require, 'dapui')
  if not ok then return nil end
  local list = dapui.elements.watches.get()
  if #list == 0 then return nil end
  local icons = ((require('dapui.config') or {}).icons) or {}
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local function is_header(l)
    for _, ic in ipairs({ icons.expanded, icons.collapsed }) do
      if ic and ic ~= '' and l:sub(1, #ic + 1) == ic .. ' ' then return true end
    end
    return false
  end
  -- The '> ' input line at the bottom (where a new watch is typed) is not
  -- a watch.
  if (lines[row] or ''):match('^> ') then return nil end
  local header
  for r = math.min(row, #lines), 1, -1 do
    if is_header(lines[r]) then header = r break end
  end
  if not header then return nil end
  local index = 0
  for r = 1, header do if is_header(lines[r]) then index = index + 1 end end
  local w = list[index]
  if not w then return nil end
  return { index = index, expr = w.expression, header_line = header, buf = buf }
end

local function rebuild_watches_panel()
  target = watch_at(vim.api.nvim_get_current_buf(), vim.fn.line('.'))
  local mod = "<Cmd>lua require('features.dap-watch-menu')."
  if target then
    define('1.1', 'PopUp.Remove\\ watch:\\ ' .. esc(target.expr), mod .. "remove_watch()<CR>")
    define('1.2', 'PopUp.Edit\\ watch:\\ ' .. esc(target.expr),   mod .. "edit_watch()<CR>")
  end
  local ok, dapui = pcall(require, 'dapui')
  if ok and #dapui.elements.watches.get() > 0 then
    define('1.3', 'PopUp.Remove\\ all\\ watches', mod .. "remove_all()<CR>")
  end
  if #defined > 0 then
    vim.cmd('anoremenu 1.4 ' .. SEP .. ' <Nop>')
    defined[#defined + 1] = SEP
  end
end

function M.remove_watch()
  if not target then return end
  local dapui = require('dapui')
  -- The panel may have re-rendered since the menu opened; only remove
  -- if that index still holds the same expression.
  local w = dapui.elements.watches.get()[target.index]
  if not w or w.expression ~= target.expr then
    vim.notify('Watch list changed; right-click the watch again.', vim.log.levels.WARN)
    return
  end
  dapui.elements.watches.remove(target.index)
  vim.notify('Removed watch: ' .. target.expr, vim.log.levels.INFO)
end

-- A prompt pre-filled with the expression; <CR> replaces it, <Esc> (or an
-- empty answer) leaves it alone. dap-ui's own edit key only copies the
-- expression into the panel's '> ' input line and waits there, which is
-- easy to miss, so this uses watches.edit(index, new) directly.
function M.edit_watch()
  if not target then return end
  local t = target
  vim.ui.input({ prompt = 'Edit watch: ', default = t.expr }, function(input)
    if input == nil then return end
    input = vim.trim(input)
    if input == '' or input == t.expr then return end
    local dapui = require('dapui')
    local w = dapui.elements.watches.get()[t.index]
    if not w or w.expression ~= t.expr then
      vim.notify('Watch list changed; right-click the watch again.', vim.log.levels.WARN)
      return
    end
    dapui.elements.watches.edit(t.index, input)
    vim.notify('Watch changed: ' .. t.expr .. ' → ' .. input, vim.log.levels.INFO)
  end)
end

function M.remove_all()
  local dapui = require('dapui')
  local n = #dapui.elements.watches.get()
  for i = n, 1, -1 do dapui.elements.watches.remove(i) end
  vim.notify('Removed ' .. n .. ' watch' .. (n == 1 and '' or 'es'), vim.log.levels.INFO)
end

local function rebuild()
  remove()
  pending, target = nil, nil
  if vim.bo.filetype == 'dapui_watches' then return rebuild_watches_panel() end
  if not session_running() then return end
  local mode = vim.fn.mode()
  local expr
  if mode:match('^[vVsS\22\19]') then
    expr = selection_text()
  else
    local ft = vim.bo.filetype
    local fortran = ft == 'fortran' or ft:match('^fortran') ~= nil
    expr = M.expr_at(vim.api.nvim_get_current_line(), vim.fn.col('.'), fortran)
  end
  if not expr or expr == '' then return end
  pending = expr
  -- Priority 1 puts it first; the separator below it, then the usual items.
  -- Plain <Cmd> for insert and visual/select, so the mode (and the
  -- selection) is still there when add() runs.
  define('1.1', label(expr), "<Cmd>lua require('features.dap-watch-menu').add()<CR>")
  vim.cmd('anoremenu 1.2 ' .. SEP .. ' <Nop>')
  defined[#defined + 1] = SEP
end

function M.add()
  local expr = pending
  if not expr then return end
  local ok, dapui = pcall(require, 'dapui')
  if not ok then
    vim.notify('dap-ui is not available', vim.log.levels.WARN)
    return
  end
  dapui.elements.watches.add(expr)
  vim.notify('Watching: ' .. expr, vim.log.levels.INFO)
  local mode = vim.fn.mode()
  if mode:match('^[vVsS\22\19]') then
    vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'n', false)
  end
end

vim.api.nvim_create_autocmd('MenuPopup', {
  desc     = 'Right-click: Add to watches while debugging',
  group    = vim.api.nvim_create_augroup('dap-watch-menu', { clear = true }),
  callback = rebuild,
})

return M
