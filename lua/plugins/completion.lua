-- ============================================================
-- plugins/completion.lua — Autocompletion and snippets
--
-- Uses blink.cmp as the completion engine and LuaSnip as the
-- snippet engine. blink.cmp is faster than nvim-cmp and has
-- better defaults for LSP completion.
--
-- Sources: lsp, path, snippets, buffer (words in current file)
--
-- LAZY: Yes — nothing is set up until the first InsertEnter
--       event. Completion has no effect in normal mode so there
--       is no reason to load it at startup.
-- ============================================================

local gh = require('core.utils').gh

vim.pack.add {
  { src = gh 'L3MON4D3/LuaSnip',   version = vim.version.range '2.*' },
  { src = gh 'saghen/blink.cmp',   version = vim.version.range '1.*' },
}

if vim.g.loaded_completion then return end
vim.g.loaded_completion = true

local function activate()
  if vim.g.completion_active then return end
  vim.g.completion_active = true

  -- LuaSnip: snippet engine that blink.cmp delegates expansion to
  require('luasnip').setup {}

  require('blink.cmp').setup {
    keymap = {
      -- 'default' preset: <C-y> accepts, <C-n>/<C-p> navigate,
      -- <C-e> dismisses, <C-k> shows signature help.
      preset = 'default',
    },

    appearance = {
      -- 'mono' aligns icons correctly with Nerd Font Mono variants
      nerd_font_variant = 'mono',
    },

    completion = {
      -- Show documentation popup automatically after a short delay.
      documentation = { auto_show = true, auto_show_delay_ms = 300 },
    },

    sources = {
      -- 'buffer' completes words from the current file when LSP has
      -- nothing to offer (useful in comments and string literals)
      default = { 'lsp', 'path', 'snippets', 'buffer' },
    },

    snippets = { preset = 'luasnip' },

    -- Pure-Lua fuzzy matcher — no compilation required.
    -- Switch to 'prefer_rust_with_warning' for a faster compiled matcher.
    fuzzy = { implementation = 'lua' },

    -- Floating signature help window while typing function arguments
    signature = { enabled = true },
  }
end

-- Activate on first InsertEnter — this is the earliest point at which
-- completion could possibly be needed. `once = true` removes the
-- autocmd after first fire so activate() never runs more than once.
vim.api.nvim_create_autocmd('InsertEnter', {
  once     = true,
  callback = activate,
})
