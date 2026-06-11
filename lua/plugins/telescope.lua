-- ============================================================
-- plugins/telescope.lua — Fuzzy finder and picker UI
--
-- Telescope is used for: file search, live grep, help tags,
-- keymaps, LSP references/definitions, recent files, and as
-- the backend for vim.ui.select() (via telescope-ui-select).
--
-- LAZY: No — telescope is used immediately on startup and its
--       vim.ui.select override must be in place before any
--       plugin calls that function.
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

local telescope_plugins = {
  gh 'nvim-lua/plenary.nvim',
  gh 'nvim-telescope/telescope.nvim',
  gh 'nvim-telescope/telescope-ui-select.nvim',
}

-- telescope-fzf-native provides a compiled C fuzzy matcher that is
-- significantly faster than the pure-Lua default. Only built when
-- `make` is available.
if vim.fn.executable('make') == 1 then
  table.insert(telescope_plugins, gh 'nvim-telescope/telescope-fzf-native.nvim')
end

vim.pack.add(telescope_plugins)

require('telescope').setup {
  defaults = require('telescope.themes').get_ivy(),
  extensions = {
    -- Use the dropdown theme for vim.ui.select() so pickers like
    -- cmake preset selection and workdata selection look clean
    ['ui-select'] = { require('telescope.themes').get_dropdown() },
  },
}

-- Load extensions. fzf is optional (requires compiled C); warn if the build
-- is missing so the user knows they are on the slower Lua matcher.
if vim.fn.executable('make') == 1 then
  local ok = pcall(require('telescope').load_extension, 'fzf')
  if not ok then
    vim.notify(
      'telescope-fzf-native: native sorter failed to load.\n' ..
      'Falling back to Lua matcher (slower on large projects).\n' ..
      'Try deleting ~/.local/share/nvim/site/pack/core/opt/telescope-fzf-native.nvim and restarting.',
      vim.log.levels.WARN)
  end
end
pcall(require('telescope').load_extension, 'ui-select')

-- ── Keymaps ──────────────────────────────────────────────────
local builtin = require('telescope.builtin')

-- Search commands
vim.keymap.set('n', '<leader>sh', builtin.help_tags,   { desc = 'Search: help tags' })
vim.keymap.set('n', '<leader>sk', builtin.keymaps,     { desc = 'Search: keymaps' })
vim.keymap.set('n', '<leader>ss', builtin.builtin,     { desc = 'Search: telescope pickers' })
vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = 'Search: diagnostics' })
vim.keymap.set('n', '<leader>sr', builtin.resume,      { desc = 'Search: resume last picker' })
vim.keymap.set('n', '<leader>sc', builtin.commands,    { desc = 'Search: commands' })

-- Find files — shows ALL files including hidden and gitignored.
-- no_ignore=true is intentional: build/ and other gitignored dirs are
-- sometimes useful to browse. Use <leader>sg (grep) to narrow results.
vim.keymap.set('n', '<leader>sf', function()
  builtin.find_files { hidden = true, no_ignore = true }
end, { desc = 'Search: files (all, including hidden/ignored)' })

-- Grep across files
vim.keymap.set({ 'n', 'v' }, '<leader>sw', builtin.grep_string, { desc = 'Search: word under cursor' })
vim.keymap.set('n', '<leader>sg', builtin.live_grep,            { desc = 'Search: live grep' })
vim.keymap.set('n', '<leader>s/', function()
  builtin.live_grep {
    grep_open_files = true,
    prompt_title    = 'Live grep in open buffers',
  }
end, { desc = 'Search: grep in open buffers' })

-- Recent files (replaces the separate recent-files.lua vim.ui.select picker)
vim.keymap.set('n', '<leader>rf', builtin.oldfiles, { desc = 'Recent files' })

-- Current buffer fuzzy search
vim.keymap.set('n', '<leader>/', function()
  builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
    winblend  = 10,
    previewer = false,
  })
end, { desc = 'Search: fuzzy in current buffer' })

-- Search Neovim config files
vim.keymap.set('n', '<leader>sn', function()
  builtin.find_files { cwd = vim.fn.stdpath('config') }
end, { desc = 'Search: Neovim config files' })

-- Buffer list
vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = 'Find open buffers' })

-- ── LSP pickers (attached per buffer on LspAttach) ───────────
-- These use Telescope pickers instead of the default quickfix list
-- so you get fuzzy search, preview, and consistent UI.
-- NOTE: gd/gr/gD are NOT mapped here globally — fortran-tools.lua
-- sets buffer-local versions for Fortran files only, and the
-- kickstart LSP section in lsp.lua sets grn/gra/grD globally.
vim.api.nvim_create_autocmd('LspAttach', {
  group    = vim.api.nvim_create_augroup('telescope-lsp-attach', { clear = true }),
  callback = function(ev)
    local buf = ev.buf
    vim.keymap.set('n', 'grr', builtin.lsp_references,              { buffer = buf, desc = 'LSP: references (telescope)' })
    vim.keymap.set('n', 'gri', builtin.lsp_implementations,         { buffer = buf, desc = 'LSP: implementations' })
    vim.keymap.set('n', 'grd', builtin.lsp_definitions,             { buffer = buf, desc = 'LSP: definitions' })
    vim.keymap.set('n', 'gO',  builtin.lsp_document_symbols,        { buffer = buf, desc = 'LSP: document symbols' })
    vim.keymap.set('n', 'gW',  builtin.lsp_dynamic_workspace_symbols, { buffer = buf, desc = 'LSP: workspace symbols' })
    vim.keymap.set('n', 'grt', builtin.lsp_type_definitions,        { buffer = buf, desc = 'LSP: type definition' })
  end,
})
