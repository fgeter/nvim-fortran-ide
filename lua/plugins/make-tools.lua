-- ============================================================
-- plugins/make-tools.lua — Make build integration
--
-- Activates for Fortran projects that have a Makefile but no
-- CMakeLists.txt (cmake-tools.lua takes priority when both exist).
--
-- Keymaps mirror cmake-tools so muscle memory transfers:
--   <leader>cb  pick debug/release → parallel build (all CPU cores via nproc)
--   <leader>cB  pick debug/release → single-threaded build (-j 1, cleaner errors)
--   <leader>cx  pick debug/release/both → make clean
--   <leader>cr  run executable (vim.g.project_executable or auto-detect)
--
-- LAZY: Yes — activate() runs only when a Makefile project is detected,
--       either at startup or after :cd.
-- ============================================================

if vim.g.loaded_make_tools_wrapper then return end
vim.g.loaded_make_tools_wrapper = true

-- Walk up the directory tree from `path`.
-- Returns true only if a Makefile is found before (or without) a CMakeLists.txt.
-- cmake-tools.lua takes priority: if CMakeLists.txt is encountered first, return false.
local function is_make_project(path)
  while path ~= '/' do
    if vim.fn.filereadable(path .. '/CMakeLists.txt') == 1 then
      return false
    end
    for _, name in ipairs({ 'Makefile', 'makefile', 'GNUmakefile' }) do
      if vim.fn.filereadable(path .. '/' .. name) == 1 then
        return true
      end
    end
    path = vim.fn.fnamemodify(path, ':h')
  end
  return false
end

local function activate()
  if vim.g.make_tools_active then return end
  vim.g.make_tools_active = true

  local project = require('core.project')
  local roots   = project.roots()
  local REPO_ROOT, BUILD_ROOT = roots.repo, roots.build

  local utils = require('core.utils')
  local term  = utils.make_terminal()

  ---------------------------------------------------------------------------
  -- Build: make [-jN] in a dedicated terminal (same UX as cmake-tools)
  ---------------------------------------------------------------------------
  local function run_build(build_type, jobs)
    local j = jobs or vim.g.project_build_jobs or utils.get_cpu_count()
    vim.notify('Building ' .. build_type .. ' with make -j' .. j, vim.log.levels.INFO)
    local make_cmd = 'make -j' .. j
      .. ' BUILD_TYPE=' .. build_type
      .. ' -C ' .. vim.fn.shellescape(REPO_ROOT)
    utils.run_build_cmd(make_cmd .. project.build_done_suffix)
  end

  local function do_build(jobs)
    vim.ui.select({ 'debug', 'release' }, {
      prompt = 'Build type:',
      format_item = function(item) return item:sub(1, 1):upper() .. item:sub(2) end,
    }, function(choice)
      if not choice then return end
      run_build(choice, jobs)
    end)
  end

  ---------------------------------------------------------------------------
  -- Run: pick executable → optionally pick workdata → launch
  ---------------------------------------------------------------------------
  -- Discovery, the two-step picker, and pre-run output cleaning are shared
  -- with cmake-tools/fortran-tools via core/project.lua. When the project
  -- has no workdata directories the launch falls back to the repo root
  -- (unlike cmake-tools, which treats missing workdata as an error).
  local function launch(program, cwd)
    local removed = project.clean_output_files(cwd)
    if removed > 0 then
      vim.notify('Removed ' .. removed .. ' previous output file(s) from '
        .. vim.fn.fnamemodify(cwd, ':t'), vim.log.levels.INFO)
    end
    term.run('cd ' .. vim.fn.shellescape(cwd) .. ' && ' .. vim.fn.shellescape(program))
  end

  local function pick_and_run()
    local execs = project.find_executables { root = BUILD_ROOT }
    if #execs == 0 then
      vim.notify(
        'No executables found under ' .. BUILD_ROOT .. '.\n' ..
        'Build first with <leader>cb.',
        vim.log.levels.WARN)
      return
    end
    project.pick_and_launch {
      execs            = execs,
      launch           = launch,
      workdir_fallback = REPO_ROOT,
    }
  end

  ---------------------------------------------------------------------------
  -- Keymaps
  ---------------------------------------------------------------------------
  vim.keymap.set('n', '<leader>cb', function() do_build() end,
    { desc = 'Make: build (all CPU cores)', nowait = true })

  vim.keymap.set('n', '<leader>cB', function() do_build(1) end,
    { desc = 'Make: build single-threaded (debug compile errors)', nowait = true })

  vim.keymap.set('n', '<leader>cx', function()
    vim.ui.select({ 'debug', 'release', 'both' }, {
      prompt = 'Clean build type:',
      format_item = function(item) return item:sub(1, 1):upper() .. item:sub(2) end,
    }, function(choice)
      if not choice then return end
      local base = 'make -C ' .. vim.fn.shellescape(REPO_ROOT) .. ' BUILD_TYPE='
      if choice == 'both' then
        term.run(base .. 'debug clean && ' .. base .. 'release clean')
      else
        term.run(base .. choice .. ' clean')
      end
    end)
  end, { desc = 'Make: clean' })

  vim.keymap.set('n', '<leader>cr', pick_and_run,
    { desc = 'Make: run executable', nowait = true })

  vim.notify('Make tools activated.', vim.log.levels.INFO)
end

-- ── Entry point ───────────────────────────────────────────────
if is_make_project(vim.fn.getcwd()) then
  activate()
else
  vim.api.nvim_create_autocmd('DirChanged', {
    callback = function()
      if is_make_project(vim.fn.getcwd()) then
        activate()
        return true
      end
    end,
  })
end
