-- ============================================================
-- features/edit.lua — <leader>E: Edit (indentation, language, file format)
--
-- The keymaps behind the menu bar's Edit drop-down (features/topbar.lua).
-- <leader>e was taken (LSP diagnostic float), hence the capital E.
--
--   Ew  tab width (picker: 2 / 3 / 4 / 8)      El  language / syntax (picker)
--   Et  indent with spaces / tabs (toggle)     Eh  syntax highlighting on/off
--   Ec  convert this file's indentation        Ee  line endings LF / CRLF
--   Ed  detect indentation from the file       Eu  file encoding (picker)
--   Ex  trim trailing whitespace               Ep  auto-close brackets on/off
--   Ef  format on save on/off (plugins/formatting.lua; it owns conform)
--
-- Everything acts on the current buffer. M.state(key, win, buf) feeds the
-- drop-down's state column: true/false for toggles, a short string for
-- settings with a value (tab width, language, …), nil for plain actions.
-- Added 2026-11-03.
-- ============================================================

local M = {}

local function map(lhs, rhs, desc)
  vim.keymap.set('n', '<leader>' .. lhs, rhs, { desc = 'Edit: ' .. desc, silent = true })
end

local function info(msg) vim.notify(msg, vim.log.levels.INFO) end

-- ── Indentation ──────────────────────────────────────────────
local function set_width(n)
  vim.bo.tabstop, vim.bo.shiftwidth, vim.bo.softtabstop = n, n, n
end

map('Ew', function()
  vim.ui.select({ 2, 3, 4, 8 }, {
    prompt = 'Tab width',
    format_item = function(n) return n .. ' columns' .. (n == vim.fn.shiftwidth() and '  ✓' or '') end,
  }, function(n)
    if not n then return end
    set_width(n)
    info('Tab width ' .. n)
  end)
end, 'tab width…')

map('Et', function()
  vim.bo.expandtab = not vim.bo.expandtab
  info('Indent with ' .. (vim.bo.expandtab and 'spaces' or 'tabs')
    .. ' (Edit › Convert to change existing lines)')
end, 'indent with spaces (toggle)')

