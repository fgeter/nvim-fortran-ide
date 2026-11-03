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

-- Tab navigation. gt/gT are native; ]t/[t match the unimpaired-style
-- motion family. [[/]] stay as Vim section jumps (and treesitter later).
vim.keymap.set('n', ']t', ':tabn<CR>',        { silent = true, desc = 'Tab: next' })
vim.keymap.set('n', '[t', ':tabprevious<CR>', { silent = true, desc = 'Tab: previous' })

-- Close the current file without destroying the window layout. Unsaved
-- changes get the File menu's Save / Discard / Review / Cancel prompt with
-- the changes highlighted (features/file.lua, loaded after this file —
-- hence required at call time).
vim.keymap.set('n', '<leader>bd', function()
  require('features.file').close_buffer(0)
end, { silent = true, desc = 'Buffer: close file (keep layout)' })

-- ── Terminal ─────────────────────────────────────────────────
-- <Esc><Esc> exits terminal insert mode. The default <C-\><C-n> is
-- hard to discover and awkward to type.
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Terminal: exit insert mode' })

-- ── Horizontal scrolling ─────────────────────────────────────
-- Only meaningful when wrap=false. The z-prefix commands are built-in
-- but undiscoverable; explicit mappings surface them in which-key.
vim.keymap.set('n', 'zl', '5zl', { desc = 'Scroll right ~1 word' })
vim.keymap.set('n', 'zh', '5zh', { desc = 'Scroll left ~1 word' })

vim.keymap.set('n', 'ze', 'ze', { desc = 'Scroll cursor to right edge' })
vim.keymap.set('n', 'zs', 'zs', { desc = 'Scroll cursor to left edge' })
-- Alt+arrow: move cursor 5 chars; window scrolls naturally when cursor
-- reaches the edge (standard Neovim sidescroll behaviour).
vim.keymap.set('n', '<A-Right>', function() vim.cmd('normal! 5l') end,
  { desc = 'Move cursor right 5 chars (hold to repeat)' })
vim.keymap.set('n', '<A-Left>', function() vim.cmd('normal! 5h') end,
  { desc = 'Move cursor left 5 chars (hold to repeat)' })

-- ── Hard text wrap ───────────────────────────────────────────
-- Toggle auto-wrapping of lines at textwidth columns (default 80).
-- This inserts *real* newlines as you type past the limit — distinct from
-- vim.o.wrap which only changes how long lines are displayed without modifying
-- the file. The 't' flag in formatoptions is what triggers insertion-time wrap.
-- Use :set textwidth=72 (etc.) before toggling on to change the column.
-- Use gq{motion} to hard-wrap existing text to the current textwidth.
vim.keymap.set('n', '<leader>tW', function()
  local has_t = vim.opt_local.formatoptions:get().t
  if has_t then
    vim.opt_local.formatoptions:remove('t')
    vim.notify('Auto-wrap off', vim.log.levels.INFO)
  else
    if vim.opt_local.textwidth:get() == 0 then
      vim.opt_local.textwidth = 80
    end
    vim.opt_local.formatoptions:append('t')
    vim.notify(string.format('Auto-wrap on at col %d', vim.opt_local.textwidth:get()),
      vim.log.levels.INFO)
  end
end, { desc = 'Toggle hard text wrap at textwidth (default 80)' })

-- ── Relative line numbers ────────────────────────────────────
-- Off by default (see core/options.lua). relativenumber is window-local,
-- so toggling only `vim.o` leaves it inconsistent across already-open
-- splits/tabs (each keeps whatever value it had when created) — apply
-- the change to every real editor window (skipping neo-tree, terminals,
-- dap panels, etc.) so the toggle is unambiguous regardless of focus.
vim.keymap.set('n', '<leader>tr', function()
  local new_val = not vim.o.relativenumber
  vim.o.relativenumber = new_val
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if require('core.utils').is_editor_buf(vim.api.nvim_win_get_buf(win)) then
        vim.wo[win].relativenumber = new_val
      end
    end
  end
  vim.notify('Relative line numbers ' .. (new_val and 'on' or 'off'), vim.log.levels.INFO)
end, { desc = 'Toggle relative line numbers' })

-- ── Diagnostics ──────────────────────────────────────────────
-- Open all diagnostics for the current buffer in the quickfix list
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Diagnostics: quickfix list' })
