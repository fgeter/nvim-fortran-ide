# Keymap Reference

---

## General

| Key | Action | Plugin |
|-----|--------|--------|
| `<Esc>` | Clear search highlights | `core/keymaps.lua` |
| `<C-s>` | Save file  | `core/keymaps.lua` |
| `<C-s>` | Save file  | `core/keymaps.lua` |
| `<C-h>` | Focus left window | `core/keymaps.lua` |
| `<C-j>` | Focus lower window | `core/keymaps.lua` |
| `<C-k>` | Focus upper window | `core/keymaps.lua` |
| `<C-l>` | Focus right window | `core/keymaps.lua` |
| `<leader>q` | Open diagnostics in location list | `core/keymaps.lua` |
| `gF` | Go to file:line under cursor in split | `core/keymaps.lua` |
| `<Esc><Esc>` | Exit terminal insert mode | `core/keymaps.lua` |
| `:q` | Close window; if only neo-tree would remain, auto-reopens editor with next buffer | `plugins/neo-tree.lua` |

---

## Horizontal scrolling

> `nowrap` is enabled globally. A floating `▁` bar appears at the bottom of
> buffer windows when content is wider than the window width.

| Key | Action | Plugin |
|-----|--------|--------|
| `<A-Right>` | Move cursor right 5 chars; window scrolls when cursor hits edge (hold to repeat) | `core/keymaps.lua` |
| `<A-Left>` | Move cursor left 5 chars; window scrolls when cursor hits edge (hold to repeat) | `core/keymaps.lua` |
| `zl` | Scroll window right ~1 word | `core/keymaps.lua` |
| `zh` | Scroll window left ~1 word | `core/keymaps.lua` |
| `ze` | Scroll cursor to right edge | `core/keymaps.lua` |
| `zs` | Scroll cursor to left edge | `core/keymaps.lua` |

---

