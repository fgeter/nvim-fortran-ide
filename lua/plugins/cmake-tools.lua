-- ============================================================
-- plugins/cmake-tools.lua — CMake integration
--
-- Wraps cmake-tools.nvim with:
--   • Lazy activation — nothing runs until a CMakeLists.txt is
--     detected in cwd or a parent directory
--   • Focus restoration — the editor window regains focus after
--     cmake output windows open and close
--   • Chained preset+generate — <leader>cp selects a preset AND
--     automatically runs CMakeGenerate afterwards
--   • Build via terminal — <leader>cb builds using all CPU cores
--     (detected via nproc at call time); <leader>cB builds with
--     -j 1 for clean single-threaded compile error output
--   • Run picker — <leader>cr shows ALL executables from
--     build/debug/ and build/release/ so you can choose which
--     build to run without changing the active preset
--
-- LAZY: Yes — activate() is not called unless/until a CMake
--       project is detected. When Neovim starts outside a CMake
--       project only two small functions and one autocmd are
--       registered. vim.pack.add, cmake.setup(), and all keymaps
--       are deferred into activate().
--
-- Sequencing notes (event-driven, no fixed timers):
--   • The output window is detected with a one-shot WinNew watcher
--     registered before the cmake command runs, not by scanning the
--     window list after a delay.
--   • Post-close cleanup runs in vim.schedule from WinClosed, which
--     executes after Neovim finishes the synchronous window teardown.
--   • <leader>cp chains CMakeGenerate from the completion callback of
--     cmake.select_configure_preset() (a documented cmake-tools API),
--     not from a timer guessing when the picker is done.
-- ============================================================

if vim.g.loaded_cmake_tools_wrapper then return end
vim.g.loaded_cmake_tools_wrapper = true

-- ── CMake project detection ───────────────────────────────────
-- Walk up the directory tree from `path` looking for CMakeLists.txt.
-- Returns true if found, false if we reach the filesystem root.
local function is_cmake_project(path)
  while path ~= '/' do
    if vim.fn.filereadable(path .. '/CMakeLists.txt') == 1 then
      return true
    end
    path = vim.fn.fnamemodify(path, ':h')
  end
  return false
end

