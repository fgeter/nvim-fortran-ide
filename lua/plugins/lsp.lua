-- ============================================================
-- plugins/lsp.lua — Language Server Protocol configuration
--
-- Sets up Mason (LSP/tool installer), mason-lspconfig (bridge
-- between Mason and Neovim's built-in LSP client), and fidget
-- (LSP progress spinner).
--
-- Fortran LSP (fortls) is configured in plugins/fortran-tools.lua
-- rather than here because it is lazy-loaded on FileType fortran.
--
-- LAZY: No — LSP must be available immediately when any source
--       file is opened.
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

-- fidget: shows LSP progress (indexing, loading, etc.) in the
-- bottom-right corner so you know when the server is ready
vim.pack.add { gh 'j-hui/fidget.nvim' }
require('fidget').setup {}

-- Mason: downloads and manages LSP servers, formatters, and linters
-- into Neovim's data directory (~/.local/share/nvim)
vim.pack.add {
  gh 'neovim/nvim-lspconfig',
  gh 'mason-org/mason.nvim',
  gh 'mason-org/mason-lspconfig.nvim',
  gh 'WhoIsSethDaniel/mason-tool-installer.nvim',
}

require('mason').setup {}

-- Servers and tools to auto-install via Mason.
-- stylua: Lua formatter (used with conform.nvim)
-- lua_ls: Lua language server for editing this config
local servers = {
  stylua = {},

  -- Python tools (used by plugins/python.lua)
  -- Install with :MasonInstall or they are auto-installed below
  basedpyright = {},
  debugpy      = {},
  ruff         = {},

  lua_ls = {
    on_init = function(client)
      -- Disable lua_ls formatting in favour of stylua (via conform.nvim)
      client.server_capabilities.documentFormattingProvider = false

      -- Only apply Neovim-specific Lua settings when working inside
      -- the Neovim config directory. For other Lua projects, use
      -- the project's own .luarc.json instead.
      if client.workspace_folders then
        local path = client.workspace_folders[1].name
        if path ~= vim.fn.stdpath('config')
          and (vim.uv.fs_stat(path .. '/.luarc.json')
            or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then
          return
        end
      end

      client.config.settings.Lua = vim.tbl_deep_extend('force',
        client.config.settings.Lua, {
          runtime  = { version = 'LuaJIT', path = { 'lua/?.lua', 'lua/?/init.lua' } },
          workspace = {
            checkThirdParty = false,
            library = vim.tbl_extend('force',
              vim.api.nvim_get_runtime_file('', true), {
                '${3rd}/luv/library',
                '${3rd}/busted/library',
              }),
          },
        })
    end,
    settings = {
      Lua = { format = { enable = false } },
    },
  },
}

require('mason-tool-installer').setup {
  ensure_installed = vim.tbl_keys(servers),
}

for name, server in pairs(servers) do
  vim.lsp.config(name, server)
  vim.lsp.enable(name)
end

-- ── Global LSP keymaps (all languages) ───────────────────────
-- These attach to every LSP-connected buffer. Language-specific
-- keymaps (Fortran) are added in plugins/fortran-tools.lua.
vim.api.nvim_create_autocmd('LspAttach', {
  group    = vim.api.nvim_create_augroup('lsp-global-attach', { clear = true }),
  callback = function(ev)
    local map = function(keys, func, desc, mode)
      vim.keymap.set(mode or 'n', keys, func,
        { buffer = ev.buf, desc = 'LSP: ' .. desc })
    end

    -- Rename symbol across the project
    map('grn', vim.lsp.buf.rename,       '[R]e[n]ame symbol')
    -- Code action (fix, refactor, import, etc.)
    map('gra', vim.lsp.buf.code_action,  '[G]oto code [a]ction', { 'n', 'x' })
    -- Go to declaration (header / interface, not implementation)
    map('grD', vim.lsp.buf.declaration,  '[G]oto [D]eclaration')

    -- Toggle inlay hints (e.g. parameter names, return types) if supported
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method('textDocument/inlayHint', ev.buf) then
      map('<leader>th', function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = ev.buf })
      end, '[T]oggle inlay [h]ints')
    end

    -- Reference highlighting: when the cursor rests on a symbol, all
    -- other occurrences in the buffer are highlighted. Cleared on move.
    if client and client:supports_method('textDocument/documentHighlight', ev.buf) then
      local grp = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })
      vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
        buffer   = ev.buf,
        group    = grp,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        buffer   = ev.buf,
        group    = grp,
        callback = vim.lsp.buf.clear_references,
      })
      vim.api.nvim_create_autocmd('LspDetach', {
        group    = vim.api.nvim_create_augroup('lsp-detach', { clear = true }),
        callback = function(ev2)
          vim.lsp.buf.clear_references()
          vim.api.nvim_clear_autocmds { group = 'lsp-highlight', buffer = ev2.buf }
        end,
      })
    end
  end,
})
