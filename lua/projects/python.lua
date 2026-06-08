-- ============================================================
-- lua/projects/python.lua — Shared Python project configuration
--
-- Sourced by project-local .nvim.lua files for Python projects.
-- Activates basedpyright LSP, debugpy DAP, and ruff formatting.
-- Reads paths from vim.g variables set by the calling .nvim.lua.
--
-- Required vim.g variables:
--   vim.g.project_repo_root  — absolute path to project root
--
-- Optional vim.g variables:
--   vim.g.project_name       — display name for notifications
--   vim.g.project_venv       — path to virtualenv (e.g. .venv)
--                              if not set, uses VIRTUAL_ENV env var
--                              or falls back to system python3
--   vim.g.project_python_bin — explicit python binary path override
-- ============================================================

if vim.g.python_project_loaded then return end
vim.g.python_project_loaded = true

if not vim.g.project_repo_root then
  vim.notify(
    'projects/python.lua: vim.g.project_repo_root is not set.',
    vim.log.levels.ERROR)
  return
end

local name = vim.g.project_name or vim.fn.fnamemodify(vim.g.project_repo_root, ':t')
vim.notify('Loading Python project: ' .. name, vim.log.levels.INFO)

-- Reset python_tools_active so python.lua activate() re-runs
-- with the correct project context if switching projects
vim.g.python_tools_active = nil

-- Force activation if a Python buffer is already open
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buf].filetype == 'python' then
    vim.api.nvim_exec_autocmds('FileType', {
      pattern  = 'python',
      modeline = false,
    })
    break
  end
end
