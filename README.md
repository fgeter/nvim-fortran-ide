# Neovim Configuration

A Neovim configuration that provides a full IDE experience with first-class 
support for Fortran in a CMake build environment. It includes
debugging, CMake integration, git tooling, and fuzzy search — with a
project-local config system that keeps language-specific paths out of the
shared config. Support/features for other computer languages have been added
but have not rigorously tested.  These languages include Python, C, C++, Java,
JavaScript, TypeScript, React (JSX/TSX), Rust, Bash, HTML, CSS, JSON, YAML,
TOML, and Lua — LSP,

> **Platform:** This configuration has been developed and tested on **Linux
> only** (Arch Linux with Wayland). It should work on macOS with minor
> adjustments (notably `nproc` → `sysctl -n hw.logicalcpu` for CPU core
> detection, and system package manager differences), but this has not been
> verified. **Pull requests adding macOS instructions or compatibility fixes
> are very welcome.**

## Credits
The owner/creator of this repository worked extensively with AI to develop this
NeoVim IDE and to extend its features.  Primary AI tools were Claude Code, 
Claude, Grok, and Gemini in that order.

## Features

- **LSP** — Fortran (`fortls`), Python (`basedpyright`), Lua (`lua_ls`), C/C++ (`clangd`), Bash (`bashls`), JSON/YAML with schema validation (`jsonls`/`yamlls` + schemastore), TOML (`taplo`), Rust (`rust_analyzer`), HTML/CSS (`html`/`cssls`), TypeScript/JavaScript/React (`ts_ls`, `eslint`), Java (`jdtls` via nvim-jdtls)
- **Debugging** — GDB for Fortran and C/C++, debugpy for Python, jdtls DAP for Java, pwa-node for JS/TS/React — all with full DAP UI and inline virtual-text variable values
- **CMake** — preset selection, configure, parallel build, run with workdata picker
- **Git** — inline hunk signs (gitsigns), lazygit UI, async push/pull, branch management
- **File navigation** — neo-tree sidebar, Telescope fuzzy finder, recent files
- **Jupyter notebooks** — double-click `.ipynb` in neo-tree opens in JupyterLab (browser); `<leader>jq` stops the server when done
- **HTML preview** — double-click `.html` in neo-tree opens in the default browser via `xdg-open`
- **Completion** — `blink.cmp` with LSP, path, snippet, and buffer sources
- **Formatting** — `conform.nvim`: stylua (Lua), ruff (Python), clang-format (C/C++), google-java-format (Java), shfmt (shell), prettier (JS/TS/JSX/TSX/HTML/CSS/JSON/YAML/Markdown)
- **Linting** — `nvim-lint` with shellcheck for shell scripts (supplements bashls)
- **Surround** — `nvim-surround` for adding/changing/deleting surrounding pairs (`ys`, `cs`, `ds`)
- **Spell checking** — built-in US English spell check; auto-on for Markdown/text/commit messages; `<leader>ts` toggles in any buffer; `zg` adds words to a version-controlled personal dictionary
- **Markdown** — `render-markdown.nvim` for rendered tables, headings, and code blocks
- **Project-local config** — per-project `.nvim.lua` sets paths; shared language
  configs in `lua/projects/` are inherited so plugin files have no hardcoded paths

## Language support status

| Language | LSP | Debug | Format | Status |
|----------|-----|-------|--------|--------|
| Fortran | ✅ fortls | ✅ GDB | — | **Tested / production** |
| Lua | ✅ lua_ls | — | ✅ stylua | **Tested / production** |
| Python | ✅ basedpyright | ✅ debugpy | ✅ ruff | ⚠️ Preliminary — untested |
| C | ✅ clangd | ✅ GDB | ✅ clang-format | ⚠️ Preliminary — untested |
| C++ | ✅ clangd | ✅ GDB | ✅ clang-format | ⚠️ Preliminary — untested |
| Bash / Shell | ✅ bashls | — | ✅ shfmt | ⚠️ Preliminary — untested |
| JavaScript | ✅ ts_ls + eslint | ✅ pwa-node | ✅ prettier | ⚠️ Preliminary — untested |
| TypeScript | ✅ ts_ls + eslint | ✅ pwa-node | ✅ prettier | ⚠️ Preliminary — untested |
| React (JSX/TSX) | ✅ ts_ls + eslint | ✅ pwa-node | ✅ prettier | ⚠️ Preliminary — untested |
| Java | ✅ jdtls | ✅ java-debug | ✅ google-java-format | ⚠️ Preliminary — untested |
| Rust | ✅ rust_analyzer | — | — | ⚠️ Preliminary — untested |
| HTML | ✅ html | — | ✅ prettier | ⚠️ Preliminary — untested |
| CSS | ✅ cssls | — | ✅ prettier | ⚠️ Preliminary — untested |
| JSON | ✅ jsonls + schemas | — | ✅ prettier | ⚠️ Preliminary — untested |
| YAML | ✅ yamlls + schemas | — | ✅ prettier | ⚠️ Preliminary — untested |
| TOML | ✅ taplo | — | — | ⚠️ Preliminary — untested |

