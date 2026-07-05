-- ============================================================
-- plugins/grug-far.lua — Project-wide search & replace UI
--
-- Telescope finds; grug-far edits. Opens a split where you type a
-- search pattern, replacement, and optional file filter — matches
-- preview live (ripgrep underneath), then apply all with <leader>
-- keybinds shown in the buffer header, or edit individual result
-- lines and :w them like a normal buffer.
--
-- Keymaps:
--   <leader>sR  (n) — open search & replace
--   <leader>sR  (v) — open with the visual selection pre-filled
--
-- LAZY: setup deferred to first use.
-- ============================================================

local gh = require('core.utils').gh

vim.pack.add { { src = gh 'MagicDuck/grug-far.nvim', version = vim.version.range '1.*' } }

local function grug()
  if not vim.g.grug_far_setup_done then
    vim.g.grug_far_setup_done = true
    require('grug-far').setup {}
  end
  return require('grug-far')
end

vim.keymap.set('n', '<leader>sR', function() grug().open() end,
  { desc = 'Search: project-wide replace (grug-far)' })
vim.keymap.set('v', '<leader>sR', function() grug().with_visual_selection() end,
  { desc = 'Search: replace selection project-wide (grug-far)' })
