-- ============================================================
-- plugins/web-tools.lua — JavaScript / TypeScript / React DAP
--
-- Configures the pwa-node debug adapter (from js-debug-adapter)
-- for running and attaching to Node.js processes.
-- Works for plain JS, TypeScript, React (JSX/TSX).
--
-- LSP (ts_ls, eslint) and formatting (prettier) are handled by
-- lsp.lua and formatting.lua respectively.
-- js-debug-adapter is installed by lsp.lua via Mason.
--
-- Keymaps (buffer-local, active only in JS/TS/JSX/TSX buffers):
--   <leader>ds — DAP: start / continue
--
-- LAZY: Yes — activates on first JS/TS/JSX/TSX FileType event.
-- ============================================================

if vim.g.loaded_web_tools then return end
vim.g.loaded_web_tools = true

local function activate()
  if vim.g.web_tools_active then return end
  vim.g.web_tools_active = true

  local mason_path = vim.fn.stdpath('data') .. '/mason/packages'
  local js_debug   = mason_path .. '/js-debug-adapter/js-debug/src/dapDebugServer.js'

  if vim.fn.filereadable(js_debug) == 0 then
    vim.notify(
      'js-debug-adapter not installed — run :MasonInstall js-debug-adapter',
      vim.log.levels.WARN)
    return
  end

  local dap = require('dap')

  dap.adapters['pwa-node'] = {
    type = 'server',
    host = 'localhost',
    port = '${port}',
    executable = {
      command = 'node',
      args    = { js_debug, '${port}' },
    },
  }

  local js_configs = {
    {
      type    = 'pwa-node',
      request = 'launch',
      name    = 'Launch current file (Node)',
      program = '${file}',
      cwd     = '${workspaceFolder}',
    },
    {
      type      = 'pwa-node',
      request   = 'attach',
      name      = 'Attach to running Node process',
      processId = require('dap.utils').pick_process,
      cwd       = '${workspaceFolder}',
    },
  }

  for _, ft in ipairs({ 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' }) do
    dap.configurations[ft] = js_configs
  end
end

local ft_list = { 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' }

vim.api.nvim_create_autocmd('FileType', {
  pattern  = ft_list,
  once     = true,
  callback = activate,
})

vim.api.nvim_create_autocmd('FileType', {
  pattern  = ft_list,
  callback = function()
    vim.keymap.set('n', '<leader>ds', function()
      require('dap').continue()
    end, { buffer = true, desc = 'DAP: start / continue (JS/TS)' })
  end,
})
