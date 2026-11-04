-- ============================================================
-- features/file-history.lua — undo / redo for file operations in the tree
--
-- The menu bar's undo / redo icons (features/topbar.lua) act on this
-- history while the file tree is the focused window; in a file they undo
-- text, as before. In the tree also: u / Ctrl+Z undo, U / Ctrl+Y redo.
--
-- What is recorded (from neo-tree's events and the tree's trash):
--   rename, move (cut + paste)  → undo moves it back
--   copy (paste), new file/dir  → undo moves the new item to the trash
--   delete (moved to the trash) → undo restores it from the trash
-- Several items done by one action (a multi-selection paste or delete)
-- are one step. Nothing is ever deleted for good: undoing a copy or a
-- new file puts it in the trash, where redo fetches it back from.
--
-- Refuses rather than overwrites: if something now sits where an item
-- would go back to, or a file it would move has unsaved changes in a
-- buffer, that step is left alone and kept on the history.
--
-- For this Neovim session only; the history starts empty on restart.
-- Added 2026-11-03.
-- ============================================================

local M = {}

local uv = vim.uv
local undo_stack, redo_stack = {}, {}
local MAX = 50
local GROUP_MS = 1500           -- events this close together are one step
local last_record = 0
local replaying = false

local function info(msg, level) vim.notify(msg, level or vim.log.levels.INFO) end
local function short(p) return vim.fn.fnamemodify(p, ':~:.') end
local function exists(p) return uv.fs_lstat(p) ~= nil end

local function changed()
  pcall(function() require('neo-tree.sources.manager').refresh('filesystem') end)
  pcall(vim.cmd, 'redrawtabline')
end

-- ── Trash (gio) ──────────────────────────────────────────────
local function trash_list()
  local out, set = vim.fn.systemlist({ 'gio', 'trash', '--list' }), {}
  if vim.v.shell_error ~= 0 then return set end
  for _, l in ipairs(out) do
    local uri, orig = l:match('^(%S+)\t(.*)$')
    if uri then set[uri] = orig end
  end
  return set
end

-- The trash entry that appeared since `before` for `path`.
local function new_trash_entry(before, path)
  for uri, orig in pairs(trash_list()) do
    if not before[uri] and orig == path then return uri end
  end
end

-- Move to the trash; returns the trash URI (for restoring), or nil + why.
local function trash(path)
  local before = trash_list()
  vim.fn.system({ 'gio', 'trash', path })
  if vim.v.shell_error ~= 0 then return nil, 'could not move ' .. short(path) .. ' to the trash' end
  return new_trash_entry(before, path) or ''
end

local function restore(uri, path)
  if exists(path) then return false, short(path) .. ' already exists' end
  if not uri or uri == '' then return false, 'trash entry for ' .. short(path) .. ' not found' end
  vim.fn.system({ 'gio', 'trash', '--restore', uri })
  if vim.v.shell_error ~= 0 or not exists(path) then
    return false, 'could not restore ' .. short(path) .. ' (emptied from the trash?)'
  end
  return true
end

