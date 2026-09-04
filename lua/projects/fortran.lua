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

-- Gate on repo root, not a boolean: :cd into a second Fortran project
-- must be allowed to load that project's .nvim.lua.
local root = vim.g.project_repo_root
if vim.g.fortran_project_loaded == root then return end
vim.g.fortran_project_loaded = root

local name = vim.g.project_name or vim.fn.fnamemodify(root, ':t')
vim.notify('Loading project: ' .. name, vim.log.levels.INFO)

-- cmake-tools / fortran-tools / make-tools now read vim.g.project_* at
-- keypress, so we only need to ensure they have been activated (install +
-- keymaps). Do NOT nil the *_active guards: that left the plugins running
-- with the flag false and never actually re-called activate().
if vim.fn.filereadable(root .. '/CMakeLists.txt') == 1 then
  local cmake = require('plugins.cmake-tools')
  if cmake and cmake.activate then cmake.activate() end
else
  local make = require('plugins.make-tools')
  if make and make.activate then make.activate() end
end

local fortran = require('plugins.fortran-tools')
if fortran and fortran.activate then fortran.activate() end
