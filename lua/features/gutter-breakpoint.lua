-- ============================================================
-- features/gutter-breakpoint.lua — Click the gutter to toggle a breakpoint
--
-- A left click in the gutter of a file window (the sign column with the
-- breakpoint ● and git signs, the line numbers, a fold column — everything
-- left of the text) toggles a DAP breakpoint on that line, the same as
-- <leader>db / F4. A double click toggles once, not twice.
--
-- The click itself is not swallowed: Neovim still handles it as usual
-- (focus the window, cursor to that line), then the breakpoint is toggled
-- on the clicked line.
--
-- Input: vim.on_key, not a <LeftMouse> mapping — features/hscrollbar.lua
-- already owns the global <LeftMouse> map, and a second one would replace
-- it. on_key sees the click without taking it.
--
-- Only plain file buffers (buftype ''), in normal or insert mode; never
-- floats, neo-tree, terminals, help or the scrollbar/menu chrome.
-- :GutterBreakpointToggle turns it off/on for the session.
-- ============================================================

if vim.g.loaded_gutter_breakpoint then return end
vim.g.loaded_gutter_breakpoint = true

local enabled = true
local K_LEFT  = vim.keycode('<LeftMouse>')

local excluded_ft = { ['neo-tree'] = true, ['topbar'] = true, ['hscroll'] = true,
                      ['help'] = true, ['toggleterm'] = true, ['dapui_scopes'] = true,
                      ['dapui_breakpoints'] = true, ['dapui_stacks'] = true,
                      ['dapui_watches'] = true, ['dapui_console'] = true, ['dap-repl'] = true }

-- The clicked { win, line } when the click is in a file window's gutter.
-- getmousepos(): wincol is 1-based inside the window; the gutter is the
-- first `textoff` columns (getwininfo). line is 0 past the end of the
-- buffer (the ~ rows) and on the status line, so those never count.
local function gutter_hit()
  local mp = vim.fn.getmousepos()
  local win = mp.winid
  if win == 0 or (mp.line or 0) < 1 or not vim.api.nvim_win_is_valid(win) then return nil end
  if vim.api.nvim_win_get_config(win).relative ~= '' then return nil end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' or excluded_ft[vim.bo[buf].filetype] then return nil end
  local info = vim.fn.getwininfo(win)[1]
  if not info or info.textoff < 1 then return nil end
  if mp.wincol < 1 or mp.wincol > info.textoff then return nil end
  if mp.winrow > vim.api.nvim_win_get_height(win) then return nil end   -- status line
  return { win = win, line = mp.line }
end

vim.on_key(function(_, typed)
  if not enabled or typed ~= K_LEFT then return end
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= 'n' and mode:sub(1, 1) ~= 'i' then return end
  local hit = gutter_hit()
  if not hit then return end
  -- After Neovim has processed the click (focus + cursor), so the toggle
  -- acts on the clicked window and line.
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(hit.win) then return end
    local ok_d, dapcfg = pcall(require, 'plugins.dap')
    if ok_d and type(dapcfg) == 'table' and dapcfg.activate then dapcfg.activate() end
    local ok, dap = pcall(require, 'dap')
    if not ok then
      vim.notify('nvim-dap is not available', vim.log.levels.WARN)
      return
    end
    vim.api.nvim_set_current_win(hit.win)
    local last = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(hit.win))
    vim.api.nvim_win_set_cursor(hit.win, { math.min(hit.line, last), 0 })
    dap.toggle_breakpoint()
  end)
end, vim.api.nvim_create_namespace('gutter-breakpoint'))

vim.api.nvim_create_user_command('GutterBreakpointToggle', function()
  enabled = not enabled
  vim.notify('Click gutter to toggle breakpoint: ' .. (enabled and 'on' or 'off'))
end, { desc = 'Toggle click-in-gutter breakpoints' })
