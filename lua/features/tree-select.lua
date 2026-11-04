-- ============================================================
-- features/tree-select.lua — select several files / folders in neo-tree
--
-- The usual file-manager way:
--   Ctrl+click    add or remove one item (the item clicked before stays
--                 selected, so Ctrl+clicking a second one gives two)
--   Shift+click   select every item from the last clicked one to this one
--   plain click / moving with the keys   drops the selection
-- Selected items are highlighted (Visual). The right-click menu's Cut /
-- Copy / Delete (plugins/neo-tree.lua) act on all of them when the click
-- is on one of them; right-clicking elsewhere drops the selection first.
-- Paste is unchanged: it pastes everything that was cut / copied into the
-- clicked folder. Cut / copy use neo-tree's own multi-item commands (the
-- ones behind its visual-mode x / y); delete moves each to the trash.
--
-- Shift+click: Ghostty keeps Shift+click for its own text selection unless
-- the program asks for it (XTSHIFTESCAPE), so Neovim asks while it runs
-- and hands it back on exit / suspend. Inside Neovim a Shift+drag then no
-- longer makes a terminal selection; outside Neovim nothing changes.
-- Added 2026-11-03.
-- ============================================================

local M = {}

local ns = vim.api.nvim_create_namespace('tree-select')
local selected = {}     -- node id → true
local anchor = nil      -- id of the last clicked item (Shift+click range start)
local expect_line = nil -- our own cursor move, which must not clear

local function t(k) return vim.api.nvim_replace_termcodes(k, true, false, true) end

local function state_for(win)
  local ok, state = pcall(require('neo-tree.sources.manager').get_state_for_window, win)
  if ok and state and state.tree and state.name == 'filesystem' then return state end
end

local function is_tree_win(win)
  return win ~= 0 and vim.api.nvim_win_is_valid(win)
    and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'neo-tree'
end

-- Not the "← .." line and not the root folder.
local function selectable(node)
  return node and node.id ~= '__nav_up__' and node:get_depth() > 1
end

function M.paint(state)
  if not (state and state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)) then return end
  vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
  for id in pairs(selected) do
    local node, first, last = state.tree:get_node(id)
    if node and first then
      for l = first, last or first do
        pcall(vim.api.nvim_buf_set_extmark, state.bufnr, ns, l - 1, 0,
          { line_hl_group = 'Visual', priority = 200 })
      end
    end
  end
end

function M.clear(state)
  if next(selected) == nil then return end
  selected = {}
  M.paint(state)
end

local function count() local n = 0 for _ in pairs(selected) do n = n + 1 end return n end

-- ── Clicks ───────────────────────────────────────────────────
function M.click(kind, win, line)
  if not is_tree_win(win) then return end
  vim.api.nvim_set_current_win(win)
  local state = state_for(win)
  if not state then return end
  local node = state.tree:get_node(line)
  if not selectable(node) then return end
  local before = state.tree:get_node()   -- the item clicked / moved to before

  if kind == 'ctrl' then
    if next(selected) == nil and selectable(before) and before.id ~= node.id then
      selected[before.id] = true
    end
    if selected[node.id] then selected[node.id] = nil else selected[node.id] = true end
    anchor = node.id
  else
    local from = anchor or (selectable(before) and before.id) or node.id
    local _, a = state.tree:get_node(from)
    a = a or line
    selected = {}
    for l = math.min(a, line), math.max(a, line) do
      local n = state.tree:get_node(l)
      if selectable(n) then selected[n.id] = true end
    end
    anchor = anchor or from
  end

  expect_line = line
  pcall(vim.api.nvim_win_set_cursor, win, { line, vim.api.nvim_win_get_cursor(win)[2] })
  M.paint(state)
end

-- Right-click (plugins/neo-tree.lua): outside the selection drops it.
function M.on_right_click(win, line)
  local state = state_for(win)
  if not state then return end
  local node = state.tree:get_node(line)
  if not (node and selected[node.id]) then M.clear(state) end
  if node then anchor = node.id end
  expect_line = line
end

