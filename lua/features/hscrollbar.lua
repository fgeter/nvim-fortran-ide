-- ============================================================
-- features/hscrollbar.lua — Scrollbars for buffer windows
--
-- Horizontal: shown when wrap=false and a line is wider than the window.
--   Two layouts, picked by 'laststatus' (see compact_h):
--   • laststatus<3 — the editor's own statusline row *is* the track
--     (___hscroll_track), and the bar window below it is squeezed to zero
--     height so it contributes only its statusline, which renders the
--     editor's status (___hscroll_status). Two rows, both carrying
--     something: track, then status below it. The editor's statusline
--     would otherwise sit between the text and the track saying nothing.
--   • laststatus=3 — no window has a statusline to borrow, so the bar is a
--     1-row split whose *buffer* holds the track, and the single global
--     status line is already below it.
-- Vertical: two layers, because a float opened before the TUI attaches
--   is in the window list (and receives clicks) but is often missing from
--   the first painted frame — you had to click the empty right edge to
--   "reveal" it.
--   1. A decoration provider paints the track/thumb in the editor itself,
--      so the bar is on the first frame of a long file.
--   2. A 1-col float on the right of the pane (one cell in from the
--      window edge — the last TUI column often does not receive mouse
--      events). Not torn down after startup, not reconfigured while
--      dragging.
--
-- Click/drag: a global <LeftMouse> hit-test starts a drag on button-down; MouseMove
-- (via edge-scroll.lua) and <LeftDrag> update the view until release.
-- Drag (vertical or horizontal) scrolls a covering copy of the window.
-- The real cursor stays put. Horizontal uses the overlay so leftcol is
-- not clamped to the cursor line — the range is the file's longest line.
-- On release the copy stays on screen (click a line to move the cursor
-- there; a key returns to the cursor's line).
-- ============================================================

local BAR_FT = 'hscroll'
-- One cell, one column in from the window edge. The last column of a TUI
-- window often does not get mouse events, so a 2-col bar looked grab-able
-- on the far right but that half never started a drag.
local VBAR_W      = 1
local VBAR_INSET  = 1
local VBAR_THUMB  = '█'
local VBAR_TRACK  = '│'
local VBAR_CURSOR = '◆'

local function vbar_col0(width)
  return math.max(0, width - VBAR_W - VBAR_INSET)
end

local excluded_ft = { ['neo-tree'] = true, ['toggleterm'] = true,
                      ['help'] = true, ['TelescopePrompt'] = true,
                      ['topbar'] = true, [BAR_FT] = true }
local excluded_bt = { terminal = true, prompt = true, nofile = true }

local maxlen    = {}  -- bufnr → max display width
local hbars     = {}  -- parent winid → { win, buf }
local vbars     = {}  -- parent winid → { win, buf }
local parent_of = {}  -- bar winid → parent winid
local kind_of    = {}  -- bar winid → 'h' | 'v' | 'view'
local viewports  = {}  -- parent winid → { win }
local drag       = nil -- { win, grab, kind, bar }
local creating  = false
local saved_so  = {}  -- parent winid → scrolloff to restore after a vertical drag
local drag_cul  = {}  -- parent winid → cursorline to restore after a vertical drag
local cur_hist  = {}  -- winid → { prev = {lnum,col}, last = {lnum,col} }
local saved_stl = {}  -- parent winid → its local 'statusline' before the swap
local vbar_ns   = vim.api.nvim_create_namespace('hscroll_vbar')
local hbar_ns   = vim.api.nvim_create_namespace('hscroll_hbar')

-- Compact layout: the editor's own statusline row *is* the track, and the
-- bar window is squeezed to zero height so it contributes only its own
-- statusline, which carries the status. Two rows of chrome, both useful:
--
--     text … │ ▄▄▄▄ track │ NORMAL  init.lua  main  1:1
--
-- The alternative — track as buffer content in a one-row split — leaves the
-- editor's statusline stranded between the text and the track with nothing
-- to say. It is still the layout under laststatus=3, where windows have no
-- statusline of their own to borrow.
local function compact_h()
  return vim.o.laststatus ~= 3
end

local function flush_win(win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim__redraw, { win = win, valid = false, flush = true })
  end
end

local function setup_highlights()
  local function attr(group, key)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    return ok and hl and hl[key] or nil
  end
  local thumb = attr('WinSeparator', 'fg') or attr('Function', 'fg')
  local track = attr('Comment', 'fg')
  local bg    = attr('CursorLine', 'bg')
  -- Must not use CursorLineNr: in this colorscheme it is the same lavender
  -- as WinSeparator, so a cursor mark on the thumb was invisible.
  local cursor = attr('DiagnosticWarn', 'fg') or attr('WarningMsg', 'fg') or attr('String', 'fg')
  vim.api.nvim_set_hl(0, 'HScrollTrack', { fg = track, bg = bg })
  vim.api.nvim_set_hl(0, 'HScrollThumb', { fg = thumb, bg = thumb, bold = true })
  vim.api.nvim_set_hl(0, 'HScrollCursor', { fg = cursor, bg = cursor, bold = true })
end

setup_highlights()
vim.api.nvim_create_autocmd('ColorScheme', {
  group    = vim.api.nvim_create_augroup('hscrollbar-hl', { clear = true }),
  callback = setup_highlights,
})

local function get_maxlen(bufnr)
  if maxlen[bufnr] then return maxlen[bufnr] end
  local max = 0
  for _, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local ok, w = pcall(vim.fn.strdisplaywidth, l)
    if ok and w > max then max = w end
  end
  maxlen[bufnr] = max
  return max
end

local function is_bar_win(win)
  if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then return false end
  return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == BAR_FT
end

-- Neovim moves the cursor to the click, THEN runs the mapping. Remember
-- the previous position so a bar click can put it back.
local function remember_cursor(win)
  if vim.g.hscroll_dragging then return end
  win = win or vim.api.nvim_get_current_win()
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  if is_bar_win(win) then return end
  local ok, cur = pcall(vim.api.nvim_win_get_cursor, win)
  if not ok or not cur then return end
  local h = cur_hist[win]
  if h and h.last and h.last[1] == cur[1] and h.last[2] == cur[2] then return end
  cur_hist[win] = { prev = h and h.last or nil, last = { cur[1], cur[2] } }
end

local function cursor_before_mouse(win)
  local ok, now = pcall(vim.api.nvim_win_get_cursor, win)
  if not ok or not now then return { 1, 0 } end
  local h = cur_hist[win]
  if h and h.last and h.last[1] == now[1] and h.last[2] == now[2] and h.prev then
    return { h.prev[1], h.prev[2] }
  end
  if h and h.last then return { h.last[1], h.last[2] } end
  return { now[1], now[2] }
end

local function eligible(winid)
  if not vim.api.nvim_win_is_valid(winid) then return false end
  if vim.api.nvim_win_get_config(winid).relative ~= '' then return false end
  if is_bar_win(winid) then return false end
  if kind_of[winid] == 'view' then return false end
  local bufnr = vim.api.nvim_win_get_buf(winid)
  if excluded_ft[vim.bo[bufnr].filetype] or excluded_bt[vim.bo[bufnr].buftype] then
    return false
  end
  return true
end

local function view_win(parent)
  local vp = viewports[parent]
  if vp and vim.api.nvim_win_is_valid(vp.win) then return vp.win end
  return parent
end

local function close_viewport(parent)
  local vp = viewports[parent]
  viewports[parent] = nil
  if not vp then return end
  parent_of[vp.win] = nil
  kind_of[vp.win] = nil
  if vim.api.nvim_win_is_valid(vp.win) then
    pcall(vim.api.nvim_win_close, vp.win, true)
  end
end

local function place_viewport(parent)
  local vp = viewports[parent]
  if not vp or not vim.api.nvim_win_is_valid(vp.win) then return end
  if not vim.api.nvim_win_is_valid(parent) then close_viewport(parent); return end
  local ph = math.max(1, vim.api.nvim_win_get_height(parent))
  local pw = vim.api.nvim_win_get_width(parent)
  pcall(vim.api.nvim_win_set_config, vp.win, {
    relative = 'win',
    win      = parent,
    anchor   = 'NW',
    row      = 0,
    col      = 0,
    width    = pw,
    height   = ph,
  })
end

local function ensure_viewport(parent)
  if not vim.api.nvim_win_is_valid(parent) then return nil end
  local vp = viewports[parent]
  if vp and vim.api.nvim_win_is_valid(vp.win) then
    place_viewport(parent)
    return vp.win
  end
  local buf = vim.api.nvim_win_get_buf(parent)
  local ph = math.max(1, vim.api.nvim_win_get_height(parent))
  local pw = vim.api.nvim_win_get_width(parent)
  creating = true
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
    relative  = 'win',
    win       = parent,
    anchor    = 'NW',
    row       = 0,
    col       = 0,
    width     = pw,
    height    = ph,
    focusable = false,
    mouse     = true,
    zindex    = 35,
    border    = 'none',
  })
  creating = false
  if not ok then return nil end
  viewports[parent] = { win = win }
  parent_of[win] = parent
  kind_of[win] = 'view'
  vim.wo[win].number         = vim.wo[parent].number
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn     = vim.wo[parent].signcolumn
  vim.wo[win].foldcolumn     = vim.wo[parent].foldcolumn
  vim.wo[win].statuscolumn   = vim.wo[parent].statuscolumn
  vim.wo[win].list           = vim.wo[parent].list
  vim.wo[win].wrap           = vim.wo[parent].wrap
  vim.wo[win].cursorline     = false
  vim.wo[win].winbar         = ''
  vim.wo[win].scrolloff      = 0
  vim.wo[win].sidescrolloff  = 0
  -- virtualedit=all lets leftcol travel the longest line even when the
  -- cursor sits on a short one. Keep it for the life of the overlay.
  vim.wo[win].virtualedit    = 'all'
  -- Opaque so the real window (still at the cursor) cannot show through.
  vim.wo[win].winhighlight   = 'Normal:NormalFloat,EndOfBuffer:NormalFloat,SignColumn:NormalFloat'
  local view = vim.api.nvim_win_call(parent, vim.fn.winsaveview)
  vim.api.nvim_win_call(win, function()
    vim.wo.scrolloff = 0
    pcall(vim.fn.winrestview, view)
  end)
  return win
