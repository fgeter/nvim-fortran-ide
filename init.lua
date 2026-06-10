-- ============================================================
-- init.lua — Entry point for Neovim configuration
--
-- This file is intentionally small. It:
--   1. Enables Lua bytecode caching for faster startup
--   2. Sets leader keys (must happen before any plugin loads)
--   3. Sets the Nerd Font flag used by UI plugins
--   4. Loads core settings, keymaps, and autocmds
--   5. Auto-loads every plugin file in lua/plugins/
--
-- To add a new plugin, create a new .lua file in lua/plugins/.
-- To change a core setting, edit lua/core/options.lua.
-- To change a global keymap, edit lua/core/keymaps.lua.
-- ============================================================

-- Must be first: enables Lua bytecode caching so every subsequent
-- require() loads from the cache rather than re-parsing Lua source.
vim.loader.enable()

-- Leader keys must be set before any plugin loads, otherwise plugins
-- that define keymaps at load time will use the wrong leader.
vim.g.mapleader      = ' '
vim.g.maplocalleader = ' '

-- Controls whether icon-using plugins (neo-tree, mini.statusline, etc.)
-- render Nerd Font glyphs. Set to false if your terminal lacks a Nerd Font.
vim.g.have_nerd_font = true

-- ── Core modules ────────────────────────────────────────────
require('core.options')   -- vim.o.* / vim.opt.* settings
require('core.keymaps')   -- global keymaps (non-plugin)
require('core.autocmds')  -- global autocommands

-- ── Plugin loader ────────────────────────────────────────────
-- Auto-load every .lua file in lua/plugins/ in alphabetical order.
-- Each file is responsible for its own vim.pack.add() + setup().
-- Files are skipped silently if they error (pcall), which prevents
-- one broken plugin from stopping the rest from loading.
-- vim.fs.dir does not guarantee alphabetical order; sort explicitly so the
-- documented load order (alphabetical) is always honoured. This matters
-- because dap.lua must precede fortran-tools.lua, and neo-tree.lua must
-- precede ui.lua (which installs new packages that fire VimEnter/DirChanged).
local plugins_dir = vim.fn.stdpath('config') .. '/lua/plugins'
local plugin_files = {}
for name, ftype in vim.fs.dir(plugins_dir) do
  if ftype == 'file' and name:match('%.lua$') then
    table.insert(plugin_files, name)
  end
end
table.sort(plugin_files)
for _, name in ipairs(plugin_files) do
  local mod = name:gsub('%.lua$', '')
  local ok, err = pcall(require, 'plugins.' .. mod)
  if not ok then
    vim.notify('Error loading plugins/' .. name .. ':\n' .. err, vim.log.levels.ERROR)
  end
end

-- vim: ts=2 sts=2 sw=2 et
