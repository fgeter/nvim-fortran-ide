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
-- LAZY: Yes — setup is deferred to the first InsertEnter (same
--       pattern as completion.lua). That is early enough: setup()
--       calls force_attach() on the current buffer immediately
--       (verified in nvim-autopairs.lua), and InsertEnter fires
--       before the first character is inserted, so even the first
--       bracket typed in a session gets its closing pair.
-- ============================================================

vim.pack.add { { src = 'https://github.com/windwp/nvim-autopairs', version = vim.version.range '*' } }

vim.api.nvim_create_autocmd('InsertEnter', {
  once     = true,
  callback = function()
    require('nvim-autopairs').setup {
      check_ts = true,
    }
  end,
})
