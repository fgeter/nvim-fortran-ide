-- ============================================================
-- plugins/gitsigns.lua — Inline git decorations (plugin config)
--
-- gitsigns shows added/changed/deleted markers in the sign column
-- and provides hunk-level operations:
--   <leader>h* — hunk operations (stage, reset, preview, blame)
--   ]c / [c    — hunk navigation
--
-- The custom repository-level git workflow (<leader>g* — commit,
-- pull/push, branches, ref-diff review, remote-ahead check) is
-- homegrown code, not plugin config, and lives in
-- lua/features/git-workflow.lua.
--
-- LAZY: No — gitsigns attaches via BufRead internally.
-- ============================================================

local gh = require('core.utils').gh

-- ── gitsigns ─────────────────────────────────────────────────
-- Shows +/~/_ signs in the gutter for added/changed/deleted lines.
-- Also provides hunk navigation and staging without leaving Neovim.
-- Installed once here (removed the duplicate install from the old
-- init.lua Section 3 which had no keymaps).
vim.pack.add { { src = gh 'lewis6991/gitsigns.nvim', version = vim.version.range '2.*' } }

require('gitsigns').setup {
  signs = {
    add          = { text = '+' }, ---@diagnostic disable-line: missing-fields
    change       = { text = '~' }, ---@diagnostic disable-line: missing-fields
    delete       = { text = '_' }, ---@diagnostic disable-line: missing-fields
    topdelete    = { text = '‾' }, ---@diagnostic disable-line: missing-fields
    changedelete = { text = '~' }, ---@diagnostic disable-line: missing-fields
  },

  on_attach = function(bufnr)
    local gs = require('gitsigns')
    local function map(mode, l, r, opts)
      opts = opts or {}
      opts.buffer = bufnr
      vim.keymap.set(mode, l, r, opts)
    end

    -- Hunk navigation: jump to next/previous changed section
    -- In diff mode, uses Vim's built-in ]c/[c instead
    map('n', ']c', function()
      if vim.wo.diff then vim.cmd.normal { ']c', bang = true }
      else gs.nav_hunk('next') end
    end, { desc = 'Git: next hunk' })

    map('n', '[c', function()
      if vim.wo.diff then vim.cmd.normal { '[c', bang = true }
      else gs.nav_hunk('prev') end
    end, { desc = 'Git: prev hunk' })

    -- Hunk operations (visual mode: operate on selected lines only)
    map('v', '<leader>hs', function() gs.stage_hunk { vim.fn.line('.'), vim.fn.line('v') } end, { desc = 'Git hunk: stage' })
    map('v', '<leader>hr', function() gs.reset_hunk { vim.fn.line('.'), vim.fn.line('v') } end, { desc = 'Git hunk: reset' })

    -- Hunk operations (normal mode)
    map('n', '<leader>hs', gs.stage_hunk,          { desc = 'Git hunk: stage' })
    map('n', '<leader>hr', gs.reset_hunk,           { desc = 'Git hunk: reset' })
    map('n', '<leader>hS', gs.stage_buffer,         { desc = 'Git hunk: stage buffer' })
    map('n', '<leader>hR', gs.reset_buffer,         { desc = 'Git hunk: reset buffer' })
    map('n', '<leader>hp', gs.preview_hunk,         { desc = 'Git hunk: preview' })
    map('n', '<leader>hi', gs.preview_hunk_inline,  { desc = 'Git hunk: preview inline' })
    map('n', '<leader>hb', function() gs.blame_line { full = true } end, { desc = 'Git hunk: blame line' })
    map('n', '<leader>hd', gs.diffthis,             { desc = 'Git hunk: diff against index' })
    map('n', '<leader>hD', function() gs.diffthis('@') end, { desc = 'Git hunk: diff against last commit' })
    map('n', '<leader>hq', gs.setqflist,            { desc = 'Git hunk: quickfix (this file)' })
    map('n', '<leader>hQ', function() gs.setqflist('all') end, { desc = 'Git hunk: quickfix (all files)' })

    -- Toggles
    map('n', '<leader>tb', gs.toggle_current_line_blame, { desc = 'Toggle: git blame line' })
    map('n', '<leader>tw', gs.toggle_word_diff,          { desc = 'Toggle: git word diff' })

    -- Text object: ih selects inside a hunk (usable with d/y/c)
    map({ 'o', 'x' }, 'ih', gs.select_hunk)
  end,
}
