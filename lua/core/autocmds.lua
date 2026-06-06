-- ============================================================
-- core/autocmds.lua — Global autocommands not tied to any plugin
-- ============================================================

-- Flash the yanked region briefly so you can see what was copied.
-- Fires on every yank (y, Y, dd treated as yank-then-delete, etc.)
vim.api.nvim_create_autocmd('TextYankPost', {
  desc     = 'Highlight yanked text briefly',
  group    = vim.api.nvim_create_augroup('core-yank-highlight', { clear = true }),
  callback = function() vim.hl.on_yank() end,
})

-- Diagnostic configuration.
-- Kept here rather than in lsp.lua because diagnostics are a core Neovim
-- feature (vim.diagnostic) that work even without an LSP server attached.
vim.diagnostic.config {
  update_in_insert = false,   -- don't update diagnostics while typing
  severity_sort    = true,    -- errors before warnings in sign column
  float            = { border = 'rounded', source = 'if_many' },
  underline        = { severity = { min = vim.diagnostic.severity.WARN } },
  virtual_text     = true,    -- show diagnostic text at end of line
  virtual_lines    = false,   -- disable the multi-line virtual text variant

  -- Automatically open the float when jumping between diagnostics with
  -- [d and ]d so you don't have to press a second key to read the message
  jump = {
    on_jump = function(_, bufnr)
      vim.diagnostic.open_float {
        bufnr  = bufnr,
        scope  = 'cursor',
        focus  = false,
      }
    end,
  },
}