## Buffers (`<leader>b`)

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>bn` | Next buffer | `core/keymaps.lua` |
| `<leader>bp` | Previous buffer | `core/keymaps.lua` |
| `<leader>bd` | Delete buffer (keeps window layout) | `core/keymaps.lua` |
| `<leader><leader>` | Telescope buffer picker | `plugins/telescope.lua` |

---

## Tabs

| Key | Action | Plugin |
|-----|--------|--------|
| `]]` | Next tab | `core/keymaps.lua` |
| `[[` | Previous tab | `core/keymaps.lua` |

---

## Terminal

| Key | Action | Plugin |
|-----|--------|--------|
| `<C-\>` | Toggle terminal (normal and terminal mode) | `plugins/toggleterm.lua` |
| `<Esc><Esc>` | Exit terminal insert mode | `core/keymaps.lua` |
| `<C-g>f` | Go to file:line under cursor (usable directly in terminal insert mode) | `core/keymaps.lua` |

---

## Search (`<leader>s`)

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>sf` | Find files (all, including hidden/gitignored) | `plugins/telescope.lua` |
| `<leader>sg` | Live grep | `plugins/telescope.lua` |
| `<leader>sw` | Grep word under cursor | `plugins/telescope.lua` |
| `<leader>s/` | Grep in open buffers | `plugins/telescope.lua` |
| `<leader>sh` | Search help tags | `plugins/telescope.lua` |
| `<leader>sk` | Search keymaps | `plugins/telescope.lua` |
| `<leader>ss` | Search Telescope pickers | `plugins/telescope.lua` |
| `<leader>sd` | Search diagnostics | `plugins/telescope.lua` |
| `<leader>sr` | Resume last picker | `plugins/telescope.lua` |
| `<leader>sc` | Search commands | `plugins/telescope.lua` |
| `<leader>sn` | Search Neovim config files | `plugins/telescope.lua` |
| `<leader>/` | Fuzzy search current buffer | `plugins/telescope.lua` |
| `<leader>rf` | Recent files | `plugins/telescope.lua` |

---

## File Tree (neo-tree)

| Key | Action | Plugin |
|-----|--------|--------|
| `\` | Reveal current file in neo-tree | `plugins/neo-tree.lua` |
| `<leader>\` | Show and focus buffer list in neo-tree | `plugins/neo-tree.lua` |

## Jupyter (`<leader>j`)

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>jq` | Stop all running JupyterLab servers | `plugins/neo-tree.lua` |

Inside neo-tree:

| Key | Action | Plugin |
|-----|--------|--------|
| `← ..` | Click to navigate up one directory (visual entry at top of tree) | `plugins/neo-tree.lua` |
| `<CR>` / `o` | Open file in Neovim or expand directory; on `← ..` navigates up | `plugins/neo-tree.lua` |
| `<2-LeftMouse>` | Open file — `.ipynb` → JupyterLab in browser (requires `jupyter-lab` in PATH); `.html` → default browser via `xdg-open`; all others open in Neovim | `plugins/neo-tree.lua` |
| `s` | Open in horizontal split | `plugins/neo-tree.lua` |
| `v` | Open in vertical split | `plugins/neo-tree.lua` |
| `<BS>` | Navigate up one directory | `plugins/neo-tree.lua` |
| `t` | Open bottom terminal at directory under cursor (reuses toggleterm #1) | `plugins/neo-tree.lua` |
| `X` | Execute selected file if it has the executable bit set (reuses toggleterm #1) | `plugins/neo-tree.lua` |
| `.` | Set as tree root | `plugins/neo-tree.lua` |
| `a` | Add file/directory | `plugins/neo-tree.lua` |
| `d` | Delete | `plugins/neo-tree.lua` |
| `r` | Rename | `plugins/neo-tree.lua` |
| `c` | Copy | `plugins/neo-tree.lua` |
| `m` | Move | `plugins/neo-tree.lua` |
| `y` | Copy to clipboard | `plugins/neo-tree.lua` |
| `x` | Cut to clipboard | `plugins/neo-tree.lua` |
| `p` | Paste from clipboard | `plugins/neo-tree.lua` |
| `H` | Toggle hidden files | `plugins/neo-tree.lua` |
| `R` | Refresh tree | `plugins/neo-tree.lua` |
| `/` | Telescope find files scoped to directory under cursor | `plugins/neo-tree.lua` |
| `g/` | Telescope live grep scoped to directory under cursor | `plugins/neo-tree.lua` |
| `?` | Show help | `plugins/neo-tree.lua` |

---

## Python — run file

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>pr` | Run current file in bottom terminal (reuses toggleterm #1) | `plugins/python.lua` |

> Activates after the first Python file is opened. Uses the same Python binary resolution as the LSP and DAP (project venv → `$VIRTUAL_ENV` → system `python3`).

---

## Markdown (`<leader>m`) — markdown buffers only

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>mr` | Toggle rendering on/off | `plugins/markdown.lua` |
| `<leader>me` | Expand all sections | `plugins/markdown.lua` |
| `<leader>mc` | Collapse all sections | `plugins/markdown.lua` |

---

## Formatting

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>f` | Format buffer or selection | `plugins/formatting.lua` |

Formatters by language: Lua → stylua, Python → ruff, C/C++ → clang-format, Java → google-java-format, Shell → shfmt, JS/TS/JSX/TSX/HTML/CSS/JSON/YAML/Markdown → prettier.

---

## Surround (nvim-surround) — all buffers

| Key | Mode | Action | Plugin |
|-----|------|--------|--------|
| `ys{motion}{char}` | n | Add surrounding (e.g. `ysiw"` wraps word in `""`) | `plugins/surround.lua` |
| `cs{old}{new}` | n | Change surrounding (e.g. `cs"'` changes `"` to `'`) | `plugins/surround.lua` |
| `ds{char}` | n | Delete surrounding (e.g. `ds"` removes quotes) | `plugins/surround.lua` |
| `S{char}` | v | Surround selection | `plugins/surround.lua` |

---

## CMake (`<leader>c`) — active in CMake projects (`CMakeLists.txt` found)

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>cp` | Select preset + auto-run Generate | `plugins/cmake-tools.lua` |
| `<leader>cg` | CMake Generate (configure) | `plugins/cmake-tools.lua` |
| `<leader>cb` | Build using all CPU cores (detected via `nproc`) | `plugins/cmake-tools.lua` |
| `<leader>cB` | Build single-threaded (`-j 1`) — clean error output | `plugins/cmake-tools.lua` |
| `<leader>cx` | Clean active preset | `plugins/cmake-tools.lua` |
| `<leader>cd` | Delete build directory (prompts confirmation) | `plugins/cmake-tools.lua` |
| `<leader>cr` | Run swatplus (pick exe + workdata, cleans output first) | `plugins/cmake-tools.lua` |

---

## Make (`<leader>c`) — active in Makefile projects (Makefile found, no CMakeLists.txt)

Uses the same `<leader>c*` keys as CMake so muscle memory transfers. Activates instead of cmake-tools when only a Makefile is present.

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>cb` | Build (pick debug/release, all CPU cores via `nproc`) | `plugins/make-tools.lua` |
| `<leader>cB` | Build single-threaded (`-j 1`) — pick debug/release | `plugins/make-tools.lua` |
| `<leader>cx` | Clean (pick debug/release/both) | `plugins/make-tools.lua` |
| `<leader>cr` | Run executable (pick debug/release, then workdata directory) | `plugins/make-tools.lua` |

---

## Debug / DAP (`<leader>d`) — `<leader>ds` active after opening a Fortran, Python, C/C++, Java, or JS/TS file; all other keys available from startup

| Key | Alt key | Action | Plugin |
|-----|---------|--------|--------|
| `<leader>ds` | `<F5>` | Start / continue (Fortran: exe/workdata picker; Python/Java/JS/TS: config picker; C/C++: executable prompt) | `plugins/*-tools.lua` |
| `<leader>dq` | `<F10>` | Terminate session | `plugins/dap.lua` |
| `<leader>dr` | | Restart session | `plugins/dap.lua` |
| `<leader>dn` | `<F2>` | Step over | `plugins/dap.lua` |
| `<leader>di` | `<F1>` | Step into | `plugins/dap.lua` |
| `<leader>do` | `<F3>` | Step out | `plugins/dap.lua` |
| `<leader>dc` | `<F6>` | Run to cursor | `plugins/dap.lua` |
| `<leader>db` | `<F4>` | Toggle breakpoint | `plugins/dap.lua` |
| `<leader>dB` | `<F8>` | Conditional breakpoint | `plugins/dap.lua` |
| `<leader>dL` | | Log point | `plugins/dap.lua` |
| `<leader>dx` | `<F16>` (Shift-F4) | Clear all breakpoints | `plugins/dap.lua` |
| `<leader>dw` | | Add word under cursor to watches | `plugins/dap.lua` |
| `<leader>dU` | `<F7>` | Toggle DAP UI | `plugins/dap.lua` |
| `<leader>dC` | | Open console in floating window | `plugins/dap.lua` |
| `<leader>de` | | Eval expression / selection — cursor enters float; `q` or jump to another window to close | `plugins/dap.lua` |
| `<leader>dh` | | Toggle hover widget for variable under cursor (`<Esc>` or `<leader>dh` again to close) | `plugins/dap.lua` |
| `<leader>dR` | | Open REPL | `plugins/dap.lua` |
| `<leader>dF` | | Show F-key reference popup | `plugins/dap.lua` |

While debugging, press `K` over any variable to inspect its value; cursor enters the float so you can scroll. Press `q` or jump to another window to close it. Variable values also appear as virtual text inline in the source during stepping.

**Java-only buffer-local keymaps** (active after opening a `.java` file):

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>di` | Organize imports | `plugins/java-tools.lua` |
| `<leader>dv` | Extract variable | `plugins/java-tools.lua` |
| `<leader>dm` | Extract method | `plugins/java-tools.lua` |

---

## Git operations (`<leader>g`)

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>gg` | Open lazygit | `plugins/git.lua` |
| `<leader>gc` | Commit (with file picker) | `plugins/git.lua` |
| `<leader>gb` | Create branch | `plugins/git.lua` |
| `<leader>gp` | Pull (async) | `plugins/git.lua` |
| `<leader>gP` | Push (async) | `plugins/git.lua` |
| `<leader>gs` | Switch branch | `plugins/git.lua` |
| `<leader>gd` | Delete branch | `plugins/git.lua` |
| `<leader>gm` | Merge branch | `plugins/git.lua` |
| `<leader>gf` | Diff current file against a branch, or a typed ref (e.g. `HEAD^1`) — `do`/`dp` to pull hunks | `plugins/git.lua` |
| `<leader>gq` | Load files changed between two refs (default `HEAD^1`..`HEAD`) into the quickfix list | `plugins/git.lua` |
| `<leader>gn` | Done with this file's diff: save, close, delete buffer, advance quickfix, reopen diff on the next file (auto-skips binaries) | `plugins/git.lua` |
| `<leader>gx` | Discard all changes in current buffer's file (restores to HEAD; confirmation prompt; refuses on untracked files) | `plugins/git.lua` |

> See `doc/selective-merge.md` for the full selective branch-merge workflow these three keys were built for.

---

## Git hunks (`<leader>h`) — gitsigns

| Key | Mode | Action | Plugin |
|-----|------|--------|--------|
| `]c` | n | Next hunk | `plugins/git.lua` |
| `[c` | n | Previous hunk | `plugins/git.lua` |
| `<leader>hs` | n/v | Stage hunk | `plugins/git.lua` |
| `<leader>hr` | n/v | Reset hunk | `plugins/git.lua` |
| `<leader>hS` | n | Stage buffer | `plugins/git.lua` |
| `<leader>hR` | n | Reset buffer | `plugins/git.lua` |
| `<leader>hp` | n | Preview hunk | `plugins/git.lua` |
| `<leader>hi` | n | Preview hunk inline | `plugins/git.lua` |
| `<leader>hb` | n | Blame line | `plugins/git.lua` |
| `<leader>hd` | n | Diff against index | `plugins/git.lua` |
| `<leader>hD` | n | Diff against last commit | `plugins/git.lua` |
| `<leader>hq` | n | Quickfix hunks (this file) | `plugins/git.lua` |
| `<leader>hQ` | n | Quickfix hunks (all files) | `plugins/git.lua` |
| `ih` | o/x | Select inside hunk (text object) | `plugins/git.lua` |

---

## LSP — all languages
| Key | Mode | Action | Plugin |
|-----|------|--------|--------|
| `grn` | n | Rename symbol | `plugins/lsp.lua` |
| `gra` | n/x | Code action | `plugins/lsp.lua` |
| `grD` | n | Go to declaration | `plugins/lsp.lua` |
| `grr` | n | References (Telescope) | `plugins/telescope.lua` |
| `gri` | n | Implementations (Telescope) | `plugins/telescope.lua` |
| `grd` | n | Definition (Telescope) | `plugins/telescope.lua` |
| `gO` | n | Document symbols | `plugins/telescope.lua` |
| `gW` | n | Workspace symbols | `plugins/telescope.lua` |
| `grt` | n | Type definition | `plugins/telescope.lua` |
| `K` | n | Hover docs; during debug session evaluates variable — cursor enters float, `q` or jump away to close | `plugins/lsp.lua` via `core/utils.lua` |
| `<leader>th` | n | Toggle inlay hints | `plugins/lsp.lua` |
| `[d` | n | Previous diagnostic | `plugins/lsp.lua` |
| `]d` | n | Next diagnostic | `plugins/lsp.lua` |
| `<leader>e` | n | Show diagnostic float | `plugins/lsp.lua` |
| `<leader>rn` | n | Rename symbol | `plugins/lsp.lua` |

---

## Spell checking — all buffers

Spell checking is **off by default** in code files and **auto-enabled** in Markdown, plain text, and git commit messages. In code files with syntax or Treesitter active, Neovim automatically limits spell checking to comment and string regions — identifiers and keywords are never flagged.

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>ts` | Toggle spell on/off in current buffer | `plugins/spell.lua` |
| `<leader>tL` | Pick spell language from list (Telescope picker) | `plugins/spell.lua` |
| `]s` | Jump to next misspelled word | built-in |
| `[s` | Jump to previous misspelled word | built-in |
| `z=` | Show correction suggestions for word under cursor | built-in |
| `zg` | Add word to personal dictionary for current language | built-in |
| `zw` | Mark word as wrong | built-in |
| `zug` | Undo `zg` (remove from personal dictionary) | built-in |
| `zuw` | Undo `zw` | built-in |

**Supported languages in the picker:** English (US), English (UK), French, German, Spanish, Italian, Portuguese, Dutch, Russian. Neovim downloads the spell file for each language automatically on first use.

Personal word lists are kept per language inside this config directory (`spell/en_us.utf-8.add`, `spell/fr.utf-8.add`, etc.) and are version-controlled. The currently active language is marked with `✓` in the picker.

---

## Hard text wrap — all buffers

> **Hard wrap** inserts real newlines as you type past the column limit.  This
> is different from `wrap` (which only changes how long lines are *displayed*
> without touching the file).

| Key | Action | Notes |
|-----|--------|-------|
| `<leader>tW` | Toggle hard wrap on/off in current buffer | Defaults to col 80; see below to change |
| `gq{motion}` | Re-wrap existing text to `textwidth` | e.g. `gqip` re-wraps the current paragraph |
| `gqq` | Re-wrap current line | |

**To change the column width before toggling on:**
```
:set textwidth=72
```
Then press `<leader>tW` — the notification confirms the active column.

The toggle adds/removes the `t` flag from `formatoptions` in the current buffer
only; other buffers are unaffected. Setting `textwidth` via `:set` persists for
the buffer session; use a `.nvim.lua` or modeline to make it permanent per project.

---

## Toggles (`<leader>t`)

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>tb` | Toggle git blame line | `plugins/git.lua` |
| `<leader>tw` | Toggle git word diff | `plugins/git.lua` |
| `<leader>th` | Toggle LSP inlay hints | `plugins/lsp.lua` |
| `<leader>ts` | Toggle spell check | `plugins/spell.lua` |
| `<leader>tL` | Pick spell check language | `plugins/spell.lua` |
| `<leader>tW` | Toggle hard text wrap at textwidth (default 80) | `core/keymaps.lua` |
| `<leader>tr` | Toggle relative line numbers | `core/keymaps.lua` |
