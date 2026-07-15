-- ============================================================
-- plugins/markdown.lua — In-buffer markdown rendering
--
-- render-markdown.nvim renders markdown files visually inside
-- Neovim using the extmark system.
--
-- LAZY: No — render-markdown hooks into treesitter and the
--       display system at a low level. Lazy loading via FileType
--       causes the first buffer to miss rendering because the
--       plugin's internal FileType handler registers after the
--       event has already fired. Eager loading costs ~1ms at
--       startup and is the correct approach for this plugin.
-- ============================================================

local gh = require('core.utils').gh

vim.pack.add { { src = gh 'MeanderingProgrammer/render-markdown.nvim', version = vim.version.range '8.*' } }

require('render-markdown').setup {
  file_types    = { 'markdown' },
  render_modes  = { 'n', 'c' },

  heading = {
    enabled = true,
    sign    = false,
    icons   = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
    border  = true,
    width   = 'full',
  },
  code = {
    enabled   = true,
    sign      = false,
    style     = 'full',
    position  = 'left',
    width     = 'full',
    left_pad  = 1,
    right_pad = 1,
  },
  pipe_table = {
    enabled = true,
    style   = 'full',
    cell    = 'padded',
  },
  bullet = {
    enabled = true,
    icons   = { '●', '○', '◆', '◇' },
  },
  checkbox = {
    enabled   = true,
    unchecked = { icon = '󰄱 ' },
    checked   = { icon = '󰱒 ' },
  },
  dash = {
    enabled = true,
    icon    = '─',
    width   = 'full',
  },
}

-- Buffer-local keymaps attached when any markdown file opens
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
    vim.keymap.set('n', '<leader>mh', function()
      local md = vim.api.nvim_buf_get_name(ev.buf)
      local html = vim.fn.fnamemodify(md, ':r') .. '.html'
      vim.system({ 'pandoc', '-s', md, '-o', html }, {}, function(out)
        if out.code ~= 0 then
          vim.schedule(function() vim.notify(out.stderr, vim.log.levels.ERROR) end)
          return
        end
        vim.schedule(function()
          vim.ui.select({ 'No (default)', 'Yes' }, {
            prompt = 'Keep ' .. vim.fn.fnamemodify(html, ':t') .. '? (<Enter> = No)',
          }, function(choice)
            vim.system { 'xdg-open', html }
            if choice ~= 'Yes' then
              -- delay so a cold-starting browser reads the file before it goes
              vim.defer_fn(function() os.remove(html) end, 5000)
            end
          end)
        end)
      end)
    end, { buffer = ev.buf, desc = 'Markdown: render to HTML and open browser' })
  end,
})