end

local function click_viewport(mp)
  local win = mp.winid
  if win == 0 or kind_of[win] ~= 'view' then return false end
  local parent = parent_of[win]
  if not parent or not vim.api.nvim_win_is_valid(parent) then return false end
  local info = vim.fn.getwininfo(win)[1]
  local buf  = vim.api.nvim_win_get_buf(parent)
  local n    = vim.api.nvim_buf_line_count(buf)
  local lnum = (mp.line and mp.line > 0) and mp.line
    or math.max(1, math.min(n, (info.topline or 1) + (mp.winrow or 1) - 1))
  local col  = (mp.column and mp.column > 0) and math.max(0, mp.column - 1)
    or math.max(0, (mp.wincol or 1) - 1)
  local top  = info.topline
  local left = info.leftcol or 0
  close_viewport(parent)
  pcall(vim.api.nvim_win_set_cursor, parent, { lnum, col })
  vim.api.nvim_win_call(parent, function()
    pcall(vim.fn.winrestview, { topline = top, lnum = lnum, col = col, leftcol = left })
  end)
  return true
end

local function hgeom(parent)
  local bufnr  = vim.api.nvim_win_get_buf(parent)
  local pinfo  = vim.fn.getwininfo(parent)[1]
  local vinfo  = vim.fn.getwininfo(view_win(parent))[1] or pinfo
  local text_w = math.max(1, pinfo.width - pinfo.textoff)
  local win_w  = vim.api.nvim_win_get_width(parent)
  local ml     = get_maxlen(bufnr)
  local max_left = math.max(0, ml - text_w)
  local leftcol  = vinfo.leftcol or 0
  local thumb_w  = math.max(1, math.min(win_w, math.floor(win_w * text_w / math.max(ml, 1))))
  local track    = math.max(0, win_w - thumb_w)
  local thumb_off = (max_left > 0 and track > 0)
    and math.floor(leftcol * track / max_left) or 0
  thumb_off = math.max(0, math.min(track, thumb_off))
  return {
    text_w = text_w, win_w = win_w, ml = ml, max_left = max_left,
    thumb_w = thumb_w, track = track, thumb_off = thumb_off,
  }
end

local function vgeom(parent)
  local bufnr  = vim.api.nvim_win_get_buf(parent)
  local info   = vim.fn.getwininfo(view_win(parent))[1]
  local n      = vim.api.nvim_buf_line_count(bufnr)
  if not info then
    return {
      n = n, height = 1, max_top = 0, topline = 1,
      thumb_h = 1, track = 0, thumb_off = 0, cursor_off = 0,
      text_w = 1, win_w = 1, textoff = 0,
    }
  end
  local height = math.max(1, info.height)
  local max_top = math.max(0, n - height)
  local thumb_h = math.max(1, math.min(height, math.floor(height * height / math.max(n, 1))))
  local track   = math.max(0, height - thumb_h)
  local thumb_off = (max_top > 0 and track > 0)
    and math.floor((info.topline - 1) * track / max_top) or 0
  thumb_off = math.max(0, math.min(track, thumb_off))
  local lnum = 1
  local okc, cur = pcall(vim.api.nvim_win_get_cursor, parent)
  if okc and cur then lnum = cur[1] end
  local cursor_off = 0
  if n > 1 and height > 1 then
    cursor_off = math.floor((lnum - 1) * (height - 1) / (n - 1))
  end
  cursor_off = math.max(0, math.min(height - 1, cursor_off))
  local text_w = math.max(1, info.width - info.textoff)
  return {
    n = n, height = height, max_top = max_top, topline = info.topline,
    thumb_h = thumb_h, track = track, thumb_off = thumb_off,
    cursor_off = cursor_off,
    text_w = text_w, win_w = info.width, textoff = info.textoff,
  }
