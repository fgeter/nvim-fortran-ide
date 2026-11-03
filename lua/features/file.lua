-- ============================================================
-- features/file.lua — <leader>F: File (new, open, save, close, quit)
--
-- The keymaps behind the menu bar's File drop-down (features/topbar.lua),
-- which also lists the existing <leader>rf (recent files) and <leader>bd
-- (close file, keeping the layout).
--
--   Fn  new file                     Fs  save            (state: unsaved)
--   Fo  open… (browse any folder)    FS  save as…
--   Ff  find file in project         Fa  save all        (state: n unsaved)
--   Fe  show in file explorer        FR  reload from disk
--   Fm  rename / move file…          Fp  copy file path
--   FC  close all files (asks about each unsaved one)
--   Fr  restart Neovim (:restart; asks about unsaved files first)
--   Fq  quit (asks about unsaved files)
--
-- Part of making every essential action reachable from the menus, so the
-- editor stays usable with Vim keybindings turned off. Added 2026-11-03.
-- ============================================================

local M = {}

local function map(lhs, rhs, desc)
  vim.keymap.set('n', '<leader>' .. lhs, rhs, { desc = 'File: ' .. desc, silent = true })
end

local function info(msg, level) vim.notify(msg, level or vim.log.levels.INFO) end

-- The file in the current window, or nil for an unnamed / special buffer.
local function current_file()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= '' then return nil end
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= '' and name or nil
end

local function modified_files()
  local n = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.bo[b].modified and vim.bo[b].buftype == '' then n = n + 1 end
  end
  return n
end

-- ── New / open ───────────────────────────────────────────────
map('Fn', '<Cmd>enew<CR>', 'new file')

-- telescope-file-browser is on disk but not loaded at startup; load it the
-- first time it's needed. Starts in the current file's folder.
map('Fo', function()
  local telescope = require('telescope')
  -- Load first, then ask: telescope.extensions.<name> throws (rather than
  -- returning nil) for an extension that isn't loaded yet.
  pcall(vim.cmd.packadd, 'telescope-file-browser.nvim')   -- no-op once loaded
  if not pcall(telescope.load_extension, 'file_browser') then
    info('File browser not available; showing project files instead', vim.log.levels.WARN)
    require('telescope.builtin').find_files()
    return
  end
  local file = current_file()
  telescope.extensions.file_browser.file_browser({
    path = file and vim.fn.fnamemodify(file, ':h') or vim.fn.getcwd(),
    hidden = true,
    grouped = true,
  })
end, 'open… (browse folders)')

map('Ff', function() require('telescope.builtin').find_files() end, 'find file in project')

map('Fe', '<Cmd>Neotree reveal<CR>', 'show in file explorer')

-- ── Save ─────────────────────────────────────────────────────
local function save_as(default)
  vim.ui.input({ prompt = 'Save as: ', default = default, completion = 'file' }, function(path)
    if not path or vim.trim(path) == '' then return end
    path = vim.fn.fnamemodify(vim.fn.expand(vim.trim(path)), ':p')
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    local ok, err = pcall(vim.cmd, 'saveas ' .. vim.fn.fnameescape(path))
    if not ok then
      if tostring(err):find('E13') then   -- file exists
        if vim.fn.confirm(path .. ' exists. Overwrite?', '&Yes\n&No', 2) == 1 then
          ok, err = pcall(vim.cmd, 'saveas! ' .. vim.fn.fnameescape(path))
        else
          return
        end
      end
      if not ok then info('Save as failed: ' .. tostring(err), vim.log.levels.ERROR) return end
    end
    info('Saved ' .. vim.fn.fnamemodify(path, ':~:.'))
  end)
end

map('Fs', function()
  if vim.bo.buftype ~= '' then info('This window is not a file') return end
  if not current_file() then save_as(vim.fn.getcwd() .. '/') return end
  local ok, err = pcall(vim.cmd, 'write')
  if not ok then info('Save failed: ' .. tostring(err), vim.log.levels.ERROR) end
end, 'save')

map('FS', function()
  local file = current_file()
  save_as(file and vim.fn.fnamemodify(file, ':~:.') or (vim.fn.getcwd() .. '/'))
end, 'save as…')

