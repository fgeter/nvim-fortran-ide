-- ============================================================
-- core/utils.lua — Shared helper functions
-- ============================================================

local M = {}

-- GitHub URL shorthand for vim.pack.add lists. Defined once here instead
-- of a local copy at the top of every plugin file.
function M.gh(repo) return 'https://github.com/' .. repo end

-- True when buf holds a normal editable file: not a special buftype
-- (terminal, quickfix, prompt, …) and not one of the side-panel filetypes
-- (neo-tree, toggleterm, and all dap panels — the '^dap' prefix catches
-- dapui_*, dap-repl, and future panels). Single source of truth for the
-- "is this a real editor buffer" filter used by find_editor_win and the
-- relative-number toggle in core/keymaps.lua.
function M.is_editor_buf(buf)
  local ft = vim.bo[buf].filetype
  return vim.bo[buf].buftype == ''
    and ft ~= 'neo-tree'
    and ft ~= 'toggleterm'
    and ft ~= 'hscroll'
    and not ft:match('^dap')
end

-- Return the first window showing a normal file buffer.
-- Used by toggleterm, cmake-tools, make-tools, dap, and keymaps to
-- restore focus after side panels open and close.
function M.find_editor_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if M.is_editor_buf(vim.api.nvim_win_get_buf(win)) then
      return win
    end
  end
  return nil
end

-- Raise any floating window that appeared since `before` (a snapshot from
-- vim.api.nvim_list_wins()) above the horizontal scrollbar (zindex 10).
-- The 50ms defer is unavoidable here: the floats are opened by async LSP/
-- DAP responses that offer no completion event to hook.
function M.raise_new_floats(before)
  vim.defer_fn(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not vim.tbl_contains(before, win) then
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative ~= '' then
          cfg.zindex = 200
          vim.api.nvim_win_set_config(win, cfg)
        end
      end
    end
  end, 50)
end

-- Run fn (a function, or an Ex command string) under pcall; on failure
-- surface the error as a WARN notification prefixed with `context`
-- instead of silently swallowing it. Use this anywhere a bare
-- pcall(vim.cmd, …) would hide a real problem (session restore,
-- Neotree open/close, …). Returns the same ok, err as pcall.
function M.try(context, fn)
  local ok, err
  if type(fn) == 'string' then
    ok, err = pcall(vim.cmd, fn)
  else
    ok, err = pcall(fn)
  end
  if not ok then
    vim.notify(context .. ' failed: ' .. tostring(err), vim.log.levels.WARN)
  end
  return ok, err
end

-- Number of logical CPU cores via libuv (cross-platform, no subprocess).
-- Falls back to 4 on the off chance the API is unavailable.
function M.get_cpu_count()
  if vim.uv and vim.uv.available_parallelism then
    return vim.uv.available_parallelism()
  end
  return 4
end

-- Open a one-shot terminal in a bottom split, send shell_cmd to it, and
-- call on_exit(status, close, buf) once the shell process exits (TermClose).
-- `close()` tears the terminal down — window closed, buffer wiped, focus
-- back to the editor window that was active before the split. Whether and
-- when to call it is the caller's decision, which is the whole point of
-- the split: builds ask, runs ask, each with their own wording.
--
-- opts.follow decides how the window is left once the command is running:
--   false/nil  Terminal mode (:startinsert). Keys reach the process, which
--              is what a *run* needs — a program may read stdin. The cost
--              is that the mouse wheel goes to the process too, so the
--              output cannot be scrolled back while it runs.
--   true       Normal mode with the cursor parked on the last line. Neovim
--              keeps a terminal window scrolled to the end as long as the
--              cursor sits there, so the output still follows along, but
--              the wheel, k/j and <C-u> now scroll it — and scrolling back
--              simply stops the following until G returns to the end.
--              Right for a *build*, which reads no input.
local function one_shot_terminal(shell_cmd, on_exit, opts)
  local origin_win = M.find_editor_win()
  vim.cmd('botright split')
  vim.cmd('terminal bash')
  local buf  = vim.api.nvim_get_current_buf()
  local chan = vim.bo[buf].channel

  local function close()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then
        pcall(vim.api.nvim_win_close, win, true); break
      end
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    local target = (origin_win and vim.api.nvim_win_is_valid(origin_win))
      and origin_win or M.find_editor_win()
    if target then vim.api.nvim_set_current_win(target) end
  end

  vim.api.nvim_create_autocmd('TermClose', {
    buffer   = buf,
    once     = true,
    callback = function()
      local status = vim.v.event.status
      vim.schedule(function() on_exit(status, close, buf) end)
    end,
  })

  -- In terminal mode every key, the mouse wheel included, is handed to the
  -- process — so a program that ignores wheel events (most of them) makes
  -- the output unscrollable. Step out to normal mode and scroll there
  -- instead; `i` goes back to typing at the process.
  for _, key in ipairs({ '<ScrollWheelUp>', '<ScrollWheelDown>' }) do
    pcall(vim.keymap.set, 't', key, '<C-\\><C-n>' .. key, { buffer = buf })
  end

  pcall(vim.fn.chansend, chan, shell_cmd .. '\n')
  if opts and opts.follow then
    vim.cmd('normal! G')
  else
    vim.cmd('startinsert')
  end
