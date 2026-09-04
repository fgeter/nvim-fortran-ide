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
--   project_workdir_sort           initial order of the run-directory pick
--                                  list: 'mtime' (default, most recently
--                                  changed first) or 'name'. The list's
--                                  own Sort entry toggles it thereafter.
--   project_clean_output_patterns  list of globs offered for deletion in
--                                  the chosen run dir before each run,
--                                  e.g. { '*.txt', '*.out', '*.csv' }.
--                                  Default: nil — nothing is deleted.
--                                  The matches are always listed and
--                                  confirmed first; readme.txt is kept.
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
-- prints a success banner and exits 0, so TermClose's status check
-- reflects a real build success (a failed build never reaches the braces
-- and leaves the interactive shell sitting at its prompt with the errors
-- still on screen).
--
-- The shell used to wait here on a `read` for the user to press <CR>.
-- That only works while the terminal still holds focus *in terminal
-- mode* — and a build long enough to be worth watching is exactly the one
-- you wander off during. Once focus has moved, no <CR> can reach the
-- shell: clicking back into a terminal lands in normal mode, where <CR>
-- just moves the cursor. utils.run_build_cmd asks from Neovim's side
-- instead, which works wherever focus happens to be.
M.build_done_suffix =
  ' && { printf "\\nBuild succeeded\\n"; exit 0; }'

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

