-- ============================================================
-- core/folder_picker.lua — Floating folder browser (mouse + keys)
--
--     ╭─ Pick a build directory ──────────────────────────╮
--     │  ~/code/swatplus_repos/swatplus_fg_fork/          │
--     │                                                   │
--     │  ../                                              │
--     │  build/                         CMake build       │
--     │  doc/                                             │
--     │  src/                                             │
--     │                                                   │
--     │  [ Select this folder ]  [ Cancel ]               │
--     │  click/Enter: open · ..: up · s: select · …       │
--     ╰───────────────────────────────────────────────────╯
--
-- Navigating:  a click, <CR>, l or <Right> on a folder opens it; ../ (or
--              h, -, <BS>, <Left>) goes up — above the start folder too.
-- Selecting:   [ Select this folder ] or s picks the folder being shown;
--              <Space> on a folder line picks that folder without opening it.
-- Other:       . shows/hides dot-folders; <Esc> / q / [ Cancel ] / a click
--              outside / leaving the float cancels.
--
-- Usage:
--   require('core.folder_picker').open {
--     title     = 'Pick a build directory',
--     start     = '/abs/start/dir',
--     tag       = function(path) return 'CMake build' or nil end,  -- optional
--     on_select = function(path) ... end,
--     on_cancel = function() ... end,                              -- optional
--   }
-- The picker only picks; the caller validates what it was given.
-- ============================================================

local M = {}

local ns = vim.api.nvim_create_namespace('core-folder-picker')

local HINT = 'click/Enter: open · ../h: up · s: select this · Space: select line · .: hidden · Esc'

local function subdirs(dir, hidden)
  local out = {}
  local fs = (vim.uv or vim.loop).fs_scandir(dir)
  if not fs then return out end
  while true do
    local name, kind = (vim.uv or vim.loop).fs_scandir_next(fs)
    if not name then break end
    if hidden or name:sub(1, 1) ~= '.' then
      local path = dir == '/' and ('/' .. name) or (dir .. '/' .. name)
      if kind == 'directory' or (kind == 'link' and vim.fn.isdirectory(path) == 1) then
        table.insert(out, { name = name, path = path })
      end
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

local function parent(dir)
  if dir == '/' then return '/' end
  local p = vim.fn.fnamemodify(dir, ':h')
  return p == '' and '/' or p
end