map('Fa', function()
  local n = modified_files()
  local ok, err = pcall(vim.cmd, 'wall')
  if not ok then info('Save all: ' .. tostring(err), vim.log.levels.ERROR) return end
  info(n == 0 and 'Nothing to save' or ('Saved %d file%s'):format(n, n == 1 and '' or 's'))
end, 'save all')

-- ── Reload / rename / path ───────────────────────────────────
map('FR', function()
  if not current_file() then info('This window is not a saved file') return end
  if vim.bo.modified and vim.fn.confirm('Discard unsaved changes and reload from disk?',
      '&Reload\n&Cancel', 2) ~= 1 then
    return
  end
  vim.cmd('edit!')
  info('Reloaded from disk')
end, 'reload from disk')

map('Fm', function()
  local old = current_file()
  if not old then info('Save the file first') return end
  vim.ui.input({ prompt = 'Rename / move to: ', default = vim.fn.fnamemodify(old, ':~:.'),
                 completion = 'file' }, function(new)
    if not new or vim.trim(new) == '' then return end
    new = vim.fn.fnamemodify(vim.fn.expand(vim.trim(new)), ':p')
    if new == old then return end
    if vim.uv.fs_stat(new) then info(new .. ' already exists', vim.log.levels.ERROR) return end
    if vim.bo.modified then vim.cmd('write') end
    vim.fn.mkdir(vim.fn.fnamemodify(new, ':h'), 'p')
    local ok, err = vim.uv.fs_rename(old, new)
    if not ok then info('Rename failed: ' .. tostring(err), vim.log.levels.ERROR) return end
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(buf, new)
    vim.cmd('silent! write!')   -- re-associate the buffer with the new file
    info('Renamed to ' .. vim.fn.fnamemodify(new, ':~:.'))
  end)
end, 'rename / move file…')

map('Fp', function()
  local file = current_file()
  if not file then info('This window is not a saved file') return end
  vim.fn.setreg('+', file)
  info('Copied ' .. file)
end, 'copy file path')

