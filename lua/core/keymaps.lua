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
-- gF opens the file:line string under the cursor in a new upper-right
-- split. Useful when reading compiler error output that shows filenames
-- with line numbers (e.g. "src/main.f90:123").
vim.keymap.set('n', 'gF', function()
  local line = vim.api.nvim_get_current_line()
  local col  = vim.api.nvim_win_get_cursor(0)[2] + 1

  -- Find the word boundary around the cursor
  local s = col
  while s > 1 and not line:sub(s-1, s-1):match('[%s"\'"]') do s = s - 1 end
  local e = col
  while e <= #line and not line:sub(e, e):match('[%s"\'"]') do e = e + 1 end

  local target = line:sub(s, e - 1)
  local fname, lnum = target:match('([^:]+):(%d+)')

  if fname and lnum and vim.fn.filereadable(fname) == 1 then
    vim.cmd('split ' .. vim.fn.fnameescape(fname))
    vim.cmd('wincmd L')
    vim.cmd('wincmd K')
    vim.cmd(lnum)
  else
    local ok = pcall(vim.cmd, 'normal! \\<C-w>f')
    if ok then
      vim.cmd('wincmd L')
      vim.cmd('wincmd K')
    else
      vim.notify('No valid file found under cursor', vim.log.levels.WARN)
    end
  end
end, { desc = 'Go to file:line in upper-right split' })
