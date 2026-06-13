-- ============================================================
-- plugins/lint.lua — Async linting via nvim-lint
--
-- Currently configured for:
--   sh / bash — shellcheck (installed by lsp.lua via Mason)
--
-- bashls (from lsp.lua) provides syntax errors; shellcheck adds
-- style and portability warnings that the LSP doesn't cover.
--
-- LAZY: Yes — nvim-lint is not required until a sh/bash file opens.
-- ============================================================

if vim.g.loaded_lint then return end
vim.g.loaded_lint = true

vim.pack.add { 'https://github.com/mfussenegger/nvim-lint' }

local lint_filetypes = { 'sh', 'bash' }

-- One-time setup when the first shell file opens
vim.api.nvim_create_autocmd('FileType', {
  pattern  = lint_filetypes,
  once     = true,
  callback = function()
    require('lint').linters_by_ft = {
      sh   = { 'shellcheck' },
      bash = { 'shellcheck' },
    }
  end,
})

-- Run shellcheck after writing and when first reading a shell file
vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
  callback = function()
    local ft = vim.bo.filetype
    if ft == 'sh' or ft == 'bash' then
      local ok, lint = pcall(require, 'lint')
      if ok then lint.try_lint() end
    end
  end,
})
