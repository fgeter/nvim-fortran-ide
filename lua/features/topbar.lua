-- ============================================================
-- features/topbar.lua — Clickable IDE menu bar (homegrown)
--
-- A menu bar across the very top of the screen, above the buffer tabs,
-- with four left-click drop-down menus:
--
--     Compile   Debug   Find   Git          ← screen row 0 (tabline)
--    init.lua │ dap.lua │ ui.lua            ← screen row 1 (bufferline)
--
-- Each menu lists the same actions as its <leader> prefix
-- (<leader>c / <leader>d / <leader>s / <leader>g).  Choosing an entry
-- feeds that keymap, so there is exactly one implementation of every
-- action — the bar is a second door onto the existing keymaps, never a
-- copy of their logic.
--
-- The bar only exists inside a coding project: cwd (or a parent) must
-- contain one of PROJECT_MARKERS.  Checked at startup and on every :cd,
-- so navigating out of a project removes the bar (handing the tabline
-- straight back to bufferline) while navigating back restores it.
--
-- ── How two rows are won from a one-row budget ───────────────
-- Neovim reserves exactly one global row at the very top — the tabline —
-- and bufferline owns it by default.  Nothing can be drawn above the
-- tabline, so putting the menu above the tabs means the menu *is* the
-- tabline and the tabs have to move down a row:
--
--   • vim.o.tabline renders this module's menu (build_tabline).
--     Tablines support native %@fn@ click regions, so a click arrives
--     in ___topbar_click with the menu index — no mouse-position
--     arithmetic, and no global <LeftMouse> mapping to intercept.
--   • bufferline moves into the *statusline* of a carrier window pinned
--     across the top of the window area.  That window is squeezed to
--     zero height (which is what vim.o.winminheight = 0 buys), so it
--     contributes only its statusline — exactly one screen row — and
--     the tab strip keeps its own highlights, click handlers and
--     neo-tree offset because it is still rendered by the same
--     _G.nvim_bufferline() that the tabline used to call.
--
-- The cost of a real window is that any `topleft vsplit` (neo-tree's
-- sidebar, diffview, …) re-nests the layout and pushes the carrier
-- aside.  ensure() detects that — not at the top row, not at column 0,
-- or no longer spanning vim.o.columns — and rebuilds it, which restores
-- the full-width top row without disturbing the other windows or
-- stealing focus (nvim_open_win is called with enter = false).
--
-- LAZY: n/a — the module registers autocmds and two globals; the bar
--       itself is only built inside a project.
-- ============================================================

if vim.g.loaded_topbar then return end
vim.g.loaded_topbar = true

local utils = require('core.utils')

-- Filetype stamped on the carrier buffer. Other modules key off this to
-- skip the bar when hunting for a "real" window (features/neotree-recovery).
local BAR_FT = 'topbar'

-- What the tabline shows when the bar is down. Captured at load time,
-- i.e. after plugins/ui.lua ran bufferline's setup, so this holds
-- bufferline's own '%!v:lua.nvim_bufferline()'.
local BUFFERLINE_TABLINE = vim.o.tabline

-- A directory counts as a coding project when it — or any parent — holds
-- one of these. .git covers repos of any language; the rest cover build
-- systems that may live outside a repo. .nvim.lua is this config's own
-- per-project marker (see core/options.lua exrc).
local PROJECT_MARKERS = {
  '.git', '.nvim.lua',
  'CMakeLists.txt', 'Makefile', 'GNUmakefile',
  'pyproject.toml', 'setup.py', 'package.json', 'Cargo.toml', 'go.mod',
}

