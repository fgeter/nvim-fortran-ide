-- ============================================================
-- plugins/python.lua — Python LSP + DAP + formatting
--
-- Configures:
--   basedpyright — Python language server (actively maintained
--                  fork of pyright with better defaults)
--   debugpy      — Python debug adapter for nvim-dap
--   ruff         — Fast Python formatter + linter (replaces
--                  black + flake8 + isort in one tool)
--
-- LAZY: Yes — activates on FileType python only. Nothing runs
--       at startup for non-Python sessions.
--
-- Installation (run once):
--   :MasonInstall basedpyright debugpy ruff
--
-- Python binary resolution order:
--   1. vim.g.project_python_bin (set in .nvim.lua)
--   2. vim.g.project_venv .. '/bin/python'
--   3. $VIRTUAL_ENV/bin/python (active virtualenv)
--   4. System python3
-- ============================================================

if vim.g.loaded_python_tools then return end
vim.g.loaded_python_tools = true

local function activate()
  if vim.g.python_tools_active then return end
  vim.g.python_tools_active = true

  ---------------------------------------------------------------------------
  -- Helper: resolve the correct Python binary for this project
  ---------------------------------------------------------------------------
  local function get_python_bin()
    -- 1. Explicit override in project config
    if vim.g.project_python_bin then
      return vim.g.project_python_bin
    end
    -- 2. Project venv set in .nvim.lua
    if vim.g.project_venv then
      local bin = vim.g.project_venv .. '/bin/python'
      if vim.fn.executable(bin) == 1 then return bin end
    end
    -- 3. Active virtualenv from environment
    local venv = os.getenv('VIRTUAL_ENV')
    if venv then
      local bin = venv .. '/bin/python'
      if vim.fn.executable(bin) == 1 then return bin end
    end
    -- 4. Local .venv in project root
    if vim.g.project_repo_root then
      local bin = vim.g.project_repo_root .. '/.venv/bin/python'
      if vim.fn.executable(bin) == 1 then return bin end
    end
    -- 5. System python3
    return vim.fn.exepath('python3') or 'python3'
  end

  ---------------------------------------------------------------------------
  -- LSP: basedpyright
  ---------------------------------------------------------------------------
  -- basedpyright is a community fork of Microsoft's pyright with better
  -- type inference defaults and faster updates than the official version.
  -- Install via Mason: :MasonInstall basedpyright
  vim.lsp.config('basedpyright', {
    cmd          = { 'basedpyright-langserver', '--stdio' },
    filetypes    = { 'python' },
    root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg',
                     'requirements.txt', '.git' },
    settings     = {
      basedpyright = {
        analysis = {
          -- 'standard' catches real errors without being noisy.
          -- Change to 'strict' for maximum type checking.
          typeCheckingMode     = 'standard',
          autoSearchPaths      = true,
          useLibraryCodeForTypes = true,
          -- Point to the project venv so imports resolve correctly
          venvPath             = vim.g.project_venv
            or (vim.g.project_repo_root and (vim.g.project_repo_root .. '/.venv'))
            or nil,
        },
      },
      python = {
        pythonPath = get_python_bin(),
      },
    },
  })
  vim.lsp.enable('basedpyright')

  ---------------------------------------------------------------------------
  -- DAP: debugpy
  ---------------------------------------------------------------------------
  -- debugpy is the standard Python debug adapter. Install via Mason:
  --   :MasonInstall debugpy
  --
  -- Configurations:
  --   'Launch file'   — run the current file with the project python
  --   'Launch module' — run a module (python -m module_name)
  --   'Attach'        — attach to a running process on localhost:5678
  local dap   = require('dap')
  local dapui = require('dapui')

  dap.adapters.python = {
    type    = 'executable',
    command = get_python_bin(),
    args    = { '-m', 'debugpy.adapter' },
  }

  dap.configurations.python = {
    {
      type    = 'python',
      request = 'launch',
      name    = 'Launch current file',
      program = '${file}',
      python  = get_python_bin(),
      -- console = 'integratedTerminal' shows print() output in the terminal
      console = 'integratedTerminal',
    },
    {
      type    = 'python',
      request = 'launch',
      name    = 'Launch module',
      module  = function()
        return vim.fn.input('Module name: ')
      end,
      python  = get_python_bin(),
      console = 'integratedTerminal',
    },
    {
      type    = 'python',
      request = 'attach',
      name    = 'Attach to process (localhost:5678)',
      connect = { host = '127.0.0.1', port = 5678 },
    },
  }

  -- Auto open/close the DAP UI panels with the debug session.
  -- Uses the same dapui instance as fortran-tools so the layout
  -- is consistent across languages.
  dap.listeners.after.event_initialized['python_dapui']  = function() dapui.open()  end
  dap.listeners.before.event_terminated['python_dapui']  = function() dapui.close() end
  dap.listeners.before.event_exited['python_dapui']      = function() dapui.close() end

  ---------------------------------------------------------------------------
  -- Formatting: ruff via conform.nvim
  ---------------------------------------------------------------------------
  -- ruff handles formatting (black-compatible) and import sorting (isort-
  -- compatible) in a single fast Rust-based tool.
  -- Install via Mason: :MasonInstall ruff
  --
  -- This adds Python formatters to conform.nvim which is already configured
  -- in plugins/formatting.lua. conform must be loaded first; if it isn't
  -- (user hasn't pressed <leader>f yet) we set up a deferred registration.
  local function register_ruff()
    local ok, conform = pcall(require, 'conform')
    if ok then
      conform.formatters_by_ft = conform.formatters_by_ft or {}
      conform.formatters_by_ft.python = { 'ruff_format', 'ruff_organize_imports' }
    end
  end

  -- Try immediately; if conform isn't loaded yet, hook into its lazy load
  if vim.g.conform_active then
    register_ruff()
  else
    -- Watch for conform becoming active and register then
    vim.api.nvim_create_autocmd('User', {
      pattern  = 'ConformActivated',
      once     = true,
      callback = register_ruff,
    })
    -- Also try on first BufWritePre so format-on-save works if enabled
    vim.api.nvim_create_autocmd('BufWritePre', {
      pattern  = '*.py',
      once     = true,
      callback = function()
        -- Trigger conform setup then let it handle the save
        vim.schedule(register_ruff)
      end,
    })
  end

  ---------------------------------------------------------------------------
  -- LSP keymaps (Python-specific, buffer-local)
  ---------------------------------------------------------------------------
  vim.api.nvim_create_autocmd('LspAttach', {
    pattern  = '*.py',
    group    = vim.api.nvim_create_augroup('python-lsp-attach', { clear = true }),
    callback = function(ev)
      local opts = { buffer = ev.buf }
      vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename,
        vim.tbl_extend('force', opts, { desc = 'LSP: rename symbol' }))
      vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action,
        vim.tbl_extend('force', opts, { desc = 'LSP: code action' }))
      vim.keymap.set('n', '<leader>e',  vim.diagnostic.open_float,
        vim.tbl_extend('force', opts, { desc = 'Diagnostics: show float' }))
      vim.keymap.set('n', '[d', function() vim.diagnostic.jump({ count = -1 }) end,
        vim.tbl_extend('force', opts, { desc = 'Diagnostics: prev' }))
      vim.keymap.set('n', ']d', function() vim.diagnostic.jump({ count =  1 }) end,
        vim.tbl_extend('force', opts, { desc = 'Diagnostics: next' }))
    end,
  })

  ---------------------------------------------------------------------------
  -- DAP keymaps (same <leader>d* pattern as fortran-tools.lua)
  ---------------------------------------------------------------------------
  vim.keymap.set('n', '<leader>ds', function()
    if dap.session() then dap.continue() else dap.continue() end
  end, { desc = 'DAP: start / continue' })

  vim.keymap.set('n', '<leader>dq', function() dap.terminate()   end, { desc = 'DAP: terminate' })
  vim.keymap.set('n', '<leader>dr', function() dap.restart()     end, { desc = 'DAP: restart' })
  vim.keymap.set('n', '<leader>dn', function() dap.step_over()   end, { desc = 'DAP: step over' })
  vim.keymap.set('n', '<leader>di', function() dap.step_into()   end, { desc = 'DAP: step into' })
  vim.keymap.set('n', '<leader>do', function() dap.step_out()    end, { desc = 'DAP: step out' })
  vim.keymap.set('n', '<leader>dc', function() dap.run_to_cursor() end, { desc = 'DAP: run to cursor' })

  vim.keymap.set('n', '<leader>db', function() dap.toggle_breakpoint() end,
    { desc = 'DAP: toggle breakpoint' })
  vim.keymap.set('n', '<leader>dB', function()
    dap.set_breakpoint(vim.fn.input('Breakpoint condition: '))
  end, { desc = 'DAP: conditional breakpoint' })
  vim.keymap.set('n', '<leader>dx', function() dap.clear_breakpoints() end,
    { desc = 'DAP: clear all breakpoints' })

  vim.keymap.set('n', '<leader>dw', function()
    local word = vim.fn.expand('<cword>')
    vim.ui.input({ prompt = 'Add to watches: ', default = word }, function(input)
      if input and input ~= '' then
        require('dapui').elements['watches'].add(input)
        vim.notify('Watching: ' .. input, vim.log.levels.INFO)
      end
    end)
  end, { desc = 'DAP: add to watches' })

  vim.keymap.set('n', '<leader>dU', function() dapui.toggle() end, { desc = 'DAP: toggle UI' })
  vim.keymap.set('n', '<leader>de', function() dapui.eval()   end, { desc = 'DAP: eval expression' })
  vim.keymap.set('v', '<leader>de', function() dapui.eval()   end, { desc = 'DAP: eval selection' })
  vim.keymap.set('n', '<leader>dR', function() dap.repl.open() end, { desc = 'DAP: open REPL' })

  -- K: context-aware hover (DAP eval during session, LSP hover otherwise)
  vim.api.nvim_create_autocmd('LspAttach', {
    pattern  = '*.py',
    callback = function(ev)
      vim.keymap.set('n', 'K', function()
        if dap.session() then
          dapui.eval(nil, { enter = false })
          vim.api.nvim_create_autocmd('CursorMoved', {
            once     = true,
            callback = function()
              vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
            end,
          })
        else
          vim.lsp.buf.hover()
        end
      end, { buffer = ev.buf, desc = 'K: DAP eval / LSP hover' })
    end,
  })

  ---------------------------------------------------------------------------
  -- Run current file
  ---------------------------------------------------------------------------
  -- <leader>pr — run the current Python file in the bottom toggleterm (#1).
  -- Reuses the terminal if it exists; opens a new one otherwise.
  -- A 200ms defer is used for brand-new terminals so the shell finishes
  -- initialising before the command is sent.
  vim.keymap.set('n', '<leader>pr', function()
    local file = vim.fn.expand('%:p')
    if file == '' then
      vim.notify('No file in current buffer', vim.log.levels.WARN)
      return
    end
    local python = get_python_bin()
    local cmd    = python .. ' ' .. vim.fn.shellescape(file)
    local terms  = require('toggleterm.terminal')
    local term, is_new = terms.get_or_create_term(1, vim.fn.expand('%:p:h'), 'horizontal')
    if is_new then
      term:open(15)
      vim.defer_fn(function() term:send(cmd) end, 200)
    else
      if not term:is_open() then term:open(15) end
      term:send(cmd)
    end
  end, { desc = 'Python: run current file' })

  vim.notify('✅ Python tools loaded (LSP + DAP + ruff)', vim.log.levels.INFO)
end

-- Lazy: activate on first FileType python event
vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'python',
  once     = true,
  callback = activate,
})
