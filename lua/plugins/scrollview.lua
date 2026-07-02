-- ============================================================
-- plugins/scrollview.lua — Horizontal scrollbar for buffer windows
--
-- nvim-scrollview only does vertical bars, so this is a small
-- custom implementation: a floating 1-row window overlaid at the
-- bottom edge of a buffer window when wrap=false and content
-- exceeds the window width.
-- ============================================================

local excluded_ft = { ['neo-tree'] = true, ['toggleterm'] = true,
                      ['help'] = true, ['TelescopePrompt'] = true }
local excluded_bt = { terminal = true, prompt = true, nofile = true }

-- bar state per base winid: { win=bar_winid, buf=bar_bufnr }
local bars = {}
-- max display-width cache per bufnr, invalidated on TextChanged
local maxlen = {}

local function get_maxlen(bufnr)
  if maxlen[bufnr] then return maxlen[bufnr] end
  local max = 0
  for _, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    -- Binary files can contain lines Vim represents as a Blob rather than a
    -- String (e.g. embedded NULs); strdisplaywidth() then raises E976. Skip
    -- those lines rather than letting the error abort the calling autocmd
    -- (BufReadPost/WinEnter), which otherwise breaks unrelated things further
    -- down the same event, like quickfix navigation onto a binary file.
    local ok, w = pcall(vim.fn.strdisplaywidth, l)
    if ok and w > max then max = w end
  end
  maxlen[bufnr] = max
  return max
end

local function close_bar(winid)
  local e = bars[winid]
  if not e then return end
  if vim.api.nvim_win_is_valid(e.win) then
    pcall(vim.api.nvim_win_close, e.win, true)
  end
  bars[winid] = nil
end

local function refresh(winid)
  if not vim.api.nvim_win_is_valid(winid) then close_bar(winid); return end
  -- skip floating windows (our own bars and other plugins)
  if vim.api.nvim_win_get_config(winid).relative ~= '' then return end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  if excluded_ft[vim.bo[bufnr].filetype] or excluded_bt[vim.bo[bufnr].buftype] then
    close_bar(winid); return
  end
  if vim.wo[winid].wrap then close_bar(winid); return end

  local info = vim.fn.getwininfo(winid)[1]
  local text_w = info.width - info.textoff
  local ml = get_maxlen(bufnr)

  if ml <= text_w then close_bar(winid); return end

  -- Bar geometry: width proportional to visible fraction, offset by leftcol
  local leftcol = info.leftcol
  local bar_w   = math.max(1, math.floor(text_w * text_w / ml))
  local track   = text_w - bar_w
  local bar_off = track > 0 and math.floor(leftcol * track / (ml - text_w)) or 0

  local pos   = vim.api.nvim_win_get_position(winid)  -- {row, col}, 0-indexed
  local sc_row = pos[1] + info.height - 1             -- last content row
  local sc_col = pos[2] + info.textoff + bar_off

  local fill = string.rep('▁', bar_w)

  local e = bars[winid]
  if e and vim.api.nvim_win_is_valid(e.win) then
    vim.api.nvim_buf_set_lines(e.buf, 0, -1, false, { fill })
    vim.api.nvim_win_set_config(e.win, {
      relative = 'editor', row = sc_row, col = sc_col,
      width = bar_w, height = 1,
    })
  else
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { fill })
    local win = vim.api.nvim_open_win(buf, false, {
      relative = 'editor',
      row = sc_row, col = sc_col,
      width = bar_w, height = 1,
      style = 'minimal',
      focusable = false,
      zindex = 150,
    })
    vim.wo[win].winblend = 0
    vim.wo[win].winhighlight = 'Normal:PmenuSel'
    bars[winid] = { win = win, buf = buf }
  end
end

local group = vim.api.nvim_create_augroup('hscrollbar', { clear = true })

-- WinScrolled: match contains the scrolled window id
vim.api.nvim_create_autocmd('WinScrolled', {
  group = group,
  callback = function(ev) refresh(tonumber(ev.match)) end,
})

vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
  group = group,
  callback = function() refresh(vim.api.nvim_get_current_win()) end,
})

vim.api.nvim_create_autocmd('WinResized', {
  group = group,
  callback = function()
    for _, w in ipairs(vim.api.nvim_list_wins()) do refresh(w) end
  end,
})

vim.api.nvim_create_autocmd('WinClosed', {
  group = group,
  callback = function(ev) close_bar(tonumber(ev.match)) end,
})

-- Invalidate cached max-length when buffer content changes
vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufReadPost' }, {
  group = group,
  callback = function(ev)
    maxlen[ev.buf] = nil
    refresh(vim.api.nvim_get_current_win())
  end,
})