> ⚠️ **Preliminary languages** — LSP servers, DAP adapters, and formatters are
> configured and auto-installed via Mason, but these have not been exercised in
> real projects. They may require additional configuration (e.g. a `tsconfig.json`
> for TypeScript, a `pom.xml` / `build.gradle` for Java, Cargo.toml for Rust).
> Bug reports and fixes are welcome.

## Requirements

- **Neovim ≥ 0.11** — uses `vim.pack`, `vim.lsp.config`, and `vim.lsp.enable`
- **[Nerd Font](https://www.nerdfonts.com/)** — icons throughout the UI (Mononoki Nerd Font 11pt recommended)
- **`git`** — version control
- **`make`** — for compiling the Telescope fzf native sorter (optional but recommended)
- **`ripgrep`** — for Telescope live grep (`rg`)

**Fortran development:**
- **`fortls`** — `pip install fortls` (Arch: `pacman -S fortls`)
- **`gdb`** — GNU debugger: install via system package manager
- **`cmake`** — for CMake integration
- **`gfortran`** — for linting

**Intel Fortran compiler (optional — required for SWAT+ and other projects using `ifx`):**

The Intel oneAPI Fortran compiler (`ifx`) is needed if your CMake presets
target it. `gfortran` is used for LSP linting regardless of which compiler
you build with.

1. Download the Intel oneAPI HPC Toolkit from:
   https://www.intel.com/content/www/us/en/developer/tools/oneapi/fortran-compiler-download.html

2. Install it to `~/intel/oneapi` (the default location):
   ```bash
   # Follow the Intel installer prompts, accepting ~/intel/oneapi as the install path
   ```

3. Before starting Neovim on a project that uses `ifx`, source the Intel
   environment setup script to add the compiler to your `PATH` and set the
   required `LD_LIBRARY_PATH`:
   ```bash
   source ~/intel/oneapi/setvars.sh
   ```

4. Then open Neovim from the project root:
   ```bash
   cd ~/myproject && nvim
   ```

   The `setvars.sh` step must be repeated each time you open a new terminal
   session. To avoid doing this manually, add it to your shell's startup file
   or create a shell alias:
   ```bash
   # Add to ~/.bashrc or ~/.zshrc (sources Intel env only if installed)
   [ -f ~/intel/oneapi/setvars.sh ] && source ~/intel/oneapi/setvars.sh

   # Or create an alias to source + open nvim in one step
   alias nvim-intel='source ~/intel/oneapi/setvars.sh && nvim'
   ```

**Jupyter notebooks (optional — required for `.ipynb` double-click in neo-tree):**
- **`jupyter-lab`** — `pip install jupyterlab` or `conda install -c conda-forge jupyterlab`

Mason auto-installs all LSP servers, formatters, linters, and DAP adapters on first launch. No manual `:MasonInstall` commands are needed.

## Installation

```bash
# Back up any existing config
mv ~/.config/nvim ~/.config/nvim.bak

# Clone this repository
git clone <your-repo-url> ~/.config/nvim

# Launch Neovim — plugins download automatically on first start
nvim
```

On first launch Neovim downloads all plugins via `vim.pack`. Mason then
auto-installs all LSP servers, formatters, linters, and DAP adapters in the
background — watch the fidget spinner in the bottom-right corner. Treesitter
parsers install automatically when you first open a file of each language.

If your terminal does not have a Nerd Font, set `vim.g.have_nerd_font = false`
in `init.lua`.

## Project-local configuration

Each project has a `.nvim.lua` file in its root that sets project-specific
paths and loads the appropriate shared language config. This means the plugin
files contain no hardcoded paths and work for any project of that language.

### Setting up a project

**Step 1 — copy a template from `doc/`:**
```bash
# Fortran / CMake project
cp ~/.config/nvim/doc/swatplus.nvim.lua.template ~/myproject/.nvim.lua

# Python project
cp ~/.config/nvim/doc/python-project.nvim.lua.template ~/myproject/.nvim.lua
```

**Step 2 — edit the template** to set `vim.g.project_name` and any paths.

**Step 3 — trust the file** (required once per project):
```bash
nvim ~/myproject/.nvim.lua
# inside Neovim:
:trust
:q
```

**Step 4 — open the project:**
```bash
cd ~/myproject && nvim
```

**Step 5 — verify:**
```
:lua print(vim.g.project_name)
```

### Path variables set in `.nvim.lua`

| Variable | Description |
|----------|-------------|
| `vim.g.project_name` | Display name shown in notifications |
| `vim.g.project_repo_root` | Absolute project root path |
| `vim.g.project_src_dir` | Source files directory (Fortran) |
| `vim.g.project_work_root` | Workdata / model run directory (Fortran) |
| `vim.g.project_build_root` | CMake build output directory |
| `vim.g.project_venv` | Virtualenv path (Python, optional) |
| `vim.g.project_python_bin` | Explicit Python binary (Python, optional) |

## Configuration structure

```
~/.config/nvim/
├── init.lua                    — entry point; auto-loads lua/plugins/
├── doc/
│   ├── README.md               — this file
│   ├── keymaps.md              — full keymap reference with plugin sources
│   ├── swatplus.nvim.lua.template        — Fortran/CMake project template
│   └── python-project.nvim.lua.template  — Python project template
└── lua/
    ├── core/
    │   ├── options.lua         — editor settings
    │   ├── keymaps.lua         — global keymaps
    │   ├── autocmds.lua        — global autocommands
    │   └── utils.lua           — shared helpers (find_editor_win)
    ├── plugins/                — one file per plugin; all auto-loaded
    │   ├── ui.lua              — catppuccin, which-key, mini, todo-comments
    │   ├── telescope.lua       — fuzzy finder
    │   ├── lsp.lua             — mason, lspconfig, fidget
    │   ├── completion.lua      — blink.cmp + luasnip    [lazy: InsertEnter]
    │   ├── formatting.lua      — conform.nvim            [lazy: <leader>f]
    │   ├── treesitter.lua      — syntax highlighting     [lazy: FileType]
    │   ├── git.lua             — gitsigns + lazygit
    │   ├── neo-tree.lua        — file explorer
    │   ├── toggleterm.lua      — persistent terminal
    │   ├── dap.lua             — DAP core, dapui setup + listeners, all <leader>d* keymaps
    │   ├── markdown.lua        — render-markdown.nvim
    │   ├── scrollview.lua      — horizontal scrollbar (custom floating bar)
    │   ├── surround.lua        — nvim-surround (ys/cs/ds) [lazy: BufReadPost]
    │   ├── lint.lua            — nvim-lint + shellcheck   [lazy: FileType sh/bash]
    │   ├── cmake-tools.lua     — CMake integration        [lazy: DirChanged]
    │   ├── make-tools.lua      — Make integration         [lazy: DirChanged]
    │   ├── c-tools.lua         — C/C++ DAP (GDB)          [lazy: FileType c/cpp]
    │   ├── web-tools.lua       — JS/TS/React DAP          [lazy: FileType js/ts/jsx/tsx]
    │   ├── java-tools.lua      — Java LSP + DAP (jdtls)   [lazy: FileType java]
    │   ├── fortran-tools.lua   — Fortran LSP + DAP        [lazy: FileType fortran]
    │   └── python.lua          — Python LSP + DAP         [lazy: FileType python]
    └── projects/               — shared language configs
        ├── fortran.lua         — sourced by Fortran project .nvim.lua files
        └── python.lua          — sourced by Python project .nvim.lua files
```

## Keymaps

Leader key: `<Space>`

### General

| Key | Action |
|-----|--------|
| `<Esc>` | Clear search highlights |
| `<C-s>` | Save file |
| `<C-h/j/k/l>` | Move between splits |
| `<leader>q` | Open diagnostics in location list |
| `gF` | Open file:line under cursor in editor window (from compiler errors) |
| `<C-g>f` | Same as gF but usable directly in terminal insert mode |
| `<Esc><Esc>` | Exit terminal insert mode |

### Horizontal scrolling

Requires `nowrap` mode (enabled globally). A floating `▁` bar appears at the
bottom of buffer windows when content is wider than the window.

| Key | Action |
|-----|--------|
| `<A-h>` | Scroll left ~1 word (hold to repeat) |
| `<A-l>` | Scroll right ~1 word (hold to repeat) |
| `zl` | Scroll right ~1 word |
| `zh` | Scroll left ~1 word |
| `ze` | Scroll cursor to right edge |
| `zs` | Scroll cursor to left edge |

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
| `<C-\>` | Toggle terminal (normal and terminal mode) |
| `<Esc><Esc>` | Exit terminal insert mode |

### Search (`<leader>s`)

| Key | Action |
|-----|--------|
| `<leader>sf` | Find files (all, including hidden/gitignored) |
| `<leader>sg` | Live grep |
| `<leader>sw` | Grep word under cursor |
| `<leader>s/` | Grep in open buffers |
| `<leader>sh` | Search help tags |
| `<leader>sk` | Search keymaps |
| `<leader>ss` | Search Telescope pickers |
| `<leader>sd` | Search diagnostics |
| `<leader>sr` | Resume last picker |
| `<leader>sc` | Search commands |
| `<leader>sn` | Search Neovim config files |
| `<leader>/` | Fuzzy search current buffer |
| `<leader>rf` | Recent files |

### File tree (neo-tree)

| Key | Action |
|-----|--------|
| `\` | Reveal current file in neo-tree |
| `<leader>\` | Show and focus buffer list in neo-tree |
| `<leader>jq` | Stop all running JupyterLab servers |

Inside neo-tree:

| Key | Action |
|-----|--------|
| `← ..` | Click to navigate up (visual entry always shown at top of tree) |
| `<CR>` / `o` | Open file or expand directory in Neovim; on `← ..` navigates up |
| `<2-LeftMouse>` | Open file — `.ipynb` opens in JupyterLab, `.html` opens in browser, all others open in Neovim |
| `s` / `v` | Open in horizontal / vertical split |
| `<BS>` | Navigate up one directory |
| `t` | Open bottom terminal at directory under cursor (reuses toggleterm #1) |
| `X` | Execute selected file if it has the executable bit set (reuses toggleterm #1) |
| `.` | Set as tree root |
| `a` / `d` / `r` | Add / delete / rename |
| `c` / `m` | Copy / move |
| `y` / `x` / `p` | Copy / cut / paste |
| `H` | Toggle hidden files |
| `R` | Refresh |
| `/` | Telescope find files scoped to directory under cursor |
| `g/` | Telescope live grep scoped to directory under cursor |
| `?` | Show help |

### Python — run file

| Key | Action |
|-----|--------|
| `<leader>pr` | Run current file in bottom terminal (reuses toggleterm #1) |

Activates after the first Python file is opened. Uses the same Python binary resolution order as the LSP: project venv → `$VIRTUAL_ENV` → `.venv` in project root → system `python3`.

### Formatting

| Key | Action |
|-----|--------|
| `<leader>f` | Format buffer or selection |

Formatters: Lua → stylua, Python → ruff, C/C++ → clang-format, Java → google-java-format, Shell → shfmt, JS/TS/JSX/TSX/HTML/CSS/JSON/YAML/Markdown → prettier.

### Surround (nvim-surround) — all buffers

| Key | Mode | Action |
|-----|------|--------|
| `ys{motion}{char}` | n | Add surrounding (e.g. `ysiw"` wraps word in `""`) |
| `cs{old}{new}` | n | Change surrounding (e.g. `cs"'` changes `"` to `'`) |
| `ds{char}` | n | Delete surrounding (e.g. `ds"` removes quotes) |
| `S{char}` | v | Surround selection |

### Markdown (`<leader>m`) — markdown buffers only

| Key | Action |
|-----|--------|
| `<leader>mr` | Toggle rendering on/off |
| `<leader>me` | Expand all sections |
| `<leader>mc` | Collapse all sections |

### CMake (`<leader>c`) — activates in CMake projects (`CMakeLists.txt` found)

| Key | Action |
|-----|--------|
| `<leader>cp` | Select preset + auto-run Generate |
| `<leader>cg` | CMake Generate (configure) |
| `<leader>cb` | Build using all CPU cores (detected via `nproc`) |
| `<leader>cB` | Build single-threaded (`-j 1`) — cleaner error output |
| `<leader>cx` | Clean active preset |
| `<leader>cd` | Delete build directory (prompts confirmation) |
| `<leader>cr` | Run executable — pick exe + workdata, cleans output files first |

### Make (`<leader>c`) — activates in Makefile projects (Makefile found, no CMakeLists.txt)

Uses the same `<leader>c*` keys as CMake so muscle memory transfers. Mutually exclusive with cmake-tools.

| Key | Action |
|-----|--------|
| `<leader>cb` | Build (pick debug/release, all CPU cores via `nproc`) |
| `<leader>cB` | Build single-threaded (`-j 1`) — pick debug/release |
| `<leader>cx` | Clean (pick debug/release/both) |
| `<leader>cr` | Run executable (pick debug/release, then workdata directory) |

### Debug / DAP (`<leader>d`) — `<leader>ds` activates on first Fortran, Python, C/C++, Java, or JS/TS file; all other keys available from startup

| Key | Alt | Action |
|-----|-----|--------|
| `<leader>ds` | `<F5>` | Start / continue (Fortran: exe/workdata picker; Python/Java/JS/TS: config picker; C/C++: executable prompt) |
| `<leader>dq` | `<F10>` | Terminate session |
| `<leader>dr` | | Restart session |
| `<leader>dn` | `<F2>` | Step over |
| `<leader>di` | `<F1>` | Step into |
| `<leader>do` | `<F3>` | Step out |
| `<leader>dc` | `<F6>` | Run to cursor |
| `<leader>db` | `<F4>` | Toggle breakpoint |
| `<leader>dB` | `<F8>` | Conditional breakpoint |
| `<leader>dL` | | Log point |
| `<leader>dx` | | Clear all breakpoints |
| `<leader>dw` | | Add word under cursor to watches |
| `<leader>dU` | `<F7>` | Toggle DAP UI |
| `<leader>dC` | | Open console in floating window |
| `<leader>de` | | Eval expression / selection — cursor enters float; `q` or jump away to close |
| `<leader>dh` | | Toggle hover widget for variable under cursor (`<Esc>` or `<leader>dh` again to close) |
| `<leader>dR` | | Open REPL |
| `<leader>dF` | | Show F-key reference popup |

Press `K` over any variable during a debug session to inspect its value; cursor enters the float so you can scroll. Press `q` or jump to another window to close it. Variable values also appear as virtual text inline in the source while stepping.

Java-only keymaps (buffer-local, active after opening a `.java` file): `<leader>di` organize imports, `<leader>dv` extract variable, `<leader>dm` extract method.

### Git operations (`<leader>g`)

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

### Git hunks (`<leader>h`) — gitsigns

| Key | Mode | Action |
|-----|------|--------|
| `]c` / `[c` | n | Next / previous hunk |
| `<leader>hs` | n/v | Stage hunk |
| `<leader>hr` | n/v | Reset hunk |
| `<leader>hS` | n | Stage buffer |
| `<leader>hR` | n | Reset buffer |
| `<leader>hp` | n | Preview hunk |
| `<leader>hi` | n | Preview hunk inline |
| `<leader>hb` | n | Blame line |
| `<leader>hd` | n | Diff against index |
| `<leader>hD` | n | Diff against last commit |
| `<leader>hq` | n | Quickfix hunks (this file) |
| `<leader>hQ` | n | Quickfix hunks (all files) |
| `ih` | o/x | Select inside hunk (text object) |

### LSP — all languages

| Key | Mode | Action |
|-----|------|--------|
| `grn` | n | Rename symbol |
| `gra` | n/x | Code action |
| `grD` | n | Go to declaration |
| `grr` | n | References (Telescope) |
| `gri` | n | Implementations (Telescope) |
| `grd` | n | Definition (Telescope) |
| `gO` | n | Document symbols |
| `gW` | n | Workspace symbols |
| `grt` | n | Type definition |
| `K` | n | Hover docs; during debug session evaluates variable — cursor enters float, `q` or jump away to close |
| `<leader>th` | n | Toggle inlay hints |
| `[d` / `]d` | n | Previous / next diagnostic |
| `<leader>e` | n | Show diagnostic float |
| `<leader>rn` | n | Rename symbol |

### Toggles (`<leader>t`)

| Key | Action |
|-----|--------|
| `<leader>tb` | Toggle git blame line |
| `<leader>tw` | Toggle git word diff |
| `<leader>th` | Toggle LSP inlay hints |
| `<leader>ts` | Toggle spell check |
