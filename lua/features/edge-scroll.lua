-- ============================================================
-- features/edge-scroll.lua — Mouse edge-hover horizontal scrolling
-- (homegrown; requires vim.o.mousemoveevent, set in core/options.lua)
-- ============================================================

-- Mouse edge scrolling: hover at the right or left edge of a file window to
-- scroll continuously 5 columns at a time. Timer starts when the mouse enters
-- the edge column and stops when it moves away. Skips wrapped buffers and
-- non-file panels (neo-tree, dapui, etc.).
--
-- Terminals (Kitty, Konsole, ...) only report mouse position while the
-- pointer is inside their own window — once it moves past the terminal's
-- edge entirely, no more <MouseMove> events arrive at all, so there is no
-- event that tells us to stop. Without a safety net the scroll would
-- continue forever. IDLE_LIMIT_TICKS auto-stops after ~400ms with no
-- confirming <MouseMove>, on the assumption the pointer left the terminal.
-- A genuinely still mouse resting exactly at the edge (no OS move events at
-- all) is indistinguishable from this and would also stop — acceptable
-- since natural hand tremor while deliberately holding a position almost
-- always keeps a few events coming to reset the idle counter.
local _edge_timer = nil
local _edge_win   = nil
local _edge_dir   = nil
local _edge_idle  = 0
local IDLE_LIMIT_TICKS = 4  -- 4 * 100ms = ~400ms

local function stop_edge_scroll()
  if _edge_timer then
    _edge_timer:stop()
    _edge_timer:close()
    _edge_timer = nil
  end
  _edge_win  = nil
  _edge_dir  = nil
  _edge_idle = 0
end

local function start_edge_scroll(win, dir)
  if _edge_timer and _edge_win == win and _edge_dir == dir then
    _edge_idle = 0  -- confirmed still at the edge; reset the idle countdown
    return
  end
  stop_edge_scroll()
  _edge_win = win
  _edge_dir = dir
  _edge_timer = vim.uv.new_timer()
  _edge_timer:start(0, 100, vim.schedule_wrap(function()
    if not vim.api.nvim_win_is_valid(win) then stop_edge_scroll(); return end
    _edge_idle = _edge_idle + 1
    if _edge_idle > IDLE_LIMIT_TICKS then stop_edge_scroll(); return end
    vim.api.nvim_win_call(win, function() vim.cmd('normal! 5z' .. dir) end)
  end))
end

vim.keymap.set('n', '<MouseMove>', function()
  local mouse = vim.fn.getmousepos()
  local win   = mouse.winid
  if win == 0 or not vim.api.nvim_win_is_valid(win)
      or vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= ''
      or vim.wo[win].wrap then
    stop_edge_scroll()
    return
  end
  local wincol  = mouse.wincol
  local winwidth = vim.api.nvim_win_get_width(win)
  local textoff  = (vim.fn.getwininfo(win)[1] or {}).textoff or 0
  if     wincol >= winwidth    then start_edge_scroll(win, 'l')
  elseif wincol <= textoff + 1 then start_edge_scroll(win, 'h')
  else   stop_edge_scroll()
  end
end)
