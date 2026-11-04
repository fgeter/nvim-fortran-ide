-- ============================================================
-- features/github.lua — <leader>G: GitHub (the menu bar's GitHub menu)
--
-- Uses the gh command-line tool (signed in with `gh auth login`).
--
--   GC  Clone a repository…            (only outside a git repository)
--   GR  Publish this folder to GitHub… (only without a GitHub remote)
--   Go  Open on GitHub                 (the repository page, in the browser;
--                                       its address shows in the menu)
--   Gi  Repository info                (address, clone URLs, branches,
--                                       open PRs / issues, stars …)
--   Gf  Open this file on GitHub       (at the cursor line / selection)
--   Gy  Copy GitHub link to this line  (or selection)
--   Gp  Pull requests…   Gv  This branch's pull request   GP  Create PR…
--   Gs  Issues…          GI  New issue…
--   Ga  Actions: recent workflow runs…
--   GA  GitHub account / sign in
--
-- Slow gh calls run in the background; nothing here blocks the editor.
-- M.state gives the menu's state column (the repository address, or why
-- an entry can't be used here). Added 2026-11-03.
-- ============================================================

local M = {}

local function info(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = 'GitHub' }) end
local function warn(msg) info(msg, vim.log.levels.WARN) end

local function map(lhs, rhs, desc, modes)
  vim.keymap.set(modes or 'n', '<leader>' .. lhs, rhs, { desc = 'GitHub: ' .. desc, silent = true })
end

-- Run gh / git in the background; cb(ok, stdout, stderr) on the main loop.
local function run(cmd, cb, cwd)
  vim.system(cmd, { text = true, cwd = cwd }, vim.schedule_wrap(function(r)
    cb(r.code == 0, r.stdout or '', vim.trim(r.stderr or ''))
  end))
end

-- JSON null → nil (not vim.NIL), so missing fields read as absent.
local function decode(s)
  local ok, v = pcall(vim.json.decode, s, { luanil = { object = true, array = true } })
  return ok and v or nil
end

local function git(args, cwd)
  local r = vim.system(vim.list_extend({ 'git' }, args), { text = true, cwd = cwd }):wait()
  return r.code == 0 and vim.trim(r.stdout or '') or nil
end

-- ── Where we are ─────────────────────────────────────────────
-- The repository of the working directory (what the menu bar's Git
-- menu goes by too); for file links, the file's own repository.
local function repo_root(dir)
  return vim.fs.root(dir or vim.fn.getcwd(), '.git')
end

-- owner/name and the https address, from the origin remote (no network).
local cache = { root = nil, at = 0, remote = nil }
local function github_remote(root)
  root = root or repo_root()
  if not root then return nil end
  local now = vim.uv.now()
  if cache.root == root and now - cache.at < 5000 then return cache.remote end
  local url = git({ 'remote', 'get-url', 'origin' }, root)
  local remote = nil
  if url then
    local slug = url:match('github%.com[:/]([^/]+/[^/]+)$')
    if slug then
      slug = slug:gsub('%.git$', '')
      remote = { slug = slug, url = 'https://github.com/' .. slug }
    end
  end
  cache = { root = root, at = now, remote = remote }
  return remote
end

function M.in_repo() return repo_root() ~= nil end
function M.has_github() return github_remote() ~= nil end
function M.invalidate() cache.at = 0 end

local function need_github()
  if not repo_root() then warn('Not in a git repository (cd into one, or GitHub › Clone a repository…)') return nil end
  local r = github_remote()
  if not r then warn('This repository has no GitHub remote (GitHub › Publish this folder to GitHub…)') return nil end
  return r
end

-- ── A terminal for gh's interactive commands ─────────────────
local function terminal(cmd, title, on_exit)
  vim.cmd('botright 15new')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = 'wipe'
  vim.fn.jobstart(cmd, {
    term = true,
    cwd = repo_root() or vim.fn.getcwd(),
    on_exit = function(_, code)
      vim.schedule(function()
        M.invalidate()
        if on_exit then on_exit(code) end
      end)
    end,
  })
  pcall(vim.api.nvim_buf_set_name, buf, 'GitHub: ' .. title)
  vim.cmd('startinsert')
end

-- ── Pickers ──────────────────────────────────────────────────
local function picker(title, items, display, actions)
  local pickers      = require('telescope.pickers')
  local finders      = require('telescope.finders')
  local conf         = require('telescope.config').values
  local tactions     = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = items,
      entry_maker = function(it)
        local text = display(it)
        return { value = it, display = text, ordinal = text }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_buf, tmap)
      tactions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        tactions.close(prompt_buf)
        if sel then actions.default(sel.value) end
      end)
      for lhs, fn in pairs(actions.extra or {}) do
        tmap({ 'i', 'n' }, lhs, function()
          local sel = action_state.get_selected_entry()
          tactions.close(prompt_buf)
          if sel then fn(sel.value) end
        end)
      end
      return true
    end,
  }):find()
