-- ============================================================
-- plugins/dressing.lua — Floating popup for vim.ui.input
--
-- vim.ui.select() already renders as a floating window via
-- telescope-ui-select (plugins/telescope.lua). vim.ui.input()
-- was still Neovim's plain cmdline prompt — visually identical
-- to normal command-line mode, which made it easy to lose track
-- of whether a keystroke was going to the prompt or the buffer
-- behind it (see git.lua's git_ui_busy race). dressing.nvim gives
-- input() the same floating-window treatment, only used for that
-- purpose here — its own select() override is left off since
-- telescope-ui-select already owns that.
--
-- LAZY: No — like telescope's ui-select override, this needs to
--       be in place before any plugin calls vim.ui.input().
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

vim.pack.add { gh 'stevearc/dressing.nvim' }

require('dressing').setup {
  input = { enabled = true },
  select = { enabled = false },
}
