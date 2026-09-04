-- ============================================================
-- plugins/neo-tree.lua — File explorer
--
-- Neo-tree provides a sidebar file tree, buffer list, and git
-- status view. Configured to:
--   • Follow the current file automatically
--   • Show gitignored and dotfiles at startup; H toggles the filter on
--     (then only non-ignored, non-dot files remain). .git is never shown.
--   • Open alongside a file when Neovim starts
--   • NOT steal focus when toggleterm closes (handled in toggleterm.lua)
--   • Show "← .." at top of tree for navigating to parent directory
--     (injected via renderer.show_nodes monkey-patch; see bottom of file)
--   • Switch to filesystem source automatically on :cd (DirChanged autocmd)
--     so a stale buffers/git panel is never left open after changing project
--
-- Keymaps:
--   \          — reveal current file in neo-tree (or open tree)
--   <leader>\  — show and focus open buffers in neo-tree
--   t          — toggle bottom terminal (open → close → open); cd on open
--   <leader>jq — stop all running JupyterLab servers (global)
--
-- LAZY: No — neo-tree opens at startup and must be ready immediately.
-- ============================================================

local gh = require('core.utils').gh

local plugins = {
  { src = gh 'nvim-neo-tree/neo-tree.nvim', version = vim.version.range '3.*' },
  { src = gh 'nvim-lua/plenary.nvim',       version = vim.version.range '*' },
  { src = gh 'MunifTanjim/nui.nvim',        version = vim.version.range '*' },
}
if vim.g.have_nerd_font then
  -- no version pin: its only tag (v0.100) is not parseable semver,
  -- so vim.pack can offer no matching release — branch tracking only
  table.insert(plugins, gh 'nvim-tree/nvim-web-devicons')
end
vim.pack.add(plugins)

