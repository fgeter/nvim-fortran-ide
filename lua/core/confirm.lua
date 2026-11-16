-- ============================================================
-- core/confirm.lua — confirm() dialog that shows which answer <CR> picks
--
-- Neovim's built-in confirm() prints its buttons as "[Y]es, (N)o": the
-- default is marked only by square vs round brackets, which is easy to
-- miss. This replaces vim.fn.confirm for every Lua caller with a small
-- floating dialog in which the default's key is UPPERCASE and every other
-- key is lowercase:
--
--     Build succeeded.
--     Close the terminal?
--
--     [Y] yes   [n] no, keep the output
--
-- <CR> picks the uppercase one. A key picks its button in either case,
-- <Esc> / <C-c> return 0 (cancel), exactly as the built-in does. The
-- calling convention and return values are unchanged, so callers need
-- no edits: confirm(msg, choices, default, type).
--
--   choices   '\n'-separated labels; '&' marks the hotkey ('&&' = '&').
--             No '&' -> the first character. Omitted -> '&Ok'.
--   default   1-based button <CR> picks; omitted -> 1; 0 -> no default
--             (<CR> is then ignored and an explicit key is required).
--
-- Not covered: Vimscript's own confirm dialogs (`:confirm quit`, the
-- swap-file E325 "[O]pen Read-Only, (E)dit anyway…" prompt, plugins
-- written in Vimscript). They go straight to the C function.
-- Headless (no UI attached) falls back to the built-in.
-- ============================================================

local M = {}

local native = vim.fn.confirm
local ns = vim.api.nvim_create_namespace('core_confirm')

-- '&Yes\n&No, keep' -> { { key = 'y', text = 'Yes' }, { key = 'n', text = 'No, keep' } }
local function parse(choices)
  local buttons = {}
  for label in (choices .. '\n'):gmatch('([^\n]*)\n') do
    if label ~= '' then
      local key
      local text = label:gsub('&(.)', function(c)
        if c == '&' then return '&' end
        key = key or c
        return c
      end)
      key = key or text:sub(1, 1)
      buttons[#buttons + 1] = { key = key:lower(), text = text }
    end
  end
  return buttons
end

local function lower_first(s)
  return s:sub(1, 1):lower() .. s:sub(2)
end

function M.confirm(msg, choices, default, kind)
  if #vim.api.nvim_list_uis() == 0 then
    return native(msg, choices, default, kind)
  end
  local buttons = parse(choices or '&Ok')
  if #buttons == 0 then return 0 end
  default = tonumber(default) or 1
  if default > #buttons then default = 0 end

  -- Button row: "[Y] yes   [n] no, keep the output". Remember each
  -- button's byte span so it can be highlighted.
  local row, spans = '', {}
  for i, b in ipairs(buttons) do
    if i > 1 then row = row .. '   ' end
    local tag = '[' .. (i == default and b.key:upper() or b.key) .. '] '
      .. lower_first(b.text)
    spans[i] = { #row, #row + #tag }
    row = row .. tag
  end

  local lines = vim.split(tostring(msg or ''), '\n', { plain = true })
  lines[#lines + 1] = ''
  lines[#lines + 1] = row
  -- one column of margin inside the border on each side
  for i, l in ipairs(lines) do lines[i] = ' ' .. l .. ' ' end
  for _, s in ipairs(spans) do s[1], s[2] = s[1] + 1, s[2] + 1 end

  -- Size: widest line, capped to the screen; wrapped lines add height.
  local maxw = math.max(20, vim.o.columns - 6)
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(width, maxw)
  local height = 0
  for _, l in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / width))
  end
  height = math.min(height, math.max(1, vim.o.lines - 4))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  for i, s in ipairs(spans) do
    vim.api.nvim_buf_set_extmark(buf, ns, #lines - 1, s[1], {
      end_col = s[2],
      hl_group = i == default and 'MoreMsg' or 'Normal',
    })
  end
  local title = ({ Error = ' Error ', Warning = ' Warning ', Question = ' Question ',
                   Info = ' Info ' })[kind] or ' Confirm '
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    title = title, title_pos = 'center', focusable = false, zindex = 250,
    -- A float that is not focusable ignores the mouse too unless told
    -- otherwise: a click went straight through to the window underneath.
    mouse = true,
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
  })
  vim.wo[win].wrap = true
  vim.wo[win].winhighlight = 'NormalFloat:NormalFloat,FloatBorder:FloatBorder'

  local CLICK = vim.keycode('<LeftMouse>')
  local answer = 0
  while true do
    vim.cmd('redraw')
    local ok, c = pcall(vim.fn.getcharstr)
    if not ok or c == '\27' or c == '\3' then answer = 0; break end   -- <Esc>, <C-c>
    if c == '\r' or c == '\n' then
      if default > 0 then answer = default; break end
    elseif c == CLICK then
      -- A click on a button picks it; anywhere else is ignored (the
      -- question still needs an answer).
      local mp = vim.fn.getmousepos()
      local hit
      if mp.winid == win and mp.line == #lines then
        for i, s in ipairs(spans) do
          if mp.column - 1 >= s[1] and mp.column - 1 < s[2] then hit = i; break end
        end
      end
      if hit then answer = hit; break end
    else
      local hit
      for i, b in ipairs(buttons) do
        if c:lower() == b.key then hit = i; break end
      end
      if hit then answer = hit; break end
    end
  end

  if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  vim.cmd('redraw')
  return answer