-- Re-encode only *leading* whitespace, to whatever expandtab/tabstop say
-- now. (:retab! would also turn runs of spaces inside strings into tabs.)
map('Ec', function()
  local ts, spaces = vim.bo.tabstop, vim.bo.expandtab
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local changed = 0
  for i, line in ipairs(lines) do
    local lead = line:match('^[ \t]*')
    if lead ~= '' then
      local col = 0
      for c in lead:gmatch('.') do
        col = (c == '\t') and (col - col % ts + ts) or (col + 1)
      end
      local new = spaces and string.rep(' ', col)
        or (string.rep('\t', math.floor(col / ts)) .. string.rep(' ', col % ts))
      if new ~= lead then
        lines[i] = new .. line:sub(#lead + 1)
        changed = changed + 1
      end
    end
  end
  if changed == 0 then info('Indentation already uses ' .. (spaces and 'spaces' or 'tabs')) return end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  info(('Converted %d line%s to %s'):format(changed, changed == 1 and '' or 's',
    spaces and 'spaces' or 'tabs'))
end, 'convert indentation to current setting')

-- Guess from the file itself: tabs vs spaces by majority, and for spaces
-- the widest step (8, 4, 3, 2) that nearly every indented line fits.
map('Ed', function()
  local tabs, spaced, counts = 0, 0, {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, math.min(2000, vim.api.nvim_buf_line_count(0)), false)) do
    if line:match('^\t') then
      tabs = tabs + 1
    else
      local n = #(line:match('^ +') or '')
      if n > 0 and line:sub(n + 1, n + 1) ~= '*' then   -- skip ' * ' comment bodies
        spaced = spaced + 1
        counts[#counts + 1] = n
      end
    end
  end
  if tabs == 0 and spaced == 0 then info('No indented lines to learn from') return end
  if tabs > spaced then
    vim.bo.expandtab = false
    info(('Detected: tabs (%d tab-indented vs %d space-indented lines)'):format(tabs, spaced))
    return
  end
  local width = 2
  for _, w in ipairs({ 8, 4, 3, 2 }) do
    local fit = 0
    for _, n in ipairs(counts) do if n % w == 0 then fit = fit + 1 end end
    if fit >= 0.9 * #counts then width = w break end
  end
  vim.bo.expandtab = true
  set_width(width)
  info(('Detected: %d spaces'):format(width))
end, 'detect indentation from file')

map('Ex', function()
  local view = vim.fn.winsaveview()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local changed = 0
  for i, line in ipairs(lines) do
    local t = line:gsub('%s+$', '')
    if t ~= line then lines[i], changed = t, changed + 1 end
  end
  if changed > 0 then vim.api.nvim_buf_set_lines(0, 0, -1, false, lines) end
  vim.fn.winrestview(view)
  info(changed == 0 and 'No trailing whitespace' or ('Trimmed %d line%s'):format(changed, changed == 1 and '' or 's'))
end, 'trim trailing whitespace')

-- ── Language / highlighting ──────────────────────────────────
map('El', function()
  local cur = vim.bo.filetype
  vim.ui.select(vim.fn.getcompletion('', 'filetype'), {
    prompt = 'Language' .. (cur ~= '' and (' (now ' .. cur .. ')') or ''),
  }, function(ft)
    if ft then vim.bo.filetype = ft end
  end)
end, 'language / syntax…')

local function highlighting_on(buf)
  return vim.treesitter.highlighter.active[buf] ~= nil
    or (vim.bo[buf].syntax ~= '' and vim.bo[buf].syntax ~= 'OFF')
end

map('Eh', function()
  local buf = vim.api.nvim_get_current_buf()
  if highlighting_on(buf) then
    pcall(vim.treesitter.stop, buf)
    vim.bo[buf].syntax = 'OFF'
    info('Syntax highlighting off')
  else
    if not pcall(vim.treesitter.start, buf) then vim.bo[buf].syntax = vim.bo[buf].filetype end
    info('Syntax highlighting on')
  end
end, 'syntax highlighting (toggle)')

-- ── File format ──────────────────────────────────────────────
map('Ee', function()
  vim.bo.fileformat = vim.bo.fileformat == 'dos' and 'unix' or 'dos'
  info('Line endings ' .. (vim.bo.fileformat == 'dos' and 'CRLF (Windows)' or 'LF (Unix)')
    .. ' — applies when you save')
end, 'line endings LF / CRLF')

map('Eu', function()
  local cur = vim.bo.fileencoding ~= '' and vim.bo.fileencoding or vim.o.encoding
  vim.ui.select({ 'utf-8', 'utf-16le', 'utf-16', 'latin1', 'cp1252' }, {
    prompt = 'Save with encoding (now ' .. cur .. ')',
  }, function(enc)
    if not enc then return end
    vim.bo.fileencoding = enc
    info('Encoding ' .. enc .. ' — applies when you save')
  end)
end, 'file encoding…')

-- ── Typing helpers ───────────────────────────────────────────
map('Ep', function()
  local ap = require('nvim-autopairs')
  ap.toggle()
  info('Auto-close brackets ' .. (ap.state.disabled and 'off' or 'on'))
end, 'auto-close brackets (toggle)')

-- ── State column ─────────────────────────────────────────────
local STATES = {
  Ew = function() return tostring(vim.fn.shiftwidth()) end,
  Et = function(_, buf) return vim.bo[buf].expandtab end,
  El = function(_, buf) return vim.bo[buf].filetype ~= '' and vim.bo[buf].filetype or 'none' end,
  Eh = function(_, buf) return highlighting_on(buf) end,
  Ee = function(_, buf) return vim.bo[buf].fileformat == 'dos' and 'CRLF' or 'LF' end,
  Eu = function(_, buf) return vim.bo[buf].fileencoding ~= '' and vim.bo[buf].fileencoding or vim.o.encoding end,
  Ep = function()
    local ok, ap = pcall(require, 'nvim-autopairs')
    return ok and not ap.state.disabled
  end,
  Ef = function() return vim.g.format_on_save == true end,
}

function M.state(key, win, buf)
  local f = STATES[key]
  if not f then return nil end
  win = (win and vim.api.nvim_win_is_valid(win)) and win or vim.api.nvim_get_current_win()
  buf = (buf and vim.api.nvim_buf_is_valid(buf)) and buf or vim.api.nvim_win_get_buf(win)
  local ok, v
  if key == 'Ew' then
    ok, v = pcall(vim.api.nvim_buf_call, buf, f)
  else
    ok, v = pcall(f, win, buf)
  end
  if not ok then return nil end
  if type(v) == 'string' then return v end
  return v and true or false
end

return M
