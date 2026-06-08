-- ============================================================
-- core/utils.lua — Shared helper functions
-- ============================================================

local M = {}

-- Return the first window showing a normal file buffer, skipping
-- neo-tree, terminal windows, and all dap-ui panels.
-- Used by toggleterm, cmake-tools, and keymaps to restore focus
-- after side panels open and close.
function M.find_editor_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft  = vim.bo[buf].filetype
    if vim.bo[buf].buftype == ''
      and ft ~= 'neo-tree'
      and ft ~= 'toggleterm'
      and ft ~= 'dapui_watches'
      and ft ~= 'dapui_scopes'
      and ft ~= 'dapui_breakpoints'
      and ft ~= 'dapui_stacks'
      and ft ~= 'dap-repl' then
      return win
    end
  end
  return nil
end

return M
