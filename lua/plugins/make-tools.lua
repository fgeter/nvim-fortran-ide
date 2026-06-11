-- ============================================================
-- plugins/make-tools.lua — Make build integration
--
-- Activates for Fortran projects that have a Makefile but no
-- CMakeLists.txt (cmake-tools.lua takes priority when both exist).
--
-- Keymaps mirror cmake-tools so muscle memory transfers:
--   <leader>cb  parallel build (all CPU cores via nproc)
--   <leader>cB  single-threaded build (-j 1, cleaner error output)
--   <leader>cx  make clean
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

  local get_editor_win = require('core.utils').find_editor_win

  ---------------------------------------------------------------------------
  -- CPU count (same logic as cmake-tools)
  ---------------------------------------------------------------------------
  local function get_cpu_count()
    local nproc  = tonumber((vim.fn.system('nproc 2>/dev/null'):gsub('%s+', '')))
    local sysctl = tonumber((vim.fn.system('sysctl -n hw.logicalcpu 2>/dev/null'):gsub('%s+', '')))
    return nproc or sysctl or 4
  end

  ---------------------------------------------------------------------------
  -- Persistent terminal (same pattern as cmake-tools)
  ---------------------------------------------------------------------------
  local term_buf  = nil
  local term_chan = nil

  local function register_focus_restore(origin_win)
    if not term_buf then return end
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer   = term_buf,
      once     = true,
      callback = function()
        vim.schedule(function()
          local target = (origin_win and vim.api.nvim_win_is_valid(origin_win))
            and origin_win or get_editor_win()
          if target then vim.api.nvim_set_current_win(target) end
        end)
      end,
    })
  end

  local function open_terminal()
    local origin_win = get_editor_win()
    vim.cmd('botright split')
    vim.cmd('terminal bash')
    term_buf  = vim.api.nvim_get_current_buf()
    term_chan = vim.bo[term_buf].channel
    register_focus_restore(origin_win)
  end

  local function run_in_terminal(cmd)
    if term_buf and not vim.api.nvim_buf_is_valid(term_buf) then
      term_buf = nil; term_chan = nil
    end

    if not term_buf then
      open_terminal()
    else
      local term_win = nil
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == term_buf then
          term_win = win; break
        end
      end
      if not term_win then
        local origin_win = get_editor_win()
        vim.cmd('botright split')
        vim.api.nvim_win_set_buf(0, term_buf)
        register_focus_restore(origin_win)
      else
        vim.api.nvim_set_current_win(term_win)
      end
    end

    local ok = pcall(vim.fn.chansend, term_chan, cmd .. '\n')
    if not ok then
      open_terminal()
      pcall(vim.fn.chansend, term_chan, cmd .. '\n')
    end
    vim.cmd('startinsert')
  end

  ---------------------------------------------------------------------------
  -- Build: make [-jN] in a dedicated terminal (same UX as cmake-tools)
  ---------------------------------------------------------------------------
  local function do_build(jobs)
    local j = jobs or get_cpu_count()
    vim.notify('Building with make -j' .. j, vim.log.levels.INFO)

    local make_cmd = 'make -j' .. j .. ' -C ' .. vim.fn.shellescape(REPO_ROOT)
    local shell_cmd = make_cmd
      .. ' && { printf "\\nBuild succeeded — press <CR> to close\\n"; read; exit 0; }'

    local origin_win = get_editor_win()
    vim.cmd('botright split')
    vim.cmd('terminal bash')
    local build_buf  = vim.api.nvim_get_current_buf()
    local build_chan = vim.bo[build_buf].channel

    vim.api.nvim_create_autocmd('TermClose', {
      buffer   = build_buf,
      once     = true,
      callback = function()
        vim.schedule(function()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == build_buf then
              vim.api.nvim_win_close(win, true); break
            end
          end
          if vim.api.nvim_buf_is_valid(build_buf) then
            vim.api.nvim_buf_delete(build_buf, { force = true })
          end
          local target = (origin_win and vim.api.nvim_win_is_valid(origin_win))
            and origin_win or get_editor_win()
          if target then vim.api.nvim_set_current_win(target) end
        end)
      end,
    })

    pcall(vim.fn.chansend, build_chan, shell_cmd .. '\n')
    vim.cmd('startinsert')
  end

  ---------------------------------------------------------------------------
  -- Executable discovery
  -- Priority: vim.g.project_executable → REPO_ROOT/bin/* → REPO_ROOT/*
  ---------------------------------------------------------------------------
  local function get_executables()
    -- Explicit override from .nvim.lua
    if vim.g.project_executable then
      local path = vim.g.project_executable
      if not vim.startswith(path, '/') then
        path = REPO_ROOT .. '/' .. path
      end
      if vim.fn.executable(path) == 1 then return { path } end
    end

    local execs = {}
    local scan_dirs = {
      REPO_ROOT .. '/bin',
      REPO_ROOT,
    }
    for _, dir in ipairs(scan_dirs) do
      if vim.fn.isdirectory(dir) == 1 then
        for _, path in ipairs(vim.fn.glob(dir .. '/*', false, true)) do
          if vim.fn.executable(path) == 1
              and vim.fn.isdirectory(path) == 0 then
            table.insert(execs, path)
          end
        end
      end
      if #execs > 0 then break end  -- prefer bin/ if it has results
    end
    return execs
  end

  ---------------------------------------------------------------------------
  -- Run: pick executable → optionally pick workdata → launch
  ---------------------------------------------------------------------------
  local function get_workdirs()
    local dirs = {}
    for _, path in ipairs(vim.fn.globpath(WORK_ROOT, '*', false, true)) do
      if vim.fn.isdirectory(path) == 1 then table.insert(dirs, path) end
    end
    return dirs
  end

  local function launch(program, cwd)
    run_in_terminal('cd ' .. vim.fn.shellescape(cwd) ..
      ' && ' .. vim.fn.shellescape(program))
  end

  local function pick_workdata_and_launch(program)
    local dirs = get_workdirs()
    if #dirs == 0 then
      -- No workdata dir — run from REPO_ROOT
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
        'No executable found.\n' ..
        'Set vim.g.project_executable in .nvim.lua, or build first with <leader>cb.',
        vim.log.levels.WARN)
      return
    end
    if #execs == 1 then pick_workdata_and_launch(execs[1]); return end
    vim.ui.select(execs, {
      prompt      = 'Select executable:',
      format_item = function(item) return item:gsub(REPO_ROOT .. '/', '') end,
    }, function(choice) if choice then pick_workdata_and_launch(choice) end end)
  end

  ---------------------------------------------------------------------------
  -- Keymaps
  ---------------------------------------------------------------------------
  vim.keymap.set('n', '<leader>cb', function() do_build() end,
    { desc = 'Make: build (all CPU cores)', nowait = true })

  vim.keymap.set('n', '<leader>cB', function() do_build(1) end,
    { desc = 'Make: build single-threaded (debug compile errors)', nowait = true })

  vim.keymap.set('n', '<leader>cx', function()
    run_in_terminal('make -C ' .. vim.fn.shellescape(REPO_ROOT) .. ' clean')
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
