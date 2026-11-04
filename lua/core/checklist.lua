-- ============================================================
-- core/checklist.lua — Floating multi-select checklist
--
-- A small centred float listing entries with a [ ] / [x] box each, and a
-- button row underneath:
--
--     ╭─ Delete build directories ─────────╮
--     │  [x] build/                        │
--     │  [ ]     build/debug/              │
--     │  [ ] build-ubuntu/                 │
--     │                                    │
--     │  [ Delete 1 selected ]  [ Cancel ] │
--     │  Space/click toggle · a all · …    │
--     ╰────────────────────────────────────╯
--
-- Toggling an entry:  <Space> or <Tab> on its line, or a left click on it.
-- Confirming:         <CR>, or a click on the action button.
-- Cancelling:         <Esc> / q, a click on [ Cancel ], or leaving the float.
-- Extra button:       opts.extra = { label = 'Browse…', key = 'b', run = fn }
--                     adds a button (and key) between the action and Cancel.
--                     Pressing it closes the float and calls run(); run may
--                     append to opts.items and call M.open(opts) again —
--                     ticks are kept on the items themselves (item.selected),
--                     so reopening shows the same state.
-- a toggles all entries (all on, or all off when every one is on already).
--
-- vim.ui.select is single-choice (one <CR> picks one entry and closes the
-- picker), which is why this exists instead of re-showing a select after
-- every toggle.
--
-- <Space> is the leader key here: the buffer-local mappings use nowait so
-- they fire at once instead of waiting to see whether a <leader> chord
-- follows.
--
-- Usage:
--   require('core.checklist').open {
--     title    = 'Delete build directories',
--     items    = { { label = 'build/', value = '/abs/build' }, ... },
--     action   = function(n) return 'Delete ' .. n .. ' selected' end,
--     on_confirm = function(chosen) ... end,   -- list of the chosen items
--   }
-- An item with selected = true starts ticked. opts.empty is the line shown
-- when items is empty (the buttons still work, e.g. Browse… to add one).
-- ============================================================

local M = {}

local ns = vim.api.nvim_create_namespace('core-checklist')

