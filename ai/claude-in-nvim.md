# nvim-ide — driving the Neovim IDE you are running in

You are running in a terminal split inside the user's Neovim (config:
~/.config/nvim). Through the IDE connection you already see the file and
selection the user is on, the open files and diagnostics, and your file
edits are shown to the user as diffs to accept or reject.

`nvim-ide` (on PATH; also ~/.config/nvim/bin/nvim-ide) talks to this
Neovim over its RPC socket ($NVIM):

| command | what it does |
|---|---|
| `nvim-ide state` | JSON: cwd, the editor window's file, filetype, cursor, modified; listed buffers; terminal buffers |
| `nvim-ide keymaps [filter]` | normal-mode keymaps with descriptions, `lhs<TAB>desc`, optionally filtered (e.g. `build`, `<leader>c`) |
| `nvim-ide run '<keys>'` | types keys in the editor window as the user would, mappings included: `'<leader>cb'`, `'gg'`, `'<F5>'` |
| `nvim-ide cmd '<ex command>'` | runs an Ex command in the editor window, prints its output: `'w'`, `'CMakeBuild'`, `'ls'` |
| `nvim-ide lua '<code>'` | runs Lua in Neovim, prints the result: `'return vim.fn.expand("%:p")'` |
| `nvim-ide term [buf] [n]` | last n (60) lines of a terminal buffer; default: the newest non-Claude one (the build / run terminal) |
| `nvim-ide messages` | `:messages` |
| `nvim-ide open <file> [line]` | opens a file in the editor window |

The menu bar mirrors the `<leader>` keymaps: Build = `<leader>c…`
(build, configure, run, static build), Run = `<leader>cr` / `<leader>pr`,
Debug = `<leader>d…`, Git = `<leader>g…`, Find = `<leader>s…`, Code =
`<leader>C…`, AI = `<leader>i…`. `nvim-ide keymaps` is the live list;
~/.config/nvim/doc/keymaps.md documents them.

Notes:

- `run` only queues the keys and returns at once. Builds and runs go to
  a terminal: wait, then read it with `nvim-ide term`.
- Many keymaps open a picker or prompt for the user. Running one leaves
  it waiting for the user; say so instead of trying to answer it.
- Ask the user before running anything with side effects they did not
  ask for (git push/commit, deleting build folders, discarding changes,
  closing buffers with unsaved edits).
- Prefer the IDE's own build/run/debug keymaps when the user asks you to
  build, run or debug "in the IDE"; you can still run commands yourself
  in your own shell.
- Focus moves to the editor window when you run keys there.
