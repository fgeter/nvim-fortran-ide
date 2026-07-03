-- ============================================================
-- plugins/ui.lua — Visual / UX plugins
--
-- Covers: colorscheme (catppuccin), which-key, mini.nvim modules,
--         todo-comments, guess-indent, web-devicons, indent-blankline,
--         and bufferline.
--
-- LAZY: No — UI plugins must be loaded at startup so the editor
--       looks correct on the first frame.
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

-- ── guess-indent ─────────────────────────────────────────────
-- Automatically detects the indentation style of each file (tabs vs
-- spaces, indent width) and sets the buffer options accordingly.
-- Prevents the jarring experience of opening a file and having your
-- indentation settings override the project's style.
vim.pack.add { gh 'NMAC427/guess-indent.nvim' }
require('guess-indent').setup {}

-- ── nvim-web-devicons ────────────────────────────────────────
-- Provides file-type icons used by neo-tree, telescope, and mini.
-- Only installed when a Nerd Font is available; without one the icons
-- render as boxes or question marks.
if vim.g.have_nerd_font then
  vim.pack.add { gh 'nvim-tree/nvim-web-devicons' }
end

-- ── Catppuccin colorscheme ───────────────────────────────────
-- Single colorscheme (tokyonight and kanagawa removed — unused).
-- The highlight_overrides and the ColorScheme autocmd below ensure
-- the lavender window separator colour survives plugin resets.
vim.pack.add { gh 'catppuccin/nvim' }

require('catppuccin').setup {
  flavour              = 'mocha',
  transparent_background = true,
  highlight_overrides = {
    mocha = function(colors)
      return {
        WinSeparator = { fg = colors.lavender },
        -- Default DiffChange is only a 7%-blended blue wash — easy to miss
        -- on a dark background, especially when just one character on a
        -- line changed. DiffText (the changed characters themselves) was
        -- the same hue, just more saturated, so the two didn't read as
        -- distinct. Give the whole changed line a plain neutral background
        -- and make the exact changed text pop with a contrasting color.
        DiffChange = { bg = colors.surface1 },
        DiffText   = { bg = colors.yellow, fg = colors.base, bold = true },
      }
    end,
  },
}

-- Re-apply custom highlights whenever the colorscheme is set (or reset
-- by a plugin). The 100ms defer is required because mini.statusline
-- resets its highlight groups slightly after ColorScheme fires.
vim.api.nvim_create_autocmd('ColorScheme', {
  group    = vim.api.nvim_create_augroup('ui-colorscheme-overrides', { clear = true }),
  callback = function(ev)
    if ev.match:match('^catppuccin') then
      vim.defer_fn(function()
        local c = '#b4befe'  -- catppuccin-mocha lavender
        vim.api.nvim_set_hl(0, 'WinSeparator',        { fg = c })
        vim.api.nvim_set_hl(0, 'NeoTreeWinSeparator', { fg = c })
        vim.api.nvim_set_hl(0, 'StatusLine',          { fg = c, bg = c })
        vim.api.nvim_set_hl(0, 'StatusLineNC',        { fg = c, bg = c })
      end, 100)
    end
  end,
})

vim.cmd.colorscheme('catppuccin')

-- ── which-key ────────────────────────────────────────────────
-- Shows a popup of available keymaps after pressing a leader prefix.
-- The spec table documents key groups so which-key can label them.
vim.pack.add { gh 'folke/which-key.nvim' }
require('which-key').setup {
  delay = 0,
  icons = { mappings = vim.g.have_nerd_font },
  spec  = {
    { '<leader>b', group = 'Buffer' },
    { '<leader>c', group = 'CMake' },
    { '<leader>d', group = 'Debug (DAP)' },
    { '<leader>g', group = 'Git' },
    { '<leader>h', group = 'Git hunks' },
    { '<leader>j', group = 'Jupyter' },
    { '<leader>r', group = 'Recent / Rename' },
    { '<leader>s', group = 'Search',  mode = { 'n', 'v' } },
    { '<leader>t', group = 'Toggle' },
    { 'gr',        group = 'LSP actions' },
  },
}

