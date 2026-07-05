-- ============================================================
-- plugins/harpoon.lua — Pin a working set of files (harpoon v2)
--
-- Buffers come and go while chasing references; the harpoon list is
-- the deliberate working set. Pin the 3-5 files a task lives in, then
-- each is one keystroke away from anywhere. The list is per-project
-- (keyed on cwd) and persists across restarts.
--
-- Keymaps:
--   <leader>a    — add current file to the list
--   <leader>A    — remove current file from the list
--   <leader>1-4  — jump straight to pinned file 1-4
--   <leader>0    — open the list menu ("the list" = 0): an editable
--                  buffer — reorder lines, dd to remove, <CR> to open
--
-- (<leader>e was the natural menu key but is taken by diagnostics.)
--
-- v2 lives on the 'harpoon2' branch — do not "upgrade" this to master.
-- plenary is declared here too (not just in neo-tree/telescope): this
-- file loads alphabetically BEFORE those, and require('harpoon') below
-- needs plenary on the runtimepath already. vim.pack.add is idempotent,
-- so the later declarations are harmless.
-- ============================================================

local gh = require('core.utils').gh

vim.pack.add {
  { src = gh 'nvim-lua/plenary.nvim', version = vim.version.range '*' },
  { src = gh 'ThePrimeagen/harpoon',  version = 'harpoon2' },
}

local harpoon = require('harpoon')
harpoon:setup()

vim.keymap.set('n', '<leader>a', function()
  harpoon:list():add()
  vim.notify('Harpooned: ' .. vim.fn.expand('%:t')
    .. '  (' .. harpoon:list():length() .. ' pinned)', vim.log.levels.INFO)
end, { desc = 'Harpoon: add file' })

vim.keymap.set('n', '<leader>A', function()
  harpoon:list():remove()
  vim.notify('Un-harpooned: ' .. vim.fn.expand('%:t')
    .. '  (' .. harpoon:list():length() .. ' pinned)', vim.log.levels.INFO)
end, { desc = 'Harpoon: remove file' })

vim.keymap.set('n', '<leader>0', function()
  harpoon.ui:toggle_quick_menu(harpoon:list())
end, { desc = 'Harpoon: menu' })

for i = 1, 4 do
  vim.keymap.set('n', '<leader>' .. i, function()
    harpoon:list():select(i)
  end, { desc = 'Harpoon: file ' .. i })
end
