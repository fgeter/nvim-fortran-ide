# Neovim Configuration

## Structure

```
~/.config/nvim/
├── init.lua                    — entry point (tiny)
├── doc/
│   ├── keymaps.md              — full keymap reference
│   ├── swatplus.nvim.lua.template     — copy to SWAT+ project root
│   └── python-project.nvim.lua.template — copy to Python project root
└── lua/
    ├── core/
    │   ├── options.lua         — editor settings
    │   ├── keymaps.lua         — global keymaps
    │   └── autocmds.lua        — global autocommands
    ├── plugins/                — one file per plugin, auto-loaded
    │   ├── ui.lua              — catppuccin, which-key, mini, todo-comments
    │   ├── telescope.lua       — fuzzy finder
    │   ├── lsp.lua             — mason, lspconfig, fidget
    │   ├── completion.lua      — blink.cmp + luasnip (lazy: InsertEnter)
    │   ├── formatting.lua      — conform.nvim (lazy: <leader>f)
    │   ├── treesitter.lua      — syntax highlighting
    │   ├── git.lua             — gitsigns + lazygit
    │   ├── neo-tree.lua        — file explorer
    │   ├── toggleterm.lua      — persistent terminal
    │   ├── dap.lua             — DAP core + F-key aliases
    │   ├── markdown.lua        — render-markdown.nvim
    │   ├── cmake-tools.lua     — CMake integration (lazy: DirChanged)
    │   ├── fortran-tools.lua   — Fortran LSP + DAP (lazy: FileType fortran)
    │   └── python.lua          — Python LSP + DAP (lazy: FileType python)
    └── projects/               — shared language project configs
        ├── fortran.lua         — inherited by Fortran project .nvim.lua files
        └── python.lua          — inherited by Python project .nvim.lua files
```

## Project-local configuration

Each project can have a `.nvim.lua` file in its root directory that sets
project-specific paths and loads the appropriate shared config.

### Setting up a new project

**Fortran/CMake project (e.g. SWAT+):**
```bash
cp ~/.config/nvim/doc/swatplus.nvim.lua.template ~/myproject/.nvim.lua
# Edit .nvim.lua to set the correct paths
nvim ~/myproject/
# Run :trust to allow the file to execute
```

**Python project:**
```bash
cp ~/.config/nvim/doc/python-project.nvim.lua.template ~/myproject/.nvim.lua
# Edit .nvim.lua to set the project name and venv path if needed
nvim ~/myproject/
# Run :trust to allow the file to execute
```

### How it works

1. `vim.o.exrc = true` in `core/options.lua` enables per-directory configs
2. Neovim sources `.nvim.lua` from the cwd on startup (if trusted)
3. `.nvim.lua` sets `vim.g.project_*` path variables
4. `.nvim.lua` calls `require('projects.fortran')` or `require('projects.python')`
5. The shared project config activates `cmake-tools` and `fortran-tools` / `python`
   with the correct paths from `vim.g`

### Path variables (set in .nvim.lua)

| Variable | Used by | Description |
|----------|---------|-------------|
| `vim.g.project_name` | notifications | Display name |
| `vim.g.project_repo_root` | cmake, fortran, python | Project root |
| `vim.g.project_src_dir` | fortran-tools | Source files directory |
| `vim.g.project_work_root` | cmake-tools | Workdata/run directory |
| `vim.g.project_build_root` | cmake-tools | Build output directory |
| `vim.g.project_venv` | python | Virtualenv path |
| `vim.g.project_python_bin` | python | Explicit python binary |

## Mason — installing language tools

Run these once after first launch:

```
:MasonInstall basedpyright debugpy ruff    # Python
```

Fortran tools (`fortls`, `gfortran`) are installed via your system package
manager, not Mason.

## Trusted project files

Neovim stores trusted files in `~/.local/share/nvim/trust`.
To list or manage trusted files: `:help trust`
