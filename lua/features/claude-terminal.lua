-- ============================================================
-- features/claude-terminal.lua — Claude Code in a toggleterm split
--
-- Runs the `claude` CLI in a dedicated vertical toggleterm instance:
-- editor on the left, Claude on the right, toggled with one key.
-- Deliberately separate from the <C-\> bottom terminal (hidden = true
-- keeps it out of :ToggleTerm's normal rotation) so builds/runs and
-- the Claude session never fight over the same window.
--
-- Keymap:
--   <F9> (normal + terminal mode) — toggle the Claude panel.
--        The session keeps running while hidden; toggling back
--        returns to the same conversation.
--
-- Workflow notes (no IDE-protocol integration — this is the plain
-- terminal setup): reference files as @path/to/file in prompts, and
-- review Claude's edits with the usual git tooling (<leader>gw for a
-- diffview of the working tree, gitsigns hunks to accept/reject).
-- ============================================================

local claude_term = nil

local function toggle_claude()
  if vim.fn.executable('claude') ~= 1 then
    vim.notify('`claude` CLI not found on PATH — install Claude Code first.',
      vim.log.levels.ERROR)
    return
  end
  if not claude_term then
    claude_term = require('toggleterm.terminal').Terminal:new {
      cmd           = 'claude',
      direction     = 'vertical',
      hidden        = true,   -- not part of :ToggleTerm / <C-\> rotation
      close_on_exit = true,
      -- 40% of the editor width; Claude Code's TUI adapts fine to this.
      size          = function() return math.floor(vim.o.columns * 0.4) end,
    }
  end
  claude_term:toggle()
end

vim.keymap.set('n', '<F9>', toggle_claude, { desc = 'Claude Code: toggle panel' })
vim.keymap.set('t', '<F9>', toggle_claude, { desc = 'Claude Code: toggle panel' })