-- ── Menu contents ────────────────────────────────────────────
-- The full inventory of each <leader> prefix. Entries whose keymap does
-- not exist in the current context are still listed, greyed out and
-- inert — so the menus stay a stable, predictable reference rather than
-- changing shape as cmake-tools activates or a filetype attaches.
--
-- `label` is only a fallback: when the keymap exists its own `desc` wins,
-- so renaming a keymap's description also renames the menu entry. The
-- "CMake: " / "Make: " / "DAP: " / … prefix is stripped (the menu title
-- already says which family it is).
local MENUS = {
  {
    id = 'c', label = 'Compile', icon = '',
    items = {
      { key = 'cp', label = 'Select preset + generate' },
      { key = 'cg', label = 'Generate' },
      { key = 'cb', label = 'Build (all CPU cores)' },
      { key = 'cB', label = 'Build single-threaded' },
      { key = 'cx', label = 'Clean' },
      { key = 'cd', label = 'Delete build directory' },
      { key = 'cr', label = 'Run executable' },
    },
  },
  {
    id = 'd', label = 'Debug', icon = '',
    items = {
      { key = 'ds', label = 'Start / continue - F5' },
      { key = 'db', label = 'Toggle breakpoint - F4' },
      { key = 'dB', label = 'Conditional breakpoint - F8' },
      { key = 'dL', label = 'Log point' },
      { key = 'dx', label = 'Clear all breakpoints - Shift-F4' },
      { key = 'dn', label = 'Step over - F2' },
      { key = 'di', label = 'Step into - F1' },
      { key = 'do', label = 'Step out - F3' },
      { key = 'dc', label = 'Run to cursor - F6' },
      { key = 'dr', label = 'Restart' },
      { key = 'dq', label = 'Terminate - F10' },
      { key = 'dU', label = 'Toggle UI - F7' },
      { key = 'dC', label = 'Open console float' },
      { key = 'dR', label = 'Open REPL' },
      { key = 'de', label = 'Eval expression / selection' },
      { key = 'dw', label = 'Add to watches' },
      { key = 'dh', label = 'Toggle hover' },
      { key = 'dF', label = 'Show F-key reference' },
    },
  },
  {
    id = 's', label = 'Find', icon = '',
    items = {
      { key = 'sf', label = 'Files (all, including hidden/ignored)' },
      { key = 'sg', label = 'Live grep' },
      { key = 'sw', label = 'Word under cursor' },
      { key = 's/', label = 'Grep in open buffers' },
      { key = 'sa', label = 'Files containing ALL words' },
      { key = 'sR', label = 'Project-wide replace (grug-far)' },
      { key = 'sn', label = 'Neovim config files' },
      { key = 'sd', label = 'Diagnostics' },
      { key = 'sh', label = 'Help tags' },
      { key = 'sk', label = 'Keymaps' },
      { key = 'sc', label = 'Commands' },
      { key = 'ss', label = 'Telescope pickers' },
      { key = 'sr', label = 'Resume last picker' },
    },
  },
  {
    id = 'g', label = 'Git', icon = '',
    items = {
      { key = 'gg', label = 'Open lazygit' },
      { key = 'gc', label = 'Commit' },
      { key = 'gp', label = 'Pull' },
      { key = 'gP', label = 'Push' },
      { key = 'gb', label = 'Create branch' },
      { key = 'gs', label = 'Switch branch' },
      { key = 'gm', label = 'Merge branch' },
      { key = 'gd', label = 'Delete branch' },
      { key = 'gw', label = 'Review working-tree changes (diffview)' },
      { key = 'gv', label = 'Review changes against branch/ref (diffview)' },
      { key = 'gf', label = 'Diff current file against branch/ref (diffview)' },
      { key = 'gh', label = 'File history (diffview)' },
      { key = 'gx', label = 'Discard changes in buffer' },
      { key = 'gR', label = 'Check if origin is ahead' },
    },
  },
}

-- ── Highlights ───────────────────────────────────────────────
-- Derived from the active colorscheme rather than hardcoded, so the bar
-- follows catppuccin (or anything else) automatically. :colorscheme runs
-- `hi clear`, which wipes these, hence the ColorScheme autocmd below.
local function setup_highlights()
  local function attr(group, key)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    return ok and hl and hl[key] or nil
  end

  -- Pmenu carries a solid background in every theme worth using — exactly
  -- what a menu bar needs on a transparent background.
  local bg   = attr('Pmenu', 'bg')
  local fg   = attr('Pmenu', 'fg') or attr('Normal', 'fg')
  local blue = attr('Function', 'fg') or attr('Directory', 'fg')
  local dim  = attr('Comment', 'fg')

  vim.api.nvim_set_hl(0, 'TopBar',        { bg = bg, fg = fg })
  vim.api.nvim_set_hl(0, 'TopBarFill',    { bg = bg, fg = fg })
  vim.api.nvim_set_hl(0, 'TopBarTitle',   { bg = bg, fg = blue, bold = true })
  vim.api.nvim_set_hl(0, 'TopBarTitleOn', { link = 'PmenuSel' })
  vim.api.nvim_set_hl(0, 'TopBarKey',     { bg = bg, fg = blue })
  vim.api.nvim_set_hl(0, 'TopBarItem',    { bg = bg, fg = fg })
  vim.api.nvim_set_hl(0, 'TopBarDim',     { bg = bg, fg = dim })
  vim.api.nvim_set_hl(0, 'TopBarBorder',  { bg = bg, fg = blue })
