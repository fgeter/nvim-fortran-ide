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
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
  })
  vim.wo[win].wrap = true
  vim.wo[win].winhighlight = 'NormalFloat:NormalFloat,FloatBorder:FloatBorder'

  local answer = 0
  while true do
    vim.cmd('redraw')
    local ok, c = pcall(vim.fn.getcharstr)
    if not ok or c == '\27' or c == '\3' then answer = 0; break end   -- <Esc>, <C-c>
    if c == '\r' or c == '\n' then
      if default > 0 then answer = default; break end
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
-- one entry from a short list. Same signature as vim.ui.select, so it can
-- stand in for it around a plugin call (see <leader>cp in
-- plugins/cmake-tools.lua). It is NOT installed as vim.ui.select: long
-- lists still want telescope's fuzzy filter.
--
--     ╭──────── Select CMake preset ────────╮
--     │  1  gfortran_debug_linux    gfortran…│
--     │▶ 2  gfortran_release_linux  gfortran…│   <- highlighted
--     │                                      │
--     │ <CR> pick   j/k move   1-9 pick   <Esc> cancel │
--     ╰──────────────────────────────────────╯
--
-- The highlighted row starts on opts.default (an item, or its index) and
-- <CR> picks it, so "keep what I have" is one keypress. j/k or the arrow
-- keys move, a row's number or letter picks it directly, <Esc>/<C-c>/q
-- cancel. on_choice(item, idx), or on_choice(nil, nil) on cancel.
--
--   opts.prompt       window title
--   opts.format_item  item -> main text (default tostring)
--   opts.detail       item -> dimmed text after it (optional)
--   opts.default      item or index highlighted first
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

local KEYS = '123456789abcdefghijklmnoprstuvwxyz'   -- no j/k/q: they move / cancel
KEYS = KEYS:gsub('[jkq]', '')

function M.select(items, opts, on_choice)
  opts = opts or {}
  local n = #items
  if n == 0 then on_choice(nil, nil); return end
  local fmt = opts.format_item or tostring

  local cur = 1
  if type(opts.default) == 'number' and items[opts.default] ~= nil then
    cur = opts.default
  elseif opts.default ~= nil then
    for i, it in ipairs(items) do if it == opts.default then cur = i; break end end
  end

  local mainw = 0
  for _, it in ipairs(items) do mainw = math.max(mainw, vim.fn.strdisplaywidth(fmt(it))) end
  local lines, keyof = {}, {}
  for i, it in ipairs(items) do
    local k = KEYS:sub(i, i)
    keyof[i] = k ~= '' and k or nil
    local main = fmt(it)
    local line = ('  %s  %s'):format(keyof[i] or ' ', main)
    if opts.detail then
      local d = opts.detail(it)
      if d and d ~= '' then
        line = line .. string.rep(' ', mainw - vim.fn.strdisplaywidth(main) + 3) .. d
      end
    end
    lines[i] = line .. ' '
  end
  local last = keyof[n] and (n <= 9 and ('1-' .. n) or ('1-9, a-' .. keyof[n])) or '1-9'
  lines[n + 1] = ''
  lines[n + 2] = (' <CR> pick   j/k move   %s pick   <Esc> cancel '):format(last)

  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(width, math.max(20, vim.o.columns - 6))
  local height = math.min(#lines, math.max(1, vim.o.lines - 4))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  for i = 1, n do   -- key column and detail text
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 2, { end_col = 3, hl_group = 'Number' })
    local dstart = 5 + #fmt(items[i])
    if #lines[i] > dstart then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, dstart, { end_col = #lines[i], hl_group = 'Comment' })
    end
  end
  vim.api.nvim_buf_set_extmark(buf, ns, n + 1, 0, { end_col = #lines[n + 2], hl_group = 'Comment' })

  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    title = ' ' .. (opts.prompt or 'Select') .. ' ', title_pos = 'center',
    focusable = false, zindex = 250, width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
  })

  local sel = vim.api.nvim_create_namespace('core_confirm_sel')
  local function paint()
    vim.api.nvim_buf_clear_namespace(buf, sel, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, sel, cur - 1, 0, {
      line_hl_group = 'Visual', virt_text = { { '▶', 'MoreMsg' } },
      virt_text_pos = 'overlay', priority = 300,
    })
  end

  local down, up = vim.keycode('<Down>'), vim.keycode('<Up>')
  local pick
  while true do
    paint()
    vim.cmd('redraw')
    local ok, c = pcall(vim.fn.getcharstr)
    if not ok or c == '\27' or c == '\3' or c == 'q' then break end
    if c == '\r' or c == '\n' then pick = cur; break end
    if c == 'j' or c == down then cur = cur % n + 1
    elseif c == 'k' or c == up then cur = (cur - 2) % n + 1
    else
      for i = 1, n do
        if keyof[i] == c:lower() then pick = i; break end
      end
      if pick then break end
    end
  end

  if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  vim.cmd('redraw')
  if pick then on_choice(items[pick], pick) else on_choice(nil, nil) end
end

return M
