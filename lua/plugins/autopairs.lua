-- ============================================================
-- plugins/autopairs.lua — Auto-closing bracket and quote pairs
--
-- Inserts the closing pair automatically as you type:
--   (  →  ()    [  →  []    {  →  {}
--   "  →  ""    '  →  ''    `  →  ``
--
-- check_ts uses treesitter to skip pair insertion inside strings
-- and comments where a literal bracket is more likely intended.
--
-- LAZY: No — pair mappings must be in place before any insert mode
--       keystroke, including the very first character typed.
-- ============================================================

vim.pack.add { { src = 'https://github.com/windwp/nvim-autopairs', version = vim.version.range '*' } }

require('nvim-autopairs').setup {
  check_ts = true,
}