function M.open(opts)
  local items = opts.items
  -- Ticks live on the items, so a caller that reopens the checklist (see
  -- opts.extra) gets the same state back.
  local sel = setmetatable({}, {
    __index    = function(_, i) return items[i] and items[i].selected or false end,
    __newindex = function(_, i, v) items[i].selected = v end,
  })

  local first   = 1           -- buffer line of items[1] (1-based)
  local btn_row = #items + 2  -- the button line (after a blank line)
  local hint    = 'Space/click: toggle · a: all · Enter: confirm · Esc: cancel'
  if opts.extra and opts.extra.key then
    hint = hint .. ' · ' .. opts.extra.key .. ': ' .. opts.extra.label:gsub('…$', ''):lower()
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype  = 'checklist'

  local win, closed = nil, false
  local btn = {}   -- { action = {s, e}, extra = {s, e}, cancel = {s, e} } byte columns, 0-based

  local function count()
    local n = 0
    for i = 1, #items do if sel[i] then n = n + 1 end end
    return n
  end

  local function render()
    local lines = {}
    for i, it in ipairs(items) do
      lines[i] = '  ' .. (sel[i] and '[x] ' or '[ ] ') .. it.label
    end
    lines[#items + 1] = ''
    -- Nothing to tick: a placeholder line, so the buttons (Browse…) still show.
    if #items == 0 then lines[1] = '  ' .. (opts.empty or '(nothing to list)') end
    local row, col = '  ', 2
    local function button(name, text)
      text = '[ ' .. text .. ' ]'
      btn[name] = { col, col + #text }
      row, col = row .. text .. '  ', col + #text + 2
    end
    button('action', opts.action(count()))
    if opts.extra then button('extra', opts.extra.label) end
    button('cancel', 'Cancel')
    lines[btn_row] = row:gsub('%s+$', '')
    lines[btn_row + 1] = '  ' .. hint

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for i = 1, #items do
      if sel[i] then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 2,
          { end_col = 5, hl_group = 'DiagnosticWarn' })
      end
    end
    vim.api.nvim_buf_set_extmark(buf, ns, btn_row - 1, btn.action[1], {
      end_col = btn.action[2],
      hl_group = count() > 0 and 'DiagnosticError' or 'Comment',
    })
    if btn.extra then
      vim.api.nvim_buf_set_extmark(buf, ns, btn_row - 1, btn.extra[1],
        { end_col = btn.extra[2], hl_group = 'Function' })
    end
    vim.api.nvim_buf_set_extmark(buf, ns, btn_row - 1, btn.cancel[1],
      { end_col = btn.cancel[2], hl_group = 'Comment' })
    vim.api.nvim_buf_set_extmark(buf, ns, btn_row, 0,
      { end_row = btn_row + 1, hl_group = 'Comment', hl_eol = false })
    return lines
  end

  local function close()
    if closed then return end
    closed = true
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function confirm()
    local chosen = {}
    for i, it in ipairs(items) do if sel[i] then table.insert(chosen, it) end end
    if #chosen == 0 then
      vim.notify('Nothing selected: Space or click an entry first.', vim.log.levels.WARN)
      return
    end
    close()
    vim.schedule(function() opts.on_confirm(chosen) end)
  end

  local function extra()
    close()
    vim.schedule(opts.extra.run)
  end

  local function toggle(row)
    local i = row - first + 1
    if i < 1 or i > #items then return end
    sel[i] = not sel[i]
    render()
    vim.api.nvim_win_set_cursor(win, { row, 0 })
  end

  local function toggle_all()
    local all = count() == #items
    for i = 1, #items do sel[i] = not all end
    render()
  end

  local lines = render()
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(width + 2, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 4)

  win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    title = ' ' .. opts.title .. ' ', title_pos = 'center',
  })
  vim.wo[win].cursorline = true
  vim.api.nvim_win_set_cursor(win, { first, 0 })

  local function map(lhs, fn)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true })
  end

  map('<Space>', function() toggle(vim.fn.line('.')) end)
  map('<Tab>',   function() toggle(vim.fn.line('.')) end)
  map('x',       function() toggle(vim.fn.line('.')) end)
  map('a',       toggle_all)
  map('<CR>', function()
    local row = vim.fn.line('.')
    if row == btn_row then
      local col = vim.fn.col('.') - 1
      if col >= btn.cancel[1] and col < btn.cancel[2] then return close() end
      if btn.extra and col >= btn.extra[1] and col < btn.extra[2] then return extra() end
    end
    confirm()
  end)
  if opts.extra and opts.extra.key then map(opts.extra.key, extra) end
  map('<Esc>', close)
  map('q',     close)

  -- Mouse: every click is handled here (a double click arrives as
  -- <LeftMouse> then <2-LeftMouse>; both toggle, so each physical click
  -- flips the box once). Drag/release are swallowed so a click never
  -- starts a visual selection. A click outside the float cancels it.
  local function click()
    local pos = vim.fn.getmousepos()
    if pos.winid ~= win then
      close()
      if pos.winid ~= 0 and vim.api.nvim_win_is_valid(pos.winid) then
        vim.api.nvim_set_current_win(pos.winid)
      end
      return
    end
    local row, col = pos.line, pos.column - 1
    if row < 1 then return end
    vim.api.nvim_win_set_cursor(win, { row, 0 })
    if row == btn_row then
      if col >= btn.action[1] and col < btn.action[2] then return confirm() end
      if col >= btn.cancel[1] and col < btn.cancel[2] then return close() end
      if btn.extra and col >= btn.extra[1] and col < btn.extra[2] then return extra() end
      return
    end
    toggle(row)
  end
  for _, lhs in ipairs({ '<LeftMouse>', '<2-LeftMouse>', '<3-LeftMouse>', '<4-LeftMouse>' }) do
    map(lhs, click)
  end
  for _, lhs in ipairs({ '<LeftDrag>', '<LeftRelease>', '<2-LeftRelease>' }) do
    map(lhs, '<Nop>')
  end

  -- Focus moving elsewhere (another window, a terminal, …) cancels.
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf, once = true,
    callback = function() vim.schedule(close) end,
  })
end

return M