-- ── JupyterLab helpers ───────────────────────────────────────
-- `jupyter-lab <file>` starts a BRAND NEW server on every invocation, each on
-- the next free port and each holding a kernel (~190 MB resident). Six of them
-- accumulated in one session here and held 1.8 GB, which is enough to push the
-- browser into the OOM killer while it renders a plot-heavy notebook. So reuse
-- a running server whenever one already serves a directory containing the file.
--
-- Reuse fixes the browser choice too. A fresh `jupyter-lab` hands the browser a
-- file:// URL to a generated jpserver-<pid>-open.html, so xdg-open routes it by
-- text/html and NOT by x-scheme-handler/http. Opening the server's own URL
-- keeps it an http:// URL, which lands in the XDG default browser.
--
-- Needs the `jupyter` CLI on PATH. pipx only links jupyter-lab, so this is a
-- symlink: ~/.local/bin/jupyter -> the jupyterlab venv's bin/jupyter.
local function jupyter_servers()
  local out = vim.fn.system({ 'jupyter', 'server', 'list', '--json' })
  if vim.v.shell_error ~= 0 then return {} end
  local servers = {}
  for line in out:gmatch('[^\r\n]+') do
    local ok, srv = pcall(vim.json.decode, line)
    if ok and type(srv) == 'table' and srv.url then servers[#servers + 1] = srv end
  end
  return servers
end

-- URL of `path` on an already-running server, or nil if none serves it.
local function jupyter_url_for(path)
  for _, srv in ipairs(jupyter_servers()) do
    local root = srv.root_dir
    if root then
      local prefix = (root == '/') and '/' or (root .. '/')
      if path:sub(1, #prefix) == prefix then
        -- percent-encode only what actually turns up in notebook paths
        local rel = path:sub(#prefix + 1):gsub('[ #?%%]',
          function(c) return string.format('%%%02X', c:byte()) end)
        local token = (srv.token and srv.token ~= '') and ('?token=' .. srv.token) or ''
        return srv.url .. 'lab/tree/' .. rel .. token
      end
    end
  end
  return nil
end

-- ── Keymaps ──────────────────────────────────────────────────
vim.keymap.set('n', '\\', '<Cmd>Neotree reveal<CR>',
  { desc = 'Neo-tree: reveal file', silent = true })

-- <leader>\ opens the buffers view and moves focus into the neo-tree window
vim.keymap.set('n', '<leader>\\', function()
  vim.cmd('Neotree show buffers left')
  -- vim.schedule waits for the event loop to process the Neotree command
  -- (window creation is synchronous but queued) before we scan for the window.
  vim.schedule(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'neo-tree' then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  end)
end, { desc = 'Neo-tree: focus buffer list', silent = true })

-- Stop ALL running JupyterLab servers (mirrors File > Shutdown in the browser).
-- Use after closing notebook tabs so servers do not linger in the background.
-- `jupyter lab stop` with no argument only stops the one on the default port
-- (8888), so servers on 8889+ used to survive it and pile up unnoticed.
vim.keymap.set('n', '<leader>jq', function()
  local servers = jupyter_servers()
  if #servers == 0 then
    vim.notify('No running JupyterLab server found', vim.log.levels.WARN)
    return
  end
  for _, srv in ipairs(servers) do
    vim.fn.system({ 'jupyter', 'server', 'stop', tostring(srv.port) })
  end
  vim.notify(('Stopped %d JupyterLab server(s)'):format(#servers), vim.log.levels.INFO)
end, { desc = 'Jupyter: stop all servers' })

-- ── Helpers ───────────────────────────────────────────────────
-- On the "← .." nav node call navigate_up.
-- On a .ipynb file spawn jupyter-lab in the browser (detached).
-- Everywhere else call the standard open command.
local function open_or_up(state)
  local node = state.tree:get_node()
  if node and node.id == '__nav_up__' then
    require('neo-tree.sources.filesystem.commands').navigate_up(state)
  elseif node and node.type == 'file' and node.name:match('%.ipynb$') then
    local path = node:get_id()
    local url = jupyter_url_for(path)
    if url then
      -- an http:// URL, so xdg-open routes it by x-scheme-handler/http
      vim.fn.jobstart({ 'xdg-open', url }, { detach = true })
      vim.notify('Opening ' .. node.name .. ' in the running JupyterLab', vim.log.levels.INFO)
    else
      -- No server yet. Starting one makes it open a file:// jpserver-*-open.html,
      -- which xdg-open routes by text/html -- so that mapping has to point at the
      -- same browser as x-scheme-handler/http (see ~/.config/mimeapps.list).
      vim.fn.jobstart({ 'jupyter-lab', path }, { detach = true, env = { BROWSER = 'xdg-open' } })
      vim.notify('Starting JupyterLab for ' .. node.name, vim.log.levels.INFO)
    end
  elseif node and node.type == 'file' and node.name:match('%.html$') then
    vim.fn.jobstart({ 'xdg-open', node:get_id() }, { detach = true })
    vim.notify('Opening ' .. node.name .. ' in browser', vim.log.levels.INFO)
  elseif node and node.type == 'directory' then
    -- Toggle expand/collapse (the generic 'open' command is easy to call
    -- without the filesystem toggle_directory hook).
    require('neo-tree.sources.filesystem.commands').open(state)
  else
    state.commands['open'](state)
  end
end

-- Move the node under the cursor to the system trash — no confirmation.
-- Unlike the built-in 'delete' (permanent rm), trashed items land in
-- ~/.local/share/Trash and can be restored with a file manager or
-- `gio trash --restore <uri>` (list URIs with `gio trash --list`).
local function trash_node(state)
  local node = state.tree:get_node()
  if not node or node.id == '__nav_up__' then return end
  if node:get_depth() == 1 then
    vim.notify('neo-tree: will not trash the root node', vim.log.levels.WARN)
    return
  end
  local path = node.path or node:get_id()
  local t0 = os.time()
  vim.fn.system({ 'gio', 'trash', path })
  if vim.v.shell_error ~= 0 then
    vim.notify('gio trash failed for ' .. path, vim.log.levels.ERROR)
    return
  end
  -- Wipe buffers for the trashed file (or files under a trashed directory)
  -- so a stray :w doesn't resurrect it. Windows showing one fall back to
  -- another buffer automatically.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local bname = vim.api.nvim_buf_get_name(buf)
    if bname == path or vim.startswith(bname, path .. '/') then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  local events = require('neo-tree.events')
  events.fire_event(events.FILE_DELETED, path)
  -- Report where the file landed. gio renames on collisions (name.2.txt),
  -- so find our entry by matching the original path recorded in the
  -- .trashinfo files written since the trash call — only those fresh
  -- entries are read, not the whole trash.
  local trash = vim.fn.expand('~/.local/share/Trash')
  local best, best_t
  for fname in vim.fs.dir(trash .. '/info') do
    local st = vim.uv.fs_stat(trash .. '/info/' .. fname)
    local t = st and (st.mtime.sec + st.mtime.nsec / 1e9) or 0
    if t >= t0 and (not best_t or t > best_t) then
      for _, line in ipairs(vim.fn.readfile(trash .. '/info/' .. fname, '', 5)) do
        local p = line:match('^Path=(.*)$')
        if p then
          -- Path may be percent-encoded per the freedesktop trash spec
          p = p:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
          if p == path then
            best, best_t = fname:match('^(.*)%.trashinfo$') or fname, t
          end
        end
      end
    end
  end
  local msg = 'Trashed ' .. node.name
  if best then
    msg = msg .. ' → ' .. vim.fn.fnamemodify(trash .. '/files/' .. best, ':~')
  end
  vim.notify(msg, vim.log.levels.INFO)
end

-- The global signcolumn=yes bleeds into the neo-tree window; suppress it.
-- winfixwidth protects the sidebar from 'equalalways': without it, opening
-- or (especially) closing splits elsewhere — e.g. the git.lua diff-review
-- workflow's close-then-reopen dance — redistributes width across every
-- window in the tabpage and can leave neo-tree nearly full-width.
vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'neo-tree',
  callback = function()
    vim.wo.signcolumn  = 'no'
    vim.wo.winfixwidth = true
  end,
})

-- ── Setup ────────────────────────────────────────────────────
require('neo-tree').setup {

  window = {
    width = 30,
    mappings = {
      ['\\']            = 'close_window',
      ['<CR>']          = open_or_up,
      ['<2-LeftMouse>'] = open_or_up,
      -- `o` is deliberately NOT mapped to open: it is the prefix of
      -- neo-tree's built-in ordering commands (om = by modified, on = by
      -- name, os = by size, …), and mapping it shadowed all of them —
      -- window.mapping_options defaults to nowait = true, so `o` fired
      -- instantly and the second key was never read. Opening is already
      -- covered twice over by <CR> and a double-click, so the prefix is
      -- worth more here than a third way to open a node. Press `o` alone
      -- to get neo-tree's "Order by" popup, which lists the whole set.
      ['s']             = 'open_split',
      ['v']             = 'open_vsplit',
      ['<BS>']          = 'navigate_up',
      ['.']             = 'set_root',
      ['a']             = { 'add', config = { show_path = 'relative' } },
      ['d']             = trash_node,  -- to trash, no confirm (built-in 'delete' rms permanently)
      ['r']             = 'rename',
      ['c']             = 'copy',
      ['m']             = 'move',
      ['y']             = 'copy_to_clipboard',
      ['x']             = 'cut_to_clipboard',
      ['p']             = 'paste_from_clipboard',
      ['R']             = 'refresh',
      ['?']             = 'show_help',

      -- Execute the selected file if it has the executable bit set.
      ['X'] = function(state)
        local node = state.tree:get_node()
        if node.type ~= 'file' then
          vim.notify('neo-tree: X only works on files', vim.log.levels.WARN)
          return
        end
        local path = node:get_id()
        if vim.fn.executable(path) ~= 1 then
          vim.notify('neo-tree: ' .. vim.fn.fnamemodify(path, ':t') .. ' is not executable',
            vim.log.levels.WARN)
          return
        end
        local dir   = vim.fn.fnamemodify(path, ':h')
        local terms = require('toggleterm.terminal')
        local term, is_new = terms.get_or_create_term(1, dir, 'horizontal')
        if is_new then
          -- Terminal:open() spawns the shell job synchronously (open →
          -- spawn → termopen sets job_id before returning), so send works
          -- immediately — the PTY buffers the input until the shell reads it.
          term:open(15)
          term:send(vim.fn.shellescape(path))
        else
          if not term:is_open() then term:open(15) end
          term:change_dir(dir)
          term:send(vim.fn.shellescape(path))
        end
      end,

      -- Toggle the bottom toggleterm terminal.
      -- Open: cd into the node's directory and focus the terminal.
      -- Close: hide the terminal (process keeps running) and return focus.
      ['t'] = function(state)
        local node = state.tree:get_node()
        if not node then return end
        local dir
        if node.id == '__nav_up__' then
          dir = vim.fn.fnamemodify(state.path, ':h')
        elseif node.type == 'directory' then
          dir = node:get_id()
        else
          dir = vim.fn.fnamemodify(node:get_id(), ':h')
        end

        -- Don't cd into .git internals; use the repo root instead.
        dir = dir:gsub('/%.git$', ''):gsub('/%.git/', '/')
        if dir == '' then dir = '/' end

        local terms = require('toggleterm.terminal')
        local term, is_new = terms.get_or_create_term(1, dir, 'horizontal')
        if is_new then
          term:open(15)
        elseif term:is_open() then
          term:close()
        else
          term:open(15)
          term:change_dir(dir)
        end
      end,

      -- Telescope search scoped to the directory under the cursor
      ['/'] = function(state)
        local node = state.tree:get_node()
        local dir  = node.type == 'directory'
          and node:get_id()
          or vim.fn.fnamemodify(node:get_id(), ':h')
        require('telescope.builtin').find_files {
          cwd          = dir,
          hidden       = true,
          no_ignore    = true,
          prompt_title = 'Find files in ' .. vim.fn.fnamemodify(dir, ':~:.'),
        }
      end,

      ['g/'] = function(state)
        local node = state.tree:get_node()
        local dir  = node.type == 'directory'
          and node:get_id()
          or vim.fn.fnamemodify(node:get_id(), ':h')
        require('telescope.builtin').live_grep {
          cwd          = dir,
          prompt_title = 'Live grep in ' .. vim.fn.fnamemodify(dir, ':~:.'),
        }
      end,
    },
  },

  filesystem = {
    -- Gitignored directories keep the normal directory color instead of
    -- the grey NeoTreeGitIgnored that the stock name/icon components pick
    -- for anything gitignored. Ignored FILES stay grey — only directories
    -- opt out, so untracked/modified colors on dirs are preserved too
    -- (the swap only fires when the computed highlight is the grey one).
    components = {
      name = function(config, node, state)
        local result = require('neo-tree.sources.common.components').name(config, node, state)
        local hl = require('neo-tree.ui.highlights')
        if node.type == 'directory'
            and (result.highlight == hl.GIT_IGNORED or result.highlight == hl.DIM_TEXT) then
          result.highlight = hl.DIRECTORY_NAME
        end
        return result
      end,
      icon = function(config, node, state)
        local result = require('neo-tree.sources.common.components').icon(config, node, state)
        local hl = require('neo-tree.ui.highlights')
        if node.type == 'directory'
            and (result.highlight == hl.GIT_IGNORED or result.highlight == hl.DIM_TEXT) then
          result.highlight = hl.DIRECTORY_ICON
        end
        return result
      end,
    },
    window = {
      mappings = {
        ['H'] = 'toggle_hidden',
      },
    },
    bind_to_cwd = true,
    cwd_target   = { sidebar = 'global', current = 'global' },

    follow_current_file = {
      enabled         = true,
      leave_dirs_open = true,
    },

    use_libuv_file_watcher = true,
    hijack_netrw_behavior  = 'open_current',

    filtered_items = {
      -- Start with the filter off so workdata/, build/, etc. are listed.
      -- H flips `visible`: false then hides gitignored + dotfiles.
      -- never_show wins even when visible is true, so .git never dumps
      -- object internals into the tree.
      visible         = true,
      hide_dotfiles   = true,
      hide_gitignored = true,
      never_show      = { '.git' },
    },
  },

  -- Custom renderer for the virtual "← .." navigate-up node injected below.
  renderers = {
    nav_up = {
      { 'indent', with_markers = false },
      { 'name' },
    },
  },

  close_if_last_window = false,  -- keep panel open as anchor for WinClosed recovery
  enable_git_status    = true,
  enable_diagnostics   = true,

  git_status = {
    window = {
      mappings = {
        ['A']  = 'git_add_all',
        ['gu'] = 'git_unstage_file',
        ['ga'] = 'git_add_file',
        ['gr'] = 'git_revert_file',
        ['gc'] = 'git_commit',
        ['gp'] = 'git_push',
        ['gg'] = 'git_commit_and_push',
      },
    },
  },

  buffers = {
    follow_current_file = { enabled = true },
    window = {
      mappings = { ['d'] = 'buffer_delete' },
    },
  },

  default_component_configs = {
    indent = {
      indent_size        = 2,
      padding            = 0,
      with_markers       = true,
      indent_marker      = '│',
      last_indent_marker = '└',
      highlight          = 'NeoTreeIndentMarker',
      with_expanders     = true,
      expander_collapsed = '',
      expander_expanded  = '',
      expander_highlight = 'NeoTreeExpander',
    },
    icon = {
      folder_closed = '',
      folder_open   = '',
      folder_empty  = '󰜌',
    },
    name = {
      trailing_slash        = false,
      use_git_status_colors = true,
    },
    git_status = {
      symbols = {
        added     = '✚',
        modified  = '',
        deleted   = '✖',
        renamed   = '󰁕',
        untracked = '',
        ignored   = '',
        unstaged  = '󰄱',
        staged    = '',
        conflict  = '',
      },
    },
  },
}

-- ── "← .." navigate-up node ──────────────────────────────────
-- Neo-tree has no built-in parent-navigation entry. We inject one by
-- wrapping renderer.show_nodes: on every full filesystem tree render
-- (parentId == nil) a virtual nav_up item is prepended to sourceItems.
-- The open_or_up mapping above handles clicks/Enter on that node.
-- This is a monkey-patch of neo-tree internals, so it is guarded to fail
-- LOUDLY instead of mysteriously when a neo-tree update changes shape:
--   • if renderer.show_nodes no longer exists, the patch is skipped with
--     a warning (tree still works, just without the "← .." entry)
--   • if the injection itself ever errors (e.g. state.name semantics
--     change), it warns once and passes items through unpatched.
do
  local ok, renderer = pcall(require, 'neo-tree.ui.renderer')
  if not ok or type(renderer.show_nodes) ~= 'function' then
    vim.notify(
      'neo-tree "← .." patch disabled: renderer.show_nodes not found — '
      .. 'neo-tree internals changed with an update. Tree works normally; '
      .. 'update the patch in plugins/neo-tree.lua to restore the entry.',
      vim.log.levels.WARN)
  else
    local orig = renderer.show_nodes
    local warned = false
    renderer.show_nodes = function(sourceItems, state, parentId, callback)
      local inject_ok, patched = pcall(function()
        if state.name == 'filesystem' and parentId == nil
            and sourceItems and #sourceItems > 0 then
          local items = { {
            id    = '__nav_up__',
            name  = '← ..',
            type  = 'nav_up',
            level = 0,
            extra = {},
            is_last_child = false,
          } }
          for _, v in ipairs(sourceItems) do
            table.insert(items, v)
          end
          return items
        end
        return sourceItems
      end)
      if inject_ok then
        sourceItems = patched
      elseif not warned then
        warned = true
        vim.notify(
          'neo-tree "← .." injection failed (internals changed?): '
          .. tostring(patched) .. '\nRendering unpatched items.',
          vim.log.levels.WARN)
      end
      return orig(sourceItems, state, parentId, callback)
    end
  end
end

-- ── Switch to filesystem on :cd ──────────────────────────────
-- When cwd changes (e.g. :cd ~/project) switch the sidebar back to the
-- filesystem source so the user sees the new directory, not a stale
-- buffers/git panel left open from a previous <leader>\ invocation.
--
-- Registered inside VimEnter so it is never active during plugin
-- installation: vim.pack.add fires DirChanged while cloning packages
-- (before VimEnter), which would otherwise trigger this callback before
-- the Neotree command is registered.
local function on_cwd_change()
  require('core.utils').try('Neo-tree open', 'Neotree show filesystem left')
end

local dir_group = vim.api.nvim_create_augroup('neo-tree-cwd', { clear = true })
if vim.v.vim_did_enter == 1 then
  vim.api.nvim_create_autocmd('DirChanged', { group = dir_group, callback = on_cwd_change })
else
  vim.api.nvim_create_autocmd('VimEnter', {
    group    = dir_group,
    once     = true,
    callback = function()
      vim.api.nvim_create_autocmd('DirChanged', {
        group    = dir_group,
        callback = on_cwd_change,
      })
    end,
  })
end

-- ── Startup behaviour ─────────────────────────────────────────
-- UIEnter fires after every VimEnter handler has run — including
-- session.lua's restore, which sets vim.g.session_loaded — so this
-- ordering is guaranteed by Neovim's startup sequence rather than by
-- hoping a timer (previously 50ms) lands late enough on a loaded machine.
vim.api.nvim_create_autocmd('UIEnter', {
  once     = true,
  callback = function()
    -- When a session was restored (plugins/session.lua sets this flag on
    -- VimEnter, which fires before UIEnter), our buffers and window
    -- layout are already in place — skip the 'enew' step that would wipe
    -- the restored current buffer, and just ensure neo-tree is visible.
    if vim.g.session_loaded then
      require('core.utils').try('Neo-tree open', 'Neotree show filesystem left')
      return
    end

    local argc    = vim.fn.argc()
    local arg0    = argc > 0 and vim.fn.argv(0) or ''
    local is_dir  = vim.fn.isdirectory(arg0) == 1

    if argc == 0 or is_dir then
      local original_buf = vim.api.nvim_get_current_buf()
      if is_dir then
        vim.cmd('cd ' .. vim.fn.fnameescape(vim.fn.fnamemodify(arg0, ':p')))
      end
      vim.cmd('enew')
      pcall(vim.api.nvim_buf_delete, original_buf, { force = true })
      require('core.utils').try('Neo-tree open', 'Neotree show filesystem left')
    else
      require('core.utils').try('Neo-tree open', 'Neotree show filesystem left')
    end
  end,
})
