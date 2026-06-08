# Keymap Reference

---

## General

| Key | Action | Plugin |
|-----|--------|--------|
| `<Esc>` | Clear search highlights | `core/keymaps.lua` |
| `<C-s>` | Save file | `core/keymaps.lua` |
| `<C-h>` | Focus left window | `core/keymaps.lua` |
| `<C-j>` | Focus lower window | `core/keymaps.lua` |
| `<C-k>` | Focus upper window | `core/keymaps.lua` |
| `<C-l>` | Focus right window | `core/keymaps.lua` |
| `<leader>q` | Open diagnostics in location list | `core/keymaps.lua` |
| `gF` | Go to file:line under cursor in split | `core/keymaps.lua` |
| `<Esc><Esc>` | Exit terminal insert mode | `core/keymaps.lua` |

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

Inside neo-tree:

| Key | Action | Plugin |
|-----|--------|--------|
| `<CR>` / `o` | Open file | `plugins/neo-tree.lua` |
| `s` | Open in horizontal split | `plugins/neo-tree.lua` |
| `v` | Open in vertical split | `plugins/neo-tree.lua` |
| `<BS>` | Navigate up one directory | `plugins/neo-tree.lua` |
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
| `?` | Show help | `plugins/neo-tree.lua` |

---

## Formatting

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>f` | Format buffer or selection | `plugins/formatting.lua` |

---

## CMake (`<leader>c`) — active only in CMake projects

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>cp` | Select preset + auto-run Generate | `plugins/cmake-tools.lua` |
| `<leader>cg` | CMake Generate (configure) | `plugins/cmake-tools.lua` |
| `<leader>cb` | Build active preset (`-j 32`) | `plugins/cmake-tools.lua` |
| `<leader>cx` | Clean active preset | `plugins/cmake-tools.lua` |
| `<leader>cd` | Delete build directory (prompts confirmation) | `plugins/cmake-tools.lua` |
| `<leader>cr` | Run swatplus (pick exe + workdata, cleans output first) | `plugins/cmake-tools.lua` |

---

## Debug / DAP (`<leader>d`) — active after opening a Fortran file

| Key | Alt key | Action | Plugin |
|-----|---------|--------|--------|
| `<leader>ds` | | Start / continue | `plugins/fortran-tools.lua` |
| `<leader>dq` | | Terminate session | `plugins/fortran-tools.lua` |
| `<leader>dr` | | Restart session | `plugins/fortran-tools.lua` |
| `<leader>dn` | `<F2>` | Step over | `plugins/fortran-tools.lua` / `plugins/dap.lua` |
| `<leader>di` | `<F1>` | Step into | `plugins/fortran-tools.lua` / `plugins/dap.lua` |
| `<leader>do` | `<F3>` | Step out | `plugins/fortran-tools.lua` / `plugins/dap.lua` |
| `<leader>dc` | | Run to cursor | `plugins/fortran-tools.lua` |
| `<leader>db` | | Toggle breakpoint | `plugins/fortran-tools.lua` |
| `<leader>dB` | | Conditional breakpoint | `plugins/fortran-tools.lua` |
| `<leader>dL` | | Log point | `plugins/fortran-tools.lua` |
| `<leader>dx` | | Clear all breakpoints | `plugins/fortran-tools.lua` |
| `<leader>dw` | | Add word under cursor to watches | `plugins/fortran-tools.lua` |
| `<leader>dU` | `<F7>` | Toggle DAP UI | `plugins/fortran-tools.lua` / `plugins/dap.lua` |
| `<leader>de` | | Eval expression / selection | `plugins/fortran-tools.lua` |
| `<leader>dR` | | Open REPL | `plugins/fortran-tools.lua` |
| | `<F5>` | Continue (global alias) | `plugins/dap.lua` |

While debugging, press `K` over any variable to see its current value. Move the cursor to close the popup.

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
| `K` | n | Hover docs (or DAP eval in debug session) | `plugins/fortran-tools.lua` |
| `<leader>th` | n | Toggle inlay hints | `plugins/lsp.lua` |
| `[d` | n | Previous diagnostic | `plugins/fortran-tools.lua` |
| `]d` | n | Next diagnostic | `plugins/fortran-tools.lua` |
| `<leader>e` | n | Show diagnostic float | `plugins/fortran-tools.lua` |
| `<leader>rn` | n | Rename symbol (Fortran) | `plugins/fortran-tools.lua` |
| `<leader>ca` | n | Code action (Fortran) | `plugins/fortran-tools.lua` |

---

## Toggles (`<leader>t`)

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>tb` | Toggle git blame line | `plugins/git.lua` |
| `<leader>tw` | Toggle git word diff | `plugins/git.lua` |
| `<leader>th` | Toggle LSP inlay hints | `plugins/lsp.lua` |
