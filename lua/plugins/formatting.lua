-- ============================================================
-- plugins/formatting.lua — Code formatting via conform.nvim
--
-- conform.nvim runs external formatters (or falls back to LSP
-- formatting). Format-on-save is disabled by default; use
-- <leader>f to format manually.
--
-- LAZY: Yes — conform is not loaded until <leader>f is pressed
--       for the first time. There is no reason to load a
--       formatter at startup when no formatters are configured
--       for the filetypes in use (Fortran, Lua).
-- ============================================================

local gh = require('core.utils').gh

vim.pack.add { gh 'stevearc/conform.nvim' }

if vim.g.loaded_conform then return end
vim.g.loaded_conform = true

-- Defer setup and keymap until the first time <leader>f is pressed.
-- The keymap is registered at startup (cheap) but conform itself is
-- not required until the callback fires.
local function setup_conform()
  if vim.g.conform_active then return end
  vim.g.conform_active = true

  require('conform').setup {
    notify_on_error = false,

    -- Format-on-save: add filetypes here to enable automatic formatting.
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
      lsp_format = 'fallback',
    },

    formatters_by_ft = {
      lua             = { 'stylua' },
      python          = { 'ruff' },
      sh              = { 'shfmt' },
      bash            = { 'shfmt' },
      c               = { 'clang-format' },
      cpp             = { 'clang-format' },
      java            = { 'google-java-format' },
      javascript      = { 'prettier' },
      typescript      = { 'prettier' },
      javascriptreact = { 'prettier' },
      typescriptreact = { 'prettier' },
      html            = { 'prettier' },
      css             = { 'prettier' },
      json            = { 'prettier' },
      yaml            = { 'prettier' },
      markdown        = { 'prettier' },
    },
  }
end

-- Register the keymap at startup so it appears in which-key.
-- conform is only required when the keymap is actually pressed.
vim.keymap.set({ 'n', 'v' }, '<leader>f', function()
  setup_conform()
  require('conform').format { async = true }
end, { desc = 'Format buffer / selection' })
