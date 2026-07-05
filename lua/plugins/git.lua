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

local gh = require('core.utils').gh

-- `fresh = true` forces a live git query instead of trusting the cached
-- vim.g.git_branch. The cache is only updated by switch_branch/git_create_branch
-- and on VimEnter, so it goes stale after switching branches via lazygit or a
-- terminal — callers that compare against `current` to decide whether to act
-- (e.g. switch_branch's "already on this branch" guard) must pass true or they
-- can silently no-op against the wrong branch name.
local function current_branch(fresh)
  if not fresh and vim.g.git_branch then return vim.g.git_branch end
  local branch = vim.fn.system('git branch --show-current'):gsub('\n', '')
  -- On failure (not a repo, broken git) don't cache the error text as a
  -- "branch name" — it would show up in the statusline and every prompt.
  if vim.v.shell_error ~= 0 then
    return vim.g.git_branch or ''
  end
  vim.g.git_branch = branch
  return branch
end

local function list_branches(all)
  local branches = {}
  local cmd = all and "git branch --all --format='%(refname:short)'"
                   or "git branch --format='%(refname:short)'"
  local lines = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify('git branch failed:\n' .. table.concat(lines, '\n'),
      vim.log.levels.WARN)
    return {}
  end
  for _, line in ipairs(lines) do
    line = line:match('^%s*(.-)%s*$')
    if line ~= '' then table.insert(branches, line) end
  end
  return branches
end

-- Opening/closing a window normally re-equalizes every window's size across
-- the whole tabpage ('equalalways'), which grows the neo-tree sidebar out of
-- its fixed width even though it's winfixwidth — that protects it from
-- explicit `<C-w>=`/manual equalization commands, but the automatic
-- redistribution on split/close still visibly disturbs it in practice.
-- Disabling 'equalalways' for the duration of a window open/close sequence
-- keeps every window untouched except the ones actually being resized.
local function without_equalize(fn)
  local saved = vim.o.equalalways
  vim.o.equalalways = false
  local ok, err = pcall(fn)
  vim.o.equalalways = saved
  if not ok then error(err, 0) end
end

-- Bare `:checktime` only reloads buffers currently displayed in a window —
-- any buffer that's open but hidden (not visible in a split/tab right now)
-- is skipped and keeps showing stale content until manually closed and
-- reopened. Checking each loaded buffer individually reloads all of them.
local function checktime_all_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.cmd('checktime ' .. buf)
    end
  end
end

-- ── gitsigns ─────────────────────────────────────────────────
-- Shows +/~/_ signs in the gutter for added/changed/deleted lines.
-- Also provides hunk navigation and staging without leaving Neovim.
-- Installed once here (removed the duplicate install from the old
-- init.lua Section 3 which had no keymaps).
vim.pack.add { { src = gh 'lewis6991/gitsigns.nvim', version = vim.version.range '2.*' } }

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

-- Set true by any function below while one of its vim.ui.select/vim.ui.input
-- prompts is open. Neovim's cmdline can only serve one prompt at a time, so
-- check_remote_ahead's own confirm prompt checks this before popping up —
-- otherwise a background fetch finishing mid-commit steals the cmdline from
-- the commit-message prompt and the keystrokes/Enter go to the wrong one,
-- silently dropping the commit.
local git_ui_busy = false

-- Cached result of the last successful remote-ahead check. Read by
-- maybe_check_remote_on_keypress when the debounce skips a fresh fetch, so a
-- keypress shortly after a check (e.g. <leader>gR then <leader>gs within the
-- same 5-minute window) still surfaces what's already known instead of
-- silently reporting nothing. Reset to 0 after any pull.
local last_known_ahead = 0

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
  -- `git status --porcelain` covers staged, unstaged, and untracked changes
  -- in one pass. Using `git diff --name-only` alone (as before) missed
  -- changes already staged via `git add` or gitsigns' <leader>hs, so a fully
  -- staged file looked like "nothing to commit" and was silently skipped.
  local files = {}
  for _, line in ipairs(vim.fn.systemlist('git status --porcelain')) do
    local status, name = line:match('^(..)%s(.+)$')
    if status and name then
      name = name:match('%->%s*(.+)$') or name  -- renames: "old -> new"
      table.insert(files, { name = name, status = status:gsub('%s', '') })
    end
  end
  if #files == 0 then
    vim.notify('No changes to commit', vim.log.levels.INFO)
    return
  end
  local choices = { 'Commit All Changes' }
  for _, f in ipairs(files) do table.insert(choices, f.status .. '  ' .. f.name) end
  git_ui_busy = true
  vim.ui.select(choices, { prompt = 'Select files to commit:' }, function(choice)
    if not choice then git_ui_busy = false; return end
    local add_cmd
    if choice == 'Commit All Changes' then
      add_cmd = 'git add -A'
    else
      local filename = choice:match('%s%s(.+)$')
      if not filename then git_ui_busy = false; return end
      add_cmd = 'git add ' .. vim.fn.shellescape(filename)
    end
    vim.ui.input({ prompt = 'Commit message: ' }, function(msg)
      git_ui_busy = false
      if not msg or msg == '' then return end
      local out = vim.fn.system(add_cmd .. ' && git commit -m ' .. vim.fn.shellescape(msg) .. ' 2>&1')
      if vim.v.shell_error == 0 then
        vim.notify('✅ Committed successfully', vim.log.levels.INFO)
        checktime_all_buffers()
      else
        vim.notify('Commit failed:\n' .. out, vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Pull: async so a slow network doesn't freeze the UI. Explicit --no-rebase
-- so this doesn't depend on pull.rebase/pull.ff being configured — with no
-- default set, a plain `git pull` errors out ("need to specify how to
-- reconcile divergent branches") instead of pulling whenever two machines
-- have each committed since the last sync.
local function git_pull()
  if not is_git_repo() then return end
  vim.notify('Pulling…', vim.log.levels.INFO)
  vim.system({ 'git', 'pull', '--no-rebase' }, {}, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify('✅ Git pull successful', vim.log.levels.INFO)
        last_known_ahead = 0
        checktime_all_buffers()
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

-- ── Remote-ahead check ──────────────────────────────────────────
-- On entering a repo (startup or :cd), periodically, and right before any
-- <leader>g* action, fetches in the background and asks whether to pull
-- if origin has moved ahead. Fetch
-- failures (no network, working offline) are swallowed silently — this is
-- advisory and shouldn't nag when there's nothing to fetch from. The
-- keypress-triggered path is also debounced (5 min), so a check made just
-- before the other laptop's push lands can leave this laptop "stale" for
-- up to 5 minutes — <leader>gR (force_check_remote below) bypasses that
-- for exactly this "did I miss something" moment, and reports an outcome
-- either way instead of staying silent.
local remote_check_in_progress = false
local last_remote_check        = 0
local KEYPRESS_DEBOUNCE_SECS   = 5 * 60
local PERIODIC_INTERVAL_MS     = 20 * 60 * 1000

-- fn's own prompt (e.g. switch_branch's picker) may already be open when the
-- fetch resolves — a competing vim.ui.input here would steal the cmdline
-- from it, so wait for git_ui_busy to clear before asking. Defaults to yes:
-- plain <CR> (or anything not starting with "n") pulls; only <Esc> (cancel)
-- or an explicit "n" skip it. Gives up after ~30s and falls back to a
-- passive notify if git_ui_busy is somehow never released.
local function prompt_pull_when_free(branch, ahead, retries_left)
  retries_left = retries_left or 100
  if git_ui_busy then
    if retries_left <= 0 then
      vim.notify(
        ('origin/%s is %d commit(s) ahead — pull manually or press <leader>gR'):format(branch, ahead),
        vim.log.levels.WARN)
      return
    end
    vim.defer_fn(function() prompt_pull_when_free(branch, ahead, retries_left - 1) end, 300)
    return
  end
  git_ui_busy = true
  vim.ui.input(
    { prompt = ('origin/%s is %d commit(s) ahead — pull now? (Y/n): '):format(branch, ahead) },
    function(confirm)
      git_ui_busy = false
      if confirm == nil then return end -- cancelled
      if confirm:lower():sub(1, 1) == 'n' then return end
      git_pull()
    end)
end

local function check_remote_ahead(verbose)
  if remote_check_in_progress then
    if verbose then vim.notify('Remote check already in progress…', vim.log.levels.INFO) end
    return
  end
  -- Only a *manual* call (<leader>gR) bails here: it wants an immediate
  -- answer, and another prompt is already occupying the cmdline. Keypress-
  -- triggered calls run after fn (see with_remote_check below), so fn's own
  -- prompt has almost always already set git_ui_busy by this point — that's
  -- expected, not a reason to skip the fetch; prompt_pull_when_free just
  -- waits for fn's prompt to close before asking about the pull.
  if verbose and git_ui_busy then
    vim.notify('Another git prompt is open — finish that first', vim.log.levels.WARN)
    return
  end
  if not is_git_repo() then return end
  remote_check_in_progress = true
  last_remote_check = os.time()
  if verbose then vim.notify('Checking origin…', vim.log.levels.INFO) end
  vim.system({ 'git', 'fetch' }, {}, function(result)
    remote_check_in_progress = false
    if result.code ~= 0 then
      if verbose then
        vim.schedule(function()
          vim.notify('Fetch failed (offline?):\n' .. (result.stderr or ''), vim.log.levels.WARN)
        end)
      end
      return -- offline or no remote — stay quiet when not verbose
    end
    vim.schedule(function()
      local ahead = tonumber(vim.fn.systemlist('git rev-list --count HEAD..@{u}')[1])
      if not ahead then
        if verbose then vim.notify('No upstream configured for current branch', vim.log.levels.WARN) end
        return
      end
      last_known_ahead = ahead
      if ahead == 0 then
        if verbose then vim.notify('✅ Up to date with origin', vim.log.levels.INFO) end
        return
      end
      prompt_pull_when_free(current_branch(true), ahead)
    end)
  end)
end

-- Debounced so mashing several <leader>g* keymaps in a row doesn't fire a
-- fetch on every single one; the periodic timer below runs unconditionally
-- on its own schedule instead. But debounced must not mean silent: if a
-- prior check (e.g. <leader>gR moments ago) already found origin ahead,
-- still surface that cached result here instead of skipping entirely.
local function maybe_check_remote_on_keypress()
  if os.time() - last_remote_check >= KEYPRESS_DEBOUNCE_SECS then
    check_remote_ahead()
  elseif last_known_ahead > 0 then
    prompt_pull_when_free(current_branch(true), last_known_ahead)
  end
end

-- Manual, debounce-free check for <leader>gR — always reports an outcome.
local function force_check_remote()
  check_remote_ahead(true)
end

-- Runs fn FIRST, then decides whether to kick off a background check —
-- deliberately in that order. fn sets git_ui_busy synchronously before its
-- first vim.ui.select/input call, with no async gap, so by the time this
-- checks whether to fetch, git_ui_busy already reflects reality: an
-- interactive fn skips the fetch entirely (retried on a later keypress),
-- and a non-interactive one (pull/push/lazygit) just gets checked right
-- after. The other order — check-then-fn, or worse, waiting for the check
-- to fully resolve before running fn — either leaves a race window where
-- the fetch starts before fn has claimed the cmdline, or delays fn's own
-- prompt with no visible feedback; both let stray keystrokes land in the
-- underlying buffer instead of fn's prompt.
local function with_remote_check(fn)
  return function(...)
    local result = fn(...)
    maybe_check_remote_on_keypress()
    return result
  end
end

local uv = vim.uv or vim.loop
local remote_check_timer = uv.new_timer()
remote_check_timer:start(PERIODIC_INTERVAL_MS, PERIODIC_INTERVAL_MS, function()
  vim.schedule(check_remote_ahead)
end)

-- ── Check on entering a repo ────────────────────────────────────
-- Run the same origin-ahead check (fetch → "pull now?" prompt) as soon as
-- a git repo becomes the working directory: once at startup when Neovim
-- was launched inside a repo, and again whenever :cd / neo-tree navigation
-- lands in a *different* repo than the one last checked. Keyed on the git
-- root rather than raw cwd so cd-ing between subdirectories of the same
-- repo doesn't re-fetch on every move — staying current within one repo is
-- already covered by the keypress debounce and the periodic timer above.
local last_checked_root = nil

local function git_root()
  local out = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == '' then return nil end
  return out[1]
end

local function check_if_entered_new_repo()
  local root = git_root()
  if not root or root == last_checked_root then return end
  last_checked_root = root
  check_remote_ahead()
end

-- UIEnter (not VimEnter): it is guaranteed to fire after every VimEnter
-- handler, including session.lua's restore, so the check sees the final
-- startup cwd. It also never fires headless, where a pull prompt would
-- have nowhere to go.
vim.api.nvim_create_autocmd('UIEnter', {
  once     = true,
  callback = check_if_entered_new_repo,
})

vim.api.nvim_create_autocmd('DirChanged', {
  callback = check_if_entered_new_repo,
})

local function git_create_branch()
  if not is_git_repo() then return end
  git_ui_busy = true
  vim.ui.input({ prompt = 'New branch name: ' }, function(name)
    git_ui_busy = false
    if not name or name == '' then return end
    local out = vim.fn.system('git checkout -b ' .. vim.fn.shellescape(name) .. ' 2>&1')
    if vim.v.shell_error == 0 then
      vim.g.git_branch = name
      vim.notify('✅ Created and switched to: ' .. name, vim.log.levels.INFO)
      checktime_all_buffers()
    else
      vim.notify('Failed to create branch:\n' .. out, vim.log.levels.ERROR)
    end
  end)
end

local function switch_branch()
  if not is_git_repo() then return end
  local branches = list_branches(true)
  local current  = current_branch(true)
  git_ui_busy = true
  vim.ui.select(branches, { prompt = 'Switch to branch (current: ' .. current .. '):' },
    function(choice)
      git_ui_busy = false
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
            checktime_all_buffers()
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
  git_ui_busy = true
  vim.ui.select(deletable, { prompt = 'Delete branch (current: ' .. current .. '):' },
    function(choice)
      if not choice then git_ui_busy = false; return end
      vim.fn.system('git branch -d ' .. vim.fn.shellescape(choice) .. ' 2>&1')
      if vim.v.shell_error == 0 then
        git_ui_busy = false
        vim.notify('✅ Deleted: ' .. choice, vim.log.levels.INFO)
      else
        vim.ui.input({ prompt = 'Not fully merged. Force delete "' .. choice .. '"? (y/N): ' },
          function(confirm)
            git_ui_busy = false
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
  git_ui_busy = true
  vim.ui.select(mergeable, { prompt = 'Merge into "' .. current .. '":' },
    function(choice)
      git_ui_busy = false
      if not choice then return end
      local out = vim.fn.system('git merge ' .. vim.fn.shellescape(choice) .. ' 2>&1')
      if vim.v.shell_error == 0 then
        vim.notify('Merged ' .. choice, vim.log.levels.INFO)
        checktime_all_buffers()
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
  git_ui_busy = true
  vim.ui.input({ prompt = 'Discard ALL changes in ' .. shortname .. '? (y/N): ' },
    function(confirm)
      git_ui_busy = false
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

-- Remembers the ref most recently used by open_ref_diff_for_current_buffer,
-- so a post-merge quickfix walk (<leader>gq + <leader>gn) can keep reopening
-- the diff against the same ref (e.g. HEAD^1) on each new file automatically,
-- without re-prompting every time.
local last_diff_ref = nil

-- Bumped every time a new ref-diff is opened. Lets a stale deferred cleanup
-- (see BufWipeout below) detect that a newer diff has since been set up on
-- the same (reused) window and skip itself, rather than clobbering it.
local diff_generation = 0

-- `git diff --numstat` prints "-\t-\t<path>" instead of add/delete counts
-- for files it considers binary. Cheap way to know do/dp-style text diffing
-- won't make sense for a given file before trying to render it as text.
local function is_binary_relpath(ref, relpath)
  local out = vim.fn.systemlist(
    'git diff --numstat ' .. vim.fn.shellescape(ref) .. ' -- ' .. vim.fn.shellescape(relpath))
  return out[1] ~= nil and out[1]:match('^%-\t%-\t') ~= nil
end

-- Opens the *current* buffer's file at `ref` in a side-by-side diff so you
-- can selectively pull changes with do/dp (diffget/diffput) instead of
-- merging the whole file. The comparison buffer is read-only scratch —
-- edits only ever land in your real, saveable buffer. Silently does nothing
-- if the current file isn't tracked by git (used for auto-continuing a
-- review onto whatever quickfix lands on next, which may not always apply).
local function open_ref_diff_for_current_buffer(ref)
  local file = vim.fn.expand('%:p')
  if file == '' then return end
  local relpath = vim.fn.systemlist('git ls-files --full-name ' .. vim.fn.shellescape(file))[1]
  if not relpath or relpath == '' then return end

  if is_binary_relpath(ref, relpath) then
    vim.notify('Binary file (' .. relpath .. ') — skipping diff view, do/dp do not apply',
      vim.log.levels.WARN)
    return
  end

  local content = vim.fn.system('git show ' .. vim.fn.shellescape(ref .. ':' .. relpath) .. ' 2>&1')
  if vim.v.shell_error ~= 0 then
    vim.notify('Failed to read ' .. relpath .. ' from ' .. ref .. ':\n' .. content, vim.log.levels.ERROR)
    return
  end

  local orig_win = vim.api.nvim_get_current_win()
  local orig_ft  = vim.bo.filetype
  local scratch

  diff_generation = diff_generation + 1
  local my_generation = diff_generation

  without_equalize(function()
    vim.cmd('belowright vsplit')
    scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, scratch)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, vim.split(content, '\n', { plain = true }))
    vim.bo[scratch].filetype   = orig_ft
    vim.bo[scratch].buftype    = 'nofile'
    vim.bo[scratch].bufhidden  = 'wipe'
    vim.bo[scratch].swapfile   = false
    vim.bo[scratch].modifiable = false
    pcall(vim.api.nvim_buf_set_name, scratch, ref .. ':' .. relpath)

    vim.cmd('diffthis')
    vim.api.nvim_set_current_win(orig_win)
    vim.cmd('diffthis')
  end)

  -- Closing the scratch (ref) window leaves the real buffer's window
  -- stuck showing diff highlighting/foldcolumn; turn that off automatically.
  -- Guarded by generation: if a newer diff has since been opened on the same
  -- (reused) window — e.g. <leader>gn immediately opening the next file's
  -- diff before this deferred callback runs — skip so it doesn't clobber it.
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer   = scratch,
    once     = true,
    callback = function()
      vim.schedule(function()
        if diff_generation == my_generation and vim.api.nvim_win_is_valid(orig_win) then
          vim.api.nvim_win_call(orig_win, function() vim.cmd('diffoff') end)
        end
      end)
    end,
  })

  last_diff_ref = ref
  vim.notify('Diffing against ' .. ref .. ' — do/dp to move hunks, ]c/[c to jump between them',
    vim.log.levels.INFO)
end

-- Offers a branch picker plus a "type a ref…" option, since post-merge
-- cleanup needs to diff against HEAD^ (pre-merge state) rather than a
-- branch name.
local function git_diff_file_against_ref()
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
  local type_ref = 'Type a ref… (e.g. HEAD^, HEAD~2, a commit SHA)'
  table.insert(branches, type_ref)
  git_ui_busy = true
  vim.ui.select(branches, { prompt = 'Diff current file against branch/ref:' }, function(choice)
    if not choice then git_ui_busy = false; return end
    if choice == type_ref then
      vim.ui.input({ prompt = 'Git ref: ', default = last_diff_ref }, function(ref)
        git_ui_busy = false
        if ref and ref ~= '' then open_ref_diff_for_current_buffer(ref) end
      end)
    else
      git_ui_busy = false
      open_ref_diff_for_current_buffer(choice)
    end
  end)
end

-- Advances the quickfix list and reports whether it actually moved.
-- pcall(vim.cmd, 'cnext')'s own success/failure isn't reliable here: landing
-- on a new buffer can trigger unrelated autocmds (scrollview, neo-tree
-- reveal, etc.) that throw *after* the jump already happened, which makes
-- pcall report failure even though the quickfix index did advance. Compare
-- the index directly instead, so an unrelated autocmd error downstream
-- doesn't get mistaken for "reached the end of the list".
local function try_cnext()
  local before = vim.fn.getqflist({ idx = 0 }).idx
  pcall(vim.cmd, 'cnext')
  local after = vim.fn.getqflist({ idx = 0 }).idx
  return after ~= before
end

-- "I am done here, moving on to the next change": for use after a <leader>gf
-- review — saves the real file, closes the read-only ref/scratch side (which
-- self-wipes and triggers the diffoff cleanup on the other window), deletes
-- the real file's buffer so it doesn't linger in the buffer list across a
-- long quickfix walk, then advances to the next quickfix entry and reopens
-- the diff there against the same ref, so the left/right panes carry over
-- from file to file without re-prompting. Identifies the two sides purely by
-- 'diff' being set on the window, so it works no matter which side (real
-- file or scratch) the cursor is on when invoked.
local function git_diff_done_next()
  local diff_wins = vim.tbl_filter(function(w) return vim.wo[w].diff end,
    vim.api.nvim_tabpage_list_wins(0))

  local real_win, real_buf, scratch_win
  for _, win in ipairs(diff_wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].modifiable then
      real_win, real_buf = win, buf
      if vim.bo[buf].modified then
        vim.api.nvim_win_call(win, function() vim.cmd('write') end)
      end
    else
      scratch_win = win
    end
  end

  -- Turn off diff mode on the real window synchronously now, rather than
  -- relying on the scratch buffer's own BufWipeout->diffoff autocmd (which
  -- runs on a deferred vim.schedule): since we're about to reuse this same
  -- window for the next file's diff, that deferred callback could otherwise
  -- fire after the new diff is already set up and incorrectly clear it.
  if real_win and vim.api.nvim_win_is_valid(real_win) then
    vim.api.nvim_win_call(real_win, function() vim.cmd('diffoff') end)
  end

  -- Advance the quickfix list *before* closing/deleting anything, with focus
  -- on the real window, so :cnext swaps that window's buffer in place. If we
  -- deleted the old buffer first instead, a window with no "alternate"
  -- buffer to fall back to (common once we've cycled through a few files)
  -- gets closed outright rather than cleared — collapsing neo-tree's sibling
  -- window and leaving the sidebar to inherit the whole row's width.
  if real_win and vim.api.nvim_win_is_valid(real_win) then
    vim.api.nvim_set_current_win(real_win)
  end
  local advanced = try_cnext()

  without_equalize(function()
    if scratch_win and vim.api.nvim_win_is_valid(scratch_win) then
      vim.api.nvim_win_close(scratch_win, true)
    end
    if real_buf and vim.api.nvim_buf_is_valid(real_buf) then
      pcall(vim.api.nvim_buf_delete, real_buf, { force = false })
    end
  end)

  if not advanced or not last_diff_ref then return end

  -- Skip forward past any binary files (do/dp diffing doesn't apply to
  -- them) so the walk doesn't stop on a garbled-looking raw-bytes buffer.
  -- Each skipped file's buffer is deleted once cnext has moved off it, same
  -- as the real-file cleanup above, so they don't pile up in the buffer list.
  while true do
    local file = vim.fn.expand('%:p')
    local relpath = file ~= '' and vim.fn.systemlist('git ls-files --full-name ' .. vim.fn.shellescape(file))[1]
    if not relpath or relpath == '' or not is_binary_relpath(last_diff_ref, relpath) then
      break
    end
    vim.notify('Skipping binary file: ' .. relpath, vim.log.levels.INFO)
    local binary_buf = vim.api.nvim_get_current_buf()
    if not try_cnext() then break end
    pcall(vim.api.nvim_buf_delete, binary_buf, { force = false })
  end

  open_ref_diff_for_current_buffer(last_diff_ref)
end

-- List every file changed between two refs (default: HEAD^1..HEAD, i.e. what
-- a merge commit just brought in relative to the branch it was merged into)
-- into the quickfix list, so a post-merge review can walk them with
-- :cnext/:cprev alongside <leader>gf instead of tracking the list by hand.
local function git_changed_files_to_quickfix()
  if not is_git_repo() then return end
  git_ui_busy = true
  vim.ui.input({ prompt = 'Base ref: ', default = 'HEAD^1' }, function(base)
    if not base or base == '' then git_ui_busy = false; return end
    vim.ui.input({ prompt = 'Target ref: ', default = 'HEAD' }, function(target)
      git_ui_busy = false
      if not target or target == '' then return end
      local files = vim.fn.systemlist(
        'git diff --name-only ' .. vim.fn.shellescape(base) .. ' ' .. vim.fn.shellescape(target))
      if vim.v.shell_error ~= 0 then
        vim.notify('Failed to diff ' .. base .. '..' .. target .. ':\n' .. table.concat(files, '\n'),
          vim.log.levels.ERROR)
        return
      end
      if #files == 0 then
        vim.notify('No changed files between ' .. base .. ' and ' .. target, vim.log.levels.INFO)
        return
      end
      local root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
      local qflist = {}
      for _, f in ipairs(files) do
        table.insert(qflist, { filename = root .. '/' .. f, lnum = 1, text = f })
      end
      vim.fn.setqflist(qflist)
      vim.cmd('copen')
      vim.notify(#files .. ' changed file(s) (' .. base .. '..' .. target .. ') loaded to quickfix',
        vim.log.levels.INFO)
    end)
  end)
end

-- ── Git keymaps ───────────────────────────────────────────────
-- Every <leader>g* action is wrapped with with_remote_check so pressing any
-- of them also triggers the debounced origin-ahead check above.
vim.keymap.set('n', '<leader>gg', with_remote_check(open_lazygit),      { desc = 'Git: open lazygit' })
vim.keymap.set('n', '<leader>gc', with_remote_check(git_commit),        { desc = 'Git: commit' })
vim.keymap.set('n', '<leader>gb', with_remote_check(git_create_branch), { desc = 'Git: create branch' })
vim.keymap.set('n', '<leader>gp', with_remote_check(git_pull),          { desc = 'Git: pull' })
vim.keymap.set('n', '<leader>gP', with_remote_check(git_push),          { desc = 'Git: push' })
vim.keymap.set('n', '<leader>gs', with_remote_check(switch_branch),     { desc = 'Git: switch branch' })
vim.keymap.set('n', '<leader>gd', with_remote_check(delete_branch),     { desc = 'Git: delete branch' })
vim.keymap.set('n', '<leader>gm', with_remote_check(merge_branch),      { desc = 'Git: merge branch' })
vim.keymap.set('n', '<leader>gf', with_remote_check(git_diff_file_against_ref), { desc = 'Git: diff file against branch/ref (do/dp to pull hunks)' })
vim.keymap.set('n', '<leader>gq', with_remote_check(git_changed_files_to_quickfix), { desc = 'Git: changed files (ref..ref) to quickfix' })
vim.keymap.set('n', '<leader>gn', with_remote_check(git_diff_done_next), { desc = 'Git: done with this diff, save + close + next quickfix' })
vim.keymap.set('n', '<leader>gx', with_remote_check(discard_buffer_changes), { desc = 'Git: discard changes in buffer' })
vim.keymap.set('n', '<leader>gR', force_check_remote, { desc = 'Git: check if origin is ahead (bypasses debounce)' })
