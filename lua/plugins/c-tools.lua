-- ============================================================
-- plugins/c-tools.lua — C / C++ DAP configuration
--
-- Configures GDB as the debug adapter for C and C++ files.
-- Reuses the GDB adapter that fortran-tools.lua may have already
-- registered; defines it here only if Fortran wasn't loaded first.
--
-- LSP (clangd) is handled by lsp.lua via Mason + vim.lsp.enable.
-- Formatting (clang-format) is handled by formatting.lua.
--
-- Keymaps (buffer-local, active only in C/C++ buffers):
--   <leader>ds — prompt for executable path and launch DAP
--
-- LAZY: Yes — activates on first FileType c or cpp event.
-- ============================================================

if vim.g.loaded_c_tools then return end
vim.g.loaded_c_tools = true

local function activate()
  if vim.g.c_tools_active then return end
  vim.g.c_tools_active = true

  require('plugins.dap').activate()  -- install/configure the DAP stack (lazy since #7)
  local dap = require('dap')

  -- Share the GDB adapter with fortran-tools.lua when both are loaded.
  if not dap.adapters.gdb then
    dap.adapters.gdb = {
      type    = 'executable',
      command = 'gdb',
      args    = { '--interpreter=dap', '--eval-command', 'set print pretty on' },
      options = { initialize_timeout_sec = 10 },
    }
  end

  dap.configurations.c = {
    {
      name    = 'Launch executable',
      type    = 'gdb',
      request = 'launch',
      program = function()
        return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
      end,
      cwd     = '${workspaceFolder}',
      stopAtBeginningOfMainSubprogram = false,
    },
  }
  -- C++ shares the same GDB config
  dap.configurations.cpp = vim.deepcopy(dap.configurations.c)
end

-- activate() is idempotent; the map must be set on every C/C++ buffer,
-- not just the first (a `once = true` FileType used to skip later files).
vim.api.nvim_create_autocmd('FileType', {
  pattern  = { 'c', 'cpp' },
  callback = function(ev)
    activate()
    vim.keymap.set('n', '<leader>ds', function()
      require('dap').continue()
    end, { buffer = ev.buf, desc = 'DAP: start / continue (C/C++) - F5' })
  end,
})
