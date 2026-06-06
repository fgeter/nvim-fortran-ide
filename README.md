# Neovim Configuration

A Neovim configuration focused on Fortran development, built around the SWAT+ hydrological model project. Provides a full IDE experience with LSP, debugging (GDB), CMake integration, and git tooling.

## Purpose

- **Fortran LSP** via `fortls` — hover docs, go-to-definition, find references, diagnostics
- **GDB debugging** via `nvim-dap` with a full UI (scopes, breakpoints, watches, call stack, REPL)
- **CMake integration** — preset selection, configure, build (`-j 32`), run with workdata picker
- **Git** — inline hunk signs, lazygit UI, async push/pull, branch management
- **File navigation** — neo-tree sidebar, Telescope fuzzy finder, recent files
- **Completion** — `blink.cmp` with LSP, path, snippet, and buffer sources

## Requirements

- **Neovim ≥ 0.11** (uses built-in `vim.pack` package manager and `vim.lsp.config`/`vim.lsp.enable`)
- **[Nerd Font](https://www.nerdfonts.com/)** in your terminal (icons throughout the UI). I use mononike nerd font 11 pt.
- **`fortls`** — Fortran language server: `pip install fortls`,  If on Arch, must be loaded via pacman.
- **`gdb`** — GNU debugger for DAP: install via your system package manager
- **`lazygit`** — terminal git UI: see [lazygit releases](https://github.com/jesseduffield/lazygit)
- **`make`** — for compiling the Telescope fzf native sorter (optional but recommended)
- **`CMake`** - must install for using cmake with swatplus
- **`git`** - must install if you wish to submit pull requests 

Mason auto-installs `lua_ls` and `stylua` on first launch.

## Installation

```bash
# Back up any existing config
mv ~/.config/nvim ~/.config/nvim.bak

# Clone this repository
git clone <your-repo-url> ~/.config/nvim

# Launch Neovim — plugins download automatically on first start
nvim
```

On first launch Neovim will download all plugins via `vim.pack`. Mason will then install `lua_ls` and `stylua`. Treesitter parsers install automatically when you first open a file of each language.

If your terminal does not have a Nerd Font, set `vim.g.have_nerd_font = false` in `init.lua`.

## Project paths (Fortran / SWAT+)

The CMake and Fortran tool configs hardcode paths to the SWAT+ project. Update these at the top of both files if your project location differs:

- `lua/plugins/cmake-tools.lua` — `REPO_ROOT`, `WORK_ROOT`, `BUILD_ROOT`
- `lua/plugins/fortran-tools.lua` — `REPO_ROOT`, `SRC_DIR`, `WORK_ROOT`, `BUILD_ROOT`

## Keymaps

Leader key: `<Space>`

### General

| Key | Action |
|-----|--------|
| `<Esc>` | Clear search highlights |
| `<C-s>` | Save file |
| `<C-h/j/k/l>` | Move between splits |
| `<leader>q` | Open diagnostics in location list |
| `gF` | Go to file:line under cursor in a split |
| `<Esc><Esc>` | Exit terminal insert mode |

### Buffers (`<leader>b`)

| Key | Action |
|-----|--------|
| `<leader>bn` | Next buffer |
| `<leader>bp` | Previous buffer |
| `<leader>bd` | Delete buffer (keeps window layout) |
| `<leader><leader>` | Telescope buffer picker |

### Tabs

| Key | Action |
|-----|--------|
| `]]` | Next tab |
| `[[` | Previous tab |

### Terminal

| Key | Action |
|-----|--------|
| `<C-\>` | Toggle terminal |

### Search (`<leader>s`)

| Key | Action |
|-----|--------|
| `<leader>sf` | Find files (including hidden/gitignored) |
| `<leader>sg` | Live grep |
| `<leader>sw` | Grep word under cursor |
| `<leader>s/` | Grep in open buffers |
| `<leader>sh` | Search help tags |
| `<leader>sk` | Search keymaps |
| `<leader>sd` | Search diagnostics |
| `<leader>sr` | Resume last picker |
| `<leader>sc` | Search commands |
| `<leader>sn` | Search Neovim config files |
| `<leader>/` | Fuzzy search current buffer |
| `<leader>rf` | Recent files |

### File Tree (neo-tree)

| Key | Action |
|-----|--------|
| `\` | Reveal current file in neo-tree |
| `<leader>\` | Show and focus buffer list in neo-tree |

Inside neo-tree:

| Key | Action |
|-----|--------|
| `<CR>` on line 1 | Navigate to parent directory (`← ..`) |
| `<CR>` / `o` | Open file or expand directory |
| `s` / `v` | Open in horizontal / vertical split |
| `<BS>` | Navigate up one directory |
| `a` / `d` / `r` | Add / delete / rename |
| `c` / `m` | Copy / move |
| `H` | Toggle hidden files |
| `R` | Refresh |

### Formatting

| Key | Action |
|-----|--------|
| `<leader>f` | Format buffer or selection |

### Markdown (`<leader>m`) — markdown buffers only

| Key | Action |
|-----|--------|
| `<leader>mr` | Toggle rendering |
| `<leader>me` | Expand all sections |
| `<leader>mc` | Collapse all sections |

### CMake (`<leader>c`) — activates in CMake projects

| Key | Action |
|-----|--------|
| `<leader>cp` | Select preset + auto-run Generate |
| `<leader>cg` | CMake Generate (configure) |
| `<leader>cb` | Build (`-j 32`) |
| `<leader>cx` | Clean |
| `<leader>cd` | Delete build directory (prompts confirmation) |
| `<leader>cr` | Run swatplus (pick executable + workdata) |

### Debug / DAP (`<leader>d`) — activates on first Fortran file

| Key | Alt | Action |
|-----|-----|--------|
| `<leader>ds` | | Start / continue (launches picker if no session) |
| `<leader>dq` | | Terminate session |
| `<leader>dr` | | Restart session |
| `<leader>dn` | `<F2>` | Step over |
| `<leader>di` | `<F1>` | Step into |
| `<leader>do` | `<F3>` | Step out |
| `<leader>dc` | | Run to cursor |
| `<leader>db` | | Toggle breakpoint |
| `<leader>dB` | | Conditional breakpoint |
| `<leader>dL` | | Log point |
| `<leader>dx` | | Clear all breakpoints |
| `<leader>dw` | | Add word under cursor to watches |
| `<leader>dU` | `<F7>` | Toggle DAP UI |
| `<leader>de` | | Eval expression / selection |
| `<leader>dR` | | Open REPL |
| | `<F5>` | Continue |

Press `K` over any variable during a debug session to inspect its value.

### Git (`<leader>g`)

| Key | Action |
|-----|--------|
| `<leader>gg` | Open lazygit |
| `<leader>gc` | Commit (with file picker) |
| `<leader>gb` | Create branch |
| `<leader>gp` | Pull (async) |
| `<leader>gP` | Push (async) |
| `<leader>gs` | Switch branch |
| `<leader>gd` | Delete branch |
| `<leader>gm` | Merge branch |

### Git Hunks (`<leader>h`) — gitsigns

| Key | Mode | Action |
|-----|------|--------|
| `]c` / `[c` | n | Next / previous hunk |
| `<leader>hs` | n/v | Stage hunk |
| `<leader>hr` | n/v | Reset hunk |
| `<leader>hS` | n | Stage buffer |
| `<leader>hR` | n | Reset buffer |
| `<leader>hp` | n | Preview hunk |
| `<leader>hb` | n | Blame line |
| `<leader>hd` | n | Diff against index |
| `<leader>hD` | n | Diff against last commit |
| `ih` | o/x | Select inside hunk |

### LSP — all languages

| Key | Mode | Action |
|-----|------|--------|
| `grn` | n | Rename symbol |
| `gra` | n/x | Code action |
| `grD` | n | Go to declaration |
| `grr` | n | References (Telescope) |
| `gri` | n | Implementations |
| `grd` | n | Definition (Telescope) |
| `gO` | n | Document symbols |
| `gW` | n | Workspace symbols |
| `K` | n | Hover docs (or DAP eval during debug) |
| `<leader>th` | n | Toggle inlay hints |
| `[d` / `]d` | n | Previous / next diagnostic |
| `<leader>e` | n | Show diagnostic float |

### Toggles (`<leader>t`)

| Key | Action |
|-----|--------|
| `<leader>tb` | Toggle git blame line |
| `<leader>tw` | Toggle git word diff |
| `<leader>th` | Toggle LSP inlay hints |