end

setup_highlights()
vim.api.nvim_create_autocmd('ColorScheme', {
  desc     = 'Re-derive top-bar highlights after :hi clear',
  group    = vim.api.nvim_create_augroup('topbar-highlights', { clear = true }),
  callback = setup_highlights,
})

-- ── State ────────────────────────────────────────────────────
local ns        = vim.api.nvim_create_namespace('topbar')
local bar_buf   = nil    -- the single scratch buffer shown in every carrier
local bars      = {}     -- tabpage handle → carrier window handle
local segments  = {}     -- title display-column ranges, rebuilt on each render
local busy      = false  -- true while we create/close a carrier (blocks re-entry)
local pending   = false  -- an ensure() is already scheduled
local menu      = nil    -- open drop-down: { win, buf, menu, items, from_win, from_mode }
local last_win  = nil    -- window focused before the menu opened
local user_off  = false  -- :TopbarToggle turned it off; stay off until toggled back
local saved_wmh = nil    -- winminheight from before the carrier squeezed to 0

local function leader()
  return vim.g.mapleader == nil and '\\' or vim.g.mapleader
end

local function is_bar_win(win)
  if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then return false end
  return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == BAR_FT
end

-- ── Project detection ────────────────────────────────────────
local function in_project()
  return #vim.fs.find(PROJECT_MARKERS, {
    path   = vim.fn.getcwd(),
    upward = true,
    limit  = 1,
  }) > 0
end

-- ── Keymap lookup ────────────────────────────────────────────
-- Resolve an item against the keymaps that actually exist right now.
-- Buffer-local maps (<leader>ds from c-tools/web-tools/java-tools, the
-- LSP maps, …) only resolve against the *editor* buffer, never the
-- carrier's scratch buffer, so the lookup runs inside nvim_buf_call.
local function resolve(item, buf)
  local lhs = leader() .. item.key
  local map
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local ok, res = pcall(vim.api.nvim_buf_call, buf, function()
      return vim.fn.maparg(lhs, 'n', false, true)
    end)
    map = ok and res or {}
  else
    map = vim.fn.maparg(lhs, 'n', false, true)
  end

  local available = type(map) == 'table' and not vim.tbl_isempty(map)
  local label     = item.label
  if available and type(map.desc) == 'string' and map.desc ~= '' then
    -- 'CMake: build (all CPU cores)' → 'Build (all CPU cores)'
    local desc = map.desc:gsub('^%a[%w%+%-/ ]-:%s*', '')
    label = desc:sub(1, 1):upper() .. desc:sub(2)
  end
  return { key = item.key, lhs = lhs, label = label, available = available }
end