-- ── Buffers follow a moved file ──────────────────────────────
local function buffers_under(path)
  local list = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name == path or vim.startswith(name, path .. '/') then list[#list + 1] = b end
  end
  return list
end

local function unsaved_under(path)
  for _, b in ipairs(buffers_under(path)) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then return b end
  end
end

local function follow(from, to)
  for _, b in ipairs(buffers_under(from)) do
    local name = vim.api.nvim_buf_get_name(b)
    local nb = vim.fn.bufadd(to .. name:sub(#from + 1))
    vim.fn.bufload(nb)
    vim.bo[nb].buflisted = true
    for _, w in ipairs(vim.fn.win_findbuf(b)) do vim.api.nvim_win_set_buf(w, nb) end
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end
end

local function move(from, to)
  if not exists(from) then return false, short(from) .. ' is no longer there' end
  if exists(to) then return false, short(to) .. ' already exists' end
  local b = unsaved_under(from)
  if b then return false, short(vim.api.nvim_buf_get_name(b)) .. ' has unsaved changes' end
  vim.fn.mkdir(vim.fn.fnamemodify(to, ':h'), 'p')
  local ok, err = uv.fs_rename(from, to)
  if not ok then return false, err end
  follow(from, to)
  return true
end

-- Wipe buffers of an item that went to the trash (so :w can't revive it).
local function drop_buffers(path)
  for _, b in ipairs(buffers_under(path)) do pcall(vim.api.nvim_buf_delete, b, { force = true }) end
end

-- ── Steps ────────────────────────────────────────────────────
-- op: { kind = 'move', from, to } | { kind = 'create', path, uri }
--     | { kind = 'trash', path, uri }
local function describe(op)
  if op.kind == 'move' then
    if vim.fn.fnamemodify(op.from, ':h') == vim.fn.fnamemodify(op.to, ':h') then
      return 'rename ' .. vim.fn.fnamemodify(op.from, ':t') .. ' → ' .. vim.fn.fnamemodify(op.to, ':t')
    end
    return 'move ' .. short(op.from) .. ' → ' .. short(op.to)
  elseif op.kind == 'create' then
    return 'add ' .. short(op.path)
  end
  return 'delete ' .. short(op.path)
end

local function undo_op(op)
  if op.kind == 'move' then return move(op.to, op.from) end
  if op.kind == 'create' then
    if not exists(op.path) then return false, short(op.path) .. ' is no longer there' end
    local b = unsaved_under(op.path)
    if b then return false, short(vim.api.nvim_buf_get_name(b)) .. ' has unsaved changes' end
    local uri, err = trash(op.path)
    if not uri then return false, err end
    op.uri = uri
    drop_buffers(op.path)
    return true
  end
  return restore(op.uri, op.path)                      -- trash
end

local function redo_op(op)
  if op.kind == 'move' then return move(op.from, op.to) end
  if op.kind == 'create' then return restore(op.uri, op.path) end
  local b = unsaved_under(op.path)                     -- trash again
  if b then return false, short(vim.api.nvim_buf_get_name(b)) .. ' has unsaved changes' end
  local uri, err = trash(op.path)
  if not uri then return false, err end
  op.uri = uri
  drop_buffers(op.path)
  return true
end

-- Run a step's operations (in reverse for undo); stop at the first that
-- can't be done, keeping the rest (and that one) on the stack.
local function run(from_stack, to_stack, fn, reverse, verb)
  local step = table.remove(from_stack)
  if not step then
    info('Nothing to ' .. verb:lower() .. ' in the file tree')
    return
  end
  replaying = true
  local done, failed, why = {}, {}, nil
  local n = #step
  for i = 1, n do
    local op = step[reverse and (n - i + 1) or i]
    if why then
      table.insert(failed, op)
    else
      local ok, err = fn(op)
      if ok then table.insert(done, op) else why = err; table.insert(failed, op) end
    end
  end
  replaying = false
  if #done > 0 then
    -- What was done goes to the other stack in its original order.
    if reverse then
      local r = {}
      for i = #done, 1, -1 do r[#r + 1] = done[i] end
      done = r
    end
    table.insert(to_stack, done)
  end
  if #failed > 0 then
    if reverse then
      local r = {}
      for i = #failed, 1, -1 do r[#r + 1] = failed[i] end
      failed = r
    end
    table.insert(from_stack, failed)
  end
  changed()
  if #done > 0 then
    local what = #done == 1 and describe(done[1]) or (#done .. ' items (' .. describe(done[1]) .. ', …)')
    info(verb .. ': ' .. what)
  end
  if why then info(verb .. ' stopped: ' .. why, vim.log.levels.WARN) end
end

function M.undo() run(undo_stack, redo_stack, undo_op, true, 'Undo') end
function M.redo() run(redo_stack, undo_stack, redo_op, false, 'Redo') end
function M.can_undo() return #undo_stack > 0 end
function M.can_redo() return #redo_stack > 0 end

function M.record(op)
  if replaying then return end
  local now = uv.now()
  local top = undo_stack[#undo_stack]
  if top and now - last_record < GROUP_MS then
    table.insert(top, op)
  else
    table.insert(undo_stack, { op })
    if #undo_stack > MAX then table.remove(undo_stack, 1) end
  end
  last_record = now
  redo_stack = {}
  pcall(vim.cmd, 'redrawtabline')
end

-- For the tree's trash (plugins/neo-tree.lua): trash with a restorable
-- record. Returns true on success.
function M.trash(path)
  local uri, err = trash(path)
  if not uri then info(err, vim.log.levels.ERROR) return false end
  M.record({ kind = 'trash', path = path, uri = uri })
  return true
end

-- ── neo-tree events ──────────────────────────────────────────
pcall(function()
  local events = require('neo-tree.events')
  local function on_move(args)
    if type(args) == 'table' and args.source and args.destination then
      M.record({ kind = 'move', from = args.source, to = args.destination })
    end
  end
  events.subscribe({ event = events.FILE_RENAMED, handler = on_move })
  events.subscribe({ event = events.FILE_MOVED, handler = on_move })
  events.subscribe({ event = events.FILE_ADDED, handler = function(path)
    if type(path) == 'string' then M.record({ kind = 'create', path = path }) end
  end })
end)

return M
