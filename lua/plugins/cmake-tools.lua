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
-- Timing notes (important — do not remove the defer_fn calls):
--   200ms outer defer — lets vim.pack.add finish making cmake-tools
--     available before require('cmake-tools') is called
--   150ms window scan — cmake-tools opens its output window
--     asynchronously; we wait before scanning for new windows
--   50ms  WinClosed defer — Neovim finishes window teardown before
--     we call set_current_win, preventing layout glitches
--   500ms before CMakeGenerate — cmake-tools keeps its internal
--     task state alive briefly after the output window closes;
--     firing CMakeGenerate too soon causes "task already running"
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
  -- download step but the Lua module is not available until after the
  -- 200ms defer below, hence the deferred require('cmake-tools').
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

  local get_editor_win = require('core.utils').find_editor_win

  ---------------------------------------------------------------------------
  -- Helper: run a cmake-tools command and restore focus when done
  ---------------------------------------------------------------------------
  -- `cmd`      — a cmake-tools Ex command string e.g. 'CMakeGenerate'
  -- `on_close` — optional function to call after the output window closes
  --              (used by <leader>cp to chain CMakeGenerate automatically)
  -- focus: when true, shifts the cursor into the output window so the
  -- user can read it and press <CR> to close. Set to false for interactive
  -- pickers (CMakeSelectConfigurePreset) that need to keep their own focus.
  local function run_cmake_cmd(cmd, on_close, focus)
    local caller_win = get_editor_win()

    -- Snapshot windows before the command so we can detect the new one
    local wins_before = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do wins_before[w] = true end

    vim.cmd(cmd)

    -- Wait 150ms for cmake-tools to open its output window asynchronously.
    -- Without this delay the scan below runs before the window exists.
    vim.defer_fn(function()
      local output_win = nil
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if not wins_before[win] then output_win = win; break end
      end

      if not output_win then
        -- cmake-tools handled the command silently (no output window).
        -- Still fire on_close after 500ms in case a background task is
        -- running (e.g. switching to an already-configured preset).
        if on_close then vim.defer_fn(on_close, 500) end
        return
      end

      -- Guard: the window must still be valid after the 150ms delay.
      -- cmake-tools can finish very quickly and close the window before
      -- we get here. Also guard the buffer separately — toggleterm can
      -- recycle/invalidate a buffer id even while the window still exists.
      if not vim.api.nvim_win_is_valid(output_win) then
        if on_close then vim.defer_fn(on_close, 500) end
        return
      end

      local output_buf = vim.api.nvim_win_get_buf(output_win)

      if not vim.api.nvim_buf_is_valid(output_buf) then
        if on_close then vim.defer_fn(on_close, 500) end
        return
      end

      local augroup = vim.api.nvim_create_augroup(
        'cmake_focus_restore_' .. output_win, { clear = true })

      -- Only shift focus and set up <CR> for output windows (generate, clean).
      -- Interactive pickers (preset selector) manage their own focus and must
      -- not be redirected or they dismiss immediately.
      if focus then
        -- Move focus into the output window so the user can read it.
        vim.api.nvim_set_current_win(output_win)
        -- Skip nvim_win_set_cursor for terminal buffers: switching to a live
        -- terminal re-enters terminal mode, and cursor ops then call nvim_exec2
        -- with a :normal command which errors ("Can't re-enter normal mode from
        -- terminal mode"). toggleterm auto_scroll=true already keeps the view
        -- at the bottom, so positioning the cursor is unnecessary.
        local buftype = vim.api.nvim_get_option_value('buftype', { buf = output_buf })
        if buftype ~= 'terminal' then
          local line_count = vim.api.nvim_buf_line_count(output_buf)
          vim.api.nvim_win_set_cursor(output_win, { line_count, 0 })
        end

        -- <CR> closes the output window, wipes the buffer, and returns focus
        -- to the editor window captured before the cmake command ran.
        -- pcall guards against the buffer becoming invalid before key press.
        pcall(vim.keymap.set, 'n', '<CR>', function()
          if vim.api.nvim_win_is_valid(output_win) then
            vim.api.nvim_win_close(output_win, true)
          end
        end, { buffer = output_buf, nowait = true, desc = 'Close cmake output' })
      end

      -- When the output window closes:
      --   1. Wipe the output buffer so it doesn't linger in the buffer list
      --   2. Restore focus to the editor window captured before the command
      --   3. Fire on_close if provided (e.g. chain CMakeGenerate after preset)
      -- 50ms defer lets Neovim finish window teardown before set_current_win
      -- and buf_delete, preventing layout glitches.
      vim.api.nvim_create_autocmd('WinClosed', {
        group   = augroup,
        pattern = tostring(output_win),
        once    = true,
        callback = function()
          vim.defer_fn(function()
            -- Wipe the buffer (force=true handles unmodified terminal buffers)
            if vim.api.nvim_buf_is_valid(output_buf) then
              pcall(vim.api.nvim_buf_delete, output_buf, { force = true })
            end
            local target = (caller_win and vim.api.nvim_win_is_valid(caller_win))
              and caller_win or get_editor_win()
            if target then vim.api.nvim_set_current_win(target) end
            vim.api.nvim_del_augroup_by_id(augroup)
            if on_close then on_close() end
          end, 50)
        end,
      })
    end, 150)
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
  -- Helper: list workdata directories
  ---------------------------------------------------------------------------
  local function get_workdirs()
    local dirs = {}
    for _, path in ipairs(vim.fn.globpath(WORK_ROOT, '*', false, true)) do
      if vim.fn.isdirectory(path) == 1 then table.insert(dirs, path) end
    end
    return dirs
  end

  ---------------------------------------------------------------------------
  -- Persistent terminal for builds and runs
  ---------------------------------------------------------------------------
  -- A single bash terminal buffer is reused across build and run commands.
  -- This is separate from the cmake-tools toggleterm so output from cmake
  -- configure (toggleterm) and cmake build (this terminal) don't mix.
  local term_buf  = nil
  local term_chan = nil

  -- Register a BufWipeout autocmd on term_buf so that when the terminal
  -- window is closed (shell exits or user types exit), focus returns to
  -- the editor window that was active before the terminal opened.
  -- Without this, neo-tree grabs focus after the terminal split closes.
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
    -- Capture editor window BEFORE opening the terminal split
    local origin_win = get_editor_win()
    vim.cmd('botright split')
    vim.cmd('terminal bash')
    term_buf  = vim.api.nvim_get_current_buf()
    term_chan = vim.bo[term_buf].channel
    register_focus_restore(origin_win)
  end

  -- Send `cmd` to the persistent terminal, opening it if needed.
  -- If the terminal buffer is valid but not visible, re-opens its window.
  local function run_in_terminal(cmd)
    -- Invalidate handles if the terminal buffer was closed
    if term_buf and not vim.api.nvim_buf_is_valid(term_buf) then
      term_buf = nil; term_chan = nil
    end

    if not term_buf then
      open_terminal()
    else
      -- Find the window showing the terminal buffer, or open a new one
      local term_win = nil
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == term_buf then
          term_win = win; break
        end
      end
      if not term_win then
        -- Terminal buffer exists but its window was closed — re-open it
        -- and re-register focus restore for this new window session.
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
      -- Channel died (e.g. shell exited); open a fresh terminal and retry
      open_terminal()
      pcall(vim.fn.chansend, term_chan, cmd .. '\n')
    end

    vim.cmd('startinsert')
  end

  ---------------------------------------------------------------------------
  -- Build: cmake --build using the active preset's build directory
  ---------------------------------------------------------------------------

  -- Detect the number of logical CPU cores available on this machine.
  -- Used as the default thread count for parallel builds.
  -- nproc is available on Linux; sysctl -n hw.logicalcpu is the macOS equivalent.
  -- Falls back to 4 if neither command is available.
  local function get_cpu_count()
    -- gsub returns (string, count) — wrap in parentheses to discard the count
    -- before passing to tonumber, otherwise tonumber gets two args and errors.
    local nproc   = tonumber((vim.fn.system('nproc 2>/dev/null'):gsub('%s+', '')))
    local sysctl  = tonumber((vim.fn.system('sysctl -n hw.logicalcpu 2>/dev/null'):gsub('%s+', '')))
    return nproc or sysctl or 4
  end

  -- Build with `jobs` parallel threads.
  -- jobs=1 is useful when debugging compile errors: the build stops at the
  -- first error with clean output rather than interleaving errors from
  -- multiple threads, making it much easier to read the error message.
  -- On success the terminal pauses with a prompt; pressing <CR> closes it and
  -- returns focus to the originating window. On failure the terminal stays open
  -- so the error output remains visible.
  local function do_build(jobs)
    local build = get_active_build_dir()
    if not build then return end
    local j = jobs or get_cpu_count()
    vim.notify('Building: ' .. build.label .. ' (-j ' .. j .. ')', vim.log.levels.INFO)

    local cmake_cmd = 'cmake --build ' .. vim.fn.shellescape(build.path) .. ' -j ' .. j
    local shell_cmd = cmake_cmd
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
              vim.api.nvim_win_close(win, true)
              break
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
    run_in_terminal('cd ' .. vim.fn.shellescape(cwd) ..
      ' && ' .. vim.fn.shellescape(program))
  end

  local function pick_workdata_and_launch(program)
    local dirs = get_workdirs()
    if #dirs == 0 then
      vim.notify('No workdata directories found in ' .. WORK_ROOT, vim.log.levels.ERROR)
      return
    end
    if #dirs == 1 then launch(program, dirs[1]); return end
    vim.ui.select(dirs, {
      prompt      = 'Select workdata directory:',
      format_item = function(item) return vim.fn.fnamemodify(item, ':t') end,
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
  -- Deferred to VimEnter so that:
  --   1. cmake-tools.nvim is fully available (vim.pack.add already ran above)
  --   2. This callback never fires inside a vim.fn.confirm() modal that other
  --      plugins trigger during their first-time install (which spins the event
  --      loop and would execute a vim.defer_fn prematurely).
  ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()
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
      run_cmake_cmd('CMakeGenerate', nil, true)
    end, { desc = 'CMake: generate' })

    -- Clean: remove build artefacts for the active preset
    vim.keymap.set('n', '<leader>cx', function()
      run_cmake_cmd('CMakeClean', nil, true)
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
    -- The 500ms delay before CMakeGenerate lets cmake-tools finish its
    -- internal task state before starting a new one (avoids "task already
    -- running" errors that occur when Generate fires too quickly).
    vim.keymap.set('n', '<leader>cp', function()
      run_cmake_cmd('CMakeSelectConfigurePreset', function()
        vim.defer_fn(function()
          run_cmake_cmd('CMakeGenerate', nil, true)
        end, 500)
      end, false)
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

  end })
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
