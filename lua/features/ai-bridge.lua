-- ============================================================
-- features/ai-bridge.lua — what `nvim-ide` (bin/nvim-ide) can do
--
-- Claude, running in a terminal inside this Neovim, has $NVIM (this
-- Neovim's RPC socket). bin/nvim-ide calls
--     luaeval("require'features.ai-bridge'.call(_A)", [sub, b64(arg)...])
-- over it; each argument is base64-encoded so any text survives the
-- trip. call() returns a string, which nvim-ide prints. A failure comes
-- back as "ERROR: …" and nvim-ide exits 1.
--
-- Keys and commands run in the last editor window (features/ai.lua
-- tracks it), not in the Claude terminal, the same as if the user had
-- clicked there and typed them.
-- ============================================================

local M = {}
local utils = require('core.utils')

local function editor_win()
  local w = vim.g.ai_last_editor_win
  if w and vim.api.nvim_win_is_valid(w) and utils.is_editor_buf(vim.api.nvim_win_get_buf(w)) then
    return w
  end
  return utils.find_editor_win()
end

local function leader_name(lhs)
  local leader = vim.g.mapleader or '\\'
  if lhs:sub(1, #leader) == leader then return '<leader>' .. lhs:sub(#leader + 1) end
  return lhs
end

local cmds = {}

function cmds.state()
  local w = editor_win()
  local out = { cwd = vim.fn.getcwd(), mode = vim.api.nvim_get_mode().mode }
  if w then
    local b = vim.api.nvim_win_get_buf(w)
    local cur = vim.api.nvim_win_get_cursor(w)
    out.file = vim.api.nvim_buf_get_name(b)
    out.filetype = vim.bo[b].filetype
    out.modified = vim.bo[b].modified
    out.cursor = { line = cur[1], col = cur[2] + 1 }
    out.lines = vim.api.nvim_buf_line_count(b)
  end
  out.buffers = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.bo[b].buftype == '' then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= '' then
        out.buffers[#out.buffers + 1] = { file = name, modified = vim.bo[b].modified }
      end
    end
  end
  out.terminals = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == 'terminal' then
      out.terminals[#out.terminals + 1] = { buf = b, name = vim.api.nvim_buf_get_name(b) }
    end
  end
  return vim.json.encode(out)
end

-- Normal-mode keymaps that have a description: "lhs<TAB>desc" per line.
-- Global ones plus the editor buffer's own (LSP, filetype tools).
function cmds.keymaps(filter)
  local seen, rows = {}, {}
  local function add(list)
    for _, m in ipairs(list) do
      local lhs = leader_name(m.lhs)
      if m.desc and m.desc ~= '' and not seen[lhs] then
        seen[lhs] = true
        rows[#rows + 1] = lhs .. '\t' .. m.desc
      end
    end
  end
  local w = editor_win()
  if w then add(vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(w), 'n')) end
  add(vim.api.nvim_get_keymap('n'))
  table.sort(rows)
  if filter and filter ~= '' then
    local f = filter:lower()
    rows = vim.tbl_filter(function(r) return r:lower():find(f, 1, true) ~= nil end, rows)
  end
  return table.concat(rows, '\n')
end

-- Type keys in the editor window, mappings included ("<leader>cb", "gg").
-- The request arrives while Neovim is usually in terminal mode in the
-- Claude panel, and terminal mode would swallow queued keys itself. So
-- the queue first leaves terminal mode (<C-\><C-n>), then a <Cmd> step
-- moves to the editor window and only then queues the keys.
local pending_keys = {}

function M._go()
  local keys = table.remove(pending_keys, 1)
  if not keys then return end
  local w = editor_win()
  if not w then
    vim.notify('nvim-ide run: no editor window', vim.log.levels.WARN)
    return
  end
  vim.api.nvim_set_current_win(w)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'mt', false)
end

function cmds.run(keys)
  if not keys or keys == '' then error('run: no keys given') end
  if not editor_win() then error('no editor window to run keys in') end
  pending_keys[#pending_keys + 1] = keys
  vim.api.nvim_feedkeys(vim.keycode([[<C-\><C-n><Cmd>lua require'features.ai-bridge']] .. '._go()<CR>'), 'n', false)
  return 'queued in the editor window: ' .. keys
end

-- An Ex command in the editor window; returns its output.
function cmds.cmd(ex)
  if not ex or ex == '' then error('cmd: no command given') end
  local w = editor_win()
  local res
  local function go() res = vim.api.nvim_exec2(ex, { output = true }) end
  if w then vim.api.nvim_win_call(w, go) else go() end
  return res.output or ''
end

-- A Lua chunk (in the editor window); returns what it returns.
function cmds.lua(code)
  if not code or code == '' then error('lua: no code given') end
  local chunk, err = loadstring(code)
  if not chunk then chunk, err = loadstring('return ' .. code) end
  if not chunk then error(err) end
  local w = editor_win()
  local res
  local function go() res = vim.F.pack_len(chunk()) end
  if w then vim.api.nvim_win_call(w, go) else go() end
  if res.n == 0 then return '' end
  local parts = {}
  for i = 1, res.n do
    local v = res[i]
    parts[#parts + 1] = type(v) == 'string' and v or vim.inspect(v)
  end
  return table.concat(parts, '\n')
end

-- Last `n` lines (default 60) of a terminal buffer: by number, or the most
-- recent non-Claude terminal (the build / run terminal) when omitted.
function cmds.term(which, n)
  n = tonumber(n) or 60
  local buf = tonumber(which)
  if not buf then
    local best
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == 'terminal'
        and not vim.b[b].claudecode_native_terminal then
        best = b   -- higher numbers are newer
      end
    end
    buf = best
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then error('no terminal buffer') end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  while #lines > 0 and lines[#lines]:match('^%s*$') do lines[#lines] = nil end
  return table.concat(vim.list_slice(lines, math.max(1, #lines - n + 1)), '\n')
end

function cmds.messages()
  return vim.api.nvim_exec2('messages', { output = true }).output or ''
end

-- Open a file (optionally at a line) in the editor window.
function cmds.open(file, line)
  if not file or file == '' then error('open: no file given') end
  local w = editor_win()
  if not w then error('no editor window') end
  vim.api.nvim_win_call(w, function()
    vim.cmd('edit ' .. vim.fn.fnameescape(file))
    if tonumber(line) then pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(line), 0 }) end
  end)
  return 'opened ' .. vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
end

function M.call(argv)
  local sub = argv[1]
  local args = {}
  for i = 2, #argv do args[#args + 1] = vim.base64.decode(argv[i]) end
  local f = cmds[sub]
  if not f then return 'ERROR: unknown command ' .. tostring(sub) end
  local ok, res = pcall(f, unpack(args))
  if not ok then return 'ERROR: ' .. tostring(res) end
  return res == nil and '' or tostring(res)
end

return M
