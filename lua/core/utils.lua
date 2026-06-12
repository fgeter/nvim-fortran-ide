-- ============================================================
-- core/utils.lua — Shared helper functions
-- ============================================================

local M = {}

-- Return the first window showing a normal file buffer, skipping
-- neo-tree, terminal windows, and all dap panels (any filetype
-- starting with 'dap' catches dapui_*, dap-repl, and future panels).
-- Used by toggleterm, cmake-tools, make-tools, and keymaps to restore
-- focus after side panels open and close.
function M.find_editor_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft  = vim.bo[buf].filetype
    if vim.bo[buf].buftype == ''
      and ft ~= 'neo-tree'
      and ft ~= 'toggleterm'
      and not ft:match('^dap') then
      return win
    end
  end
  return nil
end

-- Number of logical CPU cores. Linux: nproc; macOS: sysctl. Falls back to 4.
function M.get_cpu_count()
  local nproc  = tonumber((vim.fn.system('nproc 2>/dev/null'):gsub('%s+', '')))
  local sysctl = tonumber((vim.fn.system('sysctl -n hw.logicalcpu 2>/dev/null'):gsub('%s+', '')))
  return nproc or sysctl or 4
end

-- Run shell_cmd in a one-shot build terminal (botright split).
-- The window closes automatically and focus returns to the previous
-- editor window when the terminal process exits (TermClose).
function M.run_build_cmd(shell_cmd)
  local origin_win = M.find_editor_win()
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
          pcall(vim.api.nvim_buf_delete, build_buf, { force = true })
        end
        local target = (origin_win and vim.api.nvim_win_is_valid(origin_win))
          and origin_win or M.find_editor_win()
        if target then vim.api.nvim_set_current_win(target) end
      end)
    end,
  })

  pcall(vim.fn.chansend, build_chan, shell_cmd .. '\n')
  vim.cmd('startinsert')
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

-- List immediate subdirectories of work_root.
function M.get_workdirs(work_root)
  local dirs = {}
  for _, path in ipairs(vim.fn.globpath(work_root, '*', false, true)) do
    if vim.fn.isdirectory(path) == 1 then table.insert(dirs, path) end
  end
  return dirs
end

-- Set a buffer-local K keymap: DAP eval when a session is active,
-- LSP hover otherwise. The eval float closes on the next cursor move.
function M.attach_k_handler(bufnr, dap, dapui)
  vim.keymap.set('n', 'K', function()
    if dap.session() then
      dapui.eval(nil, { enter = false })
      vim.api.nvim_create_autocmd('CursorMoved', {
        once     = true,
        callback = function()
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
        end,
      })
    else
      vim.lsp.buf.hover()
    end
  end, { buffer = bufnr, desc = 'K: DAP eval / LSP hover' })
end

return M