end

local function ago(iso)
  if not iso or iso == '' then return '' end
  local y, mo, d, h, mi, s = iso:match('(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
  if not y then return '' end
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false })
  local utc_offset = os.time() - os.time(os.date('!*t'))
  local secs = os.time() - (t + utc_offset)
  if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. 'm ago' end
  if secs < 86400 then return math.floor(secs / 3600) .. 'h ago' end
  if secs < 86400 * 60 then return math.floor(secs / 86400) .. 'd ago' end
  return iso:sub(1, 10)
end

local function open_url(url)
  local ok, err = pcall(vim.ui.open, url)
  if not ok then warn('Could not open the browser: ' .. tostring(err)) end
end

-- ── Clone ────────────────────────────────────────────────────
local function do_clone(repo)
  local name = repo:gsub('%.git$', ''):match('([^/:]+)$')
  if not name or name == '' then warn('Not a repository: ' .. repo) return end
  vim.ui.input({ prompt = 'Clone ' .. repo .. ' into folder: ', default = vim.fn.getcwd() .. '/', completion = 'dir' },
    function(parent)
      if not parent or vim.trim(parent) == '' then return end
      parent = vim.fn.fnamemodify(vim.fn.expand(vim.trim(parent)), ':p'):gsub('/$', '')
      local dest = parent .. '/' .. name
      if vim.uv.fs_stat(dest) then warn(vim.fn.fnamemodify(dest, ':~') .. ' already exists') return end
      vim.fn.mkdir(parent, 'p')
      info('Cloning ' .. repo .. ' …')
      run({ 'gh', 'repo', 'clone', repo, dest }, function(ok, _, err)
        if not ok then warn('Clone failed: ' .. err) return end
        local choice = vim.fn.confirm('Cloned into ' .. vim.fn.fnamemodify(dest, ':~') .. '.\nOpen it now?',
          '&Open\n&Not now', 1)
        if choice == 1 then
          vim.cmd('silent cd ' .. vim.fn.fnameescape(dest))
          M.invalidate()
          for _, readme in ipairs({ 'README.md', 'README', 'readme.md', 'README.rst' }) do
            if vim.uv.fs_stat(dest .. '/' .. readme) then
              vim.cmd.edit(vim.fn.fnameescape(dest .. '/' .. readme))
              break
            end
          end
          info('Now in ' .. vim.fn.fnamemodify(dest, ':~'))
        end
      end)
    end)
end

local function clone()
  info('Fetching your repositories …')
  run({ 'gh', 'repo', 'list', '--limit', '300', '--json', 'nameWithOwner,description,isPrivate,updatedAt' },
    function(ok, out, err)
      local repos = {}
      if ok then repos = decode(out) or {} else warn('Could not list your repositories: ' .. err) end
      table.insert(repos, 1, { nameWithOwner = '', enter = true })
      picker('Clone a repository  (or the first line: type a URL / owner/name)', repos, function(r)
        if r.enter then return '✎  Enter a URL or owner/name…' end
        return ('%s%s  %s'):format(r.nameWithOwner, r.isPrivate and '  🔒' or '', r.description or '')
      end, {
        default = function(r)
          if r.enter then
            vim.ui.input({ prompt = 'Repository (URL or owner/name): ' }, function(s)
              if s and vim.trim(s) ~= '' then do_clone(vim.trim(s)) end
            end)
          else
            do_clone(r.nameWithOwner)
          end
        end,
      })
    end)
end

-- ── Publish ──────────────────────────────────────────────────
local function publish()
  if M.has_github() then info('Already on GitHub: ' .. github_remote().url) return end
  -- gh's own wizard: name, visibility, add remote, push.
  terminal({ 'gh', 'repo', 'create' }, 'publish', function(code)
    if code == 0 and M.has_github() then info('Published: ' .. github_remote().url) end
  end)
end

-- ── Open / info ──────────────────────────────────────────────
local function open_repo()
  local r = need_github(); if not r then return end
  open_url(r.url)
end

