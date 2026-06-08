-- ============================================================
-- core/keymaps.lua — Global keymaps not tied to any plugin
--
-- Plugin-specific keymaps (telescope, dap, cmake, etc.) live
-- in their respective files in lua/plugins/.
-- ============================================================

-- Clear search highlights when pressing <Esc> in normal mode.
-- Without this the highlights persist until the next search.
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Save the current buffer. <C-s> is familiar from most editors.
vim.keymap.set('n', '<C-s>', '<cmd>w<cr>', { desc = 'Save file' })

-- ── Window navigation ────────────────────────────────────────
-- Use CTRL+hjkl to move between splits without pressing <C-w> first
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Focus left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Focus right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Focus lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Focus upper window' })

-- ── Buffer navigation ────────────────────────────────────────
-- NOTE: <tab> intentionally NOT used here. In many terminals <tab> and
-- <C-i> send the same keycode, so mapping <tab> would break <C-i>
-- (jump forward in the jump list). Use <leader>bn / <leader>bp instead.
vim.keymap.set('n', '<leader>bn', ':bnext<CR>',   { silent = true, desc = 'Buffer: next' })
vim.keymap.set('n', '<leader>bp', ':bprev<CR>',   { silent = true, desc = 'Buffer: previous' })

-- Tab navigation (]] / [[ from init.lua, kept here for discoverability)
vim.keymap.set('n', ']]', ':tabn<CR>',        { silent = true, desc = 'Tab: next' })
vim.keymap.set('n', '[[', ':tabprevious<CR>', { silent = true, desc = 'Tab: previous' })

-- Delete the current buffer without destroying the window layout.
-- If the buffer has unsaved changes, Neovim's built-in prompt appears.
-- If saved, switches to the previous buffer first so the window stays open.
vim.keymap.set('n', '<leader>bd', function()
  local buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_get_option_value('modified', { buf = buf }) then
    -- Let Neovim show its "save?" dialog
    local ok = pcall(vim.cmd, 'bdelete ' .. buf)
    if not ok then return end   -- user cancelled
  else
    vim.cmd('bprevious')
    pcall(vim.cmd, 'bdelete ' .. buf)
  end
end, { silent = true, desc = 'Buffer: delete (keep layout)' })

-- ── Terminal ─────────────────────────────────────────────────
-- <Esc><Esc> exits terminal insert mode. The default <C-\><C-n> is
-- hard to discover and awkward to type.
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Terminal: exit insert mode' })

-- ── Diagnostics ──────────────────────────────────────────────
-- Open all diagnostics for the current buffer in the quickfix list
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Diagnostics: quickfix list' })

-- ── Go-to-file with line number ──────────────────────────────
-- gF opens a file:line reference from a compiler error in a split above
-- the terminal. Handles full absolute paths, e.g.:
--   /home/fgeter/.../src/gwflow_read.f90:32:5: error: ...
--
-- Two mappings:
--   gF       (normal mode) — use after <Esc><Esc> in the terminal buffer
--   <C-g>f   (terminal mode) — use directly without leaving insert mode
local function open_file_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col  = vim.api.nvim_win_get_cursor(0)[2] + 1  -- 1-based

  -- Scan the whole line for file:line patterns so that ':' inside the
  -- path doesn't break the match (the old word-boundary approach failed
  -- on absolute paths like /home/user/src/file.f90:32).
  local candidates = {}

  -- Absolute paths: /something/file.ext:LINE
  -- %.%w+ matches extensions with digits e.g. .f90 .f95 .cpp .h5
  -- (%.%a+ was wrong — %a matches only letters, so .f90 failed at '90')
  for s, fname, lnum, e in line:gmatch('()(/[%w%.%_%-/]+%.%w+):(%d+)()') do
    if vim.fn.filereadable(fname) == 1 then
      table.insert(candidates, { fname=fname, lnum=tonumber(lnum), start=s, stop=e })
    end
  end
  -- Relative paths: some/file.ext:LINE
  if #candidates == 0 then
    for s, fname, lnum, e in line:gmatch('()([%w%.%_%-][%w%.%_%-/]*%.%w+):(%d+)()') do
      if vim.fn.filereadable(fname) == 1 then
        table.insert(candidates, { fname=fname, lnum=tonumber(lnum), start=s, stop=e })
      end
    end
  end

  if #candidates == 0 then
    vim.notify('No valid file:line found on this line', vim.log.levels.WARN)
    return
  end

  -- Pick the candidate whose span contains or is nearest to the cursor
  local best, best_dist = candidates[1], math.huge
  for _, c in ipairs(candidates) do
    if col >= c.start and col <= c.stop then
      best = c; break
    end
    local dist = math.min(math.abs(col - c.start), math.abs(col - c.stop))
    if dist < best_dist then best_dist = dist; best = c end
  end

  -- Find an existing editor window to reuse, or create one above the terminal.
  local current_win = vim.api.nvim_get_current_win()
  local target_win  = require('core.utils').find_editor_win()
  -- Exclude the terminal window itself from consideration
  if target_win == current_win then target_win = nil end

  if not target_win then
    -- No editor window exists — create a split above the current window
    vim.cmd('split')
    vim.cmd('wincmd K')
    target_win = vim.api.nvim_get_current_win()
  end

  -- Switch to the target window and open the file there with :edit so it
  -- replaces the current buffer in that window rather than opening a new split
  vim.api.nvim_set_current_win(target_win)
  vim.cmd('edit ' .. vim.fn.fnameescape(best.fname))
  vim.cmd(tostring(best.lnum))
  vim.cmd('normal! zz')  -- centre the error line in the window
end

-- Normal mode (after <Esc><Esc> to exit terminal insert mode)
vim.keymap.set('n', 'gF', open_file_at_cursor,
  { desc = 'Go to file:line under cursor (compiler error)' })

-- Terminal insert mode — no need to exit insert mode first.
-- <C-g>f is safe: <C-g> is not used by bash/zsh readline.
vim.keymap.set('t', '<C-g>f', function()
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true), 'n', false)
  vim.schedule(open_file_at_cursor)
end, { desc = 'Go to file:line under cursor (terminal insert mode)' })