end

-- row is 1-based. Cursor mark sits on top of the viewport thumb.
local function vbar_cell(row, g)
  if g.cursor_off ~= nil and row == g.cursor_off + 1 then
    return VBAR_CURSOR, 'HScrollCursor'
  end
  if row > g.thumb_off and row <= g.thumb_off + (g.thumb_h or 1) then
    return VBAR_THUMB, 'HScrollThumb'
  end
  return VBAR_TRACK, 'HScrollTrack'
end

-- Painted into the editor so the bar is on the first TUI frame even when
-- the companion float has not been drawn yet (startup with a long file).
vim.api.nvim_set_decoration_provider(vbar_ns, {
  on_win = function(_, win, buf, topline, botline)
    if not eligible(win) then return false end
    local ok, g = pcall(vgeom, win)
    if not ok or not g or g.max_top <= 0 then return false end
    local col = vbar_col0(g.text_w)
    for lnum = topline, botline - 1 do
      local row = lnum - topline
      local ch, hl = vbar_cell(row + 1, g)
      pcall(vim.api.nvim_buf_set_extmark, buf, vbar_ns, lnum, 0, {
        virt_text         = { { ch, hl } },
        virt_text_pos     = 'overlay',
        virt_text_win_col = col,
        ephemeral         = true,
        hl_mode           = 'replace',
      })
    end
    return false
  end,
})

local function off_to_value(track, max_value, off)
  if track <= 0 or max_value <= 0 then return 0 end
  off = math.max(0, math.min(track, off))
  return math.floor(off * max_value / track)
end

-- Neovim never hides the cursor, so winrestview({leftcol=…}) is clamped to
-- the current line. Scroll the covering viewport instead: virtualedit=all
-- keeps virtcol on screen even when that line is short, so the range is
-- the file's longest line. The parent cursor is not moved.
local function set_leftcol(parent, leftcol)
  local win = view_win(parent)
  vim.api.nvim_win_call(win, function()
    local info   = vim.fn.getwininfo(win)[1]
    local text_w = math.max(1, info.width - info.textoff)
    local target = math.max(0, leftcol)
    local topline = info.topline

    vim.wo.virtualedit   = 'all'
    vim.wo.sidescrolloff = 0
    vim.wo.scrolloff     = 0

    local lo = target + 1
    local hi = target + text_w
    if hi < lo then hi = lo end
    local cur = vim.fn.virtcol('.')
    local new_virt = cur
    if cur < lo then new_virt = lo
    elseif cur > hi then new_virt = hi
    end
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local ei = vim.go.eventignore
    vim.go.eventignore = 'all'
    -- Do not use :normal! N| — vim.cmd treats | as an Ex separator, so
    -- the virtcol move never ran and leftcol stayed clamped.
    pcall(vim.fn.winrestview, {
      lnum    = lnum,
      col     = 0,
      coladd  = math.max(0, new_virt - 1),
      leftcol = target,
      topline = topline,
    })
    vim.go.eventignore = ei
  end)
end

-- Scroll the covering viewport, not the real window. The viewport has
-- its own cursor so the file can travel the full range; the user's
-- cursor in the parent is left alone.
local function set_topline(parent, topline)
  local win = view_win(parent)
  vim.api.nvim_win_call(win, function()
    vim.wo.scrolloff = 0
    local height = (drag and drag.height) or vim.api.nvim_win_get_height(0)
    local n      = (drag and drag.n) or vim.api.nvim_buf_line_count(0)
    local max_t  = math.max(1, n - height + 1)
    local target = math.max(1, math.min(topline, max_t))
    if drag and drag.last == target then return end
    local cur = vim.api.nvim_win_get_cursor(0)
    local bot = math.min(n, target + height - 1)
    local ei = vim.go.eventignore
    vim.go.eventignore = 'all'
    pcall(function()
      if cur[1] < target then
        vim.api.nvim_win_set_cursor(0, { target, cur[2] })
      elseif cur[1] > bot then
        vim.api.nvim_win_set_cursor(0, { bot, cur[2] })
      end
      vim.fn.winrestview({ topline = target })
    end)
    vim.go.eventignore = ei
    if drag then drag.last = target end
  end)
end

local function x_in_win(winid, mp)
  local pos = vim.api.nvim_win_get_position(winid)
  return (mp.screencol - 1) - pos[2]
end

-- Mouse row in the vertical bar (or the parent editor, if the click
-- landed on the last columns of the file instead of the float).
local function v_mouse_y(bar, mp, parent)
  local win = (bar and vim.api.nvim_win_is_valid(bar)) and bar or parent
  if not win or not vim.api.nvim_win_is_valid(win) then
    return math.max(0, (mp.winrow or 1) - 1)
  end
  local pos = vim.api.nvim_win_get_position(win)
  local h   = vim.api.nvim_win_get_height(win)
  local y   = (mp.screenrow - 1) - pos[1]
  if y < 0 then return 0 end
  if y >= h then return h - 1 end
  return y
end

local function dedupe_bar_buf(keep_win, buf)
  if not keep_win or not buf then return end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= keep_win and vim.api.nvim_win_is_valid(w)
        and vim.api.nvim_win_get_buf(w) == buf then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
end

local function cfg_num(v)
  if type(v) == 'table' then return v[1] end
  return v
end

local function place_vbar(parent)
  local e = vbars[parent]
  if not e or not vim.api.nvim_win_is_valid(e.win) then return end
  if not vim.api.nvim_win_is_valid(parent) then return end
  local ph = math.max(1, vim.api.nvim_win_get_height(parent))
  local pw = vim.api.nvim_win_get_width(parent)
  local col = vbar_col0(pw)
  local cfg = vim.api.nvim_win_get_config(e.win)
  if cfg.relative == 'win'
      and cfg.width == VBAR_W and cfg.height == ph
      and cfg_num(cfg.row) == 0 and cfg_num(cfg.col) == col then
    return
  end
  pcall(vim.api.nvim_win_set_config, e.win, {
    relative = 'win',
    win      = parent,
    anchor   = 'NW',
    row      = 0,
    col      = col,
    width    = VBAR_W,
    height   = ph,
  })
