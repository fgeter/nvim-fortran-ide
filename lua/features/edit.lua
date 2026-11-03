-- ============================================================
-- features/edit.lua — <leader>E: Edit (indentation, language, file format)
--
-- The keymaps behind the menu bar's Edit drop-down (features/topbar.lua).
-- <leader>e was taken (LSP diagnostic float), hence the capital E.
--
--   Ez/EZ undo / redo     Ek/Ey/EV cut / copy / paste     Ea select all
--   E/  comment           Es/En/EN find / next / previous  Er replace all
--   ER  replace one by one (Replace / Skip / Replace all remaining / Stop)
--   Eg  go to line
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

-- Normal + visual. The menu bar re-selects (gv) before feeding the keys
-- when it was opened from visual mode, so the visual side gets the
-- selection — the same as typing the chord with text selected.
local function map_nx(lhs, n_rhs, x_rhs, desc, remap)
  vim.keymap.set('n', '<leader>' .. lhs, n_rhs, { desc = 'Edit: ' .. desc, silent = true, remap = remap })
  vim.keymap.set('x', '<leader>' .. lhs, x_rhs, { desc = 'Edit: ' .. desc, silent = true, remap = remap })
end

-- ── Basic editing ────────────────────────────────────────────
-- What every editor's Edit menu has, so nothing here needs Vim keys.
-- Clipboard actions use the system clipboard (+), which core/options.lua
-- routes over OSC 52 in SSH sessions. With nothing selected, Cut and Copy
-- take the whole line, as VS Code does.
map('Ez', '<Cmd>undo<CR>', 'undo')
map('EZ', '<Cmd>redo<CR>', 'redo')
map_nx('Ek', '"+dd', '"+d', 'cut (line, or selection)')
map_nx('Ey', '"+yy', '"+y', 'copy (line, or selection)')
map_nx('EV', '"+P', '"_d"+P', 'paste (replaces a selection)')
map('Ea', 'ggVG', 'select all')
-- gc / gcc are Neovim's built-in comment operator; remap so they resolve.
map_nx('E/', 'gcc', 'gc', 'comment / uncomment (line, or selection)', true)

-- ── Find / replace in this file ──────────────────────────────
-- Plain text, not Vim regex: \V makes everything literal except the
-- backslash, which is escaped too.
local function literal(text) return '\\V' .. text:gsub('\\', '\\\\'):gsub('/', '\\/') end
local last_find = ''

map('Es', function()
  vim.ui.input({ prompt = 'Find in file: ', default = last_find }, function(text)
    if not text or text == '' then return end
    last_find = text
    vim.fn.setreg('/', literal(text))
    vim.o.hlsearch = true
    if vim.fn.search(vim.fn.getreg('/'), 'cw') == 0 then
      info('Not found: ' .. text, vim.log.levels.WARN)
    else
      local c = vim.fn.searchcount({ recompute = true, maxcount = 9999 })
      info(('Found %d match%s (Find next / previous to move)'):format(c.total or 0, (c.total == 1) and '' or 'es'))
    end
  end)
end, 'find in file…')

local function find_again(flags)
  if vim.fn.getreg('/') == '' then info('Nothing to find yet: use Find in file first') return end
  vim.o.hlsearch = true
  if vim.fn.search(vim.fn.getreg('/'), flags) == 0 then info('Not found', vim.log.levels.WARN) end
end
map('En', function() find_again('w') end,  'find next')
map('EN', function() find_again('bw') end, 'find previous')

-- ── Replace (all, or one by one) ─────────────────────────────
-- Both work on the whole file, or — when started with text selected — on
-- exactly the selected text: only matches lying entirely inside the
-- highlight count, whether it is a character, line or block selection.
--
-- A region is { [lnum] = { first_col, last_col } } (1-based, inclusive,
-- from getregionpos), or nil for the whole file.
local function selection_region()
  local region, first, last = {}, nil, nil
  for _, span in ipairs(vim.fn.getregionpos(vim.fn.getpos('v'), vim.fn.getpos('.'),
                                            { type = vim.fn.mode() })) do
    local lnum = span[1][2]
    local last_col = span[2][3]
    -- Cover the whole last character when it is multibyte (é, ─, …).
    local line = vim.fn.getline(lnum)
    if last_col >= 1 and last_col <= #line then
      last_col = last_col + #vim.fn.strcharpart(line:sub(last_col), 0, 1) - 1
    end
    region[lnum] = { span[1][3], last_col }
    first = math.min(first or lnum, lnum)
    last  = math.max(last or lnum, lnum)
  end
  return region, first, last
end

