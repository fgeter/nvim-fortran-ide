-- ============================================================
-- plugins/surround.lua — nvim-surround: add/change/delete pairs
--
-- Default keymaps (normal mode):
--   ys{motion}{char}  — add surrounding (e.g. ysiw" wraps word in "")
--   cs{old}{new}      — change surrounding (e.g. cs"' changes " to ')
--   ds{char}          — delete surrounding (e.g. ds" removes quotes)
-- Visual mode:
--   S{char}           — surround selection
--
-- LAZY: Yes — loaded on first BufReadPost to avoid startup cost.
-- ============================================================

if vim.g.loaded_surround then return end
vim.g.loaded_surround = true

vim.pack.add { { src = 'https://github.com/kylechui/nvim-surround', version = vim.version.range '4.*' } }

vim.api.nvim_create_autocmd('BufReadPost', {
  once     = true,
  callback = function()
    require('nvim-surround').setup {}
  end,
})
