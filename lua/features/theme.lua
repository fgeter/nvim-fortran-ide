-- ============================================================
-- features/theme.lua — pick the colour theme (View › Theme, <leader>vC)
--
-- A telescope picker with live preview over every theme that is on disk,
-- each listed once, downloaded themes before Neovim's built-ins:
-- catppuccin's four flavours (plugins/ui.lua, the default), the other
-- theme packages vim.pack downloaded earlier (tokyonight, tokyodark,
-- kanagawa, everforest — not loaded until needed, so they cost nothing at
-- startup), and Neovim's built-in schemes. Esc puts the old theme back.
--
-- The choice is remembered in stdpath('state')/colorscheme and applied at
-- startup, right after plugins/ui.lua set catppuccin. Delete that file to
-- go back to the default.
--
-- M.state('vC') is the current theme's name, for the View drop-down.
-- Added 2026-11-03.
-- ============================================================

local M = {}

local SAVE = vim.fn.stdpath('state') .. '/colorscheme'

-- The name as chosen ("kanagawa-dragon"): some themes set colors_name to
-- just their family ("kanagawa"), which is less useful in the menu.
local current = nil

-- Optional theme packages: pack dir name → its colorschemes. Found by
-- looking for colors/ inside every opt package, so a theme added later
-- with vim.pack shows up without editing this file.
local function theme_packs()
  local packs = {}
  for _, path in ipairs(vim.fn.globpath(vim.o.packpath, 'pack/*/opt/*/colors/*', false, true)) do
    local pack = path:match('/opt/([^/]+)/colors/')
    local name = vim.fn.fnamemodify(path, ':t:r')
    if pack and name ~= '' then
      packs[pack] = packs[pack] or {}
      table.insert(packs[pack], name)
    end
  end
  return packs
end

-- Make every downloaded theme available to :colorscheme (and so to the
-- picker). packadd of an already-loaded package is a no-op.
local function load_all_packs()
  for pack in pairs(theme_packs()) do pcall(vim.cmd.packadd, pack) end
end

-- Load just the package that provides `name`, if any.
local function load_pack_for(name)
  for pack, names in pairs(theme_packs()) do
    if vim.tbl_contains(names, name) then pcall(vim.cmd.packadd, pack) return end
  end
end

-- ── Restore the saved theme at startup ───────────────────────
local saved = vim.fn.filereadable(SAVE) == 1 and vim.trim(vim.fn.readfile(SAVE)[1] or '') or ''
if saved ~= '' and saved ~= vim.g.colors_name then
  load_pack_for(saved)
  if pcall(vim.cmd.colorscheme, saved) then
    current = saved
  else
    vim.notify('Saved theme "' .. saved .. '" not found; using catppuccin', vim.log.levels.WARN)
    pcall(vim.cmd.colorscheme, 'catppuccin')
  end
end

-- ── Picker ───────────────────────────────────────────────────
-- Names that are only a second name for another entry: picking one looks
-- like nothing happened. (catppuccin and catppuccin-nvim are mocha,
-- kanagawa is kanagawa-wave, tokyonight is tokyonight-moon.)
local ALIASES = {
  ['catppuccin'] = true, ['catppuccin-nvim'] = true,
  ['kanagawa'] = true, ['tokyonight'] = true,
}

-- Downloaded themes first (alphabetical), then Neovim's built-ins, each
-- name once. The current theme goes to the top so the list opens on it.
local function theme_list()
  local seen, downloaded, builtin = {}, {}, {}
  for _, names in pairs(theme_packs()) do
    for _, n in ipairs(names) do
      if not ALIASES[n] and not seen[n] then seen[n] = true; downloaded[#downloaded + 1] = n end
    end
  end
  for _, n in ipairs(vim.fn.getcompletion('', 'color')) do
    if not ALIASES[n] and not seen[n] then seen[n] = true; builtin[#builtin + 1] = n end
  end
  table.sort(downloaded)
  table.sort(builtin)

  local list, cur = {}, current or vim.g.colors_name
  for _, n in ipairs(downloaded) do
    list[#list + 1] = { name = n, builtin = false }
  end
  for _, n in ipairs(builtin) do
    list[#list + 1] = { name = n, builtin = true }
  end
  for i, t in ipairs(list) do
    if t.name == cur then table.insert(list, 1, table.remove(list, i)) break end
  end
  return list
end

-- Same live preview as telescope's own :Telescope colorscheme (which
-- can't drop entries, hence this copy): moving the selection applies the
-- theme, Enter keeps it, closing any other way puts the old one back.
local function pick_theme()
  load_all_packs()
  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local conf         = require('telescope.config').values
  local actions      = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  local before_bg, before = vim.o.background, current or vim.g.colors_name
  local restore = true

  local picker = pickers.new({}, {
    prompt_title = 'Theme',
    finder = finders.new_table({
      results = theme_list(),
      entry_maker = function(t)
        return {
          value   = t.name,
          ordinal = t.name,
          display = t.builtin and (t.name .. '   · built-in') or t.name,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_buf)
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        if not sel then return end
        restore = false
        actions.close(prompt_buf)
        pcall(vim.cmd.colorscheme, sel.value)
      end)
      return true
    end,
  })

  local set_selection = picker.set_selection
  picker.set_selection = function(self, row)
    set_selection(self, row)
    local sel = action_state.get_selected_entry()
    if sel then pcall(vim.cmd.colorscheme, sel.value) end
  end

  local close_windows = picker.close_windows
  picker.close_windows = function(status)
    close_windows(status)
    if restore and before then
      vim.o.background = before_bg
      pcall(vim.cmd.colorscheme, before)
    end
  end

  picker:find()
end

vim.keymap.set('n', '<leader>vC', pick_theme, { desc = 'View: theme…', silent = true })

-- Remember whatever theme is active. Previews fire this too, but closing
-- the picker always ends on the chosen theme (or the old one put back on
-- Esc), so the last write is the right one.
vim.api.nvim_create_autocmd('ColorScheme', {
  desc     = 'Remember the colour theme for the next start',
  group    = vim.api.nvim_create_augroup('theme-remember', { clear = true }),
  callback = function(ev)
    if ev.match and ev.match ~= '' then
      current = ev.match
      pcall(vim.fn.writefile, { ev.match }, SAVE)
    end
  end,
})

function M.state(key)
  if key ~= 'vC' then return nil end
  return current or vim.g.colors_name or 'default'
end

return M
