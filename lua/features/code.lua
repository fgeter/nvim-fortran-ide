-- ============================================================
-- features/code.lua — <leader>C: Code (language-server actions)
--
-- The keymaps behind the menu bar's Code drop-down (features/topbar.lua).
-- The usual LSP keys (grn, gra, grr, K, [d, ]d …, plugins/lsp.lua and
-- plugins/telescope.lua) are not <leader> keys, so no menu could feed them,
-- and they only exist once a server attaches. These are global and say
-- so when the file has no language server, rather than doing nothing.
--
--   Cd  go to definition          Ch  hover documentation
--   CD  go to declaration         Cg  signature help
--   Ct  go to type definition     Cn  rename symbol…
--   Ci  go to implementation      Ca  code actions…   (also on a selection)
--   Cr  find references           Ce  problem at cursor
--   Cs  symbols in this file      C]  next problem     C[  previous problem
--   CS  symbols in the project    Cq  problems in this file
--   Cb  go back   CB  go forward  CQ  problems in the project
--   Cl  language server info      CL  restart language server
--
-- M.state('Cl') names the attached server(s), for the drop-down.
-- Part of making the editor usable with Vim keybindings off.
-- Added 2026-11-03.
-- ============================================================

local M = {}

local function info(msg, level) vim.notify(msg, level or vim.log.levels.INFO) end

local function clients(buf)
  return vim.lsp.get_clients({ bufnr = buf or 0 })
end

-- Wrap an action that needs a language server.
local function needs_lsp(fn)
  return function(...)
    if #clients() == 0 then
      info('No language server for this file' .. (vim.bo.filetype ~= '' and (' (' .. vim.bo.filetype .. ')') or ''),
        vim.log.levels.WARN)
      return
    end
    fn(...)
  end
end

-- Not every server does everything (fortls has no declaration, type
-- definition, signature help or code actions). Check first, so the user
-- gets a plain sentence rather than Neovim's "method … is not supported".
local function supports(method, buf)
  for _, c in ipairs(clients(buf)) do
    if c:supports_method('textDocument/' .. method, buf or 0) then return true end
  end
  return false
end

local function server_names(buf)
  return table.concat(vim.tbl_map(function(c) return c.name end, clients(buf)), ', ')
end

local function needs(method, what, fn, fallback)
  return needs_lsp(function(...)
    if supports(method) then return fn(...) end
    if fallback and supports(fallback.method) then
      info(('%s has no %s; showing %s instead'):format(server_names(), what, fallback.what))
      return fallback.fn(...)
    end
    info(('%s (%s) can\'t do: %s'):format(server_names(), vim.bo.filetype, what), vim.log.levels.WARN)
  end)
end

local function telescope(picker, opts)
  return function() require('telescope.builtin')[picker](opts or {}) end
end

local function map(lhs, rhs, desc, modes)
  vim.keymap.set(modes or 'n', '<leader>' .. lhs, rhs, { desc = 'Code: ' .. desc, silent = true })
end

-- Which LSP method each menu entry relies on (for the state column too).
local METHOD = {
  Cd = 'definition', CD = 'declaration', Ct = 'typeDefinition', Ci = 'implementation',
  Cr = 'references', Cs = 'documentSymbol', Ch = 'hover', Cg = 'signatureHelp',
  Cn = 'rename', Ca = 'codeAction',
}

-- ── Navigate ─────────────────────────────────────────────────
local definition = telescope('lsp_definitions')
map('Cd', needs('definition', 'go to definition', definition), 'go to definition')
map('CD', needs('declaration', 'go to declaration', vim.lsp.buf.declaration,
  { method = 'definition', what = 'the definition', fn = definition }), 'go to declaration')
-- Fortran: fortls has no type definition, so search the project instead.
-- On a type name (type(my_t) :: x → my_t) find where it is defined; on a
-- variable, ask fortls where the variable is declared, read type(...) /
-- class(...) off that line, and find that type. Case-insensitive, like
-- Fortran. One match jumps there; several open a picker.
local FORTRAN_GLOBS = { '*.f', '*.for', '*.ftn', '*.f77', '*.f90', '*.f95', '*.f03', '*.f08', '*.fpp' }

local function find_type_defs(name, root)
  -- type my_t | type :: my_t | type, extends(base), public :: my_t   (not
  -- "end type"). With attributes the name must follow the "::", or
  -- "extends(my_t)" would count as defining my_t.
  local plain = [[^\s*type\s*(::)?\s*]] .. name .. [[\b]]
  local attrs = [[^\s*type\s*,[^:!]*::\s*]] .. name .. [[\b]]
  local cmd = { 'rg', '--vimgrep', '--ignore-case', '--no-heading' }
  for _, g in ipairs(FORTRAN_GLOBS) do vim.list_extend(cmd, { '--iglob', g }) end
  vim.list_extend(cmd, { '-e', plain, '-e', attrs, root })
  local res = vim.system(cmd, { text = true }):wait()
  local hits = {}
  for line in (res.stdout or ''):gmatch('[^\n]+') do
    local file, lnum, col, text = line:match('^(.-):(%d+):(%d+):(.*)$')
    -- "type is (my_t)" in select type, or type(my_t) usage, is not a definition.
    if file and not text:lower():match('^%s*type%s+is') and not text:match('^%s*[Tt][Yy][Pp][Ee]%s*%(') then
      hits[#hits + 1] = { filename = file, lnum = tonumber(lnum), col = tonumber(col), text = vim.trim(text) }
    end
  end
  return hits
end

-- The type named on a declaration line: type(my_t) / class(my_t).
local function type_on_line(text)
  local t = text:lower():match('type%s*%(%s*([%w_]+)%s*%)') or text:lower():match('class%s*%(%s*([%w_]+)%s*%)')
  if t and t ~= '*' then return t end
end

-- Where fortls says the word under the cursor is declared (line text).
local function declaration_line()
  local client = clients()[1]
  if not client or not client:supports_method('textDocument/definition', 0) then return nil end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local res = vim.lsp.buf_request_sync(0, 'textDocument/definition', params, 2000)
  for _, r in pairs(res or {}) do
    local loc = r.result and (r.result[1] or r.result)
    if loc and (loc.uri or loc.targetUri) then
      local range = loc.range or loc.targetSelectionRange or loc.targetRange
      local fname = vim.uri_to_fname(loc.uri or loc.targetUri)
      local lines = vim.fn.readfile(fname, '', range.start.line + 1)
      return lines[range.start.line + 1]
    end
  end
end

local function show(hits, title)
  if #hits == 1 then
    vim.cmd('normal! m\'')                      -- so Go back returns here
    vim.cmd('edit ' .. vim.fn.fnameescape(hits[1].filename))
    vim.api.nvim_win_set_cursor(0, { hits[1].lnum, hits[1].col - 1 })
    vim.cmd('normal! zz')
    return
  end
  vim.fn.setqflist({}, ' ', { title = title, items = hits })
  require('telescope.builtin').quickfix({ prompt_title = title })
end

local function fortran_type_definition()
  local word = vim.fn.expand('<cword>')
  if word == '' or not word:match('^[%a_][%w_]*$') then info('Put the cursor on a type or variable name') return end
  local root = vim.fs.root(0, { '.git', 'CMakeLists.txt', 'Makefile', 'fpm.toml', '.fortls' }) or vim.fn.getcwd()

  local hits = find_type_defs(word, root)
  if #hits > 0 then return show(hits, 'Type ' .. word) end

  local decl = declaration_line()
  local tname = decl and type_on_line(decl)
  if tname then
    hits = find_type_defs(tname, root)
    if #hits > 0 then return show(hits, 'Type ' .. tname .. ' (of ' .. word .. ')') end
    info(('%s is type(%s), but no "type %s" definition was found under %s'):format(
      word, tname, tname, vim.fn.fnamemodify(root, ':~')), vim.log.levels.WARN)
    return
  end
  info(('No derived type "%s" found, and %s is not declared with type(...) / class(...)'):format(word, word),
    vim.log.levels.WARN)
end

local type_definition = needs('typeDefinition', 'go to type definition', telescope('lsp_type_definitions'))
map('Ct', function()
  if vim.bo.filetype == 'fortran' and not supports('typeDefinition') then
    return fortran_type_definition()
  end
  type_definition()
end, 'go to type definition')
map('Ci', needs('implementation', 'go to implementation', telescope('lsp_implementations')), 'go to implementation')
map('Cr', needs('references', 'find references', telescope('lsp_references')), 'find references')
map('Cs', needs('documentSymbol', 'list symbols', telescope('lsp_document_symbols')), 'symbols in this file')
map('CS', needs_lsp(telescope('lsp_dynamic_workspace_symbols')), 'symbols in the project')
-- Back / forward through the places jumped to (the jumplist: <C-o> / <C-i>).
map('Cb', '<C-o>', 'go back')
map('CB', '<C-i>', 'go forward')

-- ── Understand ───────────────────────────────────────────────
map('Ch', needs('hover', 'hover documentation', function() vim.lsp.buf.hover({ border = 'rounded' }) end), 'hover documentation')
map('Cg', needs('signatureHelp', 'signature help', function() vim.lsp.buf.signature_help({ border = 'rounded' }) end), 'signature help')

-- ── Change ───────────────────────────────────────────────────
map('Cn', needs('rename', 'rename', vim.lsp.buf.rename), 'rename symbol…')
map('Ca', needs('codeAction', 'code actions', vim.lsp.buf.code_action), 'code actions…', { 'n', 'x' })

-- ── Problems (diagnostics) ───────────────────────────────────
-- These come from linters as well as language servers, so no LSP check.
map('Ce', function()
  if not vim.diagnostic.open_float({ scope = 'cursor' }) then
    if not vim.diagnostic.open_float({ scope = 'line' }) then info('No problem here') end
  end
end, 'problem at cursor')
local function jump(count)
  return function()
    if #vim.diagnostic.get(0) == 0 then info('No problems in this file') return end
    vim.diagnostic.jump({ count = count, float = true })
  end
end
map('C]', jump(1),  'next problem')
map('C[', jump(-1), 'previous problem')
map('Cq', telescope('diagnostics', { bufnr = 0 }), 'problems in this file')
map('CQ', telescope('diagnostics'),               'problems in the project')

-- ── Server ───────────────────────────────────────────────────
map('Cl', '<Cmd>checkhealth vim.lsp<CR>', 'language server info')
map('CL', needs_lsp(function()
  local names = vim.tbl_map(function(c) return c.name end, clients())
  vim.cmd('lsp restart')
  info('Restarting ' .. table.concat(names, ', '))
end), 'restart language server')

-- ── State column ─────────────────────────────────────────────
-- Cl: the attached server(s). Other entries: a dimmed note when this
-- file's server can't do it (nothing when it can, or with no server).
function M.state(key, _, buf)
  if key == 'Cl' then
    local names = server_names(buf)
    return names ~= '' and names or 'none'
  end
  local method = METHOD[key]
  if not method or #clients(buf) == 0 or supports(method, buf) then return nil end
  if key == 'CD' and supports('definition', buf) then return { text = 'uses definition', dim = true } end
  if key == 'Ct' and vim.bo[buf or 0].filetype == 'fortran' then return { text = 'by search', dim = true } end
  return { text = 'not supported', dim = true }
end

return M
