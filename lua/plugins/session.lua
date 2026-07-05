-- ============================================================
-- plugins/session.lua — Per-directory session save/restore
--
-- Uses Neovim's built-in :mksession. One session file per cwd,
-- stored in stdpath('state')/sessions/. Restored automatically
-- on startup when no files are passed as arguments.
--
-- VimLeave covers :q, :qa, :wqa, and :restart — all paths that
-- exit Neovim.
-- ============================================================

-- Exclude terminal buffers (can't be restored), blank placeholder
-- windows, and all vim options (would override user config on next start).
vim.o.sessionoptions = 'buffers,curdir,folds,help,tabpages,winsize,winpos'

local sessions_dir = vim.fn.stdpath('state') .. '/sessions'
vim.fn.mkdir(sessions_dir, 'p')

local function session_file()
  -- Encode cwd into filename by replacing path separators with '%'.
  return sessions_dir .. '/' .. vim.fn.getcwd():gsub('[/\\]', '%%') .. '.vim'
end

-- ── Restore ──────────────────────────────────────────────────
-- VimEnter fires after all plugins load, so session macros that
-- reference plugin commands (e.g. Neotree) work correctly.
-- neo-tree's UIEnter startup handler (which always runs after every
-- VimEnter handler, including this one) checks vim.g.session_loaded
-- to skip its 'enew' step when we have already restored buffers.
vim.api.nvim_create_autocmd('VimEnter', {
  once     = true,
  callback = function()
    if vim.fn.argc() ~= 0 then return end
    local sf = session_file()
    if vim.fn.filereadable(sf) == 1 then
      -- A corrupted session file used to fail silently here, leaving every
      -- startup session-less with no hint why. utils.try reports it; a
      -- partial restore still counts as loaded so neo-tree doesn't wipe
      -- whatever buffers did come back.
      local ok = require('core.utils').try('Session restore (' .. sf .. ')',
        'silent source ' .. vim.fn.fnameescape(sf))
      vim.g.session_loaded = true
      if not ok then
        vim.notify('Delete the session file to start clean: ' .. sf,
          vim.log.levels.INFO)
      end
      -- :badd in the session file adds buffers without firing BufRead,
      -- so FileType (and therefore treesitter/LSP) never runs for them.
      -- Re-detect on every loaded file buffer that still has no filetype.
      vim.schedule(function()
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf)
            and vim.bo[buf].buftype  == ''
            and vim.bo[buf].filetype == ''
            and vim.api.nvim_buf_get_name(buf) ~= '' then
            vim.api.nvim_buf_call(buf, function()
              vim.cmd('filetype detect')
            end)
          end
        end
      end)
    end
  end,
})

-- ── Save ─────────────────────────────────────────────────────
vim.api.nvim_create_autocmd('VimLeave', {
  callback = function()
    pcall(vim.cmd, 'mksession! ' .. vim.fn.fnameescape(session_file()))
  end,
})