function M.open(opts)
  local cwd    = vim.fn.fnamemodify(opts.start, ':p'):gsub('/+$', '')
  if cwd == '' then cwd = '/' end
  local hidden = false
  local rows   = {}   -- buffer line → { path = …, up = true? }
  local btn    = {}   -- { select = {s, e}, cancel = {s, e} }, byte cols, 0-based
  local btn_row

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype  = 'folderpicker'

  local width  = math.min(math.max(70, #HINT + 4), vim.o.columns - 4)
  local height = math.min(24, vim.o.lines - 6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    title = ' ' .. opts.title .. ' ', title_pos = 'center',
  })
  vim.wo[win].cursorline = true
  local closed = false

  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  -- Closing without a pick: tell the caller (it may reopen its own UI).
  local function cancel()
    if closed then return end
    close()
    if opts.on_cancel then vim.schedule(opts.on_cancel) end
  end

  local function pick(path)
    close()
    vim.schedule(function() opts.on_select(path) end)
  end

  -- Redraw for `cwd`. The folder list sits between the path header and the
  -- buttons; `focus` (a path) puts the cursor on that entry if present —
  -- used after going up, so the folder you came out of stays highlighted.
  local function render(focus)
    rows = {}
    local lines = { '  ' .. vim.fn.fnamemodify(cwd, ':~') .. (cwd == '/' and '' or '/'), '' }
    local marks = {}
    if cwd ~= '/' then
      table.insert(lines, '  ../')
      rows[#lines] = { path = parent(cwd), up = true }
    end
    local list = subdirs(cwd, hidden)
    local namew = 0
    for _, d in ipairs(list) do namew = math.max(namew, vim.fn.strdisplaywidth(d.name) + 1) end
    namew = math.min(namew, width - 20)
    for _, d in ipairs(list) do
      local tag = opts.tag and opts.tag(d.path) or nil
      local name = d.name .. '/'
      local line = '  ' .. name
      if tag then
        line = line .. (' '):rep(math.max(2, namew - vim.fn.strdisplaywidth(name) + 3)) .. tag
        table.insert(marks, { #lines, #line - #tag, #line })
      end
      table.insert(lines, line)
      rows[#lines] = { path = d.path }
    end
    if #list == 0 then table.insert(lines, '  (no subfolders)') end
    table.insert(lines, '')

    local here_tag = opts.tag and opts.tag(cwd) or nil
    local sel_text = '[ Select this folder' .. (here_tag and (' (' .. here_tag .. ')') or '') .. ' ]'
    local can_text = '[ Cancel ]'
    table.insert(lines, '  ' .. sel_text .. '  ' .. can_text)
    btn_row = #lines
    btn.select = { 2, 2 + #sel_text }
    btn.cancel = { 2 + #sel_text + 2, 2 + #sel_text + 2 + #can_text }
    table.insert(lines, '  ' .. HINT)

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #lines[1], hl_group = 'Title' })
    for row, r in pairs(rows) do
      vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 2,
        { end_col = #lines[row], hl_group = r.up and 'Comment' or 'Directory' })
    end
    for _, m in ipairs(marks) do
      vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = 'DiagnosticWarn' })
    end
    vim.api.nvim_buf_set_extmark(buf, ns, btn_row - 1, btn.select[1],
      { end_col = btn.select[2], hl_group = here_tag and 'DiagnosticWarn' or 'Function' })
    vim.api.nvim_buf_set_extmark(buf, ns, btn_row - 1, btn.cancel[1],
      { end_col = btn.cancel[2], hl_group = 'Comment' })
    vim.api.nvim_buf_set_extmark(buf, ns, btn_row, 0,
      { end_col = #lines[btn_row + 1], hl_group = 'Comment' })

    -- Cursor: on the folder we came from, else the first folder, else ../.
    local target
    for row, r in pairs(rows) do
      if focus and r.path == focus then target = row end
    end
    if not target then
      for row = 1, #lines do
        if rows[row] and not rows[row].up then target = row break end
      end
    end
    target = target or (rows[3] and 3) or btn_row
    vim.api.nvim_win_set_cursor(win, { target, 0 })
  end

  local function go(path, focus)
    if vim.fn.isdirectory(path) == 0 then return end
    cwd = path
    render(focus)
  end
  local function up() if cwd ~= '/' then go(parent(cwd), cwd) end end

  -- Act on a line: a folder opens, ../ goes up, the buttons do their thing.
  local function activate(row, col)
    if row == btn_row and col then
      if col >= btn.select[1] and col < btn.select[2] then return pick(cwd) end
      if col >= btn.cancel[1] and col < btn.cancel[2] then return cancel() end
      return
    end
    local r = rows[row]
    if not r then return end
    if r.up then up() else go(r.path) end
  end

  local function map(lhs, fn)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  local function line() return vim.fn.line('.') end

  for _, k in ipairs({ '<CR>', 'l', '<Right>' }) do
    map(k, function()
      local row = line()
      if row == btn_row then return activate(row, vim.fn.col('.') - 1) end
      activate(row)
    end)
  end
  for _, k in ipairs({ 'h', '-', '<BS>', '<Left>' }) do map(k, up) end
  map('s', function() pick(cwd) end)
  map('<Space>', function()
    local r = rows[line()]
    if r and not r.up then pick(r.path) end
  end)
  map('.', function() hidden = not hidden render() end)
  map('<Esc>', cancel)
  map('q', cancel)

  -- Mouse: one click acts (opens a folder / presses a button). A double
  -- click's second half (<2-LeftMouse>) is ignored, or it would open the
  -- folder *inside* the one the first click just opened. A click outside
  -- the float cancels and focuses what was clicked.
  map('<LeftMouse>', function()
    local pos = vim.fn.getmousepos()
    if pos.winid ~= win then
      cancel()
      if pos.winid ~= 0 and vim.api.nvim_win_is_valid(pos.winid) then
        vim.api.nvim_set_current_win(pos.winid)
      end
      return
    end
    if pos.line < 1 then return end
    vim.api.nvim_win_set_cursor(win, { pos.line, 0 })
    activate(pos.line, pos.column - 1)
  end)
  for _, lhs in ipairs({ '<2-LeftMouse>', '<3-LeftMouse>', '<4-LeftMouse>',
                         '<LeftDrag>', '<LeftRelease>', '<2-LeftRelease>' }) do
    map(lhs, '<Nop>')
  end

  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf, once = true,
    callback = function() vim.schedule(cancel) end,
  })

  render()
end

return M
