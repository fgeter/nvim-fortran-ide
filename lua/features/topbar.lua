-- ============================================================
-- features/topbar.lua — Clickable IDE menu bar (homegrown)
--
-- A menu bar across the very top of the screen, above the buffer tabs,
-- whose titles open left-click drop-down menus:
--
--     Find   Compile   Debug   Git   Other      ← screen row 0 (tabline)
--    init.lua │ dap.lua │ ui.lua                ← screen row 1 (bufferline)
--
-- Find / Compile / Debug / Git list the same actions as their <leader>
-- prefix (<leader>s / <leader>c / <leader>d / <leader>g).  Choosing an
-- entry feeds that keymap, so there is exactly one implementation of
-- every action — the bar is a second door onto the existing keymaps,
-- never a copy of their logic.
--
-- ── Which titles are shown ───────────────────────────────────
--   Find     always — searching is never out of place
--   Compile  only inside a coding project (PROJECT_MARKERS below)
--   Debug    only inside a coding project
--   Git      only inside a git worktree (a .git in cwd or a parent)
--   Other    always, and always last: everything else bound to <leader>,
--            i.e. what which-key shows when you press <leader> alone
--
-- Visibility is re-evaluated on every :cd (cached per cwd, since the
-- tabline expression runs on each redraw).  "Other" deliberately skips
-- the prefixes that already have a title of their own *at that moment*,
-- so nothing becomes unreachable: outside a git repo, for instance, the
-- Git title is gone but <leader>g reappears inside Other as a group.
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
-- LAZY: n/a — the module registers autocmds and two globals; the
--       carrier window is built on VimEnter.
-- ============================================================

if vim.g.loaded_topbar then return end
vim.g.loaded_topbar = true

local function dbg(msg)
  local f = io.open('/tmp/claude-1000/-home-fgeter--config-nvim/a4c684df-93ea-4f48-af91-dd529e363b18/scratchpad/tb.log', 'a')
  if f then f:write(tostring(msg) .. string.char(10)); f:close() end
end

local utils = require('core.utils')

-- Filetype stamped on the carrier buffer. Other modules key off this to
-- skip the bar when hunting for a "real" window (features/neotree-recovery).
local BAR_FT = 'topbar'

-- What the tabline shows when the bar is down. Captured at load time,
-- i.e. after plugins/ui.lua ran bufferline's setup, so this holds
-- bufferline's own '%!v:lua.nvim_bufferline()'.
local BUFFERLINE_TABLINE = vim.o.tabline