end

vim.fn.confirm = M.confirm

-- ------------------------------------------------------------
-- M.select(items, opts, on_choice): the same kind of dialog for picking
-- one entry from a list. Same signature as vim.ui.select, so it can
-- stand in for it around a plugin call (see <leader>cp in
-- plugins/cmake-tools.lua). It is NOT installed as vim.ui.select.
--
--     ╭──────── Select run directory (recent first) ────────╮
--     │  1  US-Ne3                 2 hours ago              │
--     │▶ 2  Riesel_one_HRU         yesterday                │   <- highlighted
--     │  3  IA-Clayton_StewRTop    3 days ago               │
--     ╰ <CR> pick  j/k move  1-9 pick  / filter  [b] browse…  <Esc> cancel ╯
--
-- The highlighted row starts on opts.default (an item, or its index;
-- default 1) and <CR> picks it. j/k, arrows, <C-n>/<C-p>, g/G,
-- <C-d>/<C-u> and the mouse wheel move (long lists scroll); a row's
-- number or letter, or a click, picks it directly. / starts a filter:
-- typed text narrows the list (substring, case-insensitive), <BS> edits,
-- <CR> picks, <Esc> clears the filter. <Esc>/<C-c>/q cancel.
-- on_choice(item, idx), or on_choice(nil, nil) on cancel.
--
--   opts.prompt       window title
--   opts.format_item  item -> main text (default tostring)
--   opts.detail       item -> dimmed text after it (optional)
--   opts.default      item or index highlighted first
--   opts.buttons      { { key = 'b', text = 'Browse…', value = X }, … }:
--                     extra actions in the footer; the key calls
--                     on_choice(X, nil)
--   opts.max_height   list rows shown at once (default 20)
-- ------------------------------------------------------------
-- ------------------------------------------------------------
-- Shared look for the other floating dialogs (core/checklist.lua,
-- core/folder_picker.lua), so they read like confirm/select above.
-- ------------------------------------------------------------

-- Button row text: { { key = 'd', text = 'Delete 2 selected', default = true }, … }
-- -> '[D] delete 2 selected   [b] browse…   [c] cancel' plus each button's
-- 0-based byte span (after `indent`). The default (<CR>) key is uppercase.
function M.button_row(buttons, indent)
  local row = indent or ''
  local spans = {}
  for i, b in ipairs(buttons) do
    if i > 1 then row = row .. '   ' end
    local tag = '[' .. (b.default and b.key:upper() or b.key:lower()) .. '] '
      .. lower_first(b.text)
    spans[i] = { #row, #row + #tag }
    row = row .. tag
  end
  return row, spans
end

-- Highlight for a button: the default one like confirm's default.
function M.button_hl(b)
  return b.hl or (b.default and 'MoreMsg' or 'Normal')
end

-- Current-row marker for a focused list float: the line in Visual and a
-- ▶ in column 0 (the rows start with blank columns), as M.select draws it.
function M.mark_cursor(win, buf)
  local mns = vim.api.nvim_create_namespace('core_confirm_cursor')
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = 'CursorLine:Visual'
  local function paint()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.api.nvim_buf_clear_namespace(buf, mns, 0, -1)
    if not vim.api.nvim_win_is_valid(win) then return end
    local row = vim.api.nvim_win_get_cursor(win)[1]
    pcall(vim.api.nvim_buf_set_extmark, buf, mns, row - 1, 0, {
      virt_text = { { '▶', 'MoreMsg' } }, virt_text_pos = 'overlay', priority = 300,
    })
  end
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'TextChanged' }, { buffer = buf, callback = paint })
  return paint
