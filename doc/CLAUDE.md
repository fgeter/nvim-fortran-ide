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

**Version pinning convention:** every plugin with tagged releases is pinned via `version = vim.version.range(...)` — a major range like `'2.*'` when the project has a stable major, or `'*'` (latest release tag, never the branch tip) for 0.x projects. Only plugins with no usable tags (mason-tool-installer, schemastore, nvim-dap-virtual-text, guess-indent, nvim-lint, telescope-ui-select, telescope-fzf-native, cmake-tools) track their default branch. Version constraints are applied by `vim.pack.update()`, not at startup, so bumping a pin takes effect on the next explicit update. When adding a plugin, check its tags and pin accordingly.

### Core modules (`lua/core/`)

| File | Purpose |
|------|---------|
| `options.lua` | All `vim.o.*` / `vim.opt.*` settings; OSC 52 clipboard enabled only when `$KITTY_WINDOW_ID` is set — other terminals (Konsole) use wl-clipboard via auto-detect |
| `keymaps.lua` | Global keymaps not tied to any plugin |
| `autocmds.lua` | Global autocommands + `vim.diagnostic.config()` |

Diagnostic configuration lives in `autocmds.lua` (not `lsp.lua`) because `vim.diagnostic` works independently of LSP.

### Plugin files (`lua/plugins/`)

Each file owns its own `vim.pack.add()` + `setup()`. The convention for lazy loading uses a guard flag at the top (`if vim.g.loaded_X then return end`) and defers all setup into a local `activate()` function.

**Always-loaded plugins** (load at startup):
- `gitsigns.lua` — inline git decorations + hunk keymaps
- `lsp.lua` — Mason + nvim-lspconfig + fidget
- `neo-tree.lua` — file explorer, opens at startup; `DirChanged` autocmd switches the panel to the filesystem source on `:cd`
- `telescope.lua` — fuzzy finder, also overrides `vim.ui.select()`
- `toggleterm.lua` — persistent terminal, used by cmake-tools
- `treesitter.lua` — parsers auto-installed on FileType
- `ui.lua` — catppuccin, which-key, mini.nvim, todo-comments

**Lazy-loaded plugins**:
- `dap.lua` — the whole DAP stack (nvim-dap, dap-ui, nio, virtual-text + dapui.setup + listeners) lives in an `activate()` triggered by the first `<leader>d*`/F-key press (the keymaps are permanent thin closures) or by a language file calling `require('plugins.dap').activate()` before its `require('dap')`
- `completion.lua` — blink.cmp + LuaSnip on first InsertEnter
- `autopairs.lua` — setup on first InsertEnter (its setup force-attaches to the current buffer, so the first bracket typed still pairs)
- `cmake-tools.lua` — activates once on startup if `CMakeLists.txt` is found in cwd or a parent, or on `DirChanged` when entering a CMake project
- `fortran-tools.lua` — activates once on first `FileType fortran` event
- `markdown.lua` — activates on `FileType markdown`

The buffer-local `K` handler (`utils.attach_k_handler`) resolves dap via `package.loaded` at keypress time, never at LspAttach — required because the DAP stack may load after LSP attaches.

### Feature files (`lua/features/`)

Homegrown subsystems with no third-party plugin behind them, loaded after `lua/plugins/` by the same init.lua loop. When a plugin update breaks something, the blast radius is immediately clear: `plugins/` files are configuration, `features/` files are our code.

| File | Purpose |
|------|---------|
| `git-workflow.lua` | Repo-level git: lazygit launcher, commit/pull/push, branch ops, ref-diff review (`<leader>gf/gq/gn`), remote-ahead check (startup, `:cd`, periodic, pre-keymap) |
| `hscrollbar.lua` | Horizontal scrollbar (floating 1-row bar; nvim-scrollview only does vertical) |
| `edge-scroll.lua` | Mouse edge-hover horizontal scrolling (needs `mousemoveevent`) |
| `goto-file-line.lua` | `gF` / `<C-g>f` — open `file:line` references from compiler errors |
| `neotree-recovery.lua` | Reopens an editor window when `:q` leaves only the neo-tree sidebar (pairs with `close_if_last_window = false`) |

### Fortran / SWAT+ project integration

