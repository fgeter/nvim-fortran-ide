-- ============================================================
-- plugins/flash.lua — flash.nvim: jump anywhere on screen
--
-- Usage:
--   s + 1-2 chars        — every visible match gets a label letter;
--                          type it to jump there (works across splits;
--                          single match jumps immediately)
--   S                    — label treesitter nodes around the cursor and
--                          select one (normal mode only: visual S stays
--                          nvim-surround's surround-selection)
--   f/t/F/T              — enhanced by flash: all matches labeled,
--                          repeat with the same key
--   r  (operator mode)   — remote motion: e.g. yr + jump yanks at the
--                          jump target without moving the cursor
--
-- s is NOT mapped in operator-pending mode: nvim-surround owns ys/cs/ds
-- as whole normal-mode mappings, so an o-mode s would be shadowed anyway.
--
-- LAZY: keymaps require flash on first press; setup is deferred into
--       the first call.
-- ============================================================

local gh = require('core.utils').gh

vim.pack.add { { src = gh 'folke/flash.nvim', version = vim.version.range '2.*' } }

local function flash()
  if not vim.g.flash_setup_done then
    vim.g.flash_setup_done = true
    require('flash').setup {}
  end
  return require('flash')
end

vim.keymap.set({ 'n', 'x' }, 's', function() flash().jump() end,       { desc = 'Flash: jump' })
vim.keymap.set('n',          'S', function() flash().treesitter() end, { desc = 'Flash: treesitter select' })
vim.keymap.set('o',          'r', function() flash().remote() end,     { desc = 'Flash: remote (operate at jump target)' })