end

local function paint_vbar(parent, opts)
  opts = opts or {}
  local e = vbars[parent]
  if not e or not vim.api.nvim_win_is_valid(e.win) then return end
  -- Reconfiguring the float mid-drag drops the mouse grab and stutters.
  if not opts.dragging then
    place_vbar(parent)
  end
  local g = opts.g or vgeom(parent)
  local h = math.max(1, vim.api.nvim_win_get_height(e.win))
  if e.thumb_off == g.thumb_off and e.thumb_h == g.thumb_h
      and e.cursor_off == g.cursor_off and e.h == h then
    return
  end
  local lines = {}
  local hls = {}
  for i = 1, h do
    local ch, hl = vbar_cell(i, g)
    lines[i], hls[i] = ch, hl
  end
  vim.bo[e.buf].modifiable = true
  vim.api.nvim_buf_set_lines(e.buf, 0, -1, false, lines)
  vim.bo[e.buf].modifiable = false
  pcall(vim.api.nvim_buf_clear_namespace, e.buf, vbar_ns, 0, -1)
  for i = 1, h do
    pcall(vim.api.nvim_buf_add_highlight, e.buf, vbar_ns, hls[i], i - 1, 0, -1)
  end
  e.thumb_off, e.thumb_h, e.cursor_off, e.h = g.thumb_off, g.thumb_h, g.cursor_off, h
  if not opts.dragging then
    dedupe_bar_buf(e.win, e.buf)
  end
end

-- ─ and █ are both 3-byte UTF-8, one cell wide.
local function paint_hbar(parent)
  local e = hbars[parent]
  if not e or not vim.api.nvim_win_is_valid(e.win) then return end
  -- Compact layout draws the track from ___hscroll_track on redraw; there is
  -- no buffer line to repaint, only a statusline to re-evaluate.
  if compact_h() then
    e.line = nil
    pcall(vim.cmd, 'redrawstatus')
    return
  end
  local g = hgeom(parent)
  local w = math.max(1, vim.api.nvim_win_get_width(e.win))
  local left_n, mid_n
  if g.ml <= g.text_w then
    left_n, mid_n = 0, 0
  else
    left_n = math.max(0, math.min(w, g.thumb_off))
    mid_n  = math.max(1, math.min(w - left_n, g.thumb_w))
  end
  local right_n = math.max(0, w - left_n - mid_n)
  local line = string.rep('─', left_n) .. string.rep('█', mid_n) .. string.rep('─', right_n)
  if e.line == line then return end
  e.line = line
  vim.bo[e.buf].modifiable = true
  vim.api.nvim_buf_set_lines(e.buf, 0, -1, false, { line })
  vim.bo[e.buf].modifiable = false
  pcall(vim.api.nvim_buf_clear_namespace, e.buf, hbar_ns, 0, -1)
  local b0 = left_n * 3
  local b1 = (left_n + mid_n) * 3
  if left_n > 0 then
    pcall(vim.api.nvim_buf_add_highlight, e.buf, hbar_ns, 'HScrollTrack', 0, 0, b0)
  end
  if mid_n > 0 then
    pcall(vim.api.nvim_buf_add_highlight, e.buf, hbar_ns, 'HScrollThumb', 0, b0, b1)
  end
  if right_n > 0 then
    pcall(vim.api.nvim_buf_add_highlight, e.buf, hbar_ns, 'HScrollTrack', 0, b1, -1)
  end
end

local function apply_drag_now()
  if not drag or not vim.api.nvim_win_is_valid(drag.win) then return end
  local mp = vim.fn.getmousepos()
  if drag.kind == 'v' then
    if (drag.max_top or 0) <= 0 then return end
    local y = v_mouse_y(drag.bar, mp, drag.win)
    local target = 1 + off_to_value(drag.track, drag.max_top, y - drag.grab)
    if drag.last == target then return end
    set_topline(drag.win, target)
    local thumb_off = 0
    if drag.track > 0 and drag.max_top > 0 then
      thumb_off = math.max(0, math.min(drag.track,
        math.floor((target - 1) * drag.track / drag.max_top)))
    end
    paint_vbar(drag.win, {
      dragging = true,
      g = {
        thumb_off  = thumb_off,
        thumb_h    = drag.thumb_h or 1,
        cursor_off = drag.cursor_off,
      },
    })
  else
    local g = hgeom(drag.win)
    if g.ml <= g.text_w then return end
    local x = x_in_win(drag.win, mp)
    set_leftcol(drag.win, off_to_value(g.track, g.max_left, x - drag.grab))
    paint_hbar(drag.win)
  end
end

-- LeftDrag, buffer-local MouseMove, and the global <MouseMove> (edge-scroll)
-- can all fire for one pointer move. Run once now, fold the rest into the
-- next event-loop tick.
local function apply_drag()
  if not drag then return end
  if drag.pending then
    drag.dirty = true
    return
  end
  drag.pending = true
  apply_drag_now()
  vim.schedule(function()
    if not drag then return end
    drag.pending = false
    if drag.dirty then
      drag.dirty = false
      apply_drag()
    end
  end)
end

local function raise_viewport(parent)
  local vp = viewports[parent]
  if not vp or not vim.api.nvim_win_is_valid(vp.win) then return end
  if not vim.api.nvim_win_is_valid(parent) then return end
  local ph = math.max(1, vim.api.nvim_win_get_height(parent))
  local pw = vim.api.nvim_win_get_width(parent)
  pcall(vim.api.nvim_win_set_config, vp.win, {
    relative = 'win',
    win      = parent,
    anchor   = 'NW',
    row      = 0,
    col      = 0,
    width    = pw,
    height   = ph,
    zindex   = 38,
  })
end

local function end_drag()
  local parent    = drag and drag.win
  local orig_lnum = drag and drag.orig_lnum
  local orig_col  = drag and drag.orig_col
  local kind      = drag and drag.kind
  drag = nil
  vim.g.hscroll_dragging = false
  for _, mode in ipairs({ 'n', 'x', 'i' }) do
    pcall(vim.keymap.del, mode, '<LeftDrag>')
    pcall(vim.keymap.del, mode, '<LeftRelease>')
  end
  if parent and vim.api.nvim_win_is_valid(parent) then
    if drag_cul[parent] ~= nil then
      vim.wo[parent].cursorline = drag_cul[parent]
      drag_cul[parent] = nil
    end
    -- Do not copy the preview onto the real window: that parks the cursor
    -- in the new view. Keep the covering copy, restore the real cursor.
    if orig_lnum then
      pcall(vim.api.nvim_win_set_cursor, parent, { orig_lnum, orig_col or 0 })
    end
    pcall(vim.api.nvim_set_current_win, parent)
    if kind == 'v' or kind == 'h' then
      raise_viewport(parent)
      if kind == 'v' and vbars[parent] then paint_vbar(parent) end
      if kind == 'h' and hbars[parent] then paint_hbar(parent) end
    end
  end
