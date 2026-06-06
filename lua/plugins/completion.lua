-- ============================================================
-- plugins/completion.lua — Autocompletion and snippets
--
-- Uses blink.cmp as the completion engine and LuaSnip as the
-- snippet engine. blink.cmp is faster than nvim-cmp and has
-- better defaults for LSP completion.
--
-- Sources: lsp (language server), path (filesystem), snippets
--          (LuaSnip), buffer (words in current file — useful
--          when LSP has nothing to offer, e.g. in comments)
--
-- LAZY: No — completion must be available as soon as a buffer
--       opens in insert mode.
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

-- LuaSnip: the snippet engine blink.cmp delegates expansion to
vim.pack.add { { src = gh 'L3MON4D3/LuaSnip', version = vim.version.range '2.*' } }
require('luasnip').setup {}

-- blink.cmp: fast completion engine written in Rust + Lua
vim.pack.add { { src = gh 'saghen/blink.cmp', version = vim.version.range '1.*' } }
require('blink.cmp').setup {
  keymap = {
    -- 'default' preset: <C-y> accepts, <C-n>/<C-p> navigate,
    -- <C-e> dismisses, <C-k> toggles signature help.
    -- See :help blink-cmp-config-keymap for custom bindings.
    preset = 'default',
  },

  appearance = {
    -- 'mono' aligns icons correctly with Nerd Font Mono variants
    nerd_font_variant = 'mono',
  },

  completion = {
    -- Documentation popup: show automatically after a short delay.
    -- Set auto_show = false if you prefer to open it manually with <C-space>.
    documentation = { auto_show = true, auto_show_delay_ms = 300 },
  },

  sources = {
    -- 'buffer' added so words in the current file complete when LSP
    -- has nothing to offer (useful in comments and string literals)
    default = { 'lsp', 'path', 'snippets', 'buffer' },
  },

  snippets = { preset = 'luasnip' },

  -- Use the pure-Lua fuzzy matcher (no compilation required).
  -- Switch to 'prefer_rust_with_warning' for a faster compiled matcher.
  fuzzy = { implementation = 'lua' },

  -- Shows a floating signature help window while typing function arguments
  signature = { enabled = true },
}