local function repo_info()
  local r = need_github(); if not r then return end
  local root = repo_root()
  info('Fetching repository info …')
  local results, pending = {}, 3
  local function done()
    pending = pending - 1
    if pending > 0 then return end
    local v = results.view
    if not v then warn('Could not read the repository from GitHub: ' .. (results.err or '')) return end
    local branch = git({ 'branch', '--show-current' }, root) or '?'
    local track = git({ 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}' }, root)
    local ahead_behind = ''
    if track then
      local counts = git({ 'rev-list', '--left-right', '--count', '@{u}...HEAD' }, root)
      local behind, ahead = (counts or ''):match('(%d+)%s+(%d+)')
      ahead_behind = ('  (%s ahead, %s behind %s)'):format(ahead or '?', behind or '?', track)
    else
      ahead_behind = '  (not on GitHub yet)'
    end
    local lines = {
      ('%s  ·  %s%s'):format(v.nameWithOwner, (v.visibility or ''):lower(), v.isFork and '  ·  fork' or ''),
      v.description ~= '' and v.description or '(no description)',
      '',
      'Address        ' .. v.url,
      'Clone (SSH)    ' .. (v.sshUrl or ''),
      'Clone (HTTPS)  ' .. v.url .. '.git',
      '',
      'Default branch ' .. ((v.defaultBranchRef or {}).name or '?'),
      'This branch    ' .. branch .. ahead_behind,
      ('Open PRs       %s      Open issues  %s'):format(results.prs or '?', results.issues or '?'),
      ('Stars          %d      Forks        %d'):format(v.stargazerCount or 0, v.forkCount or 0),
    }
    if v.primaryLanguage and v.primaryLanguage.name then
      lines[#lines + 1] = 'Language       ' .. v.primaryLanguage.name
    end
    if v.licenseInfo and v.licenseInfo.name then lines[#lines + 1] = 'License        ' .. v.licenseInfo.name end
    if v.parent and v.parent.owner then
      lines[#lines + 1] = 'Fork of        ' .. v.parent.owner.login .. '/' .. v.parent.name
    end
    if v.homepageUrl and v.homepageUrl ~= '' then lines[#lines + 1] = 'Homepage       ' .. v.homepageUrl end
    lines[#lines + 1] = 'Last push      ' .. ago(v.pushedAt)
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Enter / click: open address in browser   y: copy address   s: copy SSH URL   q: close'

    local width = 0
    for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = 'wipe'
    local h = #lines
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor', style = 'minimal', border = 'rounded',
      width = width + 2, height = h,
      row = math.max(1, math.floor((vim.o.lines - h) / 2) - 1),
      col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
      title = ' Repository ', title_pos = 'center',
    })
    vim.wo[win].cursorline = true
    vim.api.nvim_win_set_cursor(win, { 4, 0 })
    local ns = vim.api.nvim_create_namespace('github-info')
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #lines[1], hl_group = 'Title' })
    for i, l in ipairs(lines) do
      local s = l:find('https://', 1, true) or l:find('git@', 1, true)
      if s then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, s - 1, { end_col = #l, hl_group = 'Underlined' })
      end
      if i > 3 and l:match('^%u[%a %(%)]+  ') then
        local e = l:find('  ', 1, true)
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = e, hl_group = 'Comment' })
      end
    end
    vim.api.nvim_buf_set_extmark(buf, ns, #lines - 1, 0, { end_col = #lines[#lines], hl_group = 'Comment' })
    local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
    -- The address under the cursor (or the repository's), for Enter / click.
    local function address_here()
      local l = vim.api.nvim_get_current_line()
      local u = l:match('(https://%S+)')
      if u then return (u:gsub('%.git$', '')) end
      return v.url
    end
    local o = { buffer = buf, nowait = true, silent = true }
    for _, k in ipairs({ 'q', '<Esc>' }) do vim.keymap.set({ 'n', 'i' }, k, close, o) end
    vim.keymap.set('n', '<CR>', function() local u = address_here(); close(); open_url(u) end, o)
    vim.keymap.set('n', '<2-LeftMouse>', function() local u = address_here(); close(); open_url(u) end, o)
    vim.keymap.set('n', '<LeftRelease>', function()
      if vim.api.nvim_get_current_line():find('https://', 1, true) then
        local u = address_here(); close(); open_url(u)
      end
    end, o)
    vim.keymap.set('n', 'y', function() vim.fn.setreg('+', v.url); close(); info('Copied ' .. v.url) end, o)
    vim.keymap.set('n', 's', function() vim.fn.setreg('+', v.sshUrl); close(); info('Copied ' .. v.sshUrl) end, o)
    -- Typing (Vim keys off) must not land in a file window: stay in normal mode here.
    vim.cmd('stopinsert')
  end

  run({ 'gh', 'repo', 'view', '--json',
        'nameWithOwner,url,sshUrl,description,defaultBranchRef,visibility,stargazerCount,forkCount,isFork,parent,homepageUrl,licenseInfo,pushedAt,primaryLanguage' },
    function(ok, out, err)
      if ok then results.view = decode(out) else results.err = err end
      done()
    end, root)
  run({ 'gh', 'pr', 'list', '--state', 'open', '--limit', '500', '--json', 'number' }, function(ok, out)
    if ok then results.prs = #(decode(out) or {}) end
    done()
  end, root)
  run({ 'gh', 'issue', 'list', '--state', 'open', '--limit', '500', '--json', 'number' }, function(ok, out)
    if ok then results.issues = #(decode(out) or {}) end
    done()
  end, root)
end

-- ── Links to the current file ────────────────────────────────
local function url_escape(path)
  return (path:gsub('[^%w%-%._~/]', function(c) return ('%%%02X'):format(c:byte()) end))
end

local function file_link()
  local file = vim.api.nvim_buf_get_name(0)
  if file == '' or vim.bo.buftype ~= '' then warn('Not a file') return nil end
  local root = repo_root(vim.fn.fnamemodify(file, ':h'))
  if not root then warn('This file is not in a git repository') return nil end
  local r = github_remote(root)
  if not r then warn('This repository has no GitHub remote') return nil end
  local rel = vim.fs.relpath and vim.fs.relpath(root, file) or file:sub(#root + 2)
  if not rel then warn('File is outside the repository') return nil end

  -- Branch on GitHub, else the default branch (the line may differ then).
  local ref, note = nil, nil
  local up = git({ 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}' }, root)
  if up then
    ref = up:gsub('^[^/]+/', '')
  else
    local head = git({ 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD' }, root)
    ref = head and head:gsub('^origin/', '') or 'HEAD'
    note = 'this branch is not on GitHub yet; linked to ' .. ref
  end
  if not note and (vim.bo.modified
      or vim.system({ 'git', 'diff', '--quiet', 'HEAD', '--', file }, { cwd = root }):wait().code ~= 0) then
    note = 'the file has changes not on GitHub; the line numbers may not match'
  end

  local mode = vim.fn.mode()
  local a, b = vim.fn.line('.'), vim.fn.line('.')
  if mode:match('^[vV\22sS\19]') then
    a, b = vim.fn.line('v'), vim.fn.line('.')
    if a > b then a, b = b, a end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  end
  local anchor = a == b and ('#L' .. a) or ('#L%d-L%d'):format(a, b)
  return ('%s/blob/%s/%s%s'):format(r.url, url_escape(ref), url_escape(rel), anchor), note
end

local function open_file()
  local url, note = file_link(); if not url then return end
  if note then info('Note: ' .. note) end
  open_url(url)
end

local function copy_link()
  local url, note = file_link(); if not url then return end
  vim.fn.setreg('+', url)
  info('Copied ' .. url .. (note and ('\nNote: ' .. note) or ''))
end

-- ── Pull requests / issues / actions ─────────────────────────
local function pull_requests()
  if not need_github() then return end
  info('Fetching pull requests …')
  run({ 'gh', 'pr', 'list', '--state', 'open', '--limit', '100', '--json',
        'number,title,author,headRefName,isDraft,url,updatedAt' }, function(ok, out, err)
    if not ok then warn('Could not list pull requests: ' .. err) return end
    local prs = decode(out) or {}
    if #prs == 0 then info('No open pull requests') return end
    picker('Pull requests  (Enter: open in browser · Ctrl+O: check out locally)', prs, function(p)
      return ('#%-5d %s%s   %s  ·  %s  ·  %s'):format(p.number, p.isDraft and '[draft] ' or '', p.title,
        p.headRefName, (p.author or {}).login or '?', ago(p.updatedAt))
    end, {
      default = function(p) open_url(p.url) end,
      extra = {
        ['<C-o>'] = function(p)
          info('Checking out #' .. p.number .. ' …')
          run({ 'gh', 'pr', 'checkout', tostring(p.number) }, function(ok2, _, err2)
            if ok2 then
              vim.cmd('checktime')
              info('Checked out #' .. p.number .. ' (' .. p.headRefName .. ')')
            else
              warn('Check out failed: ' .. err2)
            end
          end, repo_root())
        end,
      },
    })
  end, repo_root())
end

local function branch_pr()
  if not need_github() then return end
  run({ 'gh', 'pr', 'view', '--json', 'url,number,title,state' }, function(ok, out)
    if not ok then
      local b = git({ 'branch', '--show-current' }, repo_root()) or '?'
      info('No pull request for branch ' .. b .. ' (GitHub › Create pull request…)')
      return
    end
    local p = decode(out)
    info(('#%d %s (%s)'):format(p.number, p.title, (p.state or ''):lower()))
    open_url(p.url)
  end, repo_root())
end

local function create_pr()
  if not need_github() then return end
  -- gh's own prompts (title, body, base; offers to push the branch).
  terminal({ 'gh', 'pr', 'create' }, 'create pull request')
end

local function issues()
  if not need_github() then return end
  info('Fetching issues …')
  run({ 'gh', 'issue', 'list', '--state', 'open', '--limit', '100', '--json',
        'number,title,author,labels,url,updatedAt' }, function(ok, out, err)
    if not ok then warn('Could not list issues: ' .. err) return end
    local list = decode(out) or {}
    if #list == 0 then info('No open issues') return end
    picker('Issues  (Enter: open in browser)', list, function(i)
      local labels = vim.tbl_map(function(l) return l.name end, i.labels or {})
      return ('#%-5d %s%s   %s  ·  %s'):format(i.number, i.title,
        #labels > 0 and ('  [' .. table.concat(labels, ', ') .. ']') or '',
        (i.author or {}).login or '?', ago(i.updatedAt))
    end, { default = function(i) open_url(i.url) end })
  end, repo_root())
end

local function new_issue()
  if not need_github() then return end
  run({ 'gh', 'issue', 'create', '--web' }, function(ok, _, err)
    if not ok then warn('Could not open the new-issue page: ' .. err) end
  end, repo_root())
end

local RUN_ICON = { success = '✓', failure = '✗', cancelled = '⊘', skipped = '↷' }

local function actions()
  if not need_github() then return end
  info('Fetching workflow runs …')
  run({ 'gh', 'run', 'list', '--limit', '40', '--json',
        'displayTitle,status,conclusion,headBranch,event,workflowName,createdAt,url' }, function(ok, out, err)
    if not ok then warn('Could not list workflow runs: ' .. err) return end
    local runs = decode(out) or {}
    if #runs == 0 then info('No workflow runs (no GitHub Actions in this repository?)') return end
    picker('Actions: recent workflow runs  (Enter: open in browser)', runs, function(x)
      local state = x.status == 'completed' and (x.conclusion or '') or x.status
      return ('%s %-10s %-18s %-16s %s  ·  %s'):format(RUN_ICON[x.conclusion] or '●', state,
        x.workflowName or '', x.headBranch or '', x.displayTitle or '', ago(x.createdAt))
    end, { default = function(x) open_url(x.url) end })
  end, repo_root())
end

-- ── Account ──────────────────────────────────────────────────
local function account()
  run({ 'gh', 'auth', 'status' }, function(ok, out, err)
    local text = vim.trim(out .. '\n' .. err)
    if ok then
      info(text)
    else
      local choice = vim.fn.confirm('Not signed in to GitHub.\nSign in now?', '&Sign in\n&Cancel', 1)
      if choice == 1 then terminal({ 'gh', 'auth', 'login' }, 'sign in') end
    end
  end)
end

-- ── Keymaps ──────────────────────────────────────────────────
map('GC', clone, 'clone a repository…')
map('GR', publish, 'publish this folder to GitHub…')
map('Go', open_repo, 'open repository on GitHub (browser)')
map('Gi', repo_info, 'repository info (address, clone URLs, …)')
map('Gf', open_file, 'open this file on GitHub', { 'n', 'x' })
map('Gy', copy_link, 'copy GitHub link to this line', { 'n', 'x' })
map('Gp', pull_requests, 'pull requests…')
map('Gv', branch_pr, "this branch's pull request")
map('GP', create_pr, 'create pull request…')
map('Gs', issues, 'issues…')
map('GI', new_issue, 'new issue… (browser)')
map('Ga', actions, 'actions: recent workflow runs…')
map('GA', account, 'GitHub account / sign in')

-- ── State column ─────────────────────────────────────────────
local REPO_KEYS = { Go = true, Gi = true, Gf = true, Gy = true, Gp = true, Gv = true, GP = true,
                    Gs = true, GI = true, Ga = true }

function M.state(key)
  if not REPO_KEYS[key] then return nil end
  if not repo_root() then return { text = 'not in a repository', dim = true } end
  local r = github_remote()
  if not r then return { text = 'no GitHub remote', dim = true } end
  if key == 'Go' then return { text = r.url:gsub('^https://', ''), dim = false } end
  return nil
end

if vim.fn.executable('gh') == 0 then
  vim.schedule(function() warn('GitHub menu: the gh command is not installed') end)
end

return M
