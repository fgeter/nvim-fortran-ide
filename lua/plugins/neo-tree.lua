-- ============================================================
-- plugins/neo-tree.lua — File explorer
--
-- Neo-tree provides a sidebar file tree, buffer list, and git
-- status view. Configured to:
--   • Follow the current file automatically
--   • Hide dotfiles and gitignored files by default; H toggles them
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

local function gh(repo) return 'https://github.com/' .. repo end

local plugins = {
  { src = gh 'nvim-neo-tree/neo-tree.nvim', version = vim.version.range '*' },
  gh 'nvim-lua/plenary.nvim',
  gh 'MunifTanjim/nui.nvim',
}
if vim.g.have_nerd_font then
  table.insert(plugins, gh 'nvim-tree/nvim-web-devicons')
end
vim.pack.add(plugins)

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

-- Stop all running JupyterLab servers (mirrors File > Shutdown in the browser).
-- Use after closing notebook tabs to prevent the server lingering in the background.
vim.keymap.set('n', '<leader>jq', function()
  vim.fn.jobstart({ 'jupyter', 'lab', 'stop' }, {
    on_exit = function(_, code)
      if code == 0 then
        vim.notify('JupyterLab server stopped', vim.log.levels.INFO)
      else
        vim.notify('No running JupyterLab server found', vim.log.levels.WARN)
      end
    end,
  })
end, { desc = 'Jupyter: stop server' })

-- ── Helpers ───────────────────────────────────────────────────
-- On the "← .." nav node call navigate_up.
-- On a .ipynb file spawn jupyter-lab in the browser (detached).
-- Everywhere else call the standard open command.
local function open_or_up(state)
  local node = state.tree:get_node()
  if node and node.id == '__nav_up__' then
    require('neo-tree.sources.filesystem.commands').navigate_up(state)
  elseif node and node.type == 'file' and node.name:match('%.ipynb$') then
    vim.fn.jobstart({ 'jupyter-lab', node:get_id() }, { detach = true })
    vim.notify('Opening ' .. node.name .. ' in JupyterLab', vim.log.levels.INFO)
  elseif node and node.type == 'file' and node.name:match('%.html$') then
    vim.fn.jobstart({ 'xdg-open', node:get_id() }, { detach = true })
    vim.notify('Opening ' .. node.name .. ' in browser', vim.log.levels.INFO)
  else
    state.commands['open'](state)
  end
end

-- ── Setup ────────────────────────────────────────────────────
require('neo-tree').setup {

  window = {
    width = 35,
    mappings = {
      ['\\']            = 'close_window',
      ['<CR>']          = open_or_up,
      ['<2-LeftMouse>'] = open_or_up,
      ['o']             = open_or_up,
      ['s']             = 'open_split',
      ['v']             = 'open_vsplit',
      ['<BS>']          = 'navigate_up',
      ['.']             = 'set_root',
      ['a']             = { 'add', config = { show_path = 'relative' } },
      ['d']             = 'delete',
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
          term:open(15)
          vim.defer_fn(function() term:send(vim.fn.shellescape(path)) end, 200)
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
      visible         = false,  -- truly hide filtered items; H toggles them back
      hide_dotfiles   = true,
      hide_gitignored = true,
    },
  },

  -- Custom renderer for the virtual "← .." navigate-up node injected below.
  renderers = {
    nav_up = {
      { 'indent', with_markers = false },
      { 'name' },
    },
  },

  enable_git_status  = true,
  enable_diagnostics = true,

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
      padding            = 1,
      with_markers       = true,
      indent_marker      = '│',
      last_indent_marker = '└',
      highlight          = 'NeoTreeIndentMarker',
      with_expanders     = true,
      expander_collapsed = '',
      expander_expanded  = '',
      expander_highlight = 'NeoTreeExpander',
    },
    icon = {
      folder_closed = '',
      folder_open   = '',
      folder_empty  = '󰜌',
    },
    name = {
      trailing_slash        = false,
      use_git_status_colors = true,
    },
    git_status = {
      symbols = {
        added     = '✚',
        modified  = '',
        deleted   = '✖',
        renamed   = '󰁕',
        untracked = '',
        ignored   = '',
        unstaged  = '󰄱',
        staged    = '',
        conflict  = '',
      },
    },
  },
}

-- ── "← .." navigate-up node ──────────────────────────────────
-- Neo-tree has no built-in parent-navigation entry. We inject one by
-- wrapping renderer.show_nodes: on every full filesystem tree render
-- (parentId == nil) a virtual nav_up item is prepended to sourceItems.
-- The open_or_up mapping above handles clicks/Enter on that node.
do
  local renderer = require('neo-tree.ui.renderer')
  local orig = renderer.show_nodes
  renderer.show_nodes = function(sourceItems, state, parentId, callback)
    if state.name == 'filesystem' and parentId == nil
        and sourceItems and #sourceItems > 0 then
      local patched = { {
        id    = '__nav_up__',
        name  = '← ..',
        type  = 'nav_up',
        level = 0,
        extra = {},
        is_last_child = false,
      } }
      for _, v in ipairs(sourceItems) do
        table.insert(patched, v)
      end
      sourceItems = patched
    end
    return orig(sourceItems, state, parentId, callback)
  end
end

-- ── Smart :q behaviour with neo-tree ────────────────────────
-- Bare :q on the last editor window switches to the next listed buffer
-- instead of closing the window (which would leave only neo-tree visible).
-- :q! / :qa / :qa! are unaffected — only bare :q is intercepted.
-- If no other listed buffers exist, :q quits Neovim as normal.
vim.api.nvim_create_user_command('SmartQ', function()
  local editor_wins = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= 'neo-tree' then
        editor_wins = editor_wins + 1
      end
    end
  end

  if editor_wins > 1 then
    -- Multiple editor splits: close just this window normally
    vim.cmd('quit')
    return
  end

  -- Last editor window: switch to another listed buffer rather than
  -- closing the window and leaving only neo-tree visible.
  local cur    = vim.api.nvim_get_current_buf()
  local others = vim.tbl_filter(
    function(b) return b.bufnr ~= cur end,
    vim.fn.getbufinfo({ buflisted = 1 })
  )
  if #others > 0 then
    vim.api.nvim_win_set_buf(0, others[1].bufnr)
    pcall(vim.api.nvim_buf_delete, cur, { force = false })
  else
    vim.cmd('quit')
  end
end, {})

vim.cmd([[cnoreabbrev <expr> q getcmdtype() ==# ':' && getcmdline() ==# 'q' ? 'SmartQ' : 'q']])

-- ── Switch to filesystem on :cd ──────────────────────────────
-- When cwd changes (e.g. :cd ~/project) switch the sidebar back to the
-- filesystem source so the user sees the new directory, not a stale
-- buffers/git panel left open from a previous <leader>\ invocation.
--
-- Registered inside VimEnter so it is never active during plugin
-- installation: vim.pack.add fires DirChanged while cloning packages
-- (before VimEnter), which would otherwise trigger this callback before
-- the Neotree command is registered.
vim.api.nvim_create_autocmd('DirChanged', {
  callback = function()
    pcall(vim.cmd, 'Neotree show filesystem left')
  end,
})

-- ── Startup behaviour ─────────────────────────────────────────
vim.defer_fn(function()
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
    pcall(vim.cmd, 'Neotree show filesystem left')
  else
    pcall(vim.cmd, 'Neotree show filesystem left')
  end
end, 50)