end

-- Run shell_cmd in a one-shot build terminal (botright split), then ask
-- whether to close it once the build finishes. Yes is the default, so a
-- single <CR> dismisses it; answering No keeps the output on screen with
-- a buffer-local `q` to close it later.
--
-- The prompt is Neovim's, not the shell's. It used to be a `read` inside
-- the build command itself ("press <CR> to close"), which only works
-- while the terminal still holds focus in terminal mode — and a build
-- worth watching is exactly the one you step away from. Once focus had
-- moved, no <CR> could reach the shell (clicking back into a terminal
-- lands in normal mode, where <CR> only moves the cursor) and the
-- terminal could not be dismissed at all. vim.fn.confirm takes the answer
-- wherever focus happens to be.
--
-- Only a *successful* build gets here: on failure the command never
-- reaches its `exit 0`, so the interactive shell stays at its prompt with
-- the errors on screen and TermClose never fires.
--
-- The window is left in normal mode (opts.follow), so the build output
-- scrolls along as it arrives *and* stays scrollable: the mouse wheel and
-- the usual motions work while the build runs, which they cannot in
-- terminal mode, where the wheel is handed to the process. Scrolling back
-- pauses the following; G returns to the end and resumes it.
--
-- `on_exit(success)`, if given, runs after the answer is handled.
function M.run_build_cmd(shell_cmd, on_exit)
  one_shot_terminal(shell_cmd, function(status, close, buf)
    local msg = status == 0
      and 'Build succeeded.\nClose the terminal?'
      or  ('Build terminal exited with status ' .. status .. '.\nClose it?')
    local answer = vim.fn.confirm(msg, '&Yes\n&No, keep the output', 1, 'Question')
    if answer == 1 then
      close()
    else
      -- Map on `buf` explicitly: focus may have wandered off while the
      -- build ran, so the current buffer is not reliably the terminal one.
      if vim.api.nvim_buf_is_valid(buf) then
        vim.keymap.set('n', 'q', close,
          { buffer = buf, nowait = true, desc = 'Close build terminal' })
      end
      vim.notify('Build output kept — press q to close the terminal.',
        vim.log.levels.INFO)
    end
    if on_exit then on_exit(status == 0) end
  end, { follow = true })
end

