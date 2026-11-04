-- ============================================================
-- features/border-pointer.lua — Resize pointer over draggable borders
--
-- When the mouse rests on something a drag would resize, the terminal's
-- mouse pointer changes shape:
--   • a vertical separator between side-by-side windows  → ew-resize  ↔
--   • a window's status line (drag to change its height) → ns-resize  ↕
-- and changes back as soon as it leaves.
--
-- Neovim has no pointer-shape control of its own in a terminal. This sends
-- OSC 22 (ESC ] 22 ; <css cursor name> ESC \), which kitty and Ghostty both
-- implement, through nvim_ui_send (0.12+: writes to the TUI's terminal).
-- Other terminals are left alone: the feature only switches on when $TERM
-- or $TERM_PROGRAM names kitty or Ghostty.
--
-- Not shown on status lines that do not resize:
--   • the top bar's carrier window (features/topbar.lua) — its status line
--     is the buffer-tab row;
--   • a compact horizontal scrollbar track (features/hscrollbar.lua) — that
--     status line scrolls the window sideways instead.
-- Floating windows have no draggable border, and with laststatus=3 the
-- single global status line does not resize anything either (getmousepos()
-- reports it as no window).
--
-- Input: vim.on_key, not a <MouseMove> mapping — edge-scroll, hscrollbar
-- and topbar already map <MouseMove>, and only one mapping can win. Needs
-- vim.o.mousemoveevent (core/options.lua sets it).
--
-- :BorderPointerToggle turns it off/on for the session.
-- vim.g.border_pointer_shapes = { vsep = 'col-resize', status = 'row-resize',
-- reset = 'default', shell = 'text' } overrides the shape names (CSS cursor names, which
-- both terminals accept); set it before this file loads (core/options.lua).
-- ============================================================

if vim.g.loaded_border_pointer then return end
vim.g.loaded_border_pointer = true

if not vim.api.nvim_ui_send then return end

local term = ((vim.env.TERM or '') .. ' ' .. (vim.env.TERM_PROGRAM or '')):lower()
local is_ghostty = term:find('ghostty', 1, true) ~= nil
local is_kitty   = term:find('kitty', 1, true) ~= nil
if not (is_ghostty or is_kitty) then return end

-- What "not over a border" goes back to. kitty: an empty name resets to its
-- configured pointer. Ghostty ignores names it does not know, an empty one
-- included, so it is told explicitly: 'default', the arrow it shows while
-- Neovim has the mouse (its 'text' I-beam is only for the plain shell).
-- vim.g.border_pointer_shapes.reset overrides it.
local RESET = (vim.g.border_pointer_shapes or {}).reset or (is_ghostty and 'default' or '')

local enabled = true
local current = RESET   -- last shape sent; nothing is sent until it changes

local function send(shape)
  if shape == current then return end
  current = shape
  pcall(vim.api.nvim_ui_send, '\27]22;' .. shape .. '\27\\')
end

local function shapes()
  local s = vim.g.border_pointer_shapes or {}
  return s.vsep or 'ew-resize', s.status or 'ns-resize'
end

-- What the mouse is over, as a pointer shape (RESET when nothing special).
-- getmousepos() reports a separator or status-line cell as belonging to the
-- window to its left / above, with line = 0 and wincol / winrow one past
-- that window's width / height (:h getmousepos).
local function shape_at()
  local mp = vim.fn.getmousepos()
  local win = mp.winid
  if win == 0 or (mp.line or 0) ~= 0 or not vim.api.nvim_win_is_valid(win) then
    return RESET
  end
  if vim.api.nvim_win_get_config(win).relative ~= '' then return RESET end
  local vsep, status = shapes()

  if mp.wincol == vim.api.nvim_win_get_width(win) + 1 then return vsep end

  if mp.winrow == vim.api.nvim_win_get_height(win) + 1 then
    local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if ft == 'topbar' then return RESET end
    local ok, hs = pcall(require, 'features.hscrollbar')
    if ok and type(hs) == 'table' and hs.is_htrack and hs.is_htrack(mp) then
      return RESET
    end
    return status
  end
  return RESET
end

local K_MOVE    = vim.keycode('<MouseMove>')
local K_RELEASE = vim.keycode('<LeftRelease>')

vim.on_key(function(_, typed)
  if not enabled or not typed then return end
  -- Only plain movement and the end of a drag re-evaluate. During a drag
  -- (<LeftDrag>) the shape is left as it was at the press, so it does not
  -- flicker while the border follows the mouse.
  if typed == K_MOVE or typed == K_RELEASE then
    send(shape_at())
  end
end, vim.api.nvim_create_namespace('border-pointer'))

-- Hand the terminal its normal pointer back whenever Neovim stops owning
-- the mouse: focus moving to another window/app, :suspend, quitting.
-- Back at the shell (quit / :suspend) Ghostty's own pointer is its 'text'
-- I-beam, not the arrow it shows over Neovim, so that is what it gets.
local SHELL = (vim.g.border_pointer_shapes or {}).shell or (is_ghostty and 'text' or '')
local group = vim.api.nvim_create_augroup('border-pointer', { clear = true })
vim.api.nvim_create_autocmd('FocusLost', {
  group = group, callback = function() send(RESET) end,
})
vim.api.nvim_create_autocmd({ 'VimSuspend', 'VimLeavePre' }, {
  group = group, callback = function() send(SHELL) end,
})
-- Back from :suspend: the shell's shape is still set; forget it so the next
-- move re-sends the right one.
vim.api.nvim_create_autocmd('VimResume', {
  group = group, callback = function() current = SHELL end,
})

vim.api.nvim_create_user_command('BorderPointerToggle', function()
  enabled = not enabled
  if not enabled then send(RESET) end
  vim.notify('Resize pointer over borders: ' .. (enabled and 'on' or 'off'))
end, { desc = 'Toggle the resize mouse pointer over window borders' })
