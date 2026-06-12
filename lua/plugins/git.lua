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

local function current_branch()
  return vim.g.git_branch or vim.fn.system('git branch --show-current'):gsub('\n', '')
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
    local add_cmd = (choice == 'Commit All Changes')
      and 'git add -A'
      or  'git add ' .. vim.fn.shellescape(choice:match('%s%s(.+)$'))
    vim.ui.input({ prompt = 'Commit message: ' }, function(msg)
      if not msg or msg == '' then return end
      vim.fn.system(add_cmd .. ' && git commit -m ' .. vim.fn.shellescape(msg))
      if vim.v.shell_error == 0 then
        vim.notify('✅ Committed successfully', vim.log.levels.INFO)
        vim.cmd('checktime')
      else
        vim.notify('Commit failed', vim.log.levels.ERROR)
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
    vim.fn.system('git checkout -b ' .. vim.fn.shellescape(name))
    if vim.v.shell_error == 0 then
      vim.g.git_branch = name
      vim.notify('✅ Created and switched to: ' .. name, vim.log.levels.INFO)
      vim.cmd('checktime')
    else
      vim.notify('Failed to create branch', vim.log.levels.ERROR)
    end
  end)
end

local function switch_branch()
  if not is_git_repo() then return end
  local branches = {}
  for _, line in ipairs(vim.fn.systemlist("git branch --all --format='%(refname:short)'")) do
    line = line:match('^%s*(.-)%s*$')
    if line ~= '' then table.insert(branches, line) end
  end
  local current = current_branch()
  vim.ui.select(branches, { prompt = 'Switch to branch (current: ' .. current .. '):' },
    function(choice)
      if not choice or choice == current then return end
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
  local branches = {}
  for _, line in ipairs(vim.fn.systemlist("git branch --format='%(refname:short)'")) do
    line = line:match('^%s*(.-)%s*$')
    if line ~= '' then table.insert(branches, line) end
  end
  local current   = current_branch()
  local deletable = vim.tbl_filter(function(b) return b ~= current end, branches)
  if #deletable == 0 then
    vim.notify('No other branches to delete.', vim.log.levels.WARN)
    return
  end
  vim.ui.select(deletable, { prompt = 'Delete branch (current: ' .. current .. '):' },
    function(choice)
      if not choice then return end
      vim.fn.system('git branch -d ' .. vim.fn.shellescape(choice))
      if vim.v.shell_error == 0 then
        vim.notify('✅ Deleted: ' .. choice, vim.log.levels.INFO)
      else
        vim.ui.input({ prompt = 'Not fully merged. Force delete "' .. choice .. '"? (y/N): ' },
          function(confirm)
            if confirm and confirm:lower() == 'y' then
              vim.fn.system('git branch -D ' .. vim.fn.shellescape(choice))
              if vim.v.shell_error == 0 then
                vim.notify('✅ Force deleted: ' .. choice, vim.log.levels.INFO)
              else
                vim.notify('Force delete failed', vim.log.levels.ERROR)
              end
            end
          end)
      end
    end)
end

local function merge_branch()
  if not is_git_repo() then return end
  local branches = {}
  for _, line in ipairs(vim.fn.systemlist("git branch --all --format='%(refname:short)'")) do
    line = line:match('^%s*(.-)%s*$')
    if line ~= '' then table.insert(branches, line) end
  end
  local current   = current_branch()
  local mergeable = vim.tbl_filter(function(b) return b ~= current end, branches)
  vim.ui.select(mergeable, { prompt = 'Merge into "' .. current .. '":' },
    function(choice)
      if not choice then return end
      vim.fn.system('git merge ' .. vim.fn.shellescape(choice))
      if vim.v.shell_error == 0 then
        vim.notify('Merged ' .. choice, vim.log.levels.INFO)
        vim.cmd('checktime')
      else
        vim.notify('Merge failed', vim.log.levels.ERROR)
      end
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
