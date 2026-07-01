-- ============================================================
-- core/options.lua — Neovim editor options
--
-- All vim.o.* and vim.opt.* settings live here so they are
-- easy to find and change without digging through plugin files.
-- ============================================================

-- Show absolute line numbers in the gutter
vim.o.number = true

-- Hybrid line numbers: relative on other lines, absolute on the cursor
-- line. Toggle with <leader>tr (core/keymaps.lua).
vim.o.relativenumber = true

-- Enable mouse support in all modes (useful for resizing splits)
vim.o.mouse          = 'a'
vim.o.mousemoveevent = true   -- fire <MouseMove> so edge-hover can scroll

-- Hide the "-- INSERT --" / "-- VISUAL --" mode indicator in the cmdline
-- because mini.statusline already shows the mode
vim.o.showmode = false

-- Use OSC 52 only in Kitty (where it works reliably without xclip/wl-clipboard).
-- In other terminals (Konsole, etc.) let Neovim auto-detect the system clipboard
-- provider (wl-clipboard on Wayland, xclip/xsel on X11).
if vim.env.KITTY_WINDOW_ID then
  vim.g.clipboard = {
    name  = 'OSC 52',
    copy  = {
      ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
      ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
    },
    paste = {
      ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
      ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
    },
  }
end
vim.o.clipboard = 'unnamedplus'

-- Wrapped lines continue visually indented (makes long lines readable)
vim.o.breakindent = true

-- Persist undo history to disk so you can undo across sessions
vim.o.undofile = true

-- Case-insensitive search by default; case-sensitive when the query
-- contains an uppercase letter or the \C flag
vim.o.ignorecase = true
vim.o.smartcase  = true

-- Always show the sign column (git signs, diagnostics) to prevent
-- the text from jumping left/right when signs appear/disappear
vim.o.signcolumn = 'yes'

-- Milliseconds before the CursorHold event fires and before the swap
-- file is written. Lower = more responsive LSP highlights and DAP hover.
vim.o.updatetime = 250

-- Milliseconds to wait for a mapped sequence to complete.
-- 300ms is a good balance: fast enough to feel snappy, slow enough
-- for which-key to show before you need to press the next key.
vim.o.timeoutlen = 300

-- New vertical splits open to the right, horizontal splits open below
vim.o.splitright = true
vim.o.splitbelow = true

-- Show invisible characters (tabs, trailing spaces, non-breaking spaces)
vim.o.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview :substitute replacements live in a split as you type
vim.o.inccommand = 'split'

-- Highlight the line the cursor is on (makes it easier to find in large files)
vim.o.cursorline = true

-- Keep at least 10 lines of context visible above/below the cursor
vim.o.scrolloff = 10

-- Horizontal scrolling (requires nowrap)
vim.o.wrap          = false  -- don't wrap long lines
vim.o.sidescroll    = 1      -- scroll one column at a time
vim.o.sidescrolloff = 5      -- keep 5 columns of context at edges

-- Neovim's default formatoptions ("tcqj") includes 't', which hard-wraps
-- text at textwidth while typing. Start with that off; <leader>tW toggles it.
vim.opt.formatoptions:remove('t')

-- Prompt to save instead of refusing to close an unsaved buffer
vim.o.confirm = true

-- Always show the statusline (required for the line separator effect)
vim.o.laststatus = 2

-- Use box-drawing characters for split separators so they connect properly
vim.opt.fillchars = {
  vert      = '│',
  horiz     = '─',
  horizup   = '┴',
  horizdown = '┬',
  vertleft  = '┤',
  vertright = '├',
  verthoriz = '┼',
  stl       = '─',   -- active statusline fill
  stlnc     = '─',   -- inactive statusline fill
}

-- Enable per-project .nvim.lua config files.
-- Each project can have a .nvim.lua in its root that sets paths
-- and loads project-specific configuration (see lua/projects/).
-- Trust a .nvim.lua once with :trust to allow it to run.
vim.o.exrc = true