end

local KEYS = '123456789abcdefghijklmnopqrstuvwxyz'

function M.select(items, opts, on_choice)
  opts = opts or {}
  local n = #items
  if n == 0 then on_choice(nil, nil); return end
  local fmt = opts.format_item or tostring
  local buttons = opts.buttons or {}

  -- Row keys: digits, then letters not already used for moving, cancelling
  -- or a button.
  local taken = { j = true, k = true, q = true, g = true }
  for _, b in ipairs(buttons) do taken[b.key:lower()] = true end
  local keys = {}
  for c in KEYS:gmatch('.') do if not taken[c] then keys[#keys + 1] = c end end

  local mains, details, hay = {}, {}, {}
  local mainw = 0
  for i, it in ipairs(items) do
    mains[i] = fmt(it)
    details[i] = opts.detail and opts.detail(it) or ''
    hay[i] = (mains[i] .. ' ' .. details[i]):lower()
    mainw = math.max(mainw, vim.fn.strdisplaywidth(mains[i]))
  end

  local default = 1
  if type(opts.default) == 'number' and items[opts.default] ~= nil then
    default = opts.default
  elseif opts.default ~= nil then
    for i, it in ipairs(items) do if it == opts.default then default = i; break end end
  end

  local filter            -- nil: not filtering; a string while filtering
  local visible = {}      -- item indices shown, in order
  local cur, top = 1, 1   -- highlighted row / first row shown (in visible)

  local function line_for(pos, i)
    local key = keys[pos] or ' '
    local l = ('  %s  %s'):format(key, mains[i])
    if details[i] ~= '' then
      l = l .. (' '):rep(mainw - vim.fn.strdisplaywidth(mains[i]) + 3) .. details[i]
    end
    return l .. ' '
  end

  local function footer_text()
    local parts = { '<CR> pick', 'j/k move' }
    local nk = math.min(#visible, #keys)
    if nk > 0 then
      parts[#parts + 1] = (nk <= 9 and ('1-' .. nk) or ('1-9, ' .. keys[10] .. '-' .. keys[nk])) .. ' pick'
    end
    parts[#parts + 1] = '/ filter'
    for _, b in ipairs(buttons) do
      parts[#parts + 1] = '[' .. b.key:lower() .. '] ' .. lower_first(b.text)
    end
    parts[#parts + 1] = '<Esc> cancel'
    return ' ' .. table.concat(parts, '   ') .. ' '
  end

  -- Fixed size, from the full list.
  local width = vim.fn.strdisplaywidth(' ' .. (opts.prompt or 'Select') .. '  /' .. (' '):rep(12))
  for i = 1, n do width = math.max(width, vim.fn.strdisplaywidth(line_for(i, i))) end
  visible = {}
  for i = 1, n do visible[i] = i end
  width = math.max(width, vim.fn.strdisplaywidth(footer_text()) + 2)
  width = math.min(width, math.max(20, vim.o.columns - 6))
  local height = math.min(n, opts.max_height or 20, math.max(1, vim.o.lines - 8))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    title = ' ' .. (opts.prompt or 'Select') .. ' ', title_pos = 'center',
    footer = { { footer_text(), 'Comment' } }, footer_pos = 'center',
    focusable = false, zindex = 250, width = width, height = height,
    mouse = true,   -- see confirm(): without it a click on a row lands underneath and cancels
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
  })
  local sel = vim.api.nvim_create_namespace('core_confirm_sel')

  local function refilter()
    visible = {}
    local f = filter and filter:lower() or ''
    for i = 1, n do
      if f == '' or hay[i]:find(f, 1, true) then visible[#visible + 1] = i end
    end
    cur, top = 1, 1
  end

  local function render()
    local lines = {}
    for pos, i in ipairs(visible) do lines[pos] = line_for(pos, i) end
    if #visible == 0 then lines[1] = '  (no match)' end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf, sel, 0, -1)
    for pos, i in ipairs(visible) do
      vim.api.nvim_buf_set_extmark(buf, ns, pos - 1, 2, { end_col = 3, hl_group = 'Number' })
      local dstart = 5 + #mains[i]
      if #lines[pos] > dstart then
        vim.api.nvim_buf_set_extmark(buf, ns, pos - 1, dstart,
          { end_col = #lines[pos], hl_group = 'Comment' })
      end
    end
    if #visible > 0 then
      if cur < top then top = cur end
      if cur > top + height - 1 then top = cur - height + 1 end
      vim.api.nvim_buf_set_extmark(buf, sel, cur - 1, 0, {
        line_hl_group = 'Visual', virt_text = { { '▶', 'MoreMsg' } },
        virt_text_pos = 'overlay', priority = 300,
      })
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ topline = top, lnum = cur, col = 0 })
      end)
    end
    local title = ' ' .. (opts.prompt or 'Select') .. ' '
    if filter then title = title .. ' /' .. filter .. '▏ ' end
    vim.api.nvim_win_set_config(win, {
      title = title, title_pos = 'center',
      footer = { { footer_text(), 'Comment' } }, footer_pos = 'center',
    })
  end

  visible = {}
  for i = 1, n do visible[i] = i end
  cur = default

  local K = function(s) return vim.keycode(s) end
  local down = { [K('<Down>')] = true, [K('<C-n>')] = true, [K('<ScrollWheelDown>')] = true }
  local up   = { [K('<Up>')] = true,   [K('<C-p>')] = true, [K('<ScrollWheelUp>')] = true }
  local BS, CD, CU = K('<BS>'), K('<C-d>'), K('<C-u>')
  local PGDN, PGUP = K('<PageDown>'), K('<PageUp>')
  local CLICK = K('<LeftMouse>')

  local result, result_idx, done = nil, nil, false
  local function pick(pos)
    local i = visible[pos]
    if i then result, result_idx, done = items[i], i, true end
  end

  while not done do
    render()
    vim.cmd('redraw')
    local ok, c = pcall(vim.fn.getcharstr)
    local m = #visible
    if not ok or c == '\3' then break end                              -- <C-c>
    if c == '\27' then                                                 -- <Esc>
      if filter then filter = nil; refilter() else break end
    elseif c == '\r' or c == '\n' then pick(cur)
    elseif down[c] then if m > 0 then cur = cur % m + 1 end
    elseif up[c] then if m > 0 then cur = (cur - 2) % m + 1 end
    elseif c == CD or c == PGDN then cur = math.min(m, cur + height)
    elseif c == CU or c == PGUP then cur = math.max(1, cur - height)
    elseif c == CLICK then
      local pos = vim.fn.getmousepos()
      if pos.winid ~= win then break end
      if pos.line >= 1 then pick(pos.line) end
    elseif filter then
      if c == BS or c == '\8' then
        filter = filter:sub(1, -2); refilter()
      elseif #c == 1 and c:byte() >= 32 and c:byte() ~= 127 then
        filter = filter .. c; refilter()
      end
    elseif c == 'q' then break
    elseif c == 'j' then if m > 0 then cur = cur % m + 1 end
    elseif c == 'k' then if m > 0 then cur = (cur - 2) % m + 1 end
    elseif c == 'g' then cur = 1
    elseif c == 'G' then cur = math.max(1, m)
    elseif c == '/' then filter = ''; refilter()
    else
      for _, b in ipairs(buttons) do
        if c:lower() == b.key:lower() then result, done = b.value, true; break end
      end
      if not done then
        for pos = 1, math.min(m, #keys) do
          if keys[pos] == c:lower() then pick(pos); break end
        end
      end
    end
  end

  if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  vim.cmd('redraw')
  on_choice(result, result_idx)
end

return M