end

local function start_drag(parent, grab, kind, bar, orig_lnum, orig_col)
  local g = (kind == 'v') and vgeom(parent) or nil
  if not orig_lnum then
    local orig = cursor_before_mouse(parent)
    orig_lnum, orig_col = orig[1], orig[2]
  end
  drag = {
    win = parent, grab = grab, kind = kind, bar = bar,
    pending = false, dirty = false, last = nil,
    height = g and g.height, n = g and g.n,
    track = g and g.track, max_top = g and g.max_top,
    thumb_h = g and g.thumb_h, cursor_off = g and g.cursor_off,
    orig_lnum = orig_lnum, orig_col = orig_col,
  }
  vim.g.hscroll_dragging = true
  if kind == 'v' or kind == 'h' then
    drag_cul[parent] = vim.wo[parent].cursorline
    vim.wo[parent].cursorline = false
  end
  for _, mode in ipairs({ 'n', 'x', 'i' }) do
    vim.keymap.set(mode, '<LeftDrag>', apply_drag,
      { silent = true, nowait = true, desc = 'Scroll: drag' })
    vim.keymap.set(mode, '<LeftRelease>', end_drag,
      { silent = true, nowait = true, desc = 'Scroll: end drag' })
  end
end

local function begin_h(parent, mp)
  local g = hgeom(parent)
  if g.ml <= g.text_w then return end
  local orig = cursor_before_mouse(parent)
  vim.g.hscroll_dragging = true
  pcall(vim.api.nvim_win_set_cursor, parent, orig)
  ensure_viewport(parent)
  g = hgeom(parent)
  local x = x_in_win(parent, mp)
  local grab
  if x >= g.thumb_off and x < g.thumb_off + g.thumb_w then
    grab = x - g.thumb_off
  else
    grab = math.floor(g.thumb_w / 2)
    set_leftcol(parent, off_to_value(g.track, g.max_left, x - grab))
    paint_hbar(parent)
  end
  local bar = hbars[parent] and hbars[parent].win
  start_drag(parent, grab, 'h', bar, orig[1], orig[2])
end

local function begin_v(parent, mp, bar)
  -- Cursor is already on the bar column (Neovim moves it before the map).
  -- Capture the real position first, then freeze it so remember_cursor
  -- does not treat the restore as a new move.
  local orig = cursor_before_mouse(parent)
  vim.g.hscroll_dragging = true
  pcall(vim.api.nvim_win_set_cursor, parent, orig)
  ensure_viewport(parent)
  local g = vgeom(parent)
  if g.max_top <= 0 then
    vim.g.hscroll_dragging = false
    close_viewport(parent)
    return
  end
  local y = v_mouse_y(bar, mp, parent)
  local grab
  if y >= g.thumb_off and y < g.thumb_off + g.thumb_h then
    grab = y - g.thumb_off
  else
    grab = math.floor(g.thumb_h / 2)
  end
  start_drag(parent, grab, 'v', bar, orig[1], orig[2])
  if y < g.thumb_off or y >= g.thumb_off + g.thumb_h then
    local t = 1 + off_to_value(g.track, g.max_top, y - grab)
    set_topline(parent, t)
    local thumb_off = 0
    if g.track > 0 and g.max_top > 0 then
      thumb_off = math.max(0, math.min(g.track, math.floor((t - 1) * g.track / g.max_top)))
    end
    paint_vbar(parent, {
      dragging = true,
      g = { thumb_off = thumb_off, thumb_h = g.thumb_h, cursor_off = drag and drag.cursor_off },
    })
  end
end

local function on_drag()
  apply_drag()
  return true
end

-- Hit-test the compact horizontal track, which is an editor window's own
-- statusline row. getmousepos() reports that row as belonging to the window
-- above it with "line" and "column" zero (:h getmousepos); winrow one past
-- the window height is what separates it from the '~' filler rows inside the
-- window, which also report line = 0.
local function htrack_hit(mp)
  if not compact_h() then return nil end
  local win = mp.winid
  if win == 0 or not hbars[win] or not vim.api.nvim_win_is_valid(win) then return nil end
  if (mp.line or 0) ~= 0 then return nil end
  if (mp.winrow or 0) ~= vim.api.nvim_win_get_height(win) + 1 then return nil end
  return win
end

local function press_on_bar()
  local mp = vim.fn.getmousepos()
  local win = mp.winid
  local htrack = htrack_hit(mp)
  if htrack then
    if vim.fn.mode():match('^i') then vim.cmd('stopinsert') end
    begin_h(htrack, mp)
    return true
  end
  if win == 0 or not is_bar_win(win) then return false end
  local parent = parent_of[win]
  if not parent or not vim.api.nvim_win_is_valid(parent) then return false end
  if kind_of[win] == 'v' then
    if vim.fn.mode():match('^i') then vim.cmd('stopinsert') end
    begin_v(parent, mp, win)
    return true
  end
  -- Compact layout: the h-bar window's only row is the status line it
  -- carries, not the track. Leave that click alone.
  if compact_h() then return false end
  if vim.fn.mode():match('^i') then vim.cmd('stopinsert') end
  begin_h(parent, mp)
  return true
end

-- Hit-test the vertical track by screen position, not just getmousepos().winid.
-- The float sits on the last columns and, when it swallowed the click
-- (mouse=true, focusable=false), winid was the float or 0 — so a click
-- "too far right" never started a drag. Include those cells, plus one
-- column past the editor (the sliver users actually click).
local function vbar_hit(mp)
  if mp.winid ~= 0 and kind_of[mp.winid] == 'v' then
    local parent = parent_of[mp.winid]
    if parent and vim.api.nvim_win_is_valid(parent) then
      return parent, mp.winid
    end
  end
  if mp.winid ~= 0 and eligible(mp.winid) then
    local info = vim.fn.getwininfo(mp.winid)[1]
    local left = info.width - VBAR_INSET - VBAR_W + 1
    local right = info.width - VBAR_INSET
    if mp.wincol >= left and mp.wincol <= right then
      local g = vgeom(mp.winid)
      if g.max_top > 0 then
        return mp.winid, vbars[mp.winid] and vbars[mp.winid].win
      end
    end
  end
  local col0, row0 = mp.screencol - 1, mp.screenrow - 1
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if eligible(win) then
      local g = vgeom(win)
      if g.max_top > 0 then
        local pos = vim.api.nvim_win_get_position(win)
        local w   = vim.api.nvim_win_get_width(win)
        local h   = vim.api.nvim_win_get_height(win)
        local bar = pos[2] + vbar_col0(w)
        if row0 >= pos[1] and row0 < pos[1] + h
            and col0 >= bar and col0 < bar + VBAR_W then
          return win, vbars[win] and vbars[win].win
        end
      end
    end
  end
  return nil
