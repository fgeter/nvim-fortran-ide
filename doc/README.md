# Neovim Configuration

## Structure

```
~/.config/nvim/
├── init.lua                    — entry point (tiny, auto-loads lua/plugins/)
├── doc/
│   ├── README.md               — this file
│   ├── keymaps.md              — full keymap reference
│   ├── native_nvim_keymaps.md  — built-in keymaps not defined in this config
│   ├── swatplus.nvim.lua.template        — copy to SWAT+ project root
│   └── python-project.nvim.lua.template  — copy to Python project root
└── lua/
    ├── core/
    │   ├── options.lua         — editor settings (vim.o.*)
    │   ├── keymaps.lua         — global keymaps (non-plugin)
    │   └── autocmds.lua        — global autocommands
    ├── plugins/                — one file per plugin, auto-loaded by init.lua
    │   ├── ui.lua              — catppuccin, which-key, mini, todo-comments, indent-blankline, bufferline
    │   ├── autopairs.lua       — nvim-autopairs (auto-close brackets/quotes)
    │   ├── telescope.lua       — fuzzy finder + LSP pickers
    │   ├── lsp.lua             — mason, lspconfig, fidget
    │   ├── completion.lua      — blink.cmp + luasnip  [lazy: InsertEnter]
    │   ├── formatting.lua      — conform.nvim          [lazy: <leader>f]
    │   ├── treesitter.lua      — syntax highlighting   [lazy: FileType]
    │   ├── git.lua             — gitsigns + lazygit
    │   ├── neo-tree.lua        — file explorer
    │   ├── toggleterm.lua      — persistent terminal
    │   ├── dap.lua             — DAP core + F-key aliases + virtual text
    │   ├── markdown.lua        — render-markdown.nvim
    │   ├── surround.lua        — nvim-surround (ys/cs/ds) [lazy: BufReadPost]
    │   ├── lint.lua            — nvim-lint + shellcheck    [lazy: FileType sh/bash]
    │   ├── cmake-tools.lua     — CMake integration         [lazy: DirChanged]
    │   ├── make-tools.lua      — Make integration          [lazy: DirChanged]
    │   ├── c-tools.lua         — C/C++ DAP (GDB)           [lazy: FileType c/cpp]
    │   ├── web-tools.lua       — JS/TS/React DAP           [lazy: FileType js/ts/jsx/tsx]
    │   ├── java-tools.lua      — Java LSP + DAP (jdtls)    [lazy: FileType java]
    │   ├── fortran-tools.lua   — Fortran LSP + DAP         [lazy: FileType fortran]
    │   └── python.lua          — Python LSP + DAP          [lazy: FileType python]
    └── projects/               — shared language configs, sourced by .nvim.lua
        ├── fortran.lua         — activates cmake + fortran tools for a project
        └── python.lua          — activates python tools for a project
```

---

## Project-local configuration

Each project can have a configuration file called `.nvim.lua`. This file is
a project specific configuration file that specifies the programing language 
and path variables your project may need.

When the .nvim.lua file is copied to your project or created in your project
directory, it first must be "trusted".  To do that open it in the project
directory and execute the nvim command ":trust". 

After you have trusted this file it once, neovim will source this file 
automatically on startup 

The .nvim.lua file sets `vim.g.project_*` path variables and then calls
`require('projects.fortran')` or `require('projects.python')` to inherit
the shared language configuration. This keeps project-specific paths out
of the plugin files so the same plugin config works for any project.

### Setting up a new project

**Step 1 — copy the template:**
```bash
# Fortran/CMake project (e.g. SWAT+)
cp ~/.config/nvim/doc/swatplus.nvim.lua.template \
   ~/path/to/project/.nvim.lua

# Python project
cp ~/.config/nvim/doc/python-project.nvim.lua.template \
   ~/path/to/project/.nvim.lua
```

**Step 2 — edit the template:**
Open `.nvim.lua` and update `vim.g.project_name` and any paths that
differ from the defaults.

**Step 3 — trust the file:**
Neovim will not source `.nvim.lua` until you explicitly trust it.
Open the file directly, run `:trust`, then quit:
```bash
nvim ~/path/to/project/.nvim.lua
# inside Neovim:
:trust
:q
```

**Step 4 — open the project:**
```bash
cd ~/path/to/project
nvim
```