-- Run a program in a one-shot terminal that stays open while it runs, so
-- its output can be watched, then asks whether to close the window once
-- the process exits (Y is the default — the usual case is "I've seen it,
-- get it out of the way"). Answering No keeps the output on screen with a
-- buffer-local `q` mapping to close it later.
-- Like a build, the window is left in normal mode so the output follows
-- along and stays scrollable while the program runs (the wheel, k/j and
-- <C-u> all work; G resumes following). A program that wants typed input
-- is still reachable: press i to enter terminal mode, <C-\><C-n> or the
-- wheel to leave it again.
--
--   shell_cmd  command line sent to the terminal's bash
--   label      program name used in the prompt (default: 'Program')
function M.run_program_cmd(shell_cmd, label)
  -- `; exit` makes bash quit as soon as the program returns, carrying its
  -- status through $? — that exit is what fires TermClose, and without it
  -- the shell would sit at a prompt and the run would never look finished.
  one_shot_terminal(shell_cmd .. '; exit', function(status, close, buf)
    local outcome = status == 0 and 'finished' or ('exited with status ' .. status)
    local answer = vim.fn.confirm(
      ('%s %s.\nClose the terminal?'):format(label or 'Program', outcome),
      '&Yes\n&No, keep the output', 1, 'Question')
    if answer == 1 then
      close()
      return
    end
    -- Map on `buf` explicitly: focus may have wandered to another window
    -- while the program ran, so the current buffer is not reliably the
    -- terminal one.
    if vim.api.nvim_buf_is_valid(buf) then
      vim.keymap.set('n', 'q', close,
        { buffer = buf, nowait = true, desc = 'Close run terminal' })
    end
    vim.notify('Run output kept — press q to close the terminal.',
      vim.log.levels.INFO)
  end, { follow = true })
end

-- Create a persistent terminal instance with its own buffer/channel state.
-- Returns a table with a single method: run(cmd) — sends cmd to the
-- terminal, opening or re-opening it as needed.
function M.make_terminal()
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
            and origin_win or M.find_editor_win()
          if target then vim.api.nvim_set_current_win(target) end
        end)
      end,
    })
  end

  local function open()
    local origin_win = M.find_editor_win()
    vim.cmd('botright split')
    vim.cmd('terminal bash')
    term_buf  = vim.api.nvim_get_current_buf()
    term_chan = vim.bo[term_buf].channel
    register_focus_restore(origin_win)
  end

  local function run(cmd)
    if term_buf and not vim.api.nvim_buf_is_valid(term_buf) then
      term_buf = nil; term_chan = nil
    end

    if not term_buf then
      open()
    else
      local term_win = nil
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == term_buf then
          term_win = win; break
        end
      end
      if not term_win then
        local origin_win = M.find_editor_win()
        vim.cmd('botright split')
        vim.api.nvim_win_set_buf(0, term_buf)
        register_focus_restore(origin_win)
      else
        vim.api.nvim_set_current_win(term_win)
      end
    end

    local ok = pcall(vim.fn.chansend, term_chan, cmd .. '\n')
    if not ok then
      open()
      pcall(vim.fn.chansend, term_chan, cmd .. '\n')
    end
    vim.cmd('startinsert')
  end

  return { run = run }
end

-- Return the filename component of a path (strips all leading directories).
function M.basename(path) return vim.fn.fnamemodify(path, ':t') end

-- List immediate subdirectories of work_root.
-- TODO(run-picker): sort by last-modified, newest first — requested as the
-- default for <leader>cr / <leader>ds workdata pick lists.
function M.get_workdirs(work_root)
  local dirs = {}
  for _, path in ipairs(vim.fn.globpath(work_root, '*', false, true)) do
    if vim.fn.isdirectory(path) == 1 then table.insert(dirs, path) end
  end
  return dirs
end

-- Set a buffer-local K keymap: DAP eval when a session is active,
-- LSP hover otherwise. The eval float closes on the next cursor move.
-- dap is resolved at keypress time, not attach time: the DAP stack is
-- lazy-loaded (plugins/dap.lua), so it may not exist when LspAttach
-- fires but be active later in the same buffer. package.loaded is
-- checked instead of require so K never forces the stack to load.
function M.attach_k_handler(bufnr)
  vim.keymap.set('n', 'K', function()
    local before = vim.api.nvim_list_wins()
    local dap = package.loaded['dap']
    if dap and dap.session() then
      require('dapui').eval(nil, { enter = true })
    else
      vim.lsp.buf.hover()
    end
    M.raise_new_floats(before)
  end, { buffer = bufnr, desc = 'K: DAP eval / LSP hover' })
end

return M