-- ── todo-comments ────────────────────────────────────────────
-- Highlights TODO / FIXME / NOTE / HACK etc. in comments and makes
-- them searchable via :TodoTelescope
vim.pack.add { gh 'folke/todo-comments.nvim' }
require('todo-comments').setup { signs = false }

-- ── mini.nvim ────────────────────────────────────────────────
-- A collection of small independent modules. We use three:
--   mini.ai        — improved text objects (va), yi', etc.)
--   mini.surround  — add/change/delete surrounding brackets/quotes
--   mini.statusline — lightweight statusline (no external config needed)
vim.pack.add { gh 'nvim-mini/mini.nvim' }

-- Better text objects. Mappings adjusted to avoid conflict with
-- Neovim >= 0.12 built-in incremental selection (which uses ia/aa).
require('mini.ai').setup {
  mappings = {
    around_next = 'aa',
    inside_next = 'ii',
  },
  n_lines = 500,
}

-- Surround operations: saiw) adds parens, sd' deletes quotes, sr)' replaces
require('mini.surround').setup()

-- Statusline: shows mode, filename, git branch, diagnostics, cursor pos
local statusline = require('mini.statusline')
statusline.setup { use_icons = vim.g.have_nerd_font }

-- Override cursor location to show LINE:COL instead of the default
---@diagnostic disable-next-line: duplicate-set-field
statusline.section_location = function() return '%2l:%-2v' end

-- Fall back to the startup-cached branch when gitsigns hasn't attached yet.
---@diagnostic disable-next-line: duplicate-set-field
statusline.section_git = function(args)
  if statusline.is_truncated(args.trunc_width) then return '' end
  local summary = vim.b.minigit_summary_string or vim.b.gitsigns_head or vim.g.git_branch
  if not summary or summary == '' then return '' end
  local icon = args.icon or (vim.g.have_nerd_font and '' or 'Git')
  return icon .. ' ' .. summary
end

-- ── indent-blankline ─────────────────────────────────────────
-- Draws a vertical guide line at each indentation level.
-- scope highlights the current indentation block under the cursor,
-- which is especially useful in Python and nested Fortran loops.
vim.pack.add { gh 'lukas-reineke/indent-blankline.nvim' }
require('ibl').setup {
  indent = { char = '│' },
  scope  = { enabled = true },
}

-- ── bufferline ───────────────────────────────────────────────
-- Shows open buffers as tabs at the top of the screen.
-- Uses catppuccin highlights natively so colours match the theme.
-- nvim-web-devicons provides file-type icons in each tab.
vim.pack.add { { src = gh 'akinsho/bufferline.nvim', version = vim.version.range '*' } }
require('bufferline').setup {
  options = {
    mode            = 'buffers',
    numbers         = 'none',
    diagnostics     = 'nvim_lsp',
    show_close_icon = false,
    separator_style = 'thin',
    offsets = {
      {
        filetype   = 'neo-tree',
        text       = 'File Explorer',
        highlight  = 'Directory',
        separator  = true,
      },
    },
    -- When closing a buffer, switch every window that is currently showing it
    -- to another listed regular-file buffer before deleting.  Checking only
    -- the focused window (get_current_buf) misses the case where focus is in
    -- neo-tree, leaving the editor window orphaned and causing Neovim to
    -- close it and show only neo-tree.
    close_command = function(bufnr)
      local others = vim.tbl_filter(function(b)
        return b.bufnr ~= bufnr and vim.bo[b.bufnr].buftype == ''
      end, vim.fn.getbufinfo({ buflisted = 1 }))

      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win)
            and vim.api.nvim_win_get_buf(win) == bufnr
            and #others > 0 then
          vim.api.nvim_win_set_buf(win, others[1].bufnr)
        end
      end

      vim.api.nvim_buf_delete(bufnr, { force = false })
    end,
  },
}