-- ── The menu bar itself (the tabline) ────────────────────────
-- Rebuilt on every redraw, which keeps `segments` — the display-column
-- range of each title, used to place its drop-down and to hit-test the
-- clicks that arrive while a drop-down holds focus — always current.
-- %N@fn@…%X wraps each title in a click region carrying its index, so
-- Neovim delivers the click to ___topbar_click with no coordinate maths.
local function build_tabline()
  local parts, disp = {}, 1
  segments = {}
  for i, m in ipairs(MENUS) do
    local text  = ' ' .. (vim.g.have_nerd_font and (m.icon .. '  ') or '') .. m.label .. ' '
    local width = vim.fn.strdisplaywidth(text)
    segments[i] = { menu = m, disp_start = disp, disp_end = disp + width - 1 }
    parts[#parts + 1] = ('%%#%s#%%%d@v:lua.___topbar_click@%s%%X'):format(
      (menu and menu.menu.id == m.id) and 'TopBarTitleOn' or 'TopBarTitle', i, text)
    disp = disp + width
  end
  parts[#parts + 1] = '%#TopBarFill#'
  return table.concat(parts)
end

_G.___topbar_tabline = build_tabline

-- Forward local: the click handler is installed with the tabline, but
-- toggle_menu needs the drop-down machinery defined further down.
local toggle_menu

_G.___topbar_click = function(minwid, _, button)
  if button ~= 'l' then return end
  local seg = segments[minwid]
  if not seg then return end
  -- Opening a window from inside a tabline expression is not allowed;
  -- run it once Neovim is back in a normal state.
  vim.schedule(function() toggle_menu(seg) end)
end

-- ── Carrier window lifecycle ─────────────────────────────────
local function make_buf()
  if bar_buf and vim.api.nvim_buf_is_valid(bar_buf) then return bar_buf end
  bar_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[bar_buf].buftype   = 'nofile'
  vim.bo[bar_buf].bufhidden = 'hide'
  vim.bo[bar_buf].swapfile  = false
  vim.bo[bar_buf].filetype  = BAR_FT
  return bar_buf
end

local function create_bar()
  -- A zero-height window contributes only its statusline, and Neovim
  -- only allows that with winminheight = 0. Remember the user's value so
  -- taking the bar down can put it back.
  if saved_wmh == nil then saved_wmh = vim.o.winminheight end
  vim.o.winminheight = 0

  local buf = make_buf()
  -- win = -1 makes the split span the whole tabpage width at its top.
  -- enter = false keeps focus where the user left it.
  local ok, win = pcall(vim.api.nvim_open_win, buf, false,
    { split = 'above', win = -1, height = 1 })
  if not ok then return nil end

  vim.wo[win].winfixheight   = true
  vim.wo[win].winfixbuf      = true
  vim.wo[win].number         = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn     = 'no'
  vim.wo[win].foldcolumn     = '0'
  vim.wo[win].cursorline     = false
  vim.wo[win].list           = false
  vim.wo[win].wrap           = false
  vim.wo[win].spell          = false
  vim.wo[win].winbar         = ''
  -- The whole point of the carrier: its statusline is the buffer-tab
  -- strip. _G.nvim_bufferline is the same renderer the tabline used to
  -- call (plugins/ui.lua wraps it for the clickable left arrow), so
  -- offsets, diagnostics, highlights and click handlers are unchanged.
  vim.wo[win].statusline = _G.nvim_bufferline and '%!v:lua.nvim_bufferline()' or ' '
  -- Whatever the tab strip does not paint (the gap after the last tab)
  -- falls back to the statusline groups, which in this config are a
  -- solid lavender rule — use bufferline's own fill instead.
  vim.wo[win].winhighlight =
    'Normal:TopBar,EndOfBuffer:TopBar,StatusLine:BufferLineFill,StatusLineNC:BufferLineFill'
  -- A statusline pads to the window width with the stl/stlnc fillchars,
  -- which this config sets to '─' to draw its window separators. On the
  -- tab strip that would trail a rule after the last tab; pad with blanks
  -- (carrying BufferLineFill from winhighlight above) instead.
  vim.wo[win].fillchars = 'stl: ,stlnc: '

  pcall(vim.api.nvim_win_set_height, win, 0)

  vim.o.showtabline = 2
  vim.o.tabline     = '%!v:lua.___topbar_tabline()'
  return win
end

local function close_bar(tab)
  local win = bars[tab]
  bars[tab] = nil
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

-- Hand the top row back to bufferline and undo the global option the
-- carrier needed. Called whenever the last carrier goes away.
local function restore_tabline()
  if next(bars) ~= nil then return end
  if vim.o.tabline == '%!v:lua.___topbar_tabline()' then
    vim.o.tabline = BUFFERLINE_TABLINE
  end
  if saved_wmh ~= nil then
    vim.o.winminheight = saved_wmh
    saved_wmh = nil
  end
end

-- The carrier is healthy only when it still owns the full top row:
-- column 0, full width, and no non-floating window above it.
local function bar_is_placed(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return false end
  local pos = vim.api.nvim_win_get_position(win)
  if pos[2] ~= 0 then return false end
  if vim.api.nvim_win_get_width(win) ~= vim.o.columns then return false end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= win and vim.api.nvim_win_get_config(w).relative == ''
        and vim.api.nvim_win_get_position(w)[1] < pos[1] then
      return false
    end
  end
  return true
end

-- Create, rebuild or remove the bar for the current tabpage.
local function ensure()
  if busy then return end
  if vim.fn.getcmdwintype() ~= '' then return end   -- command-line window: hands off
  if vim.v.exiting ~= vim.NIL then return end

  local tab = vim.api.nvim_get_current_tabpage()
  busy = true
  local ok, err = pcall(function()
    if user_off or not in_project() then
      close_bar(tab)
      restore_tabline()
      return
    end

    local win = bars[tab]
    if win and not vim.api.nvim_win_is_valid(win) then win, bars[tab] = nil, nil end

    -- Nothing but the carrier left (the last editor window was quit).
    local others = 0
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if w ~= win and vim.api.nvim_win_get_config(w).relative == '' then
        others = others + 1
      end
    end
    if win and others == 0 then
      -- nvim_win_close refuses on the very last window (E444), which is
      -- exactly the case that matters: the user typed :q on their last
      -- editor window and, without the bar, Neovim would have exited.
      -- Quit it instead so :q keeps meaning what it always meant.
      local closed = pcall(vim.api.nvim_win_close, win, true)
      bars[tab] = nil
      restore_tabline()
      if not closed then vim.cmd('confirm quit') end
      return
    end
    if others == 0 then return end   -- nothing to anchor to yet

    if bar_is_placed(win) then
      -- Equalising after a new split can hand the carrier a row back;
      -- take it away again rather than tearing the window down for it.
      if vim.api.nvim_win_get_height(win) ~= 0 then
        pcall(vim.api.nvim_win_set_height, win, 0)
      end
      return
    end
    close_bar(tab)
    bars[tab] = create_bar()
  end)
  busy = false
  if not ok then
    vim.notify('topbar: ' .. tostring(err), vim.log.levels.DEBUG)
  end
end

-- Coalesce the storm of Win* events a single :Neotree or :DiffviewOpen
-- produces into one rebuild, and run it after Neovim has settled the
-- layout rather than in the middle of it.
local function schedule_ensure()
  if pending or busy then return end
  pending = true
  vim.schedule(function()
    pending = false
    ensure()
  end)
end

-- ── Drop-down menu ───────────────────────────────────────────
local function close_menu()
  if not menu then return end
  local m = menu
  menu = nil
  if m.win and vim.api.nvim_win_is_valid(m.win) then
    pcall(vim.api.nvim_win_close, m.win, true)
  end
  if m.buf and vim.api.nvim_buf_is_valid(m.buf) then
    pcall(vim.api.nvim_buf_delete, m.buf, { force = true })
  end
  pcall(vim.cmd, 'redrawtabline')   -- drop the open title's highlight
end

-- Hand the action back to the keymap that owns it. Focus returns to the
-- window the user came from first, and a visual selection is restored
-- with gv so the visual-mode variants (<leader>sR, <leader>de, …) behave
-- exactly as they do from the keyboard.
local function run_item(entry)
  local m = menu
  close_menu()
  if not entry then return end
  if not entry.available then
    vim.notify(entry.label .. '  —  no keymap for <leader>' .. entry.key
      .. ' in this context', vim.log.levels.INFO)
    return
  end

  local target = m and m.from_win
  if not (target and vim.api.nvim_win_is_valid(target)) then
    target = utils.find_editor_win()
  end
  if target then pcall(vim.api.nvim_set_current_win, target) end

  local keys = entry.lhs
  if m and m.from_mode and m.from_mode:match('^[vV\22]') then keys = 'gv' .. keys end
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(keys, true, false, true), 'mt', false)
end

local function menu_entry_at(mp)
  if not menu or mp.winid ~= menu.win then return nil end
  if mp.line < 1 or mp.line > #menu.items then return nil end
  return mp.line
end

-- Which menu title (if any) sits under a mouse position. The tabline is
-- screen row 1 in getmousepos()'s 1-based coordinates, and it is not a
-- window, so this is the only way to hit-test it from a mapping.
local function title_at(mp)
  if mp.screenrow ~= 1 then return nil end
  if #segments == 0 then build_tabline() end
  for _, s in ipairs(segments) do
    if mp.screencol >= s.disp_start and mp.screencol <= s.disp_end then return s end
  end
  return nil
end

local function open_menu(seg)
  local from_win  = (last_win and vim.api.nvim_win_is_valid(last_win) and not is_bar_win(last_win))
                    and last_win or utils.find_editor_win()
  local from_mode = vim.fn.mode()
  local ctx_buf   = from_win and vim.api.nvim_win_get_buf(from_win) or nil

  local entries = {}
  for _, item in ipairs(seg.menu.items) do
    table.insert(entries, resolve(item, ctx_buf))
  end

  -- Layout: two leading spaces, the chord, two spaces, the label.
  local key_w, label_w = 0, 0
  for _, e in ipairs(entries) do
    key_w   = math.max(key_w,   vim.fn.strdisplaywidth(e.key))
    label_w = math.max(label_w, vim.fn.strdisplaywidth(e.label))
  end
  local width = 2 + key_w + 2 + label_w + 2

  local lines = {}
  for _, e in ipairs(entries) do
    local pad = string.rep(' ', label_w - vim.fn.strdisplaywidth(e.label))
    table.insert(lines, string.format('  %-' .. key_w .. 's  %s%s  ', e.key, e.label, pad))
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden  = 'wipe'

  for i, e in ipairs(entries) do
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 2, {
      end_col  = 2 + #e.key,
      hl_group = e.available and 'TopBarKey' or 'TopBarDim',
    })
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 2 + #e.key, {
      end_col  = #lines[i],
      hl_group = e.available and 'TopBarItem' or 'TopBarDim',
    })
  end

  -- The menu bar is the tabline (screen row 0), so the drop-down hangs
  -- from row 1: its top border replaces the tab strip while it is open,
  -- the way a menu overlays whatever is beneath it.
  local row    = 1
  local height = math.min(#lines, math.max(3, vim.o.lines - row - 4))
  local col    = math.max(0, math.min(seg.disp_start - 1, vim.o.columns - width - 2))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row      = row,
    col      = col,
    width    = width,
    height   = height,
    style    = 'minimal',
    border   = 'rounded',
    zindex   = 200,   -- above the horizontal scrollbar (zindex 150)
  })
  vim.wo[win].cursorline   = true
  vim.wo[win].winhighlight = 'Normal:TopBar,FloatBorder:TopBarBorder,CursorLine:PmenuSel'

  menu = { win = win, buf = buf, menu = seg.menu, items = entries,
           from_win = from_win, from_mode = from_mode }
  pcall(vim.cmd, 'redrawtabline')   -- light up the open title

  -- ── menu keys ──
  local function map(lhs, fn) vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true }) end
  map('<CR>', function()
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    run_item(menu and menu.items[lnum])
  end)
  for _, k in ipairs({ 'q', '<Esc>' }) do map(k, close_menu) end
  map('<LeftMouse>', function()
    local mp   = vim.fn.getmousepos()
    local lnum = menu_entry_at(mp)
    if lnum then
      run_item(menu.items[lnum])
      return
    end
    -- Click outside the drop-down. While the menu holds focus this
    -- buffer-local mapping also swallows tabline clicks (the native
    -- click region never runs), so another title is matched by hand;
    -- anything else closes the menu and hands focus to where the user
    -- pointed.
    local hit = title_at(mp)
    local target_win, target_pos = mp.winid, { mp.line, math.max(0, mp.column - 1) }
    close_menu()
    if hit then
      if hit.menu.id ~= seg.menu.id then vim.schedule(function() open_menu(hit) end) end
      return
    end
    if target_win and target_win ~= 0 and vim.api.nvim_win_is_valid(target_win)
        and not is_bar_win(target_win) then
      pcall(vim.api.nvim_set_current_win, target_win)
      if target_pos[1] and target_pos[1] > 0 then
        pcall(vim.api.nvim_win_set_cursor, target_win, target_pos)
      end
    end
  end)
  -- Pointer follows the highlight, the way a real menu behaves. This
  -- buffer-local map shadows the global <MouseMove> of features/edge-scroll
  -- only while the menu is open.
  map('<MouseMove>', function()
    local lnum = menu_entry_at(vim.fn.getmousepos())
    if lnum then pcall(vim.api.nvim_win_set_cursor, win, { lnum, 0 }) end
  end)

  -- Any other route out of the menu (a :command, <C-w>, a plugin stealing
  -- focus) closes it too.
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer   = buf,
    once     = true,
    callback = function() vim.schedule(close_menu) end,
  })