Shared project-runner logic lives in **`lua/core/project.lua`**: root resolution (`project.roots()`), executable discovery (`project.find_executables`, filtered by `vim.g.project_executable_pattern`, default `'*'`), the two-step executable→workdata picker (`project.pick_and_launch`), pre-run output cleaning (`project.clean_output_files`, driven by `vim.g.project_clean_output_patterns`, no-op when unset), and the build-terminal success suffix (`project.build_done_suffix`). `cmake-tools.lua`, `make-tools.lua`, and `fortran-tools.lua` all consume these helpers — none of them hardcodes paths or executable names.

**Important:** `project.roots()` must be called inside `activate()`, not at module load time. This ensures `:cd ~/project` before activation (cmake-tools via `DirChanged`, fortran-tools via `FileType fortran`) picks up the correct cwd rather than the cwd at Neovim startup. Also inside `activate()`: anything that waits on `VimEnter` must first check `vim.v.vim_did_enter` — on the DirChanged path VimEnter has already fired and will never fire again.

```lua
-- inside activate()
local project = require('core.project')
local roots   = project.roots()   -- { repo, build, work, src } from vim.g.project_* or cwd defaults
```

Set the `vim.g.project_*` variables in your project's `.nvim.lua` (see `doc/swatplus.nvim.lua.template`).

**Fortran LSP** (`fortls`) is configured in `fortran-tools.lua`, not `lsp.lua`, because it is lazy-loaded. It requires `fortls` to be installed separately (not via Mason).

**DAP** for Fortran uses `gdb --interpreter=dap`. `dapui.setup()` is called exactly once in `dap.lua` at startup. Do not add another `dapui.setup()` call in language files.

### Event-driven sequencing (no timing defers)

Cross-plugin sequencing is event-driven, not timer-based — keep it that way when editing:
- cmake output windows are detected via a `WinNew` watcher registered before the command runs (only terminal buffers are claimed); post-close cleanup uses `vim.schedule` from `WinClosed`
- `<leader>cp` chains `CMakeGenerate` from `cmake.select_configure_preset(callback)` — cmake-tools' own completion callback
- neo-tree's startup open runs on `UIEnter`, which is guaranteed to fire after every `VimEnter` handler (including session restore)
- `dap.lua` clears neo-tree's pending `neo-tree-follow` debounce via `neo-tree.utils.debounce(name, nil, …)` before closing the sidebar
- toggleterm `term:send` immediately after `term:open` is safe — the shell job is spawned synchronously

### LSP configuration pattern

Servers are configured with `vim.lsp.config(name, opts)` and enabled with `vim.lsp.enable(name)` (Neovim 0.11+ API). Global LSP keymaps (`grn`, `gra`, `grD`, `<leader>th`) attach via a single `LspAttach` autocmd in `lsp.lua`. Telescope-based LSP pickers (`grr`, `gri`, `grd`, etc.) attach via a separate `LspAttach` autocmd in `telescope.lua`.

### Colorscheme highlight persistence

All custom highlights (`WinSeparator`, `NeoTreeWinSeparator`, `StatusLine`, `StatusLineNC`, diff groups) live in catppuccin's `highlight_overrides` in `ui.lua`, so catppuccin itself re-applies them on every `:colorscheme catppuccin` — no ColorScheme autocmd or defer.

## Key keymap groups

| Prefix | Group | Defined in |
|--------|-------|-----------|
| `<leader>b` | Buffer operations | `core/keymaps.lua` |
| `<leader>c` | CMake | `plugins/cmake-tools.lua` |
| `<leader>d` | DAP / Debug | `plugins/dap.lua` (common); `<leader>ds` in language files |
| `<leader>g` | Git (repo-level) | `features/git-workflow.lua` |
| `<leader>h` | Git hunks (gitsigns) | `plugins/gitsigns.lua` |
| `<leader>s` | Search (Telescope) | `plugins/telescope.lua` |
| `<leader>t` | Toggles | `plugins/gitsigns.lua`, `plugins/lsp.lua` |
| `gr` | LSP actions | `plugins/lsp.lua`, `plugins/telescope.lua` |

Full keymap reference: `doc/keymaps.md` (rendered in-buffer via render-markdown.nvim).
