-- ============================================================
-- plugins/undotree.lua — Visual undo-history browser
--
-- With swapfile off and undofile as the safety net (core/options.lua),
-- this is the recovery tool: browse every past state of the buffer —
-- including across sessions and undo branches that plain u/<C-r> can't
-- reach — and restore any of them.
--
-- Keymap: <leader>tu — toggle the undotree panel (focus moves into it;
--         j/k to walk states, <CR> to restore, q to close)
--
-- LAZY: vimscript plugin; it only defines commands until toggled.
-- Tags (rel_6.1 style) are not semver, so it tracks the default branch.
-- ============================================================

local gh = require('core.utils').gh

vim.pack.add { gh 'mbbill/undotree' }

vim.g.undotree_SetFocusWhenToggle = 1
vim.g.undotree_WindowLayout       = 2  -- tree left, diff pane at the bottom

vim.keymap.set('n', '<leader>tu', '<Cmd>UndotreeToggle<CR>',
  { desc = 'Toggle: undotree (undo history browser)' })
