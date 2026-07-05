-- ============================================================
-- lua/projects/fortran.lua — Shared Fortran project configuration
--
-- This file is sourced by project-local .nvim.lua files that
-- need Fortran LSP + DAP + cmake support. It reads paths from
-- vim.g variables set by the calling .nvim.lua so it works
-- for any Fortran/CMake project, not just SWAT+.
--
-- Required vim.g variables (set in .nvim.lua before require):
--   vim.g.project_repo_root   — absolute path to project root
--   vim.g.project_build_root  — path to build directory
--   vim.g.project_src_dir     — path to Fortran source files
--   vim.g.project_work_root   — path to run/workdata directories
--                               (nil if project has no workdata)
--
-- Optional vim.g variables:
--   vim.g.project_name        — display name shown in notifications
--   vim.g.project_build_jobs  — parallel build thread count override
--                               (default: all logical cores)
--   vim.g.project_executable_pattern
--                             — glob for run/debug targets in the build
--                               tree, e.g. 'swatplus*' (default: '*',
--                               any executable file)
--   vim.g.project_clean_output_patterns
--                             — list of globs deleted from the chosen
--                               workdata dir before each run, e.g.
--                               { '*.txt', '*.out', '*.csv' }.
--                               Unset = nothing is deleted.
--                               readme.txt is always preserved.
-- ============================================================

if vim.g.fortran_project_loaded then return end
vim.g.fortran_project_loaded = true

-- Validate required paths are set
local required = {
  'project_repo_root',
  'project_build_root',
  'project_src_dir',
}
for _, key in ipairs(required) do
  if not vim.g[key] then
    vim.notify(
      'projects/fortran.lua: vim.g.' .. key .. ' is not set.\n' ..
      'Set it in your .nvim.lua before require("projects.fortran").',
      vim.log.levels.ERROR)
    return
  end
end

local name = vim.g.project_name or vim.fn.fnamemodify(vim.g.project_repo_root, ':t')
vim.notify('Loading project: ' .. name, vim.log.levels.INFO)

-- ── Activate cmake-tools for this project ─────────────────────────────
-- cmake-tools.lua reads these vim.g variables instead of hardcoded paths
-- so it works correctly for whichever project is open.
-- The DirChanged lazy trigger in cmake-tools.lua will have already fired
-- by the time .nvim.lua is sourced, so we activate directly here.
vim.g.cmake_tools_active = nil  -- reset so activate() can run again
local ok, cmake = pcall(require, 'plugins.cmake-tools')
if not ok then
  -- cmake-tools.lua guards with vim.g.cmake_tools_active; trigger via DirChanged
  vim.api.nvim_exec_autocmds('DirChanged', { modeline = false })
end

-- ── Activate fortran-tools for this project ───────────────────────────
-- fortran-tools.lua reads vim.g.project_* paths. Reset the active guard
-- so it re-runs with the new project's paths if switching projects.
vim.g.fortran_tools_active = nil

-- Force activation now if a Fortran buffer is already open,
-- otherwise the FileType autocmd in fortran-tools.lua will trigger it
-- when the first Fortran file is opened.
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buf].filetype == 'fortran' then
    vim.g.fortran_tools_active = nil
    -- Re-fire FileType to trigger fortran-tools activate()
    vim.api.nvim_exec_autocmds('FileType', {
      pattern = 'fortran',
      modeline = false,
    })
    break
  end
end
