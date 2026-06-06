-- ============================================================
-- plugins/dap.lua — Debug Adapter Protocol core
--
-- Installs nvim-dap, nvim-dap-ui, and nvim-nio (required by
-- dap-ui). Does NOT configure any language adapter or set up
-- dapui — those live in language-specific files:
--   plugins/fortran-tools.lua — gdb adapter + dapui layout
--
-- F-key aliases are provided here as ergonomic shortcuts that
-- mirror the <leader>d* keymaps in fortran-tools.lua. Having
-- both means you can use whichever is comfortable during a
-- debug session without looking at which-key.
--
-- NOTE: <leader>b and <leader>B are intentionally NOT mapped
-- here (removed from the old debug.lua). Use <leader>db and
-- <leader>dB from fortran-tools.lua instead, keeping all DAP
-- keymaps under the <leader>d prefix.
--
-- LAZY: No — DAP must be installed before fortran-tools.lua
--       calls require('dap') on first FileType fortran.
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

vim.pack.add {
  gh 'mfussenegger/nvim-dap',
  gh 'rcarriga/nvim-dap-ui',
  gh 'nvim-neotest/nvim-nio',  -- required async library for dap-ui
}

-- F-key aliases for stepping (same actions as <leader>d* in fortran-tools.lua).
-- These work globally so they are available as soon as a session starts,
-- even before a Fortran buffer is focused.
vim.keymap.set('n', '<F5>', function() require('dap').continue()   end, { desc = 'DAP: continue' })
vim.keymap.set('n', '<F1>', function() require('dap').step_into()  end, { desc = 'DAP: step into' })
vim.keymap.set('n', '<F2>', function() require('dap').step_over()  end, { desc = 'DAP: step over' })
vim.keymap.set('n', '<F3>', function() require('dap').step_out()   end, { desc = 'DAP: step out' })
vim.keymap.set('n', '<F7>', function() require('dapui').toggle()   end, { desc = 'DAP: toggle UI' })
