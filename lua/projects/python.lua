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

if not vim.g.project_repo_root then
  vim.notify(
    'projects/python.lua: vim.g.project_repo_root is not set.',
    vim.log.levels.ERROR)
  return
end

-- Gate on repo root, not a boolean, so :cd into another Python project
-- can load that project's .nvim.lua.
local root = vim.g.project_repo_root
if vim.g.python_project_loaded == root then return end
vim.g.python_project_loaded = root

local name = vim.g.project_name or vim.fn.fnamemodify(root, ':t')
vim.notify('Loading Python project: ' .. name, vim.log.levels.INFO)

-- get_python_bin / DAP / basedpyright before_init read vim.g at use time.
-- Just ensure the language layer is activated (idempotent).
local python = require('plugins.python')
if python and python.activate then python.activate() end