end

-- Declared as a forward local above so ___topbar_click can reach it.
function toggle_menu(seg)
  if vim.fn.mode():match('^i') then vim.cmd('stopinsert') end
  local open_id = menu and menu.menu.id
  close_menu()
  if seg.menu.id ~= open_id then open_menu(seg) end
end

-- ── Autocmds ─────────────────────────────────────────────────
local group = vim.api.nvim_create_augroup('topbar', { clear = true })

-- Rebuild whenever the layout could have displaced the carrier.
vim.api.nvim_create_autocmd({ 'WinNew', 'WinClosed', 'WinResized', 'VimResized', 'TabEnter' }, {
  desc     = 'Keep the tab-strip carrier spanning the top row',
  group    = group,
  callback = schedule_ensure,
})

-- Entering / leaving a project shows / hides the bar.
vim.api.nvim_create_autocmd('DirChanged', {
  desc     = 'Show the menu bar only inside a coding project',
  group    = group,
  callback = schedule_ensure,
})

vim.api.nvim_create_autocmd('VimEnter', {
  desc     = 'Create the menu bar at startup',
  group    = group,
  callback = schedule_ensure,
})

-- The carrier must never hold focus: <C-k>, :wincmd t and friends would
-- otherwise park the cursor in a zero-height scratch window.
vim.api.nvim_create_autocmd('WinLeave', {
  group    = group,
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if not is_bar_win(win) then last_win = win end
  end,
})

