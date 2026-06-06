-- ============================================================
-- plugins/neo-tree.lua — File explorer
--
-- Neo-tree provides a sidebar file tree, buffer list, and git
-- status view. Configured to:
--   • Follow the current file automatically
--   • Show hidden and gitignored files
--   • Open alongside a file when Neovim starts
--   • NOT steal focus when toggleterm closes (handled in toggleterm.lua)
--
-- Keymaps:
--   \       — reveal current file in neo-tree (or open tree)
--   <leader>\ — show open buffers in neo-tree
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
-- \ reveals the current file in the filesystem tree (or opens the tree
-- if it is closed). Inside neo-tree, \ closes the window.
vim.keymap.set('n', '\\',          '<Cmd>Neotree reveal<CR>',       { desc = 'Neo-tree: reveal file',    silent = true })
-- <leader>\ opens the buffers view in neo-tree and moves focus into it.
-- Step 1: Neotree show opens/switches the panel to the buffers source.
-- Step 2: vim.defer_fn finds the neo-tree window and sets it as current
--         so the cursor lands there ready to navigate.
-- The defer is necessary because neo-tree opens asynchronously — trying
-- to focus the window in the same tick finds nothing yet.
vim.keymap.set('n', '<leader>\\', function()
  vim.cmd('Neotree show buffers left')
  vim.defer_fn(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == 'neo-tree' then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  end, 50)
end, { desc = 'Neo-tree: focus buffer list', silent = true })

-- ── Setup helpers ────────────────────────────────────────────
-- Open the node under the cursor, or navigate to the parent directory
-- when on line 1 (the root-header line). Line 1 is always the root in
-- neo-tree's filesystem view regardless of which directory is shown.
local function open_or_navigate_up(state)
  if vim.fn.line('.') == 1 then
    require('neo-tree.sources.filesystem.commands').navigate_up(state)
  else
    require('neo-tree.sources.filesystem.commands').open(state)
  end
end

-- ── Setup ────────────────────────────────────────────────────
require('neo-tree').setup {
  filesystem = {
    -- Keep neo-tree's root in sync with Neovim's global cwd
    bind_to_cwd = true,
    cwd_target   = { sidebar = 'global', current = 'global' },

    -- Automatically scroll the tree to show the file in the active buffer
    follow_current_file = {
      enabled         = true,
      leave_dirs_open = true,  -- don't collapse parent dirs when switching files
    },

    -- Use libuv filesystem watchers for real-time updates (no manual refresh needed)
    use_libuv_file_watcher = true,

    -- Prevent netrw from opening instead of neo-tree when you open a directory
    hijack_netrw_behavior = 'open_current',

    -- Show hidden files and gitignored files (toggle with H inside the tree)
    filtered_items = {
      visible         = true,
      hide_dotfiles   = false,
      hide_gitignored = false,
    },

    window = {
      width = 35,
      mappings = {
        -- Toggle the tree closed with the same key that opens it
        ['\\']            = 'close_window',
        -- Open / expand — routes through open_or_navigate_up so that
        -- selecting the '..' entry navigates to the parent directory.
        ['<CR>']          = open_or_navigate_up,
        ['<2-LeftMouse>'] = open_or_navigate_up,
        ['o']             = open_or_navigate_up,
        ['s']             = 'open_split',
        ['v']             = 'open_vsplit',
        -- Navigation
        ['<bs>']          = 'navigate_up',    -- go up one directory
        ['.']             = 'set_root',       -- make this dir the tree root
        -- File operations
        ['a']             = { 'add', config = { show_path = 'relative' } },
        ['d']             = 'delete',
        ['r']             = 'rename',
        ['c']             = 'copy',
        ['m']             = 'move',
        ['y']             = 'copy_to_clipboard',
        ['x']             = 'cut_to_clipboard',
        ['p']             = 'paste_from_clipboard',
        -- Visibility
        ['H']             = 'toggle_hidden',  -- show/hide dotfiles
        ['R']             = 'refresh',
        ['?']             = 'show_help',
      },
    },

    -- Custom command: cd into the node's directory with .
    -- (overrides set_root to also change Neovim's global cwd)
  },

  enable_git_status  = true,
  enable_diagnostics = true,

  -- Git status source keymaps
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

  -- Buffer source: shows open buffers like a buffer list
  buffers = {
    follow_current_file = { enabled = true },
    window = {
      mappings = { ['d'] = 'buffer_delete' },
    },
  },

  -- Icon and indent styling
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

-- ── Root-header hint ──────────────────────────────────────────
-- Stamp '← ..' as EOL virtual text on line 1 of the neo-tree buffer after
-- every render. Uses nvim_buf_attach so the extmark is re-applied on ALL
-- buffer writes — both the full show_nodes path and the renderer.redraw
-- path (git-status refresh, file-watch events, expand/collapse), which do
-- not fire the AFTER_RENDER event and would otherwise leave the hint missing.
-- vim.schedule batches the on_bytes calls from one render into a single apply.
vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'neo-tree',
  callback = function(args)
    local buf = args.buf
    local ns  = vim.api.nvim_create_namespace('neo_tree_up_hint')

    local function apply()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if vim.api.nvim_buf_line_count(buf) < 1 then return end
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
        virt_text     = { { '  ← ..', 'Comment' } },
        virt_text_pos = 'eol',
      })
    end

    local pending = false
    vim.api.nvim_buf_attach(buf, false, {
      on_bytes = function()
        if pending then return false end
        pending = true
        vim.schedule(function()
          pending = false
          apply()
        end)
        return false  -- keep the attachment alive
      end,
    })
  end,
})

-- ── Startup behaviour ─────────────────────────────────────────
-- Open neo-tree on startup depending on how Neovim was launched:
--   nvim          → open tree at cwd, no file buffer
--   nvim .        → cd into the dir, open tree, wipe the dir buffer
--   nvim file.lua → open tree alongside the file
--
-- The vim.defer_fn delay lets neo-tree finish its own initialisation
-- before we try to open it.
vim.defer_fn(function()
  local argc = vim.fn.argc()
  local arg0 = argc > 0 and vim.fn.argv(0) or ''
  local is_dir = vim.fn.isdirectory(arg0) == 1

  if argc == 0 or is_dir then
    -- Record the buffer Neovim opened for the directory (or the empty
    -- scratch buffer) so we can wipe it after opening a clean one.
    local original_buf = vim.api.nvim_get_current_buf()
    if is_dir then
      vim.cmd('cd ' .. vim.fn.fnameescape(vim.fn.fnamemodify(arg0, ':p')))
    end
    vim.cmd('enew')
    -- Wipe the directory/scratch buffer so it doesn't clutter the buffer list
    pcall(vim.api.nvim_buf_delete, original_buf, { force = true })
    vim.cmd('Neotree show filesystem left')
  else
    -- A real file was given: open neo-tree alongside it
    vim.cmd('Neotree show filesystem left')
  end
end, 50)
