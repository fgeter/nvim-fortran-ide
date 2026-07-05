-- ============================================================
-- core/project.lua — Shared project-runner helpers
--
-- Single home for the executable-discovery / picker / launch logic
-- that cmake-tools.lua, make-tools.lua, and fortran-tools.lua each
-- used to reimplement with hardcoded swatplus paths. Everything is
-- driven by the vim.g.project_* variables that a project's .nvim.lua
-- sets (see doc/*.nvim.lua.template), with generic fallbacks so the
-- config works in any project without one.
--
-- vim.g variables read here (all optional):
--   project_repo_root              project root (default: cwd)
--   project_build_root             build dir   (default: <repo>/build)
--   project_work_root              workdata dir (default: <repo>/workdata)
--   project_src_dir                sources     (default: <repo>/src)
--   project_executable_pattern     glob for run/debug targets
--                                  (default: '*' — any executable file)
--   project_clean_output_patterns  list of globs deleted from the chosen
--                                  workdata dir before each run, e.g.
--                                  { '*.txt', '*.out', '*.csv' }.
--                                  Default: nil — nothing is deleted.
--                                  readme.txt is always preserved.
-- ============================================================

local utils = require('core.utils')

local M = {}

-- Resolve project roots at call time, honoring vim.g overrides from a
-- .nvim.lua. Never cache this at module load: when activation is deferred
-- (DirChanged), cwd at load time is still the pre-:cd directory.
function M.roots()
  local repo = vim.g.project_repo_root or vim.fn.getcwd()
  return {
    repo  = repo,
    build = vim.g.project_build_root or (repo .. '/build'),
    work  = vim.g.project_work_root  or (repo .. '/workdata'),
    src   = vim.g.project_src_dir    or (repo .. '/src'),
  }
end

-- Shell suffix appended to build commands run through utils.run_build_cmd:
-- prints a success banner, waits for <CR>, and exits 0 so TermClose's
-- status check reflects a real build success (a failed build leaves the
-- shell to exit with the build tool's non-zero status).
M.build_done_suffix =
  ' && { printf "\\nBuild succeeded — press <CR> to close\\n"; read; exit 0; }'

-- Find executable files matching the project pattern.
--   opts.root     directory to scan (default: roots().build)
--   opts.subdirs  also scan one level of subdirectories — build/debug,
--                 build/release, … (default: true)
function M.find_executables(opts)
  opts = opts or {}
  local root    = opts.root or M.roots().build
  local pattern = vim.g.project_executable_pattern or '*'
  local execs   = {}

  local function scan(dir)
    for _, path in ipairs(vim.fn.glob(dir .. '/' .. pattern, false, true)) do
      if vim.fn.executable(path) == 1 and vim.fn.isdirectory(path) == 0 then
        table.insert(execs, path)
      end
    end
  end

  scan(root)
  if opts.subdirs ~= false then
    for _, subdir in ipairs(vim.fn.glob(root .. '/*', false, true)) do
      if vim.fn.isdirectory(subdir) == 1 then scan(subdir) end
    end
  end
  return execs
end

-- Delete previous run outputs from `dir` according to
-- vim.g.project_clean_output_patterns (no-op when unset).
-- readme.txt is always preserved. Returns the number of files deleted;
-- the caller decides whether/how to report it.
function M.clean_output_files(dir)
  local patterns = vim.g.project_clean_output_patterns
  if not patterns then return 0 end
  local count = 0
  for _, pat in ipairs(patterns) do
    for _, path in ipairs(vim.fn.glob(dir .. '/' .. pat, false, true)) do
      if vim.fn.fnamemodify(path, ':t'):lower() ~= 'readme.txt' then
        vim.fn.delete(path)
        count = count + 1
      end
    end
  end
  return count
end

-- Two-step picker shared by cmake-tools/make-tools <leader>cr and
-- fortran-tools <leader>ds: pick an executable, then a workdata
-- directory, then call launch(program, cwd). Either step is skipped
-- when there is exactly one choice.
--   opts.execs             non-empty list of executable paths
--   opts.launch            function(program, cwd)
--   opts.strip_prefix      path prefix removed from executable labels
--                          (default: roots().build)
--   opts.workdir_fallback  cwd to use when no workdata dirs exist;
--                          nil → report an error instead of launching
function M.pick_and_launch(opts)
  local roots = M.roots()
  local strip = (opts.strip_prefix or roots.build) .. '/'

  local function pick_workdir(program)
    local dirs = utils.get_workdirs(roots.work)
    if #dirs == 0 then
      if opts.workdir_fallback then
        opts.launch(program, opts.workdir_fallback)
      else
        vim.notify('No workdata directories found in ' .. roots.work,
          vim.log.levels.ERROR)
      end
      return
    end
    if #dirs == 1 then
      opts.launch(program, dirs[1])
      return
    end
    vim.ui.select(dirs, {
      prompt      = 'Select workdata directory:',
      format_item = utils.basename,
    }, function(choice)
      if choice then opts.launch(program, choice) end
    end)
  end

  if #opts.execs == 1 then
    pick_workdir(opts.execs[1])
    return
  end
  vim.ui.select(opts.execs, {
    prompt      = 'Select executable:',
    format_item = function(item)
      return item:sub(1, #strip) == strip and item:sub(#strip + 1) or item
    end,
  }, function(choice)
    if choice then pick_workdir(choice) end
  end)
end

return M
