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

  local REPO_ROOT = vim.g.project_repo_root or vim.fn.getcwd()
  local WORK_ROOT = vim.g.project_work_root or (REPO_ROOT .. '/workdata')

  local utils = require('core.utils')
  local term  = utils.make_terminal()

  ---------------------------------------------------------------------------
  -- Build: make [-jN] in a dedicated terminal (same UX as cmake-tools)
  ---------------------------------------------------------------------------
  local function run_build(build_type, jobs)
    local j = jobs or utils.get_cpu_count()
    vim.notify('Building ' .. build_type .. ' with make -j' .. j, vim.log.levels.INFO)
    local make_cmd = 'make -j' .. j
      .. ' BUILD_TYPE=' .. build_type
      .. ' -C ' .. vim.fn.shellescape(REPO_ROOT)
    utils.run_build_cmd(make_cmd
      .. ' && { printf "\\nBuild succeeded — press <CR> to close\\n"; read; exit 0; }')
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
  -- Executable discovery
  ---------------------------------------------------------------------------
  local function get_executables()
    local candidates = {
      { label = 'Debug',   path = REPO_ROOT .. '/build/debug/swatplus' },
      { label = 'Release', path = REPO_ROOT .. '/build/release/swatplus' },
    }
    local found = {}
    for _, c in ipairs(candidates) do
      if vim.fn.executable(c.path) == 1 then
        table.insert(found, c)
      end
    end
    return found
  end

  ---------------------------------------------------------------------------
  -- Run: pick debug/release → optionally pick workdata → launch
  ---------------------------------------------------------------------------
  local function launch(program, cwd)
    term.run('cd ' .. vim.fn.shellescape(cwd) .. ' && ' .. vim.fn.shellescape(program))
  end

  local function pick_workdata_and_launch(program)
    local dirs = utils.get_workdirs(WORK_ROOT)
    if #dirs == 0 then
      launch(program, REPO_ROOT)
      return
    end
    if #dirs == 1 then launch(program, dirs[1]); return end
    vim.ui.select(dirs, {
      prompt      = 'Select working directory:',
      format_item = function(item) return vim.fn.fnamemodify(item, ':t') end,
    }, function(choice) if choice then launch(program, choice) end end)
  end

  local function pick_and_run()
    local execs = get_executables()
    if #execs == 0 then
      vim.notify(
        'No executable found in build/debug/ or build/release/.\n' ..
        'Build first with <leader>cb.',
        vim.log.levels.WARN)
      return
    end
    if #execs == 1 then pick_workdata_and_launch(execs[1].path); return end
    vim.ui.select(execs, {
      prompt      = 'Run build:',
      format_item = function(item) return item.label end,
    }, function(choice) if choice then pick_workdata_and_launch(choice.path) end end)
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
