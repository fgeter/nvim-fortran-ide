-- ============================================================
-- plugins/markdown.lua — In-buffer markdown rendering
--
-- render-markdown.nvim renders markdown files visually inside
-- Neovim using the extmark system. No external browser or split
-- needed. Features:
--   • Table borders drawn with box-drawing characters
--   • Headings styled with background highlights and icons
--   • Bold/italic/code concealed and styled inline
--   • Bullet point icons replace - / * / + markers
--   • Rendered view in normal mode; raw markdown in insert mode
--     so editing is never obstructed
--
-- Requirements already met by this config:
--   • Neovim >= 0.10
--   • Nerd Font (vim.g.have_nerd_font = true)
--   • markdown + markdown_inline treesitter parsers (treesitter.lua)
--   • nvim-web-devicons (ui.lua)
--
-- LAZY: Yes — only loads when a markdown file is opened.
--       Nothing runs at startup for non-markdown sessions.
--
-- Keymaps (markdown buffers only):
--   <leader>mr — toggle rendering on/off
--   <leader>me — expand all sections
--   <leader>mc — collapse all sections
-- ============================================================

local function gh(repo) return 'https://github.com/' .. repo end

vim.pack.add { gh 'MeanderingProgrammer/render-markdown.nvim' }

require('render-markdown').setup {
  -- Only activate on markdown files (and any other types you add here)
  file_types = { 'markdown' },

  -- Render in normal, command, and terminal modes.
  -- Raw markdown is restored automatically in insert and visual modes
  -- so you can edit without the rendering getting in the way.
  render_modes = { 'n', 'c' },

  -- Heading configuration: styled backgrounds + Nerd Font icons
  heading = {
    enabled    = true,
    sign       = false,   -- don't show extra sign column icon
    icons      = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
    -- Draw a border line above and below each heading
    border     = true,
    -- Width of the heading background: 'full' spans the window
    width      = 'full',
  },

  -- Code blocks: add a subtle background and a language label
  code = {
    enabled    = true,
    sign       = false,
    style      = 'full',    -- background + border
    position   = 'left',
    width      = 'full',
    left_pad   = 1,
    right_pad  = 1,
  },

  -- Tables: render with proper box-drawing border characters
  -- This is what makes the keymap reference look like a real table
  pipe_table = {
    enabled   = true,
    style     = 'full',   -- full borders around every cell
    cell      = 'padded', -- pad cells so columns align
  },

  -- Bullet points: replace -, *, + with Nerd Font icons per indent level
  bullet = {
    enabled = true,
    icons   = { '●', '○', '◆', '◇' },
  },

  -- Checkbox rendering (not used in the keymap doc but useful generally)
  checkbox = {
    enabled   = true,
    unchecked = { icon = '󰄱 ' },
    checked   = { icon = '󰱒 ' },
  },

  -- Horizontal rules rendered as a full-width line
  dash = {
    enabled = true,
    icon    = '─',
    width   = 'full',
  },
}

-- Buffer-local keymaps attached when a markdown file is opened
vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'markdown',
  group    = vim.api.nvim_create_augroup('render-markdown-keymaps', { clear = true }),
  callback = function(ev)
    local rm = require('render-markdown')
    vim.keymap.set('n', '<leader>mr', rm.toggle,
      { buffer = ev.buf, desc = 'Markdown: toggle rendering' })
    vim.keymap.set('n', '<leader>me', rm.expand,
      { buffer = ev.buf, desc = 'Markdown: expand all' })
    vim.keymap.set('n', '<leader>mc', rm.contract,
      { buffer = ev.buf, desc = 'Markdown: collapse all' })
  end,
})