end

local function press_on_vtrack()
  local mp = vim.fn.getmousepos()
  local parent, bar = vbar_hit(mp)
  if not parent then return false end
  if vim.fn.mode():match('^i') then vim.cmd('stopinsert') end
  begin_v(parent, mp, bar)
  return true
end

-- Consume the click only on the scrollbar. Returning <LeftMouse> for
-- everything else keeps Neovim's click-count so neo-tree still sees
-- <2-LeftMouse>. Do not fire the default click on the bar: that would
-- move the cursor to the right edge (the bar column).
-- Insert mode is mapped too: the compact track is the editor's own
-- statusline row, so it is no longer covered by the bar buffer's own
-- <LeftMouse> maps (which did include insert mode). press_on_bar leaves
-- insert mode before starting a drag.
vim.keymap.set({ 'n', 'x', 'i' }, '<LeftMouse>', function()
  local mp = vim.fn.getmousepos()
  local kind = mp.winid ~= 0 and kind_of[mp.winid] or nil
  -- In the compact layout a click on the h-bar window is a click on the
  -- status line, which keeps its normal behaviour (dragging it resizes).
  local on_bar = kind == 'v' or kind == 'view' or (kind == 'h' and not compact_h())
  if on_bar or htrack_hit(mp) or vbar_hit(mp) then
    return '<Cmd>lua require("features.hscrollbar").on_left_mouse()<CR>'
  end
  return '<LeftMouse>'
end, { expr = true, silent = true, desc = 'Scroll: maybe start drag' })

-- ── Status line placement ────────────────────────────────────
-- The horizontal bar is a split *below* the editor window, so with
-- per-window statuslines (laststatus=2, which features/topbar.lua needs —
-- see core/options.lua) the editor's own statusline would land between the
-- text and the track, i.e. status line above the scroll bar. Swap the two
-- chrome rows instead: the editor's statusline becomes the plain separator
-- rule this config draws everywhere else, and the bar window's statusline
-- carries the editor's mini.statusline content, so the rows read
--
--     text … │ rule │ ▄▄▄▄ track │ NORMAL  init.lua  main  1:1
--
-- With laststatus=3 there is no per-window statusline to swap: the single
-- global one is already below the track, which is where it belongs.
-- The track, as a statusline for the editor window it belongs to. Recomputed
-- on every redraw from hgeom, so no painting or invalidation is needed —
-- during a drag a redrawstatus is enough. Clicks are not %@ regions: a
-- completed click cannot drag, so the global <LeftMouse> hit-test in
-- htrack_hit owns this row (that is what press_on_bar does for the vertical
-- float too).
function _G.___hscroll_track()
  local win = tonumber(vim.g.statusline_winid)
  if not win or not vim.api.nvim_win_is_valid(win) then return '' end
  if not hbars[win] then return '' end
  local g = hgeom(win)
  if g.ml <= g.text_w then return '' end
  local left  = math.max(0, math.min(g.win_w, g.thumb_off))
  local mid   = math.max(1, math.min(g.win_w - left, g.thumb_w))
  local right = math.max(0, g.win_w - left - mid)
  return '%#HScrollTrack#' .. string.rep('─', left)
    .. '%#HScrollThumb#' .. string.rep('█', mid)
    .. '%#HScrollTrack#' .. string.rep('─', right)
end

