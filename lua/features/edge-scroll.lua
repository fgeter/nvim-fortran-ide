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

vim.keymap.set('n', '<MouseMove>', function()
  if vim.g.hscroll_dragging then
    require('features.hscrollbar').on_drag()
  end
end)
