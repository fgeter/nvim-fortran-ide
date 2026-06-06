-- ============================================================
-- plugins/treesitter.lua — Syntax highlighting and indentation
--
-- nvim-treesitter provides accurate syntax highlighting, smarter
-- indentation, and the foundation for text objects and folds.
-- Parsers are auto-installed on first FileType encounter so
-- startup isn't blocked by parser compilation.
--
-- LAZY: Partially — the plugin loads at startup but individual
--       language parsers are installed/attached lazily on FileType.
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

vim.pack.add { { src = gh 'nvim-treesitter/nvim-treesitter', version = 'main' } }

-- Pre-install parsers for the languages used in this config and for
-- Neovim's built-in help/query files. Others install automatically.
local core_parsers = {
  'bash', 'c', 'diff', 'html', 'lua', 'luadoc',
  'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc',
}
require('nvim-treesitter').install(core_parsers)

-- Attaches treesitter highlighting (and indentation if a query exists)
-- to a buffer. Called both when a parser is already installed and after
-- on-demand installation completes.
---@param buf      integer  Buffer handle
---@param language string   Treesitter language name
local function ts_attach(buf, language)
  if not vim.treesitter.language.add(language) then return end
  vim.treesitter.start(buf, language)

  -- Enable treesitter-based indentation only when an indent query exists
  -- for this language. Falls back to Vim's built-in indentexpr otherwise.
  if vim.treesitter.query.get(language, 'indents') ~= nil then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
end

local available = require('nvim-treesitter').get_available()

-- On every FileType event, try to attach the matching parser.
-- Install it first if available from nvim-treesitter but not yet installed.
vim.api.nvim_create_autocmd('FileType', {
  group    = vim.api.nvim_create_augroup('treesitter-attach', { clear = true }),
  callback = function(args)
    local buf      = args.buf
    local filetype = args.match
    local language = vim.treesitter.language.get_lang(filetype)
    if not language then return end

    local installed = require('nvim-treesitter').get_installed('parsers')
    if vim.tbl_contains(installed, language) then
      ts_attach(buf, language)
    elseif vim.tbl_contains(available, language) then
      -- Auto-install then attach. The callback runs asynchronously after
      -- the parser is compiled, so the current buffer benefits immediately.
      require('nvim-treesitter').install(language):await(function()
        ts_attach(buf, language)
      end)
    else
      -- Parser not in nvim-treesitter registry — try anyway in case it was
      -- installed via another mechanism (e.g. system package)
      ts_attach(buf, language)
    end
  end,
})
