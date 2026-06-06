-- ============================================================
-- plugins/formatting.lua — Code formatting via conform.nvim
--
-- conform.nvim runs external formatters (or falls back to LSP
-- formatting). Format-on-save is disabled by default to avoid
-- unwanted changes; use <leader>f to format manually.
--
-- To enable format-on-save for a filetype, add it to the
-- enabled_filetypes table below.
--
-- LAZY: Loads on first <leader>f press (conform is required
--       inside the keymap callback).
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

vim.pack.add { gh 'stevearc/conform.nvim' }

require('conform').setup {
  notify_on_error = false,

  -- Format-on-save: add filetypes here to enable automatic formatting.
  -- Example: lua = true, python = true
  format_on_save = function(bufnr)
    local enabled = {
      -- lua = true,
    }
    if enabled[vim.bo[bufnr].filetype] then
      return { timeout_ms = 500 }
    end
  end,

  default_format_opts = {
    -- Use an external formatter if configured; fall back to LSP formatting.
    -- Set to false to disable LSP formatting entirely.
    lsp_format = 'fallback',
  },

  formatters_by_ft = {
    -- Add formatters here as needed. Examples:
    -- lua    = { 'stylua' },
    -- python = { 'isort', 'black' },
  },
}

-- <leader>f formats the current buffer (or selection in visual mode)
vim.keymap.set({ 'n', 'v' }, '<leader>f', function()
  require('conform').format { async = true }
end, { desc = 'Format buffer / selection' })