-- Statusline expression for a bar window: renders the *parent* editor's
-- mini.statusline.
--
-- Two steps, and both are needed. mini's content is built inside the parent
-- window so its sections (mode, git head, diagnostics, is_truncated's width
-- test) read that buffer and width — but the string they return still holds
-- statusline items like %F and %l, and those expand against whichever window
-- finally draws them. Returned raw from a %! expression they would resolve
-- in the bar's own scratch buffer, which is how the file name came out as
-- "[Scratch]". So the content is rendered to text + highlight ranges in the
-- parent's context with nvim_eval_statusline, then re-emitted as literal
-- text (with % escaped) carrying explicit %#group# switches.
--
-- Active vs inactive is mini's own test aimed at the parent, but it cannot
-- borrow mini's g:actual_curwin: that variable is only set while evaluating
-- a %{} item, and this is a %! expression, where it comes back nil. Under %!
-- the real focused window is simply the current one (verified: current_win
-- is the editor, statusline_winid the bar), so compare against that and keep
-- g:actual_curwin as the fallback for a %{} caller.
function _G.___hscroll_status()
  local bar    = tonumber(vim.g.statusline_winid)
  local parent = bar and parent_of[bar]
  local ms     = package.loaded['mini.statusline']
  if not (parent and ms and vim.api.nvim_win_is_valid(parent)) then return ' ' end

  local active = vim.api.nvim_get_current_win() == parent
    or tonumber(vim.g.actual_curwin) == parent
  local ok, content = pcall(vim.api.nvim_win_call, parent, function()
    return active and ms.active() or ms.inactive()
  end)
  if not (ok and type(content) == 'string') then return ' ' end

  local rendered
  ok, rendered = pcall(vim.api.nvim_eval_statusline, content, {
    winid      = parent,
    maxwidth   = vim.api.nvim_win_get_width(parent),
    highlights = true,
  })
  if not ok then return ' ' end

  local str, hls = rendered.str, rendered.highlights or {}
  if #hls == 0 then return (str:gsub('%%', '%%%%')) end
  local parts = {}
  for i, hl in ipairs(hls) do
    local stop = hls[i + 1] and hls[i + 1].start or #str
    parts[#parts + 1] = '%#' .. (hl.group or 'StatusLine') .. '#'
      .. str:sub(hl.start + 1, stop):gsub('%%', '%%%%')
  end
  return table.concat(parts)
end

local function adopt_statusline(parent, bar)
  if not compact_h() then return end
  if saved_stl[parent] == nil then
    saved_stl[parent] =
      vim.api.nvim_get_option_value('statusline', { win = parent, scope = 'local' })
  end
  pcall(vim.api.nvim_set_option_value, 'statusline', '%!v:lua.___hscroll_track()',
    { win = parent, scope = 'local' })
  pcall(vim.api.nvim_set_option_value, 'statusline', '%!v:lua.___hscroll_status()',
    { win = bar, scope = 'local' })
  -- Only the statusline of this window is wanted, never a text row.
  if vim.o.winminheight > 0 then vim.o.winminheight = 0 end
  pcall(vim.api.nvim_win_set_height, bar, 0)
end

-- Give the editor its own statusline back (an empty local value falls back
-- to mini's global one, which is what it had before the swap).
local function release_statusline(parent)
  local saved = saved_stl[parent]
  saved_stl[parent] = nil
  if saved == nil or not vim.api.nvim_win_is_valid(parent) then return end
  pcall(vim.api.nvim_set_option_value, 'statusline', saved,
    { win = parent, scope = 'local' })
end

local function close_one(map, parent)
  local e = map[parent]
  map[parent] = nil
  if not e then return end
  parent_of[e.win] = nil
  kind_of[e.win] = nil
  if vim.api.nvim_win_is_valid(e.win) then
    pcall(vim.api.nvim_win_close, e.win, true)
  end
  if e.buf and vim.api.nvim_buf_is_valid(e.buf) then
    pcall(vim.api.nvim_buf_delete, e.buf, { force = true })
  end
end

local function close_hbar(parent)
  close_one(hbars, parent)
  release_statusline(parent)
end
local function close_vbar(parent) close_one(vbars, parent) end

local function style_common(win, buf)
  vim.bo[buf].buftype     = 'nofile'
  vim.bo[buf].bufhidden   = 'wipe'
  vim.bo[buf].swapfile    = false
  vim.bo[buf].filetype    = BAR_FT
  vim.bo[buf].modifiable  = false
  vim.b[buf].ministatusline_disable = true
  vim.wo[win].number         = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn     = 'no'
  vim.wo[win].foldcolumn     = '0'
  vim.wo[win].statuscolumn   = ''
  vim.wo[win].cursorline     = false
  vim.wo[win].list           = false
  vim.wo[win].wrap           = false
  vim.wo[win].spell          = false
  vim.wo[win].winbar         = ''
  vim.wo[win].winfixbuf      = true
  vim.wo[win].scrolloff      = 0
  vim.wo[win].sidescrolloff  = 0
end

local function map_bar_mouse(buf, bar_win, begin)
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set({ 'n', 'x', 'i' }, '<LeftMouse>', function()
    local parent = parent_of[bar_win]
    if parent and vim.api.nvim_win_is_valid(parent) then
      begin(parent, vim.fn.getmousepos(), bar_win)
    end
  end, opts)
  vim.keymap.set({ 'n', 'x', 'i' }, '<LeftDrag>', apply_drag, opts)
  vim.keymap.set({ 'n', 'x', 'i' }, '<LeftRelease>', end_drag, opts)
  vim.keymap.set({ 'n', 'x', 'i' }, '<MouseMove>', function()
    if vim.g.hscroll_dragging then apply_drag() end
  end, opts)
end

local function map_vbar_mouse(buf, bar_win)
  map_bar_mouse(buf, bar_win, begin_v)
end

local function map_hbar_mouse(buf, bar_win)
  map_bar_mouse(buf, bar_win, function(parent, mp)
    begin_h(parent, mp)
  end)
end

local function create_hbar(parent)
  if hbars[parent] and vim.api.nvim_win_is_valid(hbars[parent].win) then
    pcall(vim.api.nvim_win_set_height, hbars[parent].win, compact_h() and 0 or 1)
    adopt_statusline(parent, hbars[parent].win)
    paint_hbar(parent)
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  creating = true
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
    split  = 'below',
    win    = parent,
    height = 1,
  })
  if not ok then
    creating = false
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return
  end
  style_common(win, buf)
  vim.wo[win].winfixheight = true
  -- Only the end-of-buffer fill is overridden: the track is buffer content
  -- (Normal), while this window's statusline is a real statusline again —
  -- it carries the parent's, so it keeps the global stl fillchar and the
  -- StatusLine groups.
  vim.wo[win].fillchars    = 'eob: '
  vim.wo[win].winhighlight = 'Normal:HScrollTrack,EndOfBuffer:HScrollTrack'
  hbars[parent] = { win = win, buf = buf }
  parent_of[win] = parent
  kind_of[win] = 'h'
  creating = false
  -- Registered above first: ___hscroll_status resolves the parent through
  -- parent_of when the new statusline is evaluated on the next redraw.
  adopt_statusline(parent, win)
  map_hbar_mouse(buf, win)
  paint_hbar(parent)
end

local function create_vbar(parent)
  if vbars[parent] and vim.api.nvim_win_is_valid(vbars[parent].win) then
    paint_vbar(parent)
    return
  end
  if not vim.api.nvim_win_is_valid(parent) then return end
  local ph = math.max(1, vim.api.nvim_win_get_height(parent))
  local pw = vim.api.nvim_win_get_width(parent)
  local buf = vim.api.nvim_create_buf(false, true)
  -- Float (not a split): splits get squeezed to zero by neo-tree / topbar /
  -- equalalways. noautocmd is intentionally off — a float opened with
  -- noautocmd before UIEnter is clickable but missing from the first frame.
  creating = true
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
    relative  = 'win',
    win       = parent,
    anchor    = 'NW',
    row       = 0,
    col       = vbar_col0(pw),
    width     = VBAR_W,
    height    = ph,
    style     = 'minimal',
    -- Do not eat mouse events: a focusable=false float with mouse=true
    -- swallowed clicks on the far-right column (mappings never ran).
    -- Clicks pass through to the editor; on_left_mouse hit-tests the track.
    focusable = false,
    mouse     = false,
    zindex    = 40,
    border    = 'none',
  })
  if not ok then
    creating = false
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return
  end
  -- Register before WinNew handlers run, so a nested refresh cannot open
  -- a second float for the same parent.
  vbars[parent] = { win = win, buf = buf }
  parent_of[win] = parent
  kind_of[win] = 'v'
  creating = false
  style_common(win, buf)
  vim.wo[win].fillchars    = 'eob: ,stl: ,stlnc: '
  vim.wo[win].winhighlight =
    'Normal:HScrollTrack,EndOfBuffer:HScrollTrack,StatusLine:HScrollTrack,StatusLineNC:HScrollTrack'
  vim.wo[win].statusline   = ' '
  map_vbar_mouse(buf, win)
  paint_vbar(parent)
  flush_win(win)
end

local function clear_old_winbar(winid)
  local wb = vim.wo[winid].winbar or ''
  if wb:find('___hscroll_winbar', 1, true) then
    pcall(vim.api.nvim_set_option_value, 'winbar', '', { win = winid })
  end
end

