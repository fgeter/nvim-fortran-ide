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
-- :restart (0.12+) saves and restores the session itself, before any of
-- this config's startup handlers run. Mark it as restored so neo-tree's
-- UIEnter handler (plugins/neo-tree.lua) does not take it for a bare start
-- and run its 'enew' + delete step, which wiped the restored current
-- buffer. :restart! means "no session", so it keeps the normal path.
-- v:startreason is newer than :restart itself (absent in 0.12.4, where it
-- reads as nil): there a restart cannot be told from a fresh start, so
-- these fixes simply do not apply and startup behaves as before.
local startreason = vim.v.startreason or 'normal'

if startreason == 'restart' then
  vim.g.session_loaded = true
end

-- :restart also reuses the original command line, file names included
-- (only files after `--` are dropped), so `nvim foo.py` reopens foo.py on
-- every restart even after it was closed: the new server opens it as an
-- argument, the session's %argdel empties the arg list, but the buffer
-- stays. So the files really open at exit are recorded, and after a
-- restart any unmodified file buffer not on that list (i.e. one that only
-- came back from the command line) is closed again.
local OPEN_AT_EXIT = vim.fn.stdpath('state') .. '/restart_open_buffers.json'

local function listed_files()
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if vim.bo[b].buflisted and vim.bo[b].buftype == '' and name ~= '' then
      out[#out + 1] = vim.fn.fnamemodify(name, ':p')
    end
  end
  return out
end

vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    pcall(vim.fn.writefile, { vim.json.encode(listed_files()) }, OPEN_AT_EXIT)
  end,
})

if startreason:match('^restart') then
  vim.api.nvim_create_autocmd('UIEnter', {
    once     = true,
    callback = function()
      -- Scheduled: after every UIEnter handler (neo-tree's included).
      vim.schedule(function()
        -- Only a list written by the server that just exited counts: a
        -- stale one (another instance, an older config that never wrote
        -- it) would close files that really were open.
        local st = (vim.uv or vim.loop).fs_stat(OPEN_AT_EXIT)
        if not st or os.time() - st.mtime.sec > 60 then return end
        local ok, data = pcall(function()
          return vim.json.decode(table.concat(vim.fn.readfile(OPEN_AT_EXIT), '\n'))
        end)
        if not ok or type(data) ~= 'table' then return end
        local keep = {}
        for _, f in ipairs(data) do keep[f] = true end
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          local name = vim.api.nvim_buf_get_name(b)
          if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted
              and vim.bo[b].buftype == '' and name ~= ''
              and not vim.bo[b].modified
              and not keep[vim.fn.fnamemodify(name, ':p')] then
            require('features.file').close_buffer(b)
          end
        end
      end)
    end,
  })
end

-- VimEnter fires after all plugins load, so session macros that
-- reference plugin commands (e.g. Neotree) work correctly.
-- neo-tree's UIEnter startup handler (which always runs after every
-- VimEnter handler, including this one) checks vim.g.session_loaded
-- to skip its 'enew' step when we have already restored buffers.
vim.api.nvim_create_autocmd('VimEnter', {
  once     = true,
  callback = function()
    if vim.fn.argc() ~= 0 then return end
    -- Already restored by :restart (see above); sourcing again is redundant.
    if startreason == 'restart' then return end
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
