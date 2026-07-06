-- ============================================================
-- plugins/diffview.lua — Diff / review UI (diffview.nvim)
--
-- Renders diffs in Neovim's native diff mode (do/dp move hunks,
-- ]c/[c jump, the catppuccin DiffChange/DiffText overrides apply)
-- inside a dedicated tab with a persistent file panel. Also
-- provides per-file history (:DiffviewFileHistory) and three-way
-- merge conflict resolution.
--
-- The <leader>g* keymaps that drive it (ref pickers, current-file
-- diff, review, history) live in features/git-workflow.lua next to
-- the rest of the git workflow.
--
-- LAZY: The plugin lazy-loads its own internals; only command
--       registration and this light setup run at startup.
-- ============================================================

local gh = require('core.utils').gh

vim.pack.add { gh 'sindrets/diffview.nvim' }  -- no tagged releases

require('diffview').setup {
  use_icons = vim.g.have_nerd_font,
  -- winbar_info shows a header on each diff window naming the revision it
  -- holds: the picked branch/ref on the left, the working copy (LOCAL) on
  -- the right. Makes it obvious which side is which.
  view = {
    default      = { winbar_info = true },
    file_history = { winbar_info = true },
  },
  keymaps = {
    -- q closes the whole review tab from anywhere, matching the
    -- lazygit / notification-history convention used elsewhere.
    view               = { { 'n', 'q', '<Cmd>DiffviewClose<CR>', { desc = 'Diffview: close' } } },
    file_panel         = { { 'n', 'q', '<Cmd>DiffviewClose<CR>', { desc = 'Diffview: close' } } },
    file_history_panel = { { 'n', 'q', '<Cmd>DiffviewClose<CR>', { desc = 'Diffview: close' } } },
  },
}
