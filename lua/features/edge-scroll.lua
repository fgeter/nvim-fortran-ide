-- ============================================================
-- features/edge-scroll.lua — MouseMove forwarder for the scrollbars
--
-- Edge-hover horizontal scrolling is off: the file pane has a real
-- horizontal scrollbar, and hovering the right edge (the vertical bar)
-- used to pan the window and snap the view back to the cursor.
--
-- <MouseMove> is still mapped so a scrollbar drag keeps receiving
-- updates (see features/hscrollbar.lua).
-- ============================================================

--
-- An expr mapping that hands the plain <MouseMove> back when no drag is
-- going on: a right-click menu reads mouse moves to highlight the item
-- under the pointer, and a mapping that ran Lua instead made it close on
-- the first move (2026-11-03).
vim.keymap.set('n', '<MouseMove>', function()
  if vim.g.hscroll_dragging then
    return "<Cmd>lua require('features.hscrollbar').on_drag()<CR>"
  end
  return '<MouseMove>'
end, { expr = true, silent = true })
