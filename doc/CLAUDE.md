# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Applying changes

This is a Neovim configuration — there is no build step. Changes take effect by restarting Neovim or running `:source %` on the edited file. For plugin changes, a full restart is usually required so `vim.pack.add` can resolve new packages.

To format Lua files: `stylua <file>` (installed via Mason; requires stylua in PATH or `~/.local/share/nvim/mason/bin/stylua`).

To check Neovim health after significant changes: `:checkhealth` inside Neovim.

## Architecture

### Entry point and loading order

`init.lua` does four things in order:
1. Enables Lua bytecode caching (`vim.loader.enable()`)
2. Sets leader keys (`<Space>` for both `mapleader` and `maplocalleader`)
3. Requires `core/options`, `core/keymaps`, `core/autocmds`
4. Auto-loads every `.lua` file in `lua/plugins/` alphabetically via `vim.fs.dir`

The alphabetical load order matters: `dap.lua` installs nvim-dap before `fortran-tools.lua` calls `require('dap')`.

### Plugin manager

This config uses **`vim.pack`** (Neovim's built-in plugin manager, available since 0.11), not lazy.nvim or packer. Every plugin is added with `vim.pack.add { 'https://github.com/...' }`. Plugins are stored in `~/.local/share/nvim/pack/`.

### Core modules (`lua/core/`)

| File | Purpose |
|------|---------|
| `options.lua` | All `vim.o.*` / `vim.opt.*` settings |
| `keymaps.lua` | Global keymaps not tied to any plugin |
| `autocmds.lua` | Global autocommands + `vim.diagnostic.config()` |

Diagnostic configuration lives in `autocmds.lua` (not `lsp.lua`) because `vim.diagnostic` works independently of LSP.

### Plugin files (`lua/plugins/`)

Each file owns its own `vim.pack.add()` + `setup()`. The convention for lazy loading uses a guard flag at the top (`if vim.g.loaded_X then return end`) and defers all setup into a local `activate()` function.

**Always-loaded plugins** (load at startup):
- `completion.lua` — blink.cmp + LuaSnip
- `dap.lua` — nvim-dap + nvim-dap-ui install + dapui.setup + listeners + all language-agnostic `<leader>d*` keymaps
- `git.lua` — gitsigns + lazygit wrappers
- `lsp.lua` — Mason + nvim-lspconfig + fidget
- `neo-tree.lua` — file explorer, opens at startup
- `telescope.lua` — fuzzy finder, also overrides `vim.ui.select()`
- `toggleterm.lua` — persistent terminal, used by cmake-tools
- `treesitter.lua` — parsers auto-installed on FileType
- `ui.lua` — catppuccin, which-key, mini.nvim, todo-comments

**Lazy-loaded plugins**:
- `cmake-tools.lua` — activates once on startup if `CMakeLists.txt` is found in cwd or a parent, or on `DirChanged` when entering a CMake project
- `fortran-tools.lua` — activates once on first `FileType fortran` event
- `markdown.lua` — activates on `FileType markdown`

### Fortran / SWAT+ project integration

Both `cmake-tools.lua` and `fortran-tools.lua` read project paths from `vim.g` variables set by the project's `.nvim.lua` file. They do **not** hardcode any paths. Each variable falls back to a cwd-relative default so the tools work for any Fortran/CMake project even without a `.nvim.lua`:

```lua
local REPO_ROOT  = vim.g.project_repo_root  or vim.fn.getcwd()
local SRC_DIR    = vim.g.project_src_dir    or (REPO_ROOT .. '/src')
local WORK_ROOT  = vim.g.project_work_root  or (REPO_ROOT .. '/workdata')
local BUILD_ROOT = vim.g.project_build_root or (REPO_ROOT .. '/build')
```

Set these in your project's `.nvim.lua` (see `doc/swatplus.nvim.lua.template`).

**Fortran LSP** (`fortls`) is configured in `fortran-tools.lua`, not `lsp.lua`, because it is lazy-loaded. It requires `fortls` to be installed separately (not via Mason).

**DAP** for Fortran uses `gdb --interpreter=dap`. `dapui.setup()` is called exactly once in `dap.lua` at startup. Do not add another `dapui.setup()` call in language files.

### Timing-sensitive defers in `cmake-tools.lua`

Several `vim.defer_fn` calls have specific delays that must not be shortened:
- **200ms** after `vim.pack.add` before `require('cmake-tools')` — cmake-tools module is not available immediately after pack install
- **150ms** before scanning for new cmake output windows — cmake-tools opens windows asynchronously
- **50ms** after `WinClosed` before `set_current_win` — lets Neovim finish window teardown
- **500ms** before `CMakeGenerate` after preset selection — cmake-tools keeps task state alive briefly

### LSP configuration pattern

Servers are configured with `vim.lsp.config(name, opts)` and enabled with `vim.lsp.enable(name)` (Neovim 0.11+ API). Global LSP keymaps (`grn`, `gra`, `grD`, `<leader>th`) attach via a single `LspAttach` autocmd in `lsp.lua`. Telescope-based LSP pickers (`grr`, `gri`, `grd`, etc.) attach via a separate `LspAttach` autocmd in `telescope.lua`.

### Colorscheme highlight persistence

`ui.lua` re-applies custom `WinSeparator` and `StatusLine` highlights via a `ColorScheme` autocmd with a **100ms defer** — required because `mini.statusline` resets its highlight groups slightly after `ColorScheme` fires.

## Key keymap groups

| Prefix | Group | Defined in |
|--------|-------|-----------|
| `<leader>b` | Buffer operations | `core/keymaps.lua` |
| `<leader>c` | CMake | `plugins/cmake-tools.lua` |
| `<leader>d` | DAP / Debug | `plugins/dap.lua` (common); `<leader>ds` in language files |
| `<leader>g` | Git (repo-level) | `plugins/git.lua` |
| `<leader>h` | Git hunks (gitsigns) | `plugins/git.lua` |
| `<leader>s` | Search (Telescope) | `plugins/telescope.lua` |
| `<leader>t` | Toggles | `plugins/git.lua`, `plugins/lsp.lua` |
| `gr` | LSP actions | `plugins/lsp.lua`, `plugins/telescope.lua` |

Full keymap reference: `doc/keymaps.md` (rendered in-buffer via render-markdown.nvim).