-- ── activate() ───────────────────────────────────────────────
-- Everything in this function runs exactly once, the first time a
-- CMake project is detected (either at startup or after :cd).
local function activate()
  if vim.g.cmake_tools_active then return end
  vim.g.cmake_tools_active = true

  -- Read paths now (at activation time) so :cd before activation gives the
  -- right root. vim.g overrides let a .nvim.lua pin these to a specific root.
  local REPO_ROOT  = vim.g.project_repo_root  or vim.fn.getcwd()
  local BUILD_ROOT = vim.g.project_build_root or (REPO_ROOT .. '/build')
  local WORK_ROOT  = vim.g.project_work_root  or (REPO_ROOT .. '/workdata')

  -- Install cmake-tools.nvim. vim.pack.add is synchronous for the
  -- download step but the Lua module is required only inside the VimEnter
  -- callback below, by which point it is guaranteed to be on the rtp.
  vim.pack.add { 'https://github.com/civitasv/cmake-tools.nvim' }

  -- cmake-tools configuration table passed to cmake.setup() below
  local cmake_config = {
    cmake_command            = 'cmake',
    ctest_command            = 'ctest',
    cmake_use_preset         = true,
    -- Disabled: when true cmake-tools re-runs cmake on every save using a
    -- bare cmake invocation that can write compile_commands.json into cwd
    -- rather than into the build directory. Regenerate manually with <leader>cg.
    cmake_regenerate_on_save = false,
    cmake_generate_options   = { '-DCMAKE_EXPORT_COMPILE_COMMANDS=1' },

    -- All cmake output goes into the same build/ directory. The actual
    -- subdirectory (debug/, release/) is determined by the selected preset.
    cmake_build_directory = function() return 'build' end,

    -- Use toggleterm for cmake output so it appears in the same terminal
    -- pane as builds and runs, keeping the layout consistent.
    cmake_executor = {
      name = 'toggleterm',
      opts = { direction = 'horizontal', close_on_exit = false,
               auto_scroll = true, singleton = true },
    },
    cmake_runner = {
      name = 'toggleterm',
      opts = { direction = 'horizontal', close_on_exit = false,
               auto_scroll = true, singleton = true },
    },

    cmake_notifications      = { runner = { enabled = true }, executor = { enabled = true } },

    -- cmake-tools by default creates a softlink to compile_commands.json in
    -- cwd after generation. We don't want that because:
    --   1. We cannot modify CMakePresets.json or CMakeLists.txt (shared project files)
    --   2. The copy in build/debug/ or build/release/ is what fortls needs
    -- Setting action='none' stops cmake-tools from creating the softlink/copy.
    cmake_compile_commands_options = {
      action = 'none',   -- don't softlink or copy to cwd
    },
    cmake_virtual_text_support = true,
  }

  local utils          = require('core.utils')
  local get_editor_win = utils.find_editor_win
  local term           = utils.make_terminal()

  ---------------------------------------------------------------------------
  -- Helper: run a cmake-tools command and restore focus when done
  ---------------------------------------------------------------------------
  -- `cmd` — a cmake-tools Ex command string e.g. 'CMakeGenerate'.
  -- Focus always shifts into the output window (all callers are output
  -- commands; the preset picker uses cmake.select_configure_preset directly
  -- and never comes through here).
  -- cmake-tools runs `:wall` before every generate/build/run. `:wall`
  -- throws E141 on any unnamed buffer, and Neovim always has one lying
  -- around when it's opened without a file argument (buffer 1, empty,
  -- "[No Name]"). Clear out only pristine unnamed buffers — never ones
  -- with unsaved content — so that stray buffer can't abort the command.
  local function close_empty_unnamed_buffers()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].buflisted
          and vim.api.nvim_buf_get_name(buf) == ''
          and not vim.bo[buf].modified
          and vim.api.nvim_buf_line_count(buf) == 1
          and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == '' then
        pcall(vim.api.nvim_buf_delete, buf, {})
      end
    end
  end

  -- Wires up the output window of a cmake command: shifts focus into it,
  -- maps <CR> to close it, and restores focus/wipes the buffer when it
  -- closes. Called from the WinNew watcher in run_cmake_cmd once the
  -- output window is confirmed to be a terminal.
  local function attach_output_window(output_win, output_buf, caller_win)
    local augroup = vim.api.nvim_create_augroup(
      'cmake_focus_restore_' .. output_win, { clear = true })

    -- Move focus into the output window so the user can read it.
    -- No nvim_win_set_cursor here: the output is always a live terminal
    -- (entering it resumes terminal mode, where cursor ops error with
    -- "Can't re-enter normal mode from terminal mode"), and toggleterm's
    -- auto_scroll=true already keeps the view at the bottom.
    vim.api.nvim_set_current_win(output_win)

    -- <CR> closes the output window, wipes the buffer, and returns focus
    -- to the editor window captured before the cmake command ran.
    -- pcall guards against the buffer becoming invalid before key press.
    pcall(vim.keymap.set, 'n', '<CR>', function()
      if vim.api.nvim_win_is_valid(output_win) then
        vim.api.nvim_win_close(output_win, true)
      end
    end, { buffer = output_buf, nowait = true, desc = 'Close cmake output' })

    -- When the output window closes:
    --   1. Wipe the output buffer so it doesn't linger in the buffer list
    --   2. Restore focus to the editor window captured before the command
    -- vim.schedule (not a timer): WinClosed fires during the synchronous
    -- window teardown; scheduled callbacks run right after it completes,
    -- so set_current_win/buf_delete never race the teardown.
    vim.api.nvim_create_autocmd('WinClosed', {
      group   = augroup,
      pattern = tostring(output_win),
      once    = true,
      callback = function()
        vim.schedule(function()
          -- Wipe the buffer (force=true handles unmodified terminal buffers)
          if vim.api.nvim_buf_is_valid(output_buf) then
            pcall(vim.api.nvim_buf_delete, output_buf, { force = true })
          end
          local target = (caller_win and vim.api.nvim_win_is_valid(caller_win))
            and caller_win or get_editor_win()
          if target then vim.api.nvim_set_current_win(target) end
          vim.api.nvim_del_augroup_by_id(augroup)
        end)
      end,
    })
  end

  local function run_cmake_cmd(cmd)
    close_empty_unnamed_buffers()
    local caller_win = get_editor_win()

    -- Watch for the output window with WinNew instead of scanning the
    -- window list after a fixed 150ms delay (which raced cmake-tools'
    -- asynchronous window creation). WinNew fires the moment the split is
    -- created with the new window as current; the buffer is assigned just
    -- after, so the rest runs in vim.schedule — that executes once
    -- toggleterm's synchronous open sequence has finished, regardless of
    -- how long it takes.
    local watcher
    local function disarm()
      if watcher then
        pcall(vim.api.nvim_del_autocmd, watcher)
        watcher = nil
      end
    end

    watcher = vim.api.nvim_create_autocmd('WinNew', {
      callback = function()
        local output_win = vim.api.nvim_get_current_win()
        vim.schedule(function()
          if not watcher then return end  -- already claimed by another WinNew
          if not vim.api.nvim_win_is_valid(output_win) then return end
          local output_buf = vim.api.nvim_win_get_buf(output_win)
          -- Only claim terminal windows (the toggleterm executor/runner).
          -- Unrelated windows (floats, user splits) are ignored and the
          -- watcher keeps waiting for the real output window.
          if not vim.api.nvim_buf_is_valid(output_buf)
              or vim.bo[output_buf].buftype ~= 'terminal' then
            return
          end
          disarm()
          attach_output_window(output_win, output_buf, caller_win)
        end)
      end,
    })

    vim.cmd(cmd)

    -- Garbage collection only, not sequencing: if the command never opens
    -- a window (e.g. output pane already open — toggleterm is a singleton,
    -- so re-running just reuses it), drop the watcher so it can't claim an
    -- unrelated terminal later. Nothing waits on this timer.
    vim.defer_fn(disarm, 2000)
  end

  ---------------------------------------------------------------------------
  -- Helper: get the active build directory from cmake-tools
  ---------------------------------------------------------------------------
  -- Returns { path, label } where label is the path relative to REPO_ROOT.
  -- Used by do_build() to construct the cmake --build command.
  local function get_active_build_dir()
    local ok, cmake = pcall(require, 'cmake-tools')
    if not ok then
      vim.notify('cmake-tools not available.', vim.log.levels.ERROR)
      return nil
    end
    local build_path = cmake.get_build_directory()
    if not build_path or build_path == '' then
      vim.notify('No active build set.\nRun <leader>cp to select a preset first.',
        vim.log.levels.WARN)
      return nil
    end
    local path_str = tostring(build_path)
    if vim.fn.isdirectory(path_str) == 0 then
      vim.notify('Build directory does not exist: ' .. path_str ..
        '\nRun <leader>cp then <leader>cg to configure.', vim.log.levels.WARN)
      return nil
    end
    return { path = path_str, label = path_str:gsub(REPO_ROOT .. '/', '') }
  end

  ---------------------------------------------------------------------------
  -- Helper: find all swatplus executables across all build subdirectories
  ---------------------------------------------------------------------------
  -- Scans BUILD_ROOT/*/swatplus* so both debug and release builds appear
  -- in the <leader>cr pick list. Labels show "debug/swatplus" etc.
  local function get_all_executables()
    local execs = {}
    -- Check the build root itself (flat builds without a subdirectory)
    for _, path in ipairs(vim.fn.glob(BUILD_ROOT .. '/swatplus*', false, true)) do
      if vim.fn.executable(path) == 1 then table.insert(execs, path) end
    end
    -- Check one level of subdirectories (debug/, release/, etc.)
    for _, subdir in ipairs(vim.fn.glob(BUILD_ROOT .. '/*', false, true)) do
      if vim.fn.isdirectory(subdir) == 1 then
        for _, path in ipairs(vim.fn.glob(subdir .. '/swatplus*', false, true)) do
          if vim.fn.executable(path) == 1 then table.insert(execs, path) end
        end
      end
    end
    return execs
  end

  ---------------------------------------------------------------------------
  -- Build: cmake --build using the active preset's build directory
  ---------------------------------------------------------------------------
  local function do_build(jobs)
    local build = get_active_build_dir()
    if not build then return end
    local j = jobs or utils.get_cpu_count()
    vim.notify('Building: ' .. build.label .. ' (-j ' .. j .. ')', vim.log.levels.INFO)
    local cmake_cmd = 'cmake --build ' .. vim.fn.shellescape(build.path) .. ' -j ' .. j
    utils.run_build_cmd(cmake_cmd
      .. ' && { printf "\\nBuild succeeded — press <CR> to close\\n"; read; exit 0; }')
  end

  ---------------------------------------------------------------------------
  -- Run: pick executable → pick workdata → clean outputs → launch
  ---------------------------------------------------------------------------

  -- Delete swatplus output files (*.txt, *.out, *.csv) from `dir` before
  -- launching. readme.txt is preserved. Runs silently — no confirmation
  -- prompt here because the user already confirmed by choosing to run.
  -- Returns the number of files deleted.
  local function clean_output_files(dir)
    local patterns = { '*.txt', '*.out', '*.csv' }
    local count = 0
    for _, pat in ipairs(patterns) do
      for _, path in ipairs(vim.fn.glob(dir .. '/' .. pat, false, true)) do
        local basename = vim.fn.fnamemodify(path, ':t'):lower()
        if basename ~= 'readme.txt' then
          vim.fn.delete(path)
          count = count + 1
        end
      end
    end
    return count
  end

  local function launch(program, cwd)
    -- Clean output files first so the new run starts with a fresh directory.
    local removed = clean_output_files(cwd)
    if removed > 0 then
      vim.notify('Removed ' .. removed .. ' previous output file(s) from '
        .. vim.fn.fnamemodify(cwd, ':t'), vim.log.levels.INFO)
    end
    term.run('cd ' .. vim.fn.shellescape(cwd) .. ' && ' .. vim.fn.shellescape(program))
  end

  local function pick_workdata_and_launch(program)
    local dirs = utils.get_workdirs(WORK_ROOT)
    if #dirs == 0 then
      vim.notify('No workdata directories found in ' .. WORK_ROOT, vim.log.levels.ERROR)
      return
    end
    if #dirs == 1 then launch(program, dirs[1]); return end
    vim.ui.select(dirs, {
      prompt      = 'Select workdata directory:',
      format_item = utils.basename,
    }, function(choice) if choice then launch(program, choice) end end)
  end

  local function pick_and_run()
    local execs = get_all_executables()
    if #execs == 0 then
      vim.notify('No swatplus executables found under ' .. BUILD_ROOT,
        vim.log.levels.ERROR)
      return
    end
    if #execs == 1 then pick_workdata_and_launch(execs[1]); return end
    vim.ui.select(execs, {
      prompt      = 'Select executable:',
      format_item = function(item) return item:gsub(BUILD_ROOT .. '/', '') end,
    }, function(choice) if choice then pick_workdata_and_launch(choice) end end)
  end

  ---------------------------------------------------------------------------
  -- cmake-tools setup + keymaps
  -- At startup this is deferred to VimEnter so that:
  --   1. cmake-tools.nvim is fully available (vim.pack.add already ran above)
  --   2. This callback never fires inside a vim.fn.confirm() modal that other
  --      plugins trigger during their first-time install (which spins the event
  --      loop and would execute a vim.defer_fn prematurely).
  -- When activation happens via DirChanged (navigating into a CMake project
  -- after startup), VimEnter has already fired and a VimEnter autocmd would
  -- never run — in that case setup runs immediately instead (vim.pack.add
  -- above was synchronous, so the module is already on the runtimepath).
  ---------------------------------------------------------------------------
  local function setup_cmake_tools()
    local ok, cmake = pcall(require, 'cmake-tools')
    if not ok then
      vim.notify('cmake-tools.nvim failed to load. Try restarting Neovim.',
        vim.log.levels.WARN)
      return
    end

    cmake.setup(cmake_config)
    vim.notify('CMake tools activated.', vim.log.levels.INFO)

    -- Generate: configure the cmake build system from CMakePresets.json
    vim.keymap.set('n', '<leader>cg', function()
      run_cmake_cmd('CMakeGenerate')
    end, { desc = 'CMake: generate' })

    -- Clean: remove build artefacts for the active preset
    vim.keymap.set('n', '<leader>cx', function()
      run_cmake_cmd('CMakeClean')
    end, { desc = 'CMake: clean' })

    -- Delete build directory: wipes the entire build/ folder.
    -- Prompts for confirmation first — this is not undoable.
    -- Use this when you want a completely fresh configure + build
    -- (e.g. after changing a preset or fixing a broken cmake cache).
    -- After deletion you must run <leader>cp + <leader>cb to rebuild.
    vim.keymap.set('n', '<leader>cd', function()
      if vim.fn.isdirectory(BUILD_ROOT) == 0 then
        vim.notify('Build directory does not exist: ' .. BUILD_ROOT,
          vim.log.levels.WARN)
        return
      end

      vim.ui.input({
        prompt = 'Delete ALL contents of ' .. BUILD_ROOT .. '? (yes/N): ',
      }, function(input)
        if input ~= 'yes' then
          vim.notify('Delete cancelled.', vim.log.levels.INFO)
          return
        end

        local result = vim.fn.system('rm -rf ' .. vim.fn.shellescape(BUILD_ROOT))
        if vim.v.shell_error == 0 then
          vim.notify('✅ Deleted: ' .. BUILD_ROOT ..
            '\nRun <leader>cp then <leader>cb to rebuild.', vim.log.levels.INFO)
          -- Reset cmake-tools' internal state so it doesn't reference
          -- the now-deleted build directory
          pcall(function() require('cmake-tools').cmake_build_directory = nil end)
        else
          vim.notify('Delete failed:\n' .. result, vim.log.levels.ERROR)
        end
      end)
    end, { desc = 'CMake: delete build directory (prompts for confirmation)' })

    -- Preset: select a configure preset, then automatically run Generate.
    -- cmake.select_configure_preset(callback) is cmake-tools' own Lua API:
    -- the callback fires exactly when the picker resolves, so Generate can
    -- be chained without a timer. Its internal check_active_job guard
    -- reports "task already running" itself in the (now unlikely) case a
    -- previous task is still live. On cancel/error the result is not ok
    -- and Generate is skipped.
    vim.keymap.set('n', '<leader>cp', function()
      cmake.select_configure_preset(function(result)
        if result and result.is_ok and result:is_ok() then
          run_cmake_cmd('CMakeGenerate')
        end
      end)
    end, { desc = 'CMake: select preset + generate' })

    -- Build: runs cmake --build in the persistent terminal
    -- pcall(del) first so re-sourcing this file doesn't error on duplicate maps
    -- <leader>cb  — parallel build using all available CPU cores (fast)
    -- <leader>cB  — single-threaded build (-j 1) for debugging compile errors:
    --               stops at the first error with clean, uninterleaved output
    pcall(vim.keymap.del, 'n', '<leader>cb')
    vim.keymap.set('n', '<leader>cb', function() do_build() end,
      { desc = 'CMake: build (all CPU cores)', nowait = true })

    pcall(vim.keymap.del, 'n', '<leader>cB')
    vim.keymap.set('n', '<leader>cB', function() do_build(1) end,
      { desc = 'CMake: build single-threaded (debug compile errors)', nowait = true })

    -- Run: pick executable and workdata directory, launch in terminal
    pcall(vim.keymap.del, 'n', '<leader>cr')
    vim.keymap.set('n', '<leader>cr', pick_and_run,
      { desc = 'CMake: run swatplus', nowait = true })

  end

  if vim.v.vim_did_enter == 1 then
    setup_cmake_tools()
  else
    vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = setup_cmake_tools })
  end
end

-- ── Entry point ───────────────────────────────────────────────
-- If Neovim was started inside a CMake project, activate immediately.
-- Otherwise register a DirChanged autocmd that checks on every :cd.
-- `return true` from the callback removes the autocmd after first match
-- (Neovim 0.10+ feature) so activate() never runs more than once.
if is_cmake_project(vim.fn.getcwd()) then
  activate()
else
  vim.api.nvim_create_autocmd('DirChanged', {
    callback = function()
      if is_cmake_project(vim.fn.getcwd()) then
        activate()
        return true   -- removes this autocmd
      end
    end,
  })
end
