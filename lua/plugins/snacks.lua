-- ============================================================
-- plugins/snacks.lua — snacks.nvim: notifier + floating input
--
-- Only two of snacks' modules are enabled:
--   notifier — renders vim.notify() as floating cards (stacked,
--              level-colored, auto-dismissing) with a browsable
--              session history on <leader>tn. The whole config
--              communicates through vim.notify, so this upgrades
--              every message at once — nothing else changes.
--   input    — floating vim.ui.input(), the successor to the
--              archived dressing.nvim (which this replaced).
--              vim.ui.select() stays with telescope-ui-select
--              (see plugins/telescope.lua).
--
-- LAZY: No — like dressing.nvim before it, the vim.notify and
--       vim.ui.input overrides must be in place before anything
--       calls them.
-- ============================================================

local gh = require('core.utils').gh

vim.pack.add { { src = gh 'folke/snacks.nvim', version = vim.version.range '2.*' } }

require('snacks').setup {
  notifier = {
    enabled = true,
    timeout = 3000,   -- ms a notification stays visible
  },
  input = { enabled = true },
  styles = {
    -- The history window only maps q by default; let <Esc> close it too.
    notification_history = {
      keys = { q = 'close', ['<Esc>'] = 'close' },
    },
  },
}

-- Browse every notification from this session (newest at the top).
vim.keymap.set('n', '<leader>tn', function()
  Snacks.notifier.show_history()
end, { desc = 'Toggle: notification history' })