-- ── Close all ────────────────────────────────────────────────
-- Close every open file, asking Save / Discard / Cancel for each one with
-- unsaved changes (Cancel stops and leaves the rest open). The layout
-- stays: editor windows are pointed at one empty buffer first, so deleting
-- the files closes no windows, and the file tree / terminals are untouched.
local function file_bufs()
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted and vim.bo[b].buftype == '' then
      out[#out + 1] = b
    end
  end
  return out
end

local function display_name(b)
  local name = vim.api.nvim_buf_get_name(b)
  return name ~= '' and vim.fn.fnamemodify(name, ':~:.') or '[unnamed]'
end

-- ── Showing what is unsaved ──────────────────────────────────
-- Before asking Save / Discard about a file, show it and highlight how it
-- differs from the copy on disk: added lines (DiffAdd), changed lines
-- (DiffChange), and deleted lines as greyed virtual lines where they were
-- (DiffDelete). gitsigns' +/~ signs can't answer this — they compare with
-- git, not with the saved file.
local unsaved_ns = vim.api.nvim_create_namespace('file-unsaved-changes')
local diff = (vim.text and vim.text.diff) or vim.diff

local function clear_unsaved(b)
  if vim.api.nvim_buf_is_valid(b) then vim.api.nvim_buf_clear_namespace(b, unsaved_ns, 0, -1) end
end

-- Returns counts { added, changed, deleted } and the first changed line.
local function mark_unsaved(b)
  clear_unsaved(b)
  local name = vim.api.nvim_buf_get_name(b)
  local disk = (name ~= '' and vim.fn.filereadable(name) == 1) and vim.fn.readfile(name) or {}
  local cur = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  local n = { added = 0, changed = 0, deleted = 0 }
  local first

  local function join(t) return #t == 0 and '' or (table.concat(t, '\n') .. '\n') end
  local hunks = diff(join(disk), join(cur), { result_type = 'indices' }) or {}
  for _, h in ipairs(hunks) do
    local sa, ca, sb, cb = h[1], h[2], h[3], h[4]
    -- Lines in the buffer that are new or different.
    for i = 0, cb - 1 do
      local lnum = sb + i
      local hl = (i < ca) and 'DiffChange' or 'DiffAdd'
      if hl == 'DiffChange' then n.changed = n.changed + 1 else n.added = n.added + 1 end
      vim.api.nvim_buf_set_extmark(b, unsaved_ns, lnum - 1, 0,
        { line_hl_group = hl, priority = 300 })
      first = first or lnum
    end
    -- Lines that are on disk but gone from the buffer.
    if ca > cb then
      local gone = {}
      for i = sa + cb, sa + ca - 1 do
        gone[#gone + 1] = { { ('− ' .. (disk[i] or '')), 'DiffDelete' } }
      end
      n.deleted = n.deleted + #gone
      -- After the last kept line of the hunk (sb + cb - 1), or above line 1.
      local anchor = (cb > 0) and (sb + cb - 1) or sb
      local above = anchor < 1
      anchor = math.max(1, math.min(anchor, #cur))
      if #cur > 0 then
        vim.api.nvim_buf_set_extmark(b, unsaved_ns, anchor - 1, 0,
          { virt_lines = gone, virt_lines_above = above, priority = 300 })
      end
      first = first or anchor
    end
  end
  return n, first
end

local function describe(n)
  local parts = {}
  if n.changed > 0 then parts[#parts + 1] = n.changed .. ' changed' end
  if n.added > 0 then parts[#parts + 1] = n.added .. ' added' end
  if n.deleted > 0 then parts[#parts + 1] = n.deleted .. ' deleted' end
  if #parts == 0 then return 'unsaved changes (no line differences)' end
  return table.concat(parts, ', ') .. ' line' .. ((n.changed + n.added + n.deleted) == 1 and '' or 's')
end

-- Put `b` in an editor window, cursor on `line`, and return a function
-- that puts back what that window showed before.
local function show(b, line)
  local win = vim.api.nvim_get_current_win()
  if not require('core.utils').is_editor_buf(vim.api.nvim_win_get_buf(win)) then
    win = require('core.utils').find_editor_win() or win
  end
  local prev_buf, prev_view = vim.api.nvim_win_get_buf(win), nil
  vim.api.nvim_win_call(win, function() prev_view = vim.fn.winsaveview() end)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_buf(win, b)
  if line then
    pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
    vim.cmd('normal! zz')
  end
  vim.cmd('redraw')
  return function()
    if prev_buf ~= b and vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(prev_buf) then
      pcall(vim.api.nvim_win_set_buf, win, prev_buf)
      pcall(vim.api.nvim_win_call, win, function() vim.fn.winrestview(prev_view) end)
    end
  end
end

-- Leave the highlights up for Review; drop them on the next edit or save.
local function keep_until_edited(b)
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost' }, {
    buffer = b, once = true,
    callback = function() clear_unsaved(b) end,
  })
end

-- true = OK to go on, false = stop (Cancel, Review, or a failed save).
local function settle_unsaved(b)
  if not vim.bo[b].modified then return true end
  local counts, first = mark_unsaved(b)
  local put_back = show(b, first)
  local choice = vim.fn.confirm(display_name(b) .. ': ' .. describe(counts) .. ' (highlighted).',
    '&Save\n&Discard\n&Review\n&Cancel', 1)

  if choice == 3 then          -- Review: stop here, keep the file and highlights up
    keep_until_edited(b)
    info('Unsaved changes in ' .. display_name(b) .. ' are highlighted. Run the command again when ready.')
    return false
  end
  clear_unsaved(b)
  if choice == 2 then put_back() return true end
  if choice ~= 1 then put_back() return false end

  local ok, err = pcall(vim.api.nvim_buf_call, b, function()
    if vim.api.nvim_buf_get_name(b) == '' then
      local path = vim.fn.input('Save as: ', vim.fn.getcwd() .. '/', 'file')
      if vim.trim(path) == '' then error('no file name') end
      vim.cmd('saveas ' .. vim.fn.fnameescape(vim.fn.fnamemodify(vim.fn.expand(path), ':p')))
    else
      vim.cmd('write')
    end
  end)
  put_back()
  if not ok then
    info('Not saved (' .. tostring(err):gsub('^.-:%d+: ', '') .. '); stopped', vim.log.levels.WARN)
    return false
  end
  return true
end

-- ── Close one file ───────────────────────────────────────────
-- Shared by <leader>bd (core/keymaps.lua), the buffer tabs' close button
-- (bufferline close_command in plugins/ui.lua) and the File menu: ask
-- about unsaved changes as above, then close the file without closing any
-- window — each window showing it switches to another open file (the
-- alternate one first), or to an empty buffer if it was the last.
function M.close_buffer(b)
  b = (b == nil or b == 0) and vim.api.nvim_get_current_buf() or b
  if not vim.api.nvim_buf_is_valid(b) then return false end
  if vim.bo[b].buftype ~= '' then   -- terminals, help, plugin panels: plain delete
    return pcall(vim.api.nvim_buf_delete, b, { force = false })
  end
  if not settle_unsaved(b) then return false end

  local alt = vim.fn.bufnr('#')
  local others = vim.tbl_filter(function(x)
    return x ~= b and vim.bo[x].buflisted and vim.bo[x].buftype == ''
  end, vim.api.nvim_list_bufs())
  local next_buf = (alt > 0 and vim.tbl_contains(others, alt)) and alt or others[1]
  if not next_buf then next_buf = vim.api.nvim_create_buf(true, false) end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == b then
      pcall(vim.api.nvim_win_set_buf, win, next_buf)
    end
  end
  -- force: unsaved changes were either just saved or deliberately discarded.
  return pcall(vim.api.nvim_buf_delete, b, { force = true })
end

map('FC', function()
  local bufs = file_bufs()
  if #bufs == 0 then info('No open files') return end
  for _, b in ipairs(bufs) do
    if not settle_unsaved(b) then return end
  end

  -- Windows can vanish while this loop runs: switching one window's buffer
  -- fires autocmds that close or rebuild others (notification floats,
  -- scrollbars, the menu bar's carrier), so check each one is still there.
  local empty = vim.api.nvim_create_buf(true, false)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_config(win).relative == ''
      and vim.tbl_contains(bufs, vim.api.nvim_win_get_buf(win)) then
      pcall(vim.api.nvim_win_set_buf, win, empty)
    end
  end
  local closed = 0
  for _, b in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(b) and pcall(vim.api.nvim_buf_delete, b, { force = true }) then
      closed = closed + 1
    end
  end
  info(('Closed %d file%s'):format(closed, closed == 1 and '' or 's'))
end, 'close all files (asks about unsaved)')

-- ── Restart ──────────────────────────────────────────────────
-- Neovim's own :restart (0.12+): saves the session, quits, starts a new
-- Nvim with the same arguments and restores the session. A plain :restart
-- refuses while anything is unsaved, so settle each unsaved file first
-- (same Save / Discard / Cancel as Close all). If any were discarded, quit
-- with :qall! so the discarded edits don't block the restart.
map('Fr', function()
  if vim.fn.exists(':restart') ~= 2 then
    info(':restart needs Neovim 0.12 or newer', vim.log.levels.WARN)
    return
  end
  local discarded = false
  for _, b in ipairs(file_bufs()) do
    if vim.bo[b].modified then
      if not settle_unsaved(b) then return end
      if vim.bo[b].modified then discarded = true end
    end
  end
  vim.cmd(discarded and 'restart +qall!' or 'restart')
end, 'restart Neovim (asks about unsaved)')

-- ── Quit ─────────────────────────────────────────────────────
map('Fq', '<Cmd>confirm qall<CR>', 'quit (asks about unsaved files)')

-- ── State column ─────────────────────────────────────────────
function M.state(key, _, buf)
  if key == 'Fs' then
    if buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == '' and vim.bo[buf].modified then
      return 'unsaved'
    end
    return nil
  end
  if key == 'Fa' then
    local n = modified_files()
    return n > 0 and (n .. ' unsaved') or nil
  end
  return nil
end

return M
