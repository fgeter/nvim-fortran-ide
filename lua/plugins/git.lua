-- ============================================================
-- plugins/git.lua — Git integration
--
-- Two complementary tools:
--   gitsigns  — inline git decorations (added/changed/deleted lines
--               in the sign column) and hunk-level operations
--   lazygit   — full terminal git UI opened in a dedicated tab
--
-- Keymaps:
--   <leader>g* — repository-level operations (commit, push, pull, etc.)
--   <leader>h* — hunk-level operations (stage, reset, preview, blame)
--
-- LAZY: gitsigns loads at startup (it attaches via BufRead internally).
--       lazygit functions are defined at startup but lazygit itself
--       only launches when a keymap is pressed.
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

-- `fresh = true` forces a live git query instead of trusting the cached
-- vim.g.git_branch. The cache is only updated by switch_branch/git_create_branch
-- and on VimEnter, so it goes stale after switching branches via lazygit or a
-- terminal — callers that compare against `current` to decide whether to act
-- (e.g. switch_branch's "already on this branch" guard) must pass true or they
-- can silently no-op against the wrong branch name.
local function current_branch(fresh)
  if not fresh and vim.g.git_branch then return vim.g.git_branch end
  local branch = vim.fn.system('git branch --show-current'):gsub('\n', '')
  vim.g.git_branch = branch
  return branch
end

local function list_branches(all)
  local branches = {}
  local cmd = all and "git branch --all --format='%(refname:short)'"
                   or "git branch --format='%(refname:short)'"
  for _, line in ipairs(vim.fn.systemlist(cmd)) do
    line = line:match('^%s*(.-)%s*$')
    if line ~= '' then table.insert(branches, line) end
  end
  return branches
end

-- ── gitsigns ─────────────────────────────────────────────────
-- Shows +/~/_ signs in the gutter for added/changed/deleted lines.
-- Also provides hunk navigation and staging without leaving Neovim.
-- Installed once here (removed the duplicate install from the old
-- init.lua Section 3 which had no keymaps).
vim.pack.add { gh 'lewis6991/gitsigns.nvim' }

require('gitsigns').setup {
  signs = {
    add          = { text = '+' }, ---@diagnostic disable-line: missing-fields
    change       = { text = '~' }, ---@diagnostic disable-line: missing-fields
    delete       = { text = '_' }, ---@diagnostic disable-line: missing-fields
    topdelete    = { text = '‾' }, ---@diagnostic disable-line: missing-fields
    changedelete = { text = '~' }, ---@diagnostic disable-line: missing-fields
  },

  on_attach = function(bufnr)
    local gs = require('gitsigns')
    local function map(mode, l, r, opts)
      opts = opts or {}
      opts.buffer = bufnr
      vim.keymap.set(mode, l, r, opts)
    end

    -- Hunk navigation: jump to next/previous changed section
    -- In diff mode, uses Vim's built-in ]c/[c instead
    map('n', ']c', function()
      if vim.wo.diff then vim.cmd.normal { ']c', bang = true }
      else gs.nav_hunk('next') end
    end, { desc = 'Git: next hunk' })

    map('n', '[c', function()
      if vim.wo.diff then vim.cmd.normal { '[c', bang = true }
      else gs.nav_hunk('prev') end
    end, { desc = 'Git: prev hunk' })

    -- Hunk operations (visual mode: operate on selected lines only)
    map('v', '<leader>hs', function() gs.stage_hunk { vim.fn.line('.'), vim.fn.line('v') } end, { desc = 'Git hunk: stage' })
    map('v', '<leader>hr', function() gs.reset_hunk { vim.fn.line('.'), vim.fn.line('v') } end, { desc = 'Git hunk: reset' })

    -- Hunk operations (normal mode)
    map('n', '<leader>hs', gs.stage_hunk,          { desc = 'Git hunk: stage' })
    map('n', '<leader>hr', gs.reset_hunk,           { desc = 'Git hunk: reset' })
    map('n', '<leader>hS', gs.stage_buffer,         { desc = 'Git hunk: stage buffer' })
    map('n', '<leader>hR', gs.reset_buffer,         { desc = 'Git hunk: reset buffer' })
    map('n', '<leader>hp', gs.preview_hunk,         { desc = 'Git hunk: preview' })
    map('n', '<leader>hi', gs.preview_hunk_inline,  { desc = 'Git hunk: preview inline' })
    map('n', '<leader>hb', function() gs.blame_line { full = true } end, { desc = 'Git hunk: blame line' })
    map('n', '<leader>hd', gs.diffthis,             { desc = 'Git hunk: diff against index' })
    map('n', '<leader>hD', function() gs.diffthis('@') end, { desc = 'Git hunk: diff against last commit' })
    map('n', '<leader>hq', gs.setqflist,            { desc = 'Git hunk: quickfix (this file)' })
    map('n', '<leader>hQ', function() gs.setqflist('all') end, { desc = 'Git hunk: quickfix (all files)' })

    -- Toggles
    map('n', '<leader>tb', gs.toggle_current_line_blame, { desc = 'Toggle: git blame line' })
    map('n', '<leader>tw', gs.toggle_word_diff,          { desc = 'Toggle: git word diff' })

    -- Text object: ih selects inside a hunk (usable with d/y/c)
    map({ 'o', 'x' }, 'ih', gs.select_hunk)
  end,
}

-- ── lazygit ──────────────────────────────────────────────────
-- Full git UI launched in a dedicated terminal tab.
-- Closes automatically when you quit lazygit (q inside lazygit).
-- Functions use vim.system() (async, non-blocking) for operations
-- that may take time (pull, push) so Neovim's UI stays responsive.

if vim.g.loaded_lazygit then return end
vim.g.loaded_lazygit = true

-- Returns true if the current working directory is inside a git repo
local function is_git_repo()
  local result = vim.fn.systemlist(
    'git -C ' .. vim.fn.shellescape(vim.fn.getcwd()) .. ' rev-parse --is-inside-work-tree 2>/dev/null'
  )
  return result[1] == 'true'
end

-- Open lazygit in a new tab with a clean terminal buffer.
-- The tab is wiped when lazygit exits so it leaves no orphan buffers.
local function open_lazygit()
  if not is_git_repo() then
    vim.notify('Not inside a Git repository.\nCurrent dir: ' .. vim.fn.getcwd(), vim.log.levels.WARN)
    return
  end
  vim.cmd('tabnew')
  vim.cmd('terminal lazygit')
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd('setlocal bufhidden=wipe nobuflisted nonumber norelativenumber signcolumn=no nocursorline')
  vim.keymap.set('n', 'q', '<cmd>q<CR>', { buffer = buf, silent = true, nowait = true })
  vim.cmd('startinsert')
end

-- Commit: choose which files to stage then enter a message.
-- Uses vim.fn.system (blocking) because the git add + commit is instant.
local function git_commit()
  if not is_git_repo() then return end
  local modified  = vim.fn.systemlist('git diff --name-only')
  local untracked = vim.fn.systemlist('git ls-files --others --exclude-standard')
  local files = {}
  for _, f in ipairs(modified)  do table.insert(files, { name = f, status = 'M' }) end
  for _, f in ipairs(untracked) do table.insert(files, { name = f, status = 'U' }) end
  if #files == 0 then
    vim.notify('No changes to commit', vim.log.levels.INFO)
    return
  end
  local choices = { 'Commit All Changes' }
  for _, f in ipairs(files) do table.insert(choices, f.status .. '  ' .. f.name) end
  vim.ui.select(choices, { prompt = 'Select files to commit:' }, function(choice)
    if not choice then return end
    local add_cmd
    if choice == 'Commit All Changes' then
      add_cmd = 'git add -A'
    else
      local filename = choice:match('%s%s(.+)$')
      if not filename then return end
      add_cmd = 'git add ' .. vim.fn.shellescape(filename)
    end
    vim.ui.input({ prompt = 'Commit message: ' }, function(msg)
      if not msg or msg == '' then return end
      local out = vim.fn.system(add_cmd .. ' && git commit -m ' .. vim.fn.shellescape(msg) .. ' 2>&1')
      if vim.v.shell_error == 0 then
        vim.notify('✅ Committed successfully', vim.log.levels.INFO)
        vim.cmd('checktime')
      else
        vim.notify('Commit failed:\n' .. out, vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Pull: async so a slow network doesn't freeze the UI
local function git_pull()
  if not is_git_repo() then return end
  vim.notify('Pulling…', vim.log.levels.INFO)
  vim.system({ 'git', 'pull' }, {}, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify('✅ Git pull successful', vim.log.levels.INFO)
        vim.cmd('checktime')
      else
        vim.notify('Git pull failed:\n' .. (result.stderr or ''), vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Push: async for the same reason as pull
local function git_push()
  if not is_git_repo() then return end
  vim.notify('Pushing…', vim.log.levels.INFO)
  vim.system({ 'git', 'push' }, {}, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify('✅ Git push successful', vim.log.levels.INFO)
      else
        vim.notify('Git push failed:\n' .. (result.stderr or ''), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function git_create_branch()
  if not is_git_repo() then return end
  vim.ui.input({ prompt = 'New branch name: ' }, function(name)
    if not name or name == '' then return end
    local out = vim.fn.system('git checkout -b ' .. vim.fn.shellescape(name) .. ' 2>&1')
    if vim.v.shell_error == 0 then
      vim.g.git_branch = name
      vim.notify('✅ Created and switched to: ' .. name, vim.log.levels.INFO)
      vim.cmd('checktime')
    else
      vim.notify('Failed to create branch:\n' .. out, vim.log.levels.ERROR)
    end
  end)
end

local function switch_branch()
  if not is_git_repo() then return end
  local branches = list_branches(true)
  local current  = current_branch(true)
  vim.ui.select(branches, { prompt = 'Switch to branch (current: ' .. current .. '):' },
    function(choice)
      if not choice then return end
      if choice == current then
        vim.notify('Already on: ' .. choice, vim.log.levels.INFO)
        return
      end
      vim.system({ 'git', 'checkout', choice }, {}, function(result)
        vim.schedule(function()
          if result.code == 0 then
            vim.g.git_branch = choice
            vim.notify('Switched to: ' .. choice, vim.log.levels.INFO)
            vim.cmd('checktime')
          else
            vim.notify('Failed to switch branch:\n' .. (result.stderr or ''), vim.log.levels.ERROR)
          end
        end)
      end)
    end)
end

local function delete_branch()
  if not is_git_repo() then return end
  local branches = list_branches(false)
  local current  = current_branch(true)
  local deletable = vim.tbl_filter(function(b) return b ~= current end, branches)
  if #deletable == 0 then
    vim.notify('No other branches to delete.', vim.log.levels.WARN)
    return
  end
  vim.ui.select(deletable, { prompt = 'Delete branch (current: ' .. current .. '):' },
    function(choice)
      if not choice then return end
      vim.fn.system('git branch -d ' .. vim.fn.shellescape(choice) .. ' 2>&1')
      if vim.v.shell_error == 0 then
        vim.notify('✅ Deleted: ' .. choice, vim.log.levels.INFO)
      else
        vim.ui.input({ prompt = 'Not fully merged. Force delete "' .. choice .. '"? (y/N): ' },
          function(confirm)
            if confirm and confirm:lower() == 'y' then
              local out = vim.fn.system('git branch -D ' .. vim.fn.shellescape(choice) .. ' 2>&1')
              if vim.v.shell_error == 0 then
                vim.notify('✅ Force deleted: ' .. choice, vim.log.levels.INFO)
              else
                vim.notify('Force delete failed:\n' .. out, vim.log.levels.ERROR)
              end
            end
          end)
      end
    end)
end

local function merge_branch()
  if not is_git_repo() then return end
  local branches = list_branches(true)
  local current  = current_branch(true)
  local mergeable = vim.tbl_filter(function(b) return b ~= current end, branches)
  vim.ui.select(mergeable, { prompt = 'Merge into "' .. current .. '":' },
    function(choice)
      if not choice then return end
      local out = vim.fn.system('git merge ' .. vim.fn.shellescape(choice) .. ' 2>&1')
      if vim.v.shell_error == 0 then
        vim.notify('Merged ' .. choice, vim.log.levels.INFO)
        vim.cmd('checktime')
      else
        vim.notify('Merge failed:\n' .. out, vim.log.levels.ERROR)
      end
    end)
end

-- Discards all changes (staged and unstaged) to the file behind the current
-- buffer, restoring it to HEAD. Destructive, so it requires confirmation and
-- refuses to run against an untracked file (there is no HEAD copy to restore
-- to — deleting it would be a different, more destructive operation).
local function discard_buffer_changes()
  if not is_git_repo() then return end
  local file = vim.fn.expand('%:p')
  if file == '' then
    vim.notify('No file in current buffer', vim.log.levels.WARN)
    return
  end
  local status = vim.fn.system('git status --porcelain -- ' .. vim.fn.shellescape(file))
  if status == '' then
    vim.notify('No changes to discard in this file', vim.log.levels.INFO)
    return
  end
  if status:match('^%?%?') then
    vim.notify('File is untracked — discard does not apply (delete it manually if intended)',
      vim.log.levels.WARN)
    return
  end
  local shortname = vim.fn.fnamemodify(file, ':t')
  vim.ui.input({ prompt = 'Discard ALL changes in ' .. shortname .. '? (y/N): ' },
    function(confirm)
      if not confirm or confirm:lower() ~= 'y' then return end
      local out = vim.fn.system('git checkout HEAD -- ' .. vim.fn.shellescape(file) .. ' 2>&1')
      if vim.v.shell_error == 0 then
        vim.notify('✅ Discarded changes in: ' .. shortname, vim.log.levels.INFO)
        vim.cmd('edit!')
      else
        vim.notify('Failed to discard changes:\n' .. out, vim.log.levels.ERROR)
      end
    end)
end

-- Open the current file's version on another branch in a side-by-side diff
-- so you can selectively pull changes with do/dp (diffget/diffput) instead
-- of merging the whole file. The comparison buffer is read-only scratch —
-- edits only ever land in your real, saveable buffer on the left/right
-- depending on split direction.
local function git_diff_file_against_branch()
  if not is_git_repo() then return end
  local file = vim.fn.expand('%:p')
  if file == '' then
    vim.notify('No file in current buffer', vim.log.levels.WARN)
    return
  end
  local relpath = vim.fn.systemlist('git ls-files --full-name ' .. vim.fn.shellescape(file))[1]
  if not relpath or relpath == '' then
    vim.notify('File is not tracked by git', vim.log.levels.WARN)
    return
  end
  local current  = current_branch(true)
  local branches = vim.tbl_filter(function(b) return b ~= current end, list_branches(true))
  vim.ui.select(branches, { prompt = 'Diff current file against branch:' }, function(branch)
    if not branch then return end
    local content = vim.fn.system('git show ' .. vim.fn.shellescape(branch .. ':' .. relpath) .. ' 2>&1')
    if vim.v.shell_error ~= 0 then
      vim.notify('Failed to read ' .. relpath .. ' from ' .. branch .. ':\n' .. content, vim.log.levels.ERROR)
      return
    end

    local orig_win = vim.api.nvim_get_current_win()
    local orig_ft  = vim.bo.filetype

    vim.cmd('belowright vsplit')
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, scratch)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, vim.split(content, '\n', { plain = true }))
    vim.bo[scratch].filetype   = orig_ft
    vim.bo[scratch].buftype    = 'nofile'
    vim.bo[scratch].bufhidden  = 'wipe'
    vim.bo[scratch].swapfile   = false
    vim.bo[scratch].modifiable = false
    pcall(vim.api.nvim_buf_set_name, scratch, branch .. ':' .. relpath)

    vim.cmd('diffthis')
    vim.api.nvim_set_current_win(orig_win)
    vim.cmd('diffthis')

    -- Closing the scratch (branch) window leaves the real buffer's window
    -- stuck showing diff highlighting/foldcolumn; turn that off automatically.
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer   = scratch,
      once     = true,
      callback = function()
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(orig_win) then
            vim.api.nvim_win_call(orig_win, function() vim.cmd('diffoff') end)
          end
        end)
      end,
    })

    vim.notify('Diffing against ' .. branch .. ' — do/dp to move hunks, ]c/[c to jump between them',
      vim.log.levels.INFO)
  end)
end

-- ── Git keymaps ───────────────────────────────────────────────
vim.keymap.set('n', '<leader>gg', open_lazygit,      { desc = 'Git: open lazygit' })
vim.keymap.set('n', '<leader>gc', git_commit,        { desc = 'Git: commit' })
vim.keymap.set('n', '<leader>gb', git_create_branch, { desc = 'Git: create branch' })
vim.keymap.set('n', '<leader>gp', git_pull,          { desc = 'Git: pull' })
vim.keymap.set('n', '<leader>gP', git_push,          { desc = 'Git: push' })
vim.keymap.set('n', '<leader>gs', switch_branch,     { desc = 'Git: switch branch' })
vim.keymap.set('n', '<leader>gd', delete_branch,     { desc = 'Git: delete branch' })
vim.keymap.set('n', '<leader>gm', merge_branch,      { desc = 'Git: merge branch' })
vim.keymap.set('n', '<leader>gf', git_diff_file_against_branch, { desc = 'Git: diff file against branch (do/dp to pull hunks)' })
vim.keymap.set('n', '<leader>gx', discard_buffer_changes, { desc = 'Git: discard changes in buffer' })
