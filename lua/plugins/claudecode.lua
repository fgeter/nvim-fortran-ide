-- ============================================================
-- plugins/claudecode.lua — Claude Code IDE integration (coder/claudecode.nvim)
--
-- The plugin speaks the same protocol as Claude Code's VS Code / JetBrains
-- extensions: a local WebSocket server that the `claude` CLI connects to.
-- Through it Claude sees the file you are in and your current selection,
-- can read diagnostics and the list of open files, and proposes its edits
-- as a diff in Neovim (accept / reject).
--
-- The server does NOT start with Neovim (auto_start = false). The AI menu
-- (features/ai.lua) starts it when you launch Claude, pointed at the
-- right account's config dir, and runs Claude in a split on the right
-- (neo-tree keeps the left).
--
-- LAZY: No — cheap to load; nothing runs until a Claude session starts.
-- ============================================================

local gh = require('core.utils').gh

vim.pack.add { { src = gh 'coder/claudecode.nvim' } }

require('claudecode').setup {
  auto_start      = false,
  track_selection = true,
  log_level       = 'warn',
  terminal        = {
    provider               = 'native',
    split_side             = 'right',
    split_width_percentage = 0.40,
    auto_close             = false,   -- features/ai.lua closes it (TermClose)
  },
  diff_opts       = {
    layout          = 'vertical',
    open_in_new_tab = false,
  },
}