vim.api.nvim_create_autocmd('WinEnter', {
  desc     = 'Bounce focus out of the tab-strip carrier',
  group    = group,
  callback = function()
    if not is_bar_win(vim.api.nvim_get_current_win()) then return end
    local target = (last_win and vim.api.nvim_win_is_valid(last_win)
                    and not is_bar_win(last_win)) and last_win or utils.find_editor_win()
    if target then vim.schedule(function()
      if vim.api.nvim_win_is_valid(target) then pcall(vim.api.nvim_set_current_win, target) end
    end) end
  end,
})

-- Drop the carrier before :mksession runs in plugins/session.lua
-- (VimLeave), so a restored session never comes back with a stray
-- zero-height window.
vim.api.nvim_create_autocmd('VimLeavePre', {
  group    = group,
  callback = function()
    close_menu()
    for tab, _ in pairs(bars) do
      if vim.api.nvim_tabpage_is_valid(tab) then close_bar(tab) end
    end
    restore_tabline()
  end,
})

vim.api.nvim_create_user_command('TopbarToggle', function()
  user_off = not user_off
  if user_off then
    close_menu()
    for tab, _ in pairs(bars) do
      if vim.api.nvim_tabpage_is_valid(tab) then close_bar(tab) end
    end
    restore_tabline()
    vim.notify('Top menu bar off', vim.log.levels.INFO)
  else
    ensure()
    if not in_project() then
      vim.notify('Top menu bar on (hidden: not in a coding project)', vim.log.levels.INFO)
    end
  end
end, { desc = 'Toggle the top menu bar' })

-- Open a menu without the mouse: require('features.topbar').open('g').
-- Handy for a keyboard binding, and what the tests drive.
local function open_by_id(id)
  ensure()
  close_menu()
  -- segments are a by-product of drawing the tabline; build them now in
  -- case nothing has redrawn since the bar came up.
  if #segments == 0 then build_tabline() end
  for _, s in ipairs(segments) do
    if s.menu.id == id then
      open_menu(s)
      return true
    end
  end
  return false
end

return { ensure = ensure, is_bar_win = is_bar_win, open = open_by_id }

-- vim: ts=2 sts=2 sw=2 et
