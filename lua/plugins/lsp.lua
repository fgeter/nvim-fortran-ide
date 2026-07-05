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

local gh = require('core.utils').gh

-- fidget: shows LSP progress (indexing, loading, etc.) in the
-- bottom-right corner so you know when the server is ready
vim.pack.add { { src = gh 'j-hui/fidget.nvim', version = vim.version.range '1.*' } }
require('fidget').setup {}

-- Mason: downloads and manages LSP servers, formatters, and linters
-- into Neovim's data directory (~/.local/share/nvim)
vim.pack.add {
  { src = gh 'neovim/nvim-lspconfig',          version = vim.version.range '2.*' },
  { src = gh 'mason-org/mason.nvim',           version = vim.version.range '2.*' },
  { src = gh 'mason-org/mason-lspconfig.nvim', version = vim.version.range '2.*' },
  gh 'WhoIsSethDaniel/mason-tool-installer.nvim',  -- no tagged releases
  -- schemastore provides JSON/YAML schema lists for jsonls and yamlls
  gh 'b0o/schemastore.nvim',                       -- no tagged releases
}

require('mason').setup {}

-- LSP servers and Mason tools to auto-install.
-- Non-LSP tools (stylua, debugpy, ruff) are included so Mason installs them;
-- vim.lsp.enable() on an unknown name is a no-op so they don't cause errors.
local servers = {
  stylua = {},

  -- Python tools (used by plugins/python.lua)
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

  -- ── C / C++ ──────────────────────────────────────────────────
  clangd = {},

  -- ── Shell / Bash ─────────────────────────────────────────────
  bashls = {},

  -- ── JSON — schema validation via schemastore ─────────────────
  jsonls = {
    settings = {
      json = {
        schemas = (function()
          local ok, ss = pcall(require, 'schemastore')
          return ok and ss.json.schemas() or {}
        end)(),
        validate = { enable = true },
      },
    },
  },

  -- ── YAML — schema validation via schemastore ─────────────────
  yamlls = {
    settings = {
      yaml = {
        schemaStore = { enable = false, url = '' },
        schemas = (function()
          local ok, ss = pcall(require, 'schemastore')
          return ok and ss.yaml.schemas() or {}
        end)(),
      },
    },
  },

  -- ── TOML ─────────────────────────────────────────────────────
  taplo = {},

  -- ── Rust ─────────────────────────────────────────────────────
  rust_analyzer = {},

  -- ── Web: HTML, CSS, TypeScript / JavaScript / React ──────────
  html          = {},
  cssls         = {},
  ts_ls         = {},
  eslint        = {},
}

-- Extra Mason packages that are NOT LSP servers:
-- formatters, linters, DAP adapters, and jdtls (managed by nvim-jdtls, not vim.lsp.enable).
local extra_mason_tools = {
  'jdtls',               -- Java LSP (started by java-tools.lua via nvim-jdtls)
  'java-debug-adapter',  -- Java DAP
  'js-debug-adapter',    -- Node / React DAP
  'shfmt',               -- shell formatter
  'prettier',            -- JS/TS/JSX/TSX/HTML/CSS/JSON/YAML/Markdown formatter
  'clang-format',        -- C/C++ formatter
  'google-java-format',  -- Java formatter
  'shellcheck',          -- shell linter (used by nvim-lint)
}

require('mason-tool-installer').setup {
  ensure_installed = vim.list_extend(vim.tbl_keys(servers), extra_mason_tools),
  -- The ensure_installed walk (~30 packages) runs via defer_fn with a
  -- default delay of 0, competing with first-buffer work right after
  -- startup. 3s pushes it past interactive startup entirely; missing
  -- tools still auto-install, just a few seconds later, and
  -- :MasonToolsInstall runs the check on demand.
  start_delay = 3000,
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

    -- K: DAP eval during a debug session, LSP hover otherwise.
    -- utils resolves dap lazily at keypress (the DAP stack is lazy-loaded),
    -- so this works whether debugging starts before or after LspAttach.
    require('core.utils').attach_k_handler(ev.buf)

    -- Diagnostic navigation — globally available on all LSP buffers
    map('[d',        function() vim.diagnostic.jump({ count = -1 }) end, 'prev diagnostic')
    map(']d',        function() vim.diagnostic.jump({ count =  1 }) end, 'next diagnostic')
    map('<leader>e', vim.diagnostic.open_float,                          'show diagnostic float')

    -- VS Code-style aliases (muscle memory for users coming from other editors)
    map('<leader>rn', vim.lsp.buf.rename,      'rename symbol')
    -- map('<leader>ca', vim.lsp.buf.code_action, 'code action')

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
