-- ============================================================
-- plugins/toggleterm.lua — Persistent togglable terminal
--
-- Provides a terminal that survives buffer switches and can be
-- shown/hidden with <C-\>. Used as the shell for cmake builds
-- and running swatplus executables.
--
-- Key behaviour:
--   on_open  — records which editor window was focused before
--              the terminal opened
--   on_close — restores focus to that window, preventing
--              neo-tree from stealing focus after <C-\>
--
-- LAZY: No — cmake-tools.lua sends commands to a toggleterm
--       instance, so it must be available before any cmake
--       keymap is pressed.
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

vim.pack.add { gh 'akinsho/toggleterm.nvim' }

local find_editor_win = require('core.utils').find_editor_win

require('toggleterm').setup {
  size            = 15,
  open_mapping    = [[<C-\>]],
  hide_numbers    = true,
  shade_terminals = true,
  shading_factor  = 2,
  start_in_insert = true,
  persist_mode    = false,
  insert_mappings = true,
  persist_size    = true,
  direction       = 'horizontal',
  close_on_exit   = true,
  shell           = vim.o.shell,
  float_opts      = { border = 'curved', winblend = 0 },

  -- on_open fires each time a toggleterm window opens.
  -- We record the active editor window on the terminal object so that
  -- each terminal instance independently knows where to return focus.
  on_open = function(term)
    local win = find_editor_win()
    if win then
      -- Store the origin window on the term object itself.
      -- This survives the close callback lookup because term is the
      -- same Lua table throughout the terminal's lifetime.
      term._origin_win = win
    end
  end,

  -- on_close fires when the terminal window is about to close.
  -- We use vim.schedule to defer the focus change until after toggleterm
  -- has finished its own close logic — without the defer, neo-tree or
  -- another non-editor window can grab focus in between.
  on_close = function(term)
    local target = term._origin_win
    if target and vim.api.nvim_win_is_valid(target) then
      vim.schedule(function()
        vim.api.nvim_set_current_win(target)
      end)
      return
    end

    -- Fallback: if the origin window was closed, find any editor window
    vim.schedule(function()
      local win = find_editor_win()
      if win then vim.api.nvim_set_current_win(win) end
    end)
  end,
}

-- <C-\> toggles the terminal in both normal and terminal mode
local opts = { noremap = true, silent = true }
vim.keymap.set('n', [[<C-\>]], '<Cmd>ToggleTerm<CR>', opts)
vim.keymap.set('t', [[<C-\>]], '<Cmd>ToggleTerm<CR>', opts)