-- Every match of `pat` in the region, top to bottom, non-overlapping:
-- { row, col (0-based), end_col (0-based, exclusive) }.
local function collect_matches(buf, pat, region, first, last)
  local matches = {}
  local save = vim.fn.winsaveview()
  vim.api.nvim_win_set_cursor(0, { first, 0 })
  local flags = 'cW'
  while true do
    local pos = vim.fn.searchpos(pat, flags, last)
    if pos[1] == 0 then break end
    local row, col = pos[1], pos[2] - 1
    local stop = vim.fn.searchpos(pat, 'cnWe', last)
    if stop[1] ~= row then break end            -- no multi-line matches
    local end_col = stop[2]                     -- byte after the last char…
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    end_col = end_col + #vim.fn.strcharpart(line:sub(end_col), 0, 1) - 1   -- …of a multibyte char
    local span = region and region[row]
    if not region or (span and col + 1 >= span[1] and end_col <= span[2]) then
      matches[#matches + 1] = { row, col, end_col }
    end
    -- Continue after this match (non-overlapping, like :s).
    if end_col >= #line then
      if row >= last then break end
      vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
    else
      vim.api.nvim_win_set_cursor(0, { row, end_col })
    end
    flags = 'cW'
  end
  vim.fn.winrestview(save)
  return matches
end

-- Ask for "find" and "replace with", then hand over the matches.
local function ask(prompt, then_do)
  vim.ui.input({ prompt = prompt, default = last_find }, function(find)
    if not find or find == '' then return end
    last_find = find
    vim.ui.input({ prompt = 'Replace "' .. find .. '" with: ' }, function(with)
      if with ~= nil then then_do(find, with) end
    end)
  end)
end

-- Replace matches[i] for every i in `which`, last first so earlier
-- positions stay valid, as one undo step.
local function apply(buf, matches, which, with)
  table.sort(which, function(a, b) return a > b end)
  for n, i in ipairs(which) do
    local m = matches[i]
    if n > 1 then pcall(vim.cmd, 'undojoin') end
    vim.api.nvim_buf_set_text(buf, m[1] - 1, m[2], m[1] - 1, m[3], { with })
  end
end

local function where(region) return region and 'in selection' or 'in file' end

local function replace_all(region, first, last)
  ask('Replace all ' .. where(region) .. ': ', function(find, with)
    local buf = vim.api.nvim_get_current_buf()
    local matches = collect_matches(buf, literal(find), region, first, last)
    if #matches == 0 then info('Not found ' .. where(region) .. ': ' .. find, vim.log.levels.WARN) return end
    local all = {}
    for i = 1, #matches do all[i] = i end
    local view = vim.fn.winsaveview()
    apply(buf, matches, all, with)
    vim.fn.winrestview(view)
    info(('Replaced %d match%s %s (Undo to put back)'):format(#matches,
      #matches == 1 and '' or 'es', where(region)))
  end)
end

-- One by one: highlight each match and ask Replace / Skip / Replace all
-- remaining / Stop. Decisions are collected first and applied together at
-- the end, so positions never shift under the remaining matches.
local step_ns = vim.api.nvim_create_namespace('edit-replace-step')

local function replace_step(region, first, last)
  ask('Replace one by one ' .. where(region) .. ': ', function(find, with)
    local buf, pat = vim.api.nvim_get_current_buf(), literal(find)
    local matches = collect_matches(buf, pat, region, first, last)
    if #matches == 0 then info('Not found ' .. where(region) .. ': ' .. find, vim.log.levels.WARN) return end
    local view = vim.fn.winsaveview()
    vim.fn.setreg('/', pat)
    vim.o.hlsearch = true
    local chosen, skipped, all = {}, 0, false
    for i, m in ipairs(matches) do
      local choice = 1
      if not all then
        vim.api.nvim_buf_clear_namespace(buf, step_ns, 0, -1)
        -- Earlier choices are shown too: green for "will replace".
        for _, j in ipairs(chosen) do
          local c = matches[j]
          vim.api.nvim_buf_set_extmark(buf, step_ns, c[1] - 1, c[2], { end_col = c[3], hl_group = 'DiffAdd', priority = 390 })
        end
        vim.api.nvim_buf_set_extmark(buf, step_ns, m[1] - 1, m[2],
          { end_col = m[3], hl_group = 'IncSearch', priority = 400 })
        vim.api.nvim_win_set_cursor(0, { m[1], m[2] })
        vim.cmd('normal! zz')
        vim.cmd('redraw')
        choice = vim.fn.confirm(('Replace this "%s" (%d of %d, line %d)?'):format(find, i, #matches, m[1]),
          '&Replace\n&Skip\nReplace &all remaining\n&Stop', 1)
        if choice == 3 then all = true; choice = 1 end
      end
      if choice == 1 then chosen[#chosen + 1] = i
      elseif choice == 2 then skipped = skipped + 1
      else break end
    end
    vim.api.nvim_buf_clear_namespace(buf, step_ns, 0, -1)
    apply(buf, matches, chosen, with)
    vim.fn.winrestview(view)
    info(('Replaced %d, skipped %d%s'):format(#chosen, skipped,
      #chosen > 0 and ' (Undo puts back all replacements)' or ''))
  end)
end

-- Visual: capture the exact selection, leave visual mode, then ask.
local function from_selection(fn)
  return function()
    local region, first, last = selection_region()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    fn(region, first, last)
  end
end
local function whole_file(fn)
  return function() fn(nil, 1, vim.api.nvim_buf_line_count(0)) end
end

vim.keymap.set('n', '<leader>Er', whole_file(replace_all),
  { desc = 'Edit: replace all in file…', silent = true })
vim.keymap.set('x', '<leader>Er', from_selection(replace_all),
  { desc = 'Edit: replace all in selection…', silent = true })
vim.keymap.set('n', '<leader>ER', whole_file(replace_step),
  { desc = 'Edit: replace one by one…', silent = true })
vim.keymap.set('x', '<leader>ER', from_selection(replace_step),
  { desc = 'Edit: replace one by one in selection…', silent = true })

map('Eg', function()
  local last = vim.api.nvim_buf_line_count(0)
  vim.ui.input({ prompt = ('Go to line (1-%d): '):format(last) }, function(text)
    local n = tonumber(text or '')
    if not n then return end
    n = math.max(1, math.min(last, math.floor(n)))
    vim.api.nvim_win_set_cursor(0, { n, 0 })
    vim.cmd('normal! zz')
  end)
end, 'go to line…')

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