local function refresh(winid)
  if creating or vim.g.hscroll_dragging then return end
  winid = tonumber(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end
  if kind_of[winid] == 'view' then
    local parent = parent_of[winid]
    if parent then paint_vbar(parent) end
    return
  end
  if is_bar_win(winid) then
    winid = parent_of[winid]
    if not winid then return end
  end
  clear_old_winbar(winid)

  if not eligible(winid) then
    close_hbar(winid)
    close_vbar(winid)
    close_viewport(winid)
    return
  end

  local hg = hgeom(winid)
  local info = vim.fn.getwininfo(winid)[1]
  local nlines = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(winid))
  -- Use the editor's own height, not a squashed bar's height. If the
  -- window is still 0-tall during startup, still treat a multi-line
  -- file as needing a vertical bar.
  local ed_h = math.max(1, info and info.height or 1)
  local need_h = not vim.wo[winid].wrap and hg.ml > hg.text_w
  local need_v = nlines > ed_h or (nlines > 1 and ed_h <= 1)

  if need_h then
    local e = hbars[winid]
    if e and not vim.api.nvim_win_is_valid(e.win) then hbars[winid] = nil; e = nil end
    if not e then create_hbar(winid) else
      pcall(vim.api.nvim_win_set_height, e.win, compact_h() and 0 or 1)
      adopt_statusline(winid, e.win)
      paint_hbar(winid)
    end
  else
    close_hbar(winid)
  end

  if need_v then
    local e = vbars[winid]
    if e and not vim.api.nvim_win_is_valid(e.win) then vbars[winid] = nil; e = nil end
    if not e then create_vbar(winid) else paint_vbar(winid) end
  else
    close_vbar(winid)
  end
end

local group = vim.api.nvim_create_augroup('hscrollbar', { clear = true })

vim.api.nvim_create_autocmd('WinScrolled', {
  group = group,
  callback = function(ev)
    -- Drag already updates the thumb; a full refresh here re-lays-out
    -- windows and makes the bar stutter.
    if vim.g.hscroll_dragging then return end
    refresh(ev.match)
  end,
})

vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  group = group,
  callback = function()
    local win = vim.api.nvim_get_current_win()
    remember_cursor(win)
    if vim.g.hscroll_dragging then return end
    -- After the view settles (normal! G updates topline after this event).
    vim.schedule(function()
      if vim.g.hscroll_dragging then return end
      if vim.api.nvim_win_is_valid(win) and vbars[win] then paint_vbar(win) end
    end)
  end,
})

local function refresh_soon(win)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then refresh(win) end
  end)
  vim.defer_fn(function()
    if vim.api.nvim_win_is_valid(win) then refresh(win) end
  end, 60)
end

vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
  group = group,
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if is_bar_win(win) then
      -- Bounce focus back unless a drag just started. Skipping the bounce
      -- while dragging lets the vertical bar keep receiving LeftDrag.
      local parent = parent_of[win]
      vim.schedule(function()
        if vim.g.hscroll_dragging then return end
        if parent and vim.api.nvim_win_is_valid(parent)
            and is_bar_win(vim.api.nvim_get_current_win()) then
          pcall(vim.api.nvim_set_current_win, parent)
        end
      end)
      return
    end
    remember_cursor(win)
    refresh(win)
    refresh_soon(win)
  end,
})

vim.api.nvim_create_autocmd('WinResized', {
  group = group,
  callback = function()
    if vim.g.hscroll_dragging then return end
    for parent, _ in pairs(viewports) do place_viewport(parent) end
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(w) and not is_bar_win(w) then refresh(w) end
    end
  end,
})

vim.api.nvim_create_autocmd('WinClosed', {
  group = group,
  callback = function(ev)
    local id = tonumber(ev.match)
    if not id then return end
    local kind = kind_of[id]
    local parent = parent_of[id]
    if kind == 'h' and parent then
      hbars[parent] = nil
      parent_of[id] = nil
      kind_of[id] = nil
      release_statusline(parent)
    elseif kind == 'v' and parent then
      vbars[parent] = nil
      parent_of[id] = nil
      kind_of[id] = nil
    elseif kind == 'view' and parent then
      viewports[parent] = nil
      parent_of[id] = nil
      kind_of[id] = nil
    else
      close_hbar(id)
      close_vbar(id)
      close_viewport(id)
    end
  end,
})

vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufReadPost' }, {
  group = group,
  callback = function(ev)
    maxlen[ev.buf] = nil
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_buf(w) == ev.buf then
        refresh(w)
        refresh_soon(w)
      end
    end
  end,
})

local function refresh_all()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) and not is_bar_win(w) then refresh(w) end
  end
end

-- 'wrap' decides whether the horizontal bar is wanted at all, and nothing
-- else fires when it flips: no scroll, no resize, no cursor move. Without
-- this, :set wrap left the track sitting under the window (and :set nowrap
-- left it missing) until the next unrelated event happened to refresh.
-- :setlocal changes only the current window, :set every window that has no
-- local value of its own, so both cases just refresh the lot — refresh()
-- returns immediately for a window that is already in the right state.
vim.api.nvim_create_autocmd('OptionSet', {
  group    = group,
  pattern  = 'wrap',
  callback = function() vim.schedule(refresh_all) end,
})

vim.api.nvim_create_autocmd('VimEnter', {
  group    = group,
  once     = true,
  callback = function()
    vim.schedule(refresh_all)
  end,
})

vim.api.nvim_create_autocmd('UIEnter', {
  group    = group,
  once     = true,
  callback = function()
    -- One follow-up after neo-tree/topbar settle. Do not tear the float
    -- down or keep pulsing — that left a visible bar that could not be
    -- grabbed until the timers finished.
    vim.schedule(refresh_all)
    vim.defer_fn(function()
      if not vim.g.hscroll_dragging then refresh_all() end
    end, 80)
  end,
})

local function on_left_mouse()
  if press_on_bar() then return end
  if press_on_vtrack() then return end
  click_viewport(vim.fn.getmousepos())
end

-- A key (not a mouse event) drops the preview and shows the real cursor.
vim.on_key(function(key)
  if vim.g.hscroll_dragging then return end
  if next(viewports) == nil then return end
  local name = vim.fn.keytrans(key)
  if name:find('[Mm]ouse') or name:find('Release') or name:find('Drag')
      or name:find('Scroll') or name:find('Wheel') then
    return
  end
  local parents = {}
  for p, _ in pairs(viewports) do parents[#parents + 1] = p end
  for _, p in ipairs(parents) do close_viewport(p) end
  for _, p in ipairs(parents) do
    if vbars[p] then paint_vbar(p) end
  end
end)

return {
  on_drag = on_drag,
  is_bar_win = is_bar_win,
  on_left_mouse = on_left_mouse,
}
