-- ============================================================
-- plugins/spell.lua — Built-in English spell checking
--
-- Uses Neovim's built-in spell engine (no plugin required).
-- Off by default in code files; auto-enabled for prose.
-- When enabled in a code file with syntax/treesitter active,
-- Neovim automatically limits spell checking to comment and
-- string regions — identifiers and keywords are never flagged.
--
-- Keymaps (built-in, always active when spell is on):
--   ]s          — jump to next misspelled word
--   [s          — jump to previous misspelled word
--   z=          — show correction suggestions for word under cursor
--   zg          — add word to personal dictionary (spell/en.utf-8.add)
--   zw          — mark word as wrong (add to bad-word list)
--   zug / zuw   — undo zg / zw
--
-- Toggle (defined here):
--   <leader>ts  — toggle spell check in the current buffer
--
-- Personal dictionary:
--   spell/en.utf-8.add        — plain-text, version-controlled
--   spell/en.utf-8.add.spl    — compiled binary, gitignored (auto-generated)
--
-- LAZY: No — options and autocmd registered at startup.
-- ============================================================

-- US English. Change to 'en' for generic or 'en_gb' for British.
vim.o.spelllang = 'en_us'

-- Keep the personal word list inside this config directory so it
-- is version-controlled. Neovim compiles it to .spl on first use.
vim.o.spellfile = vim.fn.stdpath('config') .. '/spell/en.utf-8.add'

-- Off by default; auto-enabled for prose filetypes below.
vim.o.spell = false

-- Auto-enable for prose filetypes where spell is always useful.
vim.api.nvim_create_autocmd('FileType', {
  group    = vim.api.nvim_create_augroup('spell-prose', { clear = true }),
  pattern  = { 'markdown', 'gitcommit', 'text', 'rst', 'mail' },
  callback = function() vim.opt_local.spell = true end,
})

-- Toggle spell check in the current buffer and show a brief notification.
vim.keymap.set('n', '<leader>ts', function()
  vim.opt_local.spell = not vim.opt_local.spell:get()
  vim.notify('Spell check ' .. (vim.opt_local.spell:get() and 'on' or 'off'),
    vim.log.levels.INFO)
end, { desc = 'Toggle spell check' })
