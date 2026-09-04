-- ============================================================
-- plugins/fortran-tools.lua — Fortran LSP + DAP configuration
--
-- Configures:
--   fortls    — Fortran language server (LSP hover, go-to-def, etc.)
--   gdb       — Debug adapter via nvim-dap
--
-- dapui.setup(), auto open/close listeners, and all language-
-- agnostic <leader>d* keymaps live in plugins/dap.lua.
-- This file only adds what is Fortran-specific:
--   • fortls LSP config
--   • buffer-local <leader>ds / <F5> — custom executable/workdata picker
--
-- LAZY: Yes — LSP/DAP setup inside activate() runs only once.
--       Start/continue maps are buffer-local so they cannot steal
--       <F5> / <leader>ds from other languages. Project paths are
--       read at keypress via core.project.roots() so .nvim.lua wins.
-- ============================================================

if vim.g.loaded_fortran_tools then return end
vim.g.loaded_fortran_tools = true

-- Assigned at the end of activate(); FileType maps call through this so
-- they always hit the current picker rather than a stale closure.
local start_debug

local function activate()
  if vim.g.fortran_tools_active then return end
  vim.g.fortran_tools_active = true

  -- Do not snapshot roots here: activate() often runs during plugin load,
  -- before 'exrc' sources .nvim.lua. Call project.roots() at use time.
  local project = require('core.project')

  require('plugins.dap').activate()  -- install/configure the DAP stack (lazy since #7)
  local dap   = require('dap')
  local utils = require('core.utils')

  ---------------------------------------------------------------------------
  -- LSP: fortls
  ---------------------------------------------------------------------------
  vim.lsp.config('fortls', {
    cmd          = { 'fortls', '--lowercase_intrinsics' },
    filetypes    = { 'fortran' },
    root_markers = { '.fortls', '.git' },
    settings     = {
      fortran_ls = { lowercase_intrinsics = true },
    },
  })
  vim.lsp.enable('fortls')

  ---------------------------------------------------------------------------
  -- DAP: gdb adapter + custom launchers
  ---------------------------------------------------------------------------
  dap.adapters.gdb = {
    type    = 'executable',
    command = 'gdb',
    args    = { '--interpreter=dap', '--eval-command', 'set print pretty on' },
    options = { initialize_timeout_sec = 10 },
  }

  -- Only debug builds are offered — release builds strip debug symbols
  -- so gdb cannot map instructions back to source lines meaningfully.
  -- Discovery itself (vim.g.project_executable_pattern) is shared via
  -- core/project.lua; this wrapper adds the debug-specific guidance.
  local function get_executables()
    local debug_dir = project.roots().build .. '/debug'

    if vim.fn.isdirectory(debug_dir) == 0 then
      vim.notify(
        'No debug build found — ' .. debug_dir .. ' does not exist.\n' ..
        'Build a debug version first: <leader>cb → select Debug.',
        vim.log.levels.WARN)
      return {}
    end

    local execs = project.find_executables { root = debug_dir, subdirs = false }

    if #execs == 0 then
      vim.notify(
        'Debug directory exists but no executable found in ' .. debug_dir .. '.\n' ..
        'Build a debug version first: <leader>cb → select Debug.',
        vim.log.levels.WARN)
    end
    return execs
  end

  local function do_launch(program, cwd)
    local ok, err = pcall(dap.run, {
      name         = 'Launch executable',
      type         = 'gdb',
      request      = 'launch',
      program      = program,
      cwd          = cwd,
      initCommands = { 'set directories ' .. project.roots().src },
    })
    if not ok then
      vim.notify('DAP launch failed: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end

  -- Rebuilds specifically the debug directory being debugged (not "whatever
  -- preset is active" in cmake-tools, which may differ) — same command
  -- either build system would run, chosen by whether CMakeLists.txt exists,
  -- matching the detection cmake-tools.lua/make-tools.lua themselves use.
  local function rebuild_debug(on_done)
    local roots = project.roots()
    local debug_dir = roots.build .. '/debug'
    local j = vim.g.project_build_jobs or utils.get_cpu_count()
    local cmd
    if vim.fn.filereadable(roots.repo .. '/CMakeLists.txt') == 1 then
      cmd = 'cmake --build ' .. vim.fn.shellescape(debug_dir) .. ' -j ' .. j
    else
      cmd = 'make -j' .. j .. ' BUILD_TYPE=debug -C ' .. vim.fn.shellescape(roots.repo)
    end
    vim.notify('Rebuilding debug build...', vim.log.levels.INFO)
    utils.run_build_cmd(cmd .. project.build_done_suffix, on_done)
  end

  -- Heuristic: if any source file was modified after the executable, gdb's
  -- debug info won't match the current source — breakpoints silently stay
  -- "pending"/unverified and the program just runs to completion instead of
  -- stopping. mtime comparison can't know if a touch actually changed
  -- anything, so this warns rather than silently blocking.
  local function is_build_stale(program)
    local exe_mtime = vim.fn.getftime(program)
    if exe_mtime < 0 then return false end
    for _, f in ipairs(vim.fn.glob(project.roots().src .. '/*.f90', false, true)) do
      if vim.fn.getftime(f) > exe_mtime then return true end
    end
    return false
  end

  local function launch(program, cwd)
    if not is_build_stale(program) then
      do_launch(program, cwd)
      return
    end
    vim.ui.input(
      { prompt = 'Debug build looks older than source — breakpoints may not verify. Rebuild? (Y/n): ' },
      function(confirm)
        if not confirm or confirm:lower() == 'n' then return end
        rebuild_debug(function(success)
          if success then
            do_launch(program, cwd)
          else
            vim.notify('Rebuild failed — not launching debugger.', vim.log.levels.ERROR)
          end
        end)
      end)
  end

  local function pick_and_launch()
    local execs = get_executables()
    if #execs == 0 then return end
    project.pick_and_launch { execs = execs, launch = launch }
  end

  ---------------------------------------------------------------------------
  -- <leader>ds / <F5> — Fortran-specific start/continue (bound per buffer)
  ---------------------------------------------------------------------------
  start_debug = function()
    if dap.session() then dap.continue() else pick_and_launch() end
  end

  vim.notify('✅ Fortran tools loaded (LSP + DAP)', vim.log.levels.INFO)
end

-- ── Trigger ──────────────────────────────────────────────────
-- activate() is idempotent; the maps must be set on every Fortran buffer,
-- not just the first, or later .f90 files would fall through to the global
-- <F5> from dap.lua (plain continue, no exe/workdata picker).
vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'fortran',
  callback = function(ev)
    activate()
    if not start_debug then return end
    local function run() start_debug() end
    vim.keymap.set('n', '<leader>ds', run,
      { buffer = ev.buf, desc = 'DAP: start / continue - F5' })
    vim.keymap.set('n', '<F5>', run,
      { buffer = ev.buf, desc = 'DAP: start / continue' })
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'fortran',
  callback = function() vim.opt_local.textwidth = 80 end,
})

return { activate = activate }