-- True when `dir` is project_work_root or one of its subdirectories —
-- i.e. a scratch run directory rather than a folder the user browsed to.
-- Only used to pick the safer default button in the cleaning prompt.
local function under_work_root(dir)
  local work = M.roots().work:gsub('/+$', '')
  return dir == work or dir:sub(1, #work + 1) == work .. '/'
end

-- Files in `dir` matched by vim.g.project_clean_output_patterns, sorted
-- and de-duplicated (patterns can overlap). readme.txt is always kept.
local function output_files(dir)
  local patterns = vim.g.project_clean_output_patterns
  if not patterns then return {} end
  local found, seen = {}, {}
  for _, pat in ipairs(patterns) do
    for _, path in ipairs(vim.fn.glob(dir .. '/' .. pat, false, true)) do
      if not seen[path] and vim.fn.fnamemodify(path, ':t'):lower() ~= 'readme.txt' then
        seen[path] = true
        table.insert(found, path)
      end
    end
  end
  table.sort(found)
  return found
end

-- How many file names the cleaning prompt lists before summarizing the
-- rest; a finished SWAT+ run leaves hundreds of them behind.
local CLEAN_PREVIEW = 12

-- Delete previous run outputs from `dir` according to
-- vim.g.project_clean_output_patterns (no-op when unset), after asking.
-- Returns the number of files deleted; the caller decides whether/how to
-- report it. Declining deletes nothing and still lets the run proceed.
--
-- The prompt is never skipped: the patterns are broad ('*.txt' matches
-- CMakeLists.txt as readily as hru_wb_day.txt), and the run directory can
-- now be any folder on the filesystem (see Browse in pick_and_launch), so
-- the matched names are listed and the deletion confirmed every time.
-- Only the default button varies — Yes under project_work_root, where
-- everything is reproducible output, No anywhere else.
function M.clean_output_files(dir)
  local targets = output_files(dir)
  if #targets == 0 then return 0 end

  local lines = {
    ('Delete %d previous output file(s) from'):format(#targets),
    dir .. '?',
    '',
  }
  for i = 1, math.min(#targets, CLEAN_PREVIEW) do
    table.insert(lines, '    ' .. vim.fn.fnamemodify(targets[i], ':t'))
  end
  if #targets > CLEAN_PREVIEW then
    table.insert(lines, ('    … and %d more'):format(#targets - CLEAN_PREVIEW))
  end

  local answer = vim.fn.confirm(table.concat(lines, '\n'),
    '&Yes, delete them\n&No, run without cleaning',
    under_work_root(dir) and 1 or 2, 'Question')
  if answer ~= 1 then return 0 end

  for _, path in ipairs(targets) do vim.fn.delete(path) end
  return #targets
end

-- Sentinel entry leading the run-directory picker. Choosing it opens
-- a path prompt so a dataset that lives outside project_work_root can be
-- used as the run cwd — the workdata dirs are a shortcut, not a limit.
local BROWSE = { label = '󰉋  Browse for another directory…' }

-- Last directory entered through Browse, offered as the prompt default
-- next time so repeated runs against the same external dataset are cheap.
local last_browsed = nil

-- Sentinel entry that flips the run-directory ordering. A vim.ui.select
-- backend is whatever the user has configured (telescope-ui-select here),
-- so the toggle lives in the list itself rather than in a picker mapping
-- that only one backend would honor.
local SORT_TOGGLE = { label = '' }

-- Current run-directory ordering: 'mtime' (most recently changed first,
-- the default) or 'name' (alphabetical). vim.g.project_workdir_sort lets a
-- .nvim.lua pick the starting order; the toggle then holds for the session.
local workdir_sort = nil

local function sort_mode()
  if not workdir_sort then
    workdir_sort = vim.g.project_workdir_sort == 'name' and 'name' or 'mtime'
  end
  return workdir_sort
end

-- Prompt for any directory on the filesystem and hand it to `on_dir`.
-- <Tab> completes path components (snacks.input honors `completion`).
local function browse_workdir(on_dir)
  vim.ui.input({
    prompt     = 'Run directory: ',
    default    = (last_browsed or M.roots().work) .. '/',
    completion = 'dir',
  }, function(input)
    if not input or vim.trim(input) == '' then return end
    local dir = vim.fn.fnamemodify(vim.fn.expand(vim.trim(input)), ':p')
    dir = dir:gsub('/+$', '')
    if vim.fn.isdirectory(dir) == 0 then
      vim.notify('Not a directory: ' .. dir, vim.log.levels.ERROR)
      return
    end
    last_browsed = dir
    on_dir(dir)
  end)
end

-- Two-step picker shared by cmake-tools/make-tools <leader>cr and
-- fortran-tools <leader>ds: pick an executable, then a run directory,
-- then call launch(program, cwd). The executable step is skipped when
-- there is only one; the directory step always shows, because Browse is
-- an option there even when the project has a single workdata dir.
-- Run directories are listed most-recently-changed first, with a Sort
-- entry that toggles to alphabetical for the rest of the session.
--   opts.execs             non-empty list of executable paths
--   opts.launch            function(program, cwd)
--   opts.strip_prefix      path prefix removed from executable labels
--                          (default: roots().build)
--   opts.workdir_fallback  cwd offered when no workdata dirs exist;
--                          nil → Browse is the only entry
function M.pick_and_launch(opts)
  local roots = M.roots()
  local strip = (opts.strip_prefix or roots.build) .. '/'

  local function pick_workdir(program)
    local sort = sort_mode()
    local dirs, mtimes = utils.get_workdirs(roots.work, sort)
    if #dirs == 0 and opts.workdir_fallback then
      dirs, mtimes = { opts.workdir_fallback }, {}
    end

    -- Browse and the sort toggle lead the list: a project with dozens of
    -- workdata dirs would otherwise push them off the bottom of the
    -- picker, where they are invisible until you scroll the whole list.
    -- Nothing to reorder with a single directory, so the toggle only shows
    -- up when it would change the list.
    local items = { BROWSE }
    if #dirs > 1 then table.insert(items, SORT_TOGGLE) end
    vim.list_extend(items, dirs)

    local function choose(choice)
      if not choice then return end
      if choice == SORT_TOGGLE then
        workdir_sort = (sort == 'mtime') and 'name' or 'mtime'
        pick_workdir(program)
      elseif choice == BROWSE then
        browse_workdir(function(dir) opts.launch(program, dir) end)
      else
        opts.launch(program, choice)
      end
    end

    -- No workdata dirs and no fallback: go straight to the path prompt
    -- rather than showing a menu with a single entry.
    if #dirs == 0 then
      choose(BROWSE)
      return
    end

    -- Names are padded to a common width so the ages line up in a column;
    -- the age is what explains the order, so it is shown in both modes.
    local width = 0
    for _, dir in ipairs(dirs) do
      width = math.max(width, vim.fn.strdisplaywidth(utils.basename(dir)))
    end

    vim.ui.select(items, {
      prompt      = sort == 'mtime'
                    and 'Select run directory (recent first):'
                    or  'Select run directory (A-Z):',
      format_item = function(item)
        if item == BROWSE then return item.label end
        if item == SORT_TOGGLE then
          return sort == 'mtime' and '󰒺  Sort alphabetically'
                                 or  '󰃰  Sort by most recently changed'
        end
        local name = utils.basename(item)
        local age  = utils.relative_time(mtimes[item])
        if age == '' then return name end
        return ('%s%s  %s'):format(
          name, (' '):rep(width - vim.fn.strdisplaywidth(name)), age)
      end,
    }, choose)
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
