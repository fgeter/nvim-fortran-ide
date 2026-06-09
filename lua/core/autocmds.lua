-- ============================================================
-- core/autocmds.lua — Global autocommands not tied to any plugin
-- ============================================================

-- Cache the active git branch in a global so mini.statusline can show it
-- before gitsigns has attached to any buffer.
vim.api.nvim_create_autocmd('VimEnter', {
  desc  = 'Cache git branch for statusline',
  group = vim.api.nvim_create_augroup('core-git-branch-cache', { clear = true }),
  callback = function()
    local branch = vim.fn.system('git -C ' .. vim.fn.shellescape(vim.fn.getcwd()) .. ' rev-parse --abbrev-ref HEAD 2>/dev/null')
    branch = branch:gsub('%s+$', '')
    if vim.v.shell_error == 0 and branch ~= '' then
      vim.g.git_branch = branch
    end
  end,
})

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