-- A directory counts as a coding project when it — or any parent — holds
-- one of these: what gates the Compile and Debug titles. .git covers
-- repos of any language; the rest cover build systems that may live
-- outside a repo. .nvim.lua is this config's own per-project marker
-- (see core/options.lua exrc).
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
--
-- `when` decides whether the title is shown at all: 'always', 'project'
-- (inside a coding project) or 'git' (inside a git worktree).
local MENUS = {
  {
    id = 's', label = 'Find', icon = '', when = 'always',
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
    id = 'c', label = 'Compile', icon = '', when = 'project',
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
    id = 'd', label = 'Debug', icon = '', when = 'project',
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
    id = 'g', label = 'Git', icon = '', when = 'git',
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
  -- Built from the live keymap table rather than a list (see other_items).
  { id = 'o', label = 'Other', icon = '', when = 'always', dynamic = true },
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
local segments  = {}     -- visible titles: { idx, menu, disp_start, disp_end }
local busy      = false  -- true while we create/close a carrier (blocks re-entry)
local pending   = false  -- an ensure() is already scheduled
local dirty     = false  -- an event arrived while ensure() was running
local menu      = nil    -- open drop-down (see open_dropdown for its shape)
local last_win  = nil    -- window focused before the menu opened
local user_off  = false  -- :TopbarToggle turned it off; stay off until toggled back
local origin    = {}     -- where focus (and terminal mode) was when a menu chain opened
local term_left = {}     -- { win, at }: the last exit from terminal mode
local saved_wmh = nil    -- winminheight from before the carrier squeezed to 0

local function leader()
  return vim.g.mapleader == nil and '\\' or vim.g.mapleader
end

local function is_bar_win(win)
  if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then return false end
  return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == BAR_FT
end

-- Was `win` a live terminal the user was typing into, just before the
-- click currently being handled? Neovim leaves terminal mode the instant
-- a click lands outside the terminal window — before any click handler
-- runs — so mode() already says 'nt' by the time we are asked. TermLeave
-- fires on that very transition, so a fresh one for this window means the
-- click is what ended terminal mode, rather than the user having stepped
-- out of it earlier on purpose.
local TERM_LEAVE_GRACE_MS = 500

local function was_terminal_mode(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then return false end
  if vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= 'terminal' then return false end
  if vim.fn.mode():match('^t') then return true end
  return term_left.win == win
    and (vim.uv.now() - (term_left.at or 0)) < TERM_LEAVE_GRACE_MS
end

-- Put a terminal back into terminal mode, so keys reach the process again
-- (a build waiting at "press <CR> to close" being the case that matters).
local function restore_terminal_mode(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  if vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= 'terminal' then return end
  pcall(vim.api.nvim_set_current_win, win)
  -- Queued rather than :startinsert — the click that got us here is still
  -- being delivered (its release event lands after this runs) and would
  -- cancel a pending startinsert, leaving the terminal in normal mode.
  vim.api.nvim_feedkeys('i', 'n', false)
end

-- 'Git: commit' → 'Commit'. The menu title (or group heading) already
-- says which family an entry belongs to.
local function strip_prefix(desc)
  if type(desc) ~= 'string' or desc == '' then return nil end
  local s = desc:gsub('^%a[%w%+%-/ ]-:%s*', '')
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- ── Which titles are visible ─────────────────────────────────
-- build_tabline runs on every redraw, so the filesystem probes behind
-- these questions are answered once per working directory and cached.
local vis = { cwd = nil, project = false, git = false }

local function visibility()
  local cwd = vim.fn.getcwd()
  if vis.cwd ~= cwd then
    vis.cwd     = cwd
    vis.project = #vim.fs.find(PROJECT_MARKERS,
      { path = cwd, upward = true, limit = 1 }) > 0
    vis.git     = #vim.fs.find({ '.git' },
      { path = cwd, upward = true, limit = 1 }) > 0
  end
  return vis
end

local function menu_visible(m)
  local v = visibility()
  if m.when == 'project' then return v.project end
  if m.when == 'git'     then return v.git end
  return true
end

-- ── Keymap lookup ────────────────────────────────────────────
-- Resolve an item against the keymaps that actually exist right now.
-- Buffer-local maps (<leader>ds from c-tools/web-tools/java-tools, the
-- gitsigns hunk maps, …) only resolve against the *editor* buffer, never
-- the carrier's scratch buffer, so the lookup runs inside nvim_buf_call.
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
  local label     = (available and strip_prefix(map.desc)) or item.label
  return { key = item.key, disp = item.key, lhs = lhs,
           label = label, available = available }
end

-- ── The "Other" menu ─────────────────────────────────────────
-- Group headings come from the which-key spec in plugins/ui.lua, read
-- back through which-key's own config so the two can never drift.
--
-- which-key *empties* options.spec once it has folded the entries into
-- its own tree (shortly after VimEnter), so the headings are harvested
-- while they are still there — this module loads immediately after
-- plugins/ui.lua ran setup() — and cached. Later calls merge in anything
-- that has appeared since, which is why this is not simply a constant.
local wk_labels = nil

local function wk_group_labels()
  wk_labels = wk_labels or {}
  local ok, cfg = pcall(require, 'which-key.config')
  if ok then
    for _, entry in ipairs((cfg.options or {}).spec or {}) do
      local lhs = type(entry) == 'table' and entry[1] or nil
      if type(lhs) == 'string' and type(entry.group) == 'string' then
        local key = lhs:gsub('^<[Ll]eader>', '')
        if key:sub(1, 1) == leader() then key = key:sub(2) end
        if #key == 1 then wk_labels[key] = entry.group end
      end
    end
  end
  return wk_labels
end

wk_group_labels()   -- harvest before which-key clears the spec

-- Fallback heading for a prefix which-key never named: if every entry
-- under it introduces itself the same way ('Markdown: render to HTML',
-- 'Markdown: preview'), that shared word is the heading.
local function inferred_heading(items)
  local common
  for _, e in ipairs(items) do
    local word = type(e.raw_desc) == 'string' and e.raw_desc:match('^(%a[%w%+%-/ ]-):%s') or nil
    if not word then return nil end
    if common == nil then common = word elseif common ~= word then return nil end
  end
  return common
end

-- Every <leader> mapping that exists right now, keyed by what follows
-- the leader. Buffer-local maps are collected last so they win, exactly
-- as they do when the keys are typed.
local function leader_maps(ctx_buf)
  local L, out = leader(), {}
  local function collect(list)
    for _, m in ipairs(list) do
      local lhs, rest = m.lhs or '', nil
      if lhs:sub(1, #L) == L then
        rest = lhs:sub(#L + 1)
      elseif L == ' ' and lhs:lower():sub(1, 7) == '<space>' then
        rest = lhs:sub(8)
      end
      if rest and rest ~= '' and m.desc ~= 'which_key_ignore' then
        out[rest] = { desc = m.desc, rhs = m.rhs }
      end
    end
  end
  collect(vim.api.nvim_get_keymap('n'))
  if ctx_buf and vim.api.nvim_buf_is_valid(ctx_buf) then
    collect(vim.api.nvim_buf_get_keymap(ctx_buf, 'n'))
  end
  return out
end

-- Sort keys the way a menu should read: letters, then digits, then
-- punctuation; case-insensitive, with a stable tiebreak.
local function by_key(a, b)
  local function rank(k)
    local c = k:sub(1, 1)
    if c:match('%a') then return 1 elseif c:match('%d') then return 2 end
    return 3
  end
  local ra, rb = rank(a.key), rank(b.key)
  if ra ~= rb then return ra < rb end
  if a.key:lower() ~= b.key:lower() then return a.key:lower() < b.key:lower() end
  return a.key < b.key
end

local function other_items(ctx_buf)
  -- Skip the prefixes that currently have a title of their own; when one
  -- is hidden (no git repo, no project) its keys show up here instead.
  local covered = {}
  for _, m in ipairs(MENUS) do
    if not m.dynamic and menu_visible(m) then covered[m.id] = true end
  end

  local L       = leader()
  local labels  = wk_group_labels()
  local entries = {}
  local groups  = {}

  for rest, info in pairs(leader_maps(ctx_buf)) do
    local head = rest:sub(1, 1)
    if not covered[head] then
      if #rest == 1 then
        -- Top level: keep the full description ('Harpoon: add file'),
        -- since there is no heading here to supply the context.
        table.insert(entries, {
          key   = rest,
          disp  = rest == ' ' and '␣' or rest,
          lhs   = L .. rest,
          label = info.desc or info.rhs or '(no description)',
          available = true,
        })
      else
        groups[head] = groups[head] or {}
        table.insert(groups[head], {
          key      = rest,
          disp     = rest,
          lhs      = L .. rest,
          label    = strip_prefix(info.desc) or info.rhs or '(no description)',
          raw_desc = info.desc,
          available = true,
        })
      end
    end
  end

  for head, items in pairs(groups) do
    table.sort(items, by_key)
    local heading = labels[head] or inferred_heading(items) or (L .. head)
    table.insert(entries, {
      key   = head,
      disp  = head,
      label = heading .. '  ›',
      group = true,
      items = items,
      title = heading,
      available = true,
    })
  end

  table.sort(entries, by_key)
  if #entries == 0 then
    entries = { { key = '', disp = '', label = 'No other <leader> mappings here',
                  available = false } }
  end
  return entries
end

local function menu_items(m, ctx_buf)
  if m.dynamic then return other_items(ctx_buf) end
  local items = {}
  for _, item in ipairs(m.items) do table.insert(items, resolve(item, ctx_buf)) end
  return items
end

-- ── The menu bar itself (the tabline) ────────────────────────
-- Rebuilt on every redraw, which keeps `segments` — the display-column
-- range of each visible title, used to place its drop-down and to
-- hit-test the clicks that arrive while a drop-down holds focus — always
-- current.  %N@fn@…%X wraps each title in a click region carrying its
-- MENUS index, so Neovim delivers the click to ___topbar_click with no
-- coordinate maths.
local function build_tabline()
  local parts, disp = {}, 1
  segments = {}
  for i, m in ipairs(MENUS) do
    if menu_visible(m) then
      local text  = ' ' .. (vim.g.have_nerd_font and (m.icon .. '  ') or '') .. m.label .. ' '
      local width = vim.fn.strdisplaywidth(text)
      table.insert(segments,
        { idx = i, menu = m, disp_start = disp, disp_end = disp + width - 1 })
      parts[#parts + 1] = ('%%#%s#%%%d@v:lua.___topbar_click@%s%%X'):format(
        (menu and menu.id == m.id) and 'TopBarTitleOn' or 'TopBarTitle', i, text)
      disp = disp + width
    end
  end
  -- The bar's empty stretch is a click region too (index 0, matching no
  -- title). Without it a click out there would silently cost a focused
  -- terminal its terminal mode with nothing to put it back. A click
  -- region only covers the text inside it, so the remaining width is
  -- spelled out in spaces rather than left to the tabline's own padding.
  local rest = math.max(0, vim.o.columns - (disp - 1))
  parts[#parts + 1] = ('%%#TopBarFill#%%0@v:lua.___topbar_click@%s%%X')
    :format(string.rep(' ', rest))
  return table.concat(parts)
end

_G.___topbar_tabline = build_tabline

local function segment_by_idx(idx)
  for _, s in ipairs(segments) do
    if s.idx == idx then return s end
  end
end

-- Forward local: the click handler is installed with the tabline, but
-- toggle_menu needs the drop-down machinery defined further down.
local toggle_menu

_G.___topbar_click = function(minwid, _, button)
  if button ~= 'l' then return end
  local seg = segment_by_idx(minwid)
  if not seg then
    -- The bar's empty stretch: nothing to open, but the click has already
    -- knocked a focused terminal out of terminal mode. Put it back.
    local cur = vim.api.nvim_get_current_win()
    if was_terminal_mode(cur) then
      vim.schedule(function() restore_terminal_mode(cur) end)
    end
    return
  end
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
  dbg('close_bar win=' .. tostring(bars[tab]) .. string.char(10) .. debug.traceback())
  local win = bars[tab]
  bars[tab] = nil
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

-- Hand the top row back to bufferline and undo the global option the
-- carrier needed. Called whenever the last carrier goes away.
local function restore_tabline()
  dbg('restore_tabline bars=' .. vim.inspect(bars) .. string.char(10) .. debug.traceback())
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

-- Create, rebuild or remove the bar for the current tabpage. The bar
-- itself is always up (Find and Other are never hidden); which titles it
-- shows is build_tabline's business.
local function ensure()
  -- Re-entered from inside our own window juggling: remember that the
  -- layout moved again and settle it once this pass is done, rather than
  -- dropping the event and leaving the carrier stale.
  if busy then dirty = true; return end
  if vim.fn.getcmdwintype() ~= '' then return end   -- command-line window: hands off
  if vim.v.exiting ~= vim.NIL then return end

  local tab = vim.api.nvim_get_current_tabpage()
  busy = true
  local ok, err = pcall(function()
    if user_off then
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
    dbg('ensure win=' .. tostring(win) .. ' others=' .. others
      .. ' wins=' .. vim.inspect(vim.api.nvim_tabpage_list_wins(tab))
      .. ' exiting=' .. tostring(vim.v.exiting))
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
  if dirty then
    dirty = false
    vim.schedule(ensure)
  end
end

-- Coalesce the storm of Win* events a single :Neotree or :DiffviewOpen
-- produces into one rebuild, and run it after Neovim has settled the
-- layout rather than in the middle of it.
local function schedule_ensure()
  if busy then dirty = true; return end
  if pending then return end
  pending = true
  vim.schedule(function()
    pending = false
    ensure()
  end)
end

-- ── Drop-down menu ───────────────────────────────────────────
-- `restore` asks for focus to go back where the menu was opened from. It
-- matters for one case in particular: a drop-down opened while a terminal
-- had focus takes that focus into the float, which drops the terminal out
-- of terminal mode. Handing focus back is not enough — the terminal would
-- sit in normal mode, where keys no longer reach the process, so a build
-- waiting at "press <CR> to close" would ignore every <CR>. Re-enter
-- terminal mode explicitly. Not done when focus moved on deliberately
-- (the user clicked another window, or an action ran): that would yank
-- the cursor back.
local function close_menu(restore)
  if not menu then return end
  local m = menu
  menu = nil
  if m.win and vim.api.nvim_win_is_valid(m.win) then
    pcall(vim.api.nvim_win_close, m.win, true)
  end
  if m.buf and vim.api.nvim_buf_is_valid(m.buf) then
    pcall(vim.api.nvim_buf_delete, m.buf, { force = true })
  end
  if restore and origin.term then restore_terminal_mode(origin.win) end
  pcall(vim.cmd, 'redrawtabline')   -- drop the open title's highlight
end

local open_dropdown

-- Hand the action back to the keymap that owns it. Focus returns to the
-- window the user came from first, and a visual selection is restored
-- with gv so the visual-mode variants (<leader>sR, <leader>de, …) behave
-- exactly as they do from the keyboard.
local function run_item(entry)
  if not entry then return end
  local m = menu

  -- A group heading drills into its own list rather than running.
  if entry.group then
    close_menu(false)
    open_dropdown({
      id = m.id, idx = m.idx, col = m.col, items = entry.items,
      title = entry.title, parent = m, from_win = m.from_win, from_mode = m.from_mode,
    })
    return
  end

  close_menu(false)
  if not entry.available then
    if entry.lhs then
      vim.notify(entry.label .. '  —  no keymap for <leader>' .. entry.key
        .. ' in this context', vim.log.levels.INFO)
    end
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

-- spec = { id, idx, col, items, title?, parent?, from_win, from_mode }
function open_dropdown(spec)
  local entries = spec.items

  -- Layout: two leading spaces, the chord, two spaces, the label.
  local key_w, label_w = 0, 0
  for _, e in ipairs(entries) do
    key_w   = math.max(key_w,   vim.fn.strdisplaywidth(e.disp or e.key or ''))
    label_w = math.max(label_w, vim.fn.strdisplaywidth(e.label))
  end
  local width = 2 + key_w + 2 + label_w + 2

  -- %-Ns pads by bytes, and both icons and multi-byte keys break that;
  -- pad by display width instead.
  local function pad(text, want)
    return text .. string.rep(' ', math.max(0, want - vim.fn.strdisplaywidth(text)))
  end
  local lines = {}
  for _, e in ipairs(entries) do
    lines[#lines + 1] = '  ' .. pad(e.disp or e.key or '', key_w)
      .. '  ' .. pad(e.label, label_w) .. '  '
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden  = 'wipe'

  for i, e in ipairs(entries) do
    local key_bytes = #(e.disp or e.key or '')
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 2, {
      end_col  = 2 + key_bytes,
      hl_group = e.available and 'TopBarKey' or 'TopBarDim',
    })
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 2 + key_bytes, {
      end_col  = #lines[i],
      hl_group = e.available and 'TopBarItem' or 'TopBarDim',
    })
  end

  -- The menu bar is the tabline (screen row 0), so the drop-down hangs
  -- from row 1: its top border replaces the tab strip while it is open,
  -- the way a menu overlays whatever is beneath it.
  local row    = 1
  local height = math.min(#lines, math.max(3, vim.o.lines - row - 4))
  local col    = math.max(0, math.min(spec.col, vim.o.columns - width - 2))

  local cfg = {
    relative = 'editor',
    row      = row,
    col      = col,
    width    = width,
    height   = height,
    style    = 'minimal',
    border   = 'rounded',
    zindex   = 200,   -- above the horizontal scrollbar (zindex 150)
  }
  if spec.title then
    cfg.title     = ' ' .. spec.title .. ' '
    cfg.title_pos = 'left'
  end
  local win = vim.api.nvim_open_win(buf, true, cfg)
  vim.wo[win].cursorline   = true
  vim.wo[win].winhighlight = 'Normal:TopBar,FloatBorder:TopBarBorder,CursorLine:PmenuSel'

  menu = vim.tbl_extend('force', spec, { win = win, buf = buf, items = entries })
  pcall(vim.cmd, 'redrawtabline')   -- light up the open title

  -- ── menu keys ──
  local function map(lhs, fn) vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true }) end
  map('<CR>', function()
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    run_item(menu and menu.items[lnum])
  end)
  for _, k in ipairs({ 'q', '<Esc>' }) do map(k, function() close_menu(true) end) end
  -- Back out of a group into the list it came from.
  for _, k in ipairs({ '<BS>', '<Left>' }) do
    map(k, function()
      local parent = menu and menu.parent
      if not parent then return end
      close_menu(false)
      open_dropdown(parent)
    end)
  end
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
    local open_id = menu and menu.id
    local elsewhere = target_win and target_win ~= 0
      and vim.api.nvim_win_is_valid(target_win) and not is_bar_win(target_win)
    -- A click that lands nowhere in particular (the bar's empty stretch)
    -- should leave the user where they started, terminal mode included.
    close_menu(not hit and not elsewhere)
    if hit then
      -- keep_origin: the chain is only switching titles, so where it was
      -- opened from — and whether that was a terminal — still applies.
      if hit.menu.id ~= open_id then vim.schedule(function() toggle_menu(hit, true) end) end
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
  -- focus) closes it too. Scoped to *this* drop-down: drilling into a
  -- group closes the parent and opens the child in the same tick, and an
  -- unscoped handler would then close the child it just fired for.
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer   = buf,
    once     = true,
    callback = function()
      vim.schedule(function()
        if menu and menu.buf == buf then close_menu(false) end
      end)
    end,
  })
end

-- Declared as a forward local above so ___topbar_click can reach it.
-- `keep_origin` is set when one title hands over to another: the chain is
-- still the same visit, so where it started stays where it started.
function toggle_menu(seg, keep_origin)
  local open_id = menu and menu.id

  -- Remember where this visit began. Closing the menu without running
  -- anything hands focus — and terminal mode — back there.
  if not keep_origin and menu == nil then
    local cur = vim.api.nvim_get_current_win()
    origin = { win = cur, term = was_terminal_mode(cur) }
  end

  if vim.fn.mode():match('^i') then vim.cmd('stopinsert') end
  close_menu(seg.menu.id == open_id)
  if seg.menu.id == open_id then return end

  -- Where the action will run, and whose buffer decides which entries are
  -- live. Clicking the tabline does not move focus, so the window the user
  -- is in is normally the answer — but never the carrier, a float, or a
  -- terminal: a <leader> action belongs in an editor window, and feeding
  -- its keys at a terminal would type them into the process instead.
  local function usable(win)
    if not (win and vim.api.nvim_win_is_valid(win)) then return false end
    if is_bar_win(win) then return false end
    if vim.api.nvim_win_get_config(win).relative ~= '' then return false end
    return vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= 'terminal'
  end

  local candidates = { vim.api.nvim_get_current_win() }
  if origin.win then candidates[#candidates + 1] = origin.win end
  if last_win   then candidates[#candidates + 1] = last_win end
  local from_win
  for _, w in ipairs(candidates) do
    if usable(w) then from_win = w break end
  end
  from_win = from_win or utils.find_editor_win()

  open_dropdown({
    id        = seg.menu.id,
    idx       = seg.idx,
    col       = math.max(0, seg.disp_start - 1),
    items     = menu_items(seg.menu, from_win and vim.api.nvim_win_get_buf(from_win) or nil),
    from_win  = from_win,
    from_mode = vim.fn.mode(),
  })
end

-- ── Autocmds ─────────────────────────────────────────────────
local group = vim.api.nvim_create_augroup('topbar', { clear = true })

-- Rebuild whenever the layout could have displaced the carrier.
vim.api.nvim_create_autocmd({ 'WinNew', 'WinClosed', 'WinResized', 'VimResized', 'TabEnter' }, {
  desc     = 'Keep the tab-strip carrier spanning the top row',
  group    = group,
  callback = schedule_ensure,
})

-- :cd changes which titles apply (project / git repo); the tabline is
-- rebuilt on the next redraw, but ask for one so it never lags.
vim.api.nvim_create_autocmd('DirChanged', {
  desc     = 'Re-evaluate which menu titles apply after :cd',
  group    = group,
  callback = function()
    vis.cwd = nil
    schedule_ensure()
    pcall(vim.cmd, 'redrawtabline')
  end,
})

vim.api.nvim_create_autocmd('VimEnter', {
  desc     = 'Create the menu bar at startup',
  group    = group,
  callback = schedule_ensure,
})

-- Track the exit from terminal mode so a click on the bar can tell "the
-- user was typing in this terminal a moment ago" from "the user stepped
-- out of it earlier" — see was_terminal_mode.
vim.api.nvim_create_autocmd('TermLeave', {
  group    = group,
  callback = function()
    term_left = { win = vim.api.nvim_get_current_win(), at = vim.uv.now() }
  end,
})

vim.api.nvim_create_autocmd('TermEnter', {
  group    = group,
  callback = function() term_left = {} end,
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
    if not target then return end
    vim.schedule(function()
      -- Re-check: WinEnter also fires for the transient context switches
      -- other code makes (nvim_win_call, nvim_eval_statusline{winid=…}),
      -- and by now focus is back where it belongs. Bouncing regardless
      -- would yank the cursor out of whatever window — a drop-down of
      -- ours included — legitimately holds it.
      if not is_bar_win(vim.api.nvim_get_current_win()) then return end
      if vim.api.nvim_win_is_valid(target) then pcall(vim.api.nvim_set_current_win, target) end
    end)
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
    vim.notify('Top menu bar on', vim.log.levels.INFO)
  end
end, { desc = 'Toggle the top menu bar' })

-- Open a menu without the mouse: require('features.topbar').open('g').
-- Handy for a keyboard binding, and what the tests drive. Menu ids are
-- their <leader> prefix — s, c, d, g — plus 'o' for Other.
local function open_by_id(id)
  ensure()
  close_menu()
  -- segments are a by-product of drawing the tabline; build them now in
  -- case nothing has redrawn since the bar came up.
  if #segments == 0 then build_tabline() end
  for _, s in ipairs(segments) do
    if s.menu.id == id then
      toggle_menu(s)
      return true
    end
  end
  return false
end

return { ensure = ensure, is_bar_win = is_bar_win, open = open_by_id }

-- vim: ts=2 sts=2 sw=2 et
