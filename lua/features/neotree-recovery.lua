-- ============================================================
-- features/neotree-recovery.lua — Reopen an editor window when :q
-- leaves only the neo-tree sidebar visible (homegrown)
--
-- Depends on close_if_last_window = false in plugins/neo-tree.lua,
-- which keeps the sidebar open as the anchor this recovery needs.
-- ============================================================

-- ── Recover when :q leaves only neo-tree visible ─────────────
-- We cannot reliably intercept :q before the window closes, so instead
-- we detect the broken state (only neo-tree remains) in WinClosed and
-- immediately reopen an editor window with the next listed buffer.
-- close_if_last_window = false in the setup below ensures neo-tree stays
-- open as an anchor even when the last editor window closes.
--
-- QuitPre captures which buffer is about to be closed so WinClosed can
-- remove it from bufferline after the recovery window is opened.
local _closing_buf = nil

vim.api.nvim_create_autocmd('QuitPre', {
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype == '' and vim.bo[buf].filetype ~= 'neo-tree' then
      _closing_buf = buf
    end
  end,
})

vim.api.nvim_create_autocmd('WinClosed', {
  callback = function()
    local closed_buf = _closing_buf
    _closing_buf = nil

    vim.schedule(function()
      -- If any non-neo-tree window is still open, nothing to recover.
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
          if vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= 'neo-tree' then
            return
          end
        end
      end

      -- Only neo-tree remains. Find the next listed regular-file buffer,
      -- excluding the one that was just closed.
      local candidates = vim.tbl_filter(function(b)
        return vim.bo[b.bufnr].buftype == ''
            and (closed_buf == nil or b.bufnr ~= closed_buf)
      end, vim.fn.getbufinfo({ buflisted = 1 }))

      if #candidates == 0 then return end  -- no buffers left → Neovim can quit

      -- Reopen editor window to the right of the neo-tree panel.
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_open_win, candidates[1].bufnr, true,
            { split = 'right', win = win })
          pcall(vim.api.nvim_win_set_width, win, 35)
          break
        end
      end

      -- Delete the closed buffer so it disappears from bufferline.
      if closed_buf and vim.api.nvim_buf_is_valid(closed_buf) then
        pcall(vim.api.nvim_buf_delete, closed_buf, { force = false })
      end
    end)
  end,
})
