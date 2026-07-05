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

-- ── Plugin / feature loader ──────────────────────────────────
-- Auto-load every .lua file in lua/plugins/ (third-party plugin config,
-- each file owns its own vim.pack.add() + setup()) and then lua/features/
-- (homegrown subsystems with no plugin behind them — git workflow,
-- horizontal scrollbar, edge scrolling, …). A file that errors is
-- reported and skipped so one broken module can't stop the rest.
-- vim.fs.dir does not guarantee alphabetical order; sort explicitly so the
-- documented load order (alphabetical within each directory) is always
-- honoured. This matters because neo-tree.lua must precede ui.lua (which
-- installs new packages that fire VimEnter/DirChanged). dap.lua no longer
-- needs to precede the language files: they call
-- require('plugins.dap').activate() themselves.
for _, dir in ipairs({ 'plugins', 'features' }) do
  local files = {}
  for name, ftype in vim.fs.dir(vim.fn.stdpath('config') .. '/lua/' .. dir) do
    if ftype == 'file' and name:match('%.lua$') then
      table.insert(files, name)
    end
  end
  table.sort(files)
  for _, name in ipairs(files) do
    local mod = name:gsub('%.lua$', '')
    local ok, err = pcall(require, dir .. '.' .. mod)
    if not ok then
      vim.notify('Error loading ' .. dir .. '/' .. name .. ':\n' .. err, vim.log.levels.ERROR)
    end
  end
end

-- vim: ts=2 sts=2 sw=2 et