**Step 5 — verify it loaded:**
```
:lua print(vim.g.project_name)
```
Should print your project name (e.g. `SWAT+`).

---

## vim.g path variables

These are set in `.nvim.lua` and read by `cmake-tools.lua`,
`fortran-tools.lua`, and `python.lua` instead of hardcoded paths.

| Variable | Used by | Description |
|----------|---------|-------------|
| `vim.g.project_name` | notifications | Display name shown on load |
| `vim.g.project_type` | projects/ | `'fortran'` or `'python'` |
| `vim.g.project_repo_root` | cmake, fortran, python | Absolute project root path |
| `vim.g.project_src_dir` | fortran-tools | Fortran source files directory |
| `vim.g.project_work_root` | cmake-tools | Workdata / model run directory |
| `vim.g.project_build_root` | cmake-tools | CMake build output directory |
| `vim.g.project_venv` | python | Path to virtualenv (optional) |
| `vim.g.project_python_bin` | python | Explicit python binary (optional) |

---

## Jupyter notebooks and HTML preview

Neo-tree handles `.ipynb` and `.html` files specially on double-click:

| File type | Double-click action |
|-----------|-------------------|
| `.ipynb` | Opens in JupyterLab in the browser |
| `.html` | Opens in the default browser via `xdg-open` |
| All others | Opens in a Neovim buffer (normal behaviour) |

`<CR>` always opens the raw file in Neovim regardless of type.

### Requirement: JupyterLab CLI

The `.ipynb` double-click requires the `jupyter-lab` command to be available in `PATH`:

```bash
# pip
pip install jupyterlab

# or conda
conda install -c conda-forge jupyterlab

# verify
jupyter-lab --version
```

### Stopping the JupyterLab server

Closing the browser tab does **not** stop the server. Use `<leader>jq` in Neovim
to stop it cleanly (equivalent to File → Shutdown in the JupyterLab browser UI).

---

## Lazy loading summary

Most plugins load at startup. The following are deferred:

| Plugin | Trigger |
|--------|---------|
| `completion.lua` | First `InsertEnter` event |
| `formatting.lua` | First `<leader>f` press |
| `treesitter.lua` | Per-language parser on `FileType` |
| `surround.lua` | First `BufReadPost` event |
| `lint.lua` | `FileType sh` or `FileType bash` |
| `cmake-tools.lua` | `DirChanged` into a CMake project, or startup inside one |
| `make-tools.lua` | `DirChanged` into a Makefile project (no CMakeLists.txt), or startup inside one |
| `c-tools.lua` | `FileType c` or `FileType cpp` |
| `web-tools.lua` | `FileType javascript`, `typescript`, `javascriptreact`, or `typescriptreact` |
| `java-tools.lua` | `FileType java` |
| `fortran-tools.lua` | `FileType fortran` |
| `python.lua` | `FileType python` |

---

## Mason — installing language tools

Mason auto-installs all configured LSP servers, formatters, linters, and DAP
adapters on first launch. No manual `:MasonInstall` commands are needed.
Binaries go into `~/.local/share/nvim/mason/` and do not require system packages.

Tools installed automatically include: `lua-language-server`, `stylua`,
`basedpyright`, `debugpy`, `ruff`, `clangd`, `bash-language-server`,
`json-lsp`, `yaml-language-server`, `taplo`, `rust-analyzer`, `html-lsp`,
`css-lsp`, `typescript-language-server`, `eslint-lsp`, `jdtls`,
`java-debug-adapter`, `js-debug-adapter`, `shfmt`, `prettier`,
`clang-format`, `google-java-format`, `shellcheck`.

Fortran tools (`fortls`, `gfortran`, `gdb`) must be installed via your
system package manager (e.g. `pacman -S fortls gdb gcc-fortran`), not Mason.

---

## Adding a new project

1. Copy the appropriate template from `doc/` to the project root
2. Edit `vim.g.project_name` and any path variables
3. Open the file in Neovim and run `:trust`
4. Open the project root in Neovim — the config loads automatically

To check which `.nvim.lua` files are currently trusted:
```
:help trust
```
Trusted files are stored in `~/.local/share/nvim/trust`.

---

## Keymap reference

See `doc/keymaps.md` for the full keymap reference with plugin sources.
Open it in Neovim for a rendered table view (render-markdown.nvim).
