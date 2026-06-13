-- ============================================================
-- plugins/java-tools.lua — Java LSP + DAP via nvim-jdtls
--
-- Uses nvim-jdtls (NOT vim.lsp.enable) because jdtls requires:
--   • a per-project workspace directory
--   • a launcher JAR from Mason's jdtls installation
--   • special JVM arguments
--
-- jdtls, java-debug-adapter are installed by lsp.lua via Mason.
--
-- Keymaps (buffer-local, active only in Java buffers):
--   <leader>ds — DAP: start / continue
--   <leader>di — jdtls: organize imports
--   <leader>dv — jdtls: extract variable
--   <leader>dm — jdtls: extract method
--
-- LAZY: Yes — nvim-jdtls starts per-buffer on FileType java.
-- ============================================================

if vim.g.loaded_java_tools then return end
vim.g.loaded_java_tools = true

local function gh(repo) return 'https://github.com/' .. repo end
vim.pack.add { gh 'mfussenegger/nvim-jdtls' }

local mason_path = vim.fn.stdpath('data') .. '/mason/packages'

local function get_jdtls_config()
  local launcher = vim.fn.glob(
    mason_path .. '/jdtls/plugins/org.eclipse.equinox.launcher_*.jar', 1)
  if launcher == '' then
    vim.notify('jdtls not installed — run :MasonInstall jdtls', vim.log.levels.WARN)
    return nil
  end

  -- Per-project workspace under ~/.local/share/nvim/jdtls-workspaces/
  local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
  local workspace    = vim.fn.stdpath('data') .. '/jdtls-workspaces/' .. project_name

  -- OS-specific jdtls config directory
  local uname = vim.uv.os_uname().sysname
  local os_config = uname == 'Darwin' and 'mac'
    or (uname:match('Windows') and 'win' or 'linux')

  local bundles = {}
  local debug_jar = vim.fn.glob(
    mason_path .. '/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar', 1)
  if debug_jar ~= '' then
    table.insert(bundles, debug_jar)
  end

  return {
    cmd = {
      'java',
      '-Declipse.application=org.eclipse.jdt.ls.core.id1',
      '-Dosgi.bundles.defaultStartLevel=4',
      '-Declipse.product=org.eclipse.jdt.ls.core.product',
      '-Dlog.protocol=true',
      '-Dlog.level=ALL',
      '-Xmx1g',
      '--add-modules=ALL-SYSTEM',
      '--add-opens', 'java.base/java.util=ALL-UNNAMED',
      '--add-opens', 'java.base/java.lang=ALL-UNNAMED',
      '-jar', launcher,
      '-configuration', mason_path .. '/jdtls/config_' .. os_config,
      '-data', workspace,
    },
    root_dir = vim.fs.root(0, { 'pom.xml', 'build.gradle', 'gradlew', 'mvnw', '.git' }),
    settings = {
      java = {
        configuration    = { updateBuildConfiguration = 'interactive' },
        eclipse          = { downloadSources = true },
        maven            = { downloadSources = true },
        implementationsCodeLens = { enabled = true },
        referencesCodeLens      = { enabled = true },
        format           = { enabled = true },
      },
    },
    init_options = { bundles = bundles },
  }
end

-- Register the Java DAP adapter once (reused across all Java buffers).
local _java_dap_registered = false
local function ensure_java_dap()
  if _java_dap_registered then return end
  _java_dap_registered = true
  local dap = require('dap')
  if not dap.adapters['java'] then
    dap.adapters['java'] = function(cb, _)
      require('jdtls').execute_command({ command = 'vscode.java.startDebugSession' },
        function(err, port)
          if err then
            vim.notify('jdtls DAP error: ' .. tostring(err), vim.log.levels.ERROR)
            return
          end
          cb({ type = 'server', host = '127.0.0.1', port = port })
        end)
    end
  end
end

-- jdtls.start_or_attach must be called for each new Java buffer so the
-- server attaches even when switching between projects.
vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'java',
  callback = function()
    local config = get_jdtls_config()
    if not config then return end

    ensure_java_dap()
    require('jdtls').start_or_attach(config)

    -- Buffer-local keymaps
    local buf = vim.api.nvim_get_current_buf()
    local map = function(lhs, fn, desc)
      vim.keymap.set('n', lhs, fn, { buffer = buf, desc = desc })
    end
    map('<leader>ds', function() require('dap').continue() end,
      'DAP: start / continue (Java)')
    map('<leader>di', function() require('jdtls').organize_imports() end,
      'Java: organize imports')
    map('<leader>dv', function() require('jdtls').extract_variable() end,
      'Java: extract variable')
    map('<leader>dm', function() require('jdtls').extract_method() end,
      'Java: extract method')
  end,
})
