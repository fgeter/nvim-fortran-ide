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

return M