-- ── Menu actions ─────────────────────────────────────────────
-- Cut / Copy / Delete from the right-click menu: on the selection when
-- there is one, else the clicked item (the tree's own key, as before).
function M.menu(action, key)
  vim.schedule(function()
    local win = vim.api.nvim_get_current_win()
    local state = state_for(win)
    local nodes = {}
    if state then
      for id in pairs(selected) do
        local n = state.tree:get_node(id)
        if n then nodes[#nodes + 1] = n end
      end
    end
    if #nodes == 0 then
      vim.api.nvim_feedkeys(key, 'm', false)
      return
    end
    table.sort(nodes, function(a, b) return a.id < b.id end)
    local fs = require('neo-tree.sources.filesystem.commands')
    if action == 'cut' then
      fs.cut_to_clipboard_visual(state, nodes)
    elseif action == 'copy' then
      fs.copy_to_clipboard_visual(state, nodes)
    elseif action == 'delete' then
      -- Folders first removed take their contents along; skip anything
      -- inside a folder that is itself being trashed.
      for _, n in ipairs(nodes) do
        local inside = false
        for _, o in ipairs(nodes) do
          if o ~= n and vim.startswith(n.id, o.id .. '/') then inside = true break end
        end
        if not inside then _G.___neotree_trash_node(n) end
      end
    end
    local what = ({ cut = 'Cut', copy = 'Copied', delete = 'Trashed' })[action]
    if action ~= 'delete' then
      vim.notify(('%s %d items — right-click a folder › Paste'):format(what, #nodes), vim.log.levels.INFO)
    end
    selected = {}
    M.paint(state)
  end)
end

-- ── Mappings ─────────────────────────────────────────────────
-- Global, like the right-click: the click is caught even when focus is in
-- another window. Anywhere but the tree the keys do what they always did.
for lhs, kind in pairs({ ['<C-LeftMouse>'] = 'ctrl', ['<S-LeftMouse>'] = 'shift' }) do
  vim.keymap.set({ 'n', 'i', 'x', 's' }, lhs, function()
    local mp = vim.fn.getmousepos()
    if mp.line > 0 and is_tree_win(mp.winid) then
      return ("<C-\\><C-n><Cmd>lua require('features.tree-select').click('%s', %d, %d)<CR>")
        :format(kind, mp.winid, mp.line)
    end
    return lhs
  end, { expr = true, desc = 'File tree: ' .. (kind == 'ctrl' and 'add / remove item' or 'select range') })
end

-- ── Keep it right ────────────────────────────────────────────
local group = vim.api.nvim_create_augroup('tree-select', { clear = true })

-- A plain click or a key move in the tree drops the selection.
vim.api.nvim_create_autocmd('CursorMoved', {
  group = group,
  callback = function(ev)
    if vim.bo[ev.buf].filetype ~= 'neo-tree' then return end
    local line = vim.api.nvim_win_get_cursor(0)[1]
    if expect_line and line == expect_line then expect_line = nil return end
    expect_line = nil
    if next(selected) ~= nil then
      M.clear(state_for(vim.api.nvim_get_current_win()))
    end
    local state = state_for(vim.api.nvim_get_current_win())
    local node = state and state.tree:get_node()
    anchor = selectable(node) and node.id or nil
  end,
})

-- neo-tree redraws its buffer (expanding a folder, after a paste, file
-- changes): put the highlight back.
pcall(function()
  local events = require('neo-tree.events')
  events.subscribe({
    event = events.AFTER_RENDER,
    handler = function(state)
      if state and state.name == 'filesystem' and next(selected) ~= nil then
        vim.schedule(function() M.paint(state) end)
      end
    end,
  })
end)

-- Ask the terminal for Shift+click (XTSHIFTESCAPE) while Neovim runs.
local function shift_capture(on)
  pcall(vim.api.nvim_ui_send, on and '\27[>1s' or '\27[>0s')
end
vim.api.nvim_create_autocmd({ 'UIEnter', 'VimResume' }, { group = group, callback = function() shift_capture(true) end })
vim.api.nvim_create_autocmd({ 'VimLeavePre', 'VimSuspend' }, { group = group, callback = function() shift_capture(false) end })
if vim.v.vim_did_enter == 1 then shift_capture(true) end

M.count = count
return M
