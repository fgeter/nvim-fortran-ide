# Native Neovim Keymap Reference

Built-in Neovim keymaps that are worth knowing but are **not** defined anywhere
in this config (no mapping in `lua/core/keymaps.lua` or `lua/plugins/`). These
work out of the box. See `keymaps.md` for the custom mapping reference.

---

## Buffers

| Key | Action | Notes |
|-----|--------|-------|
| `<C-^>` (or `<C-6>`) | Switch to the alternate buffer (the previously displayed buffer in the current window) | Toggles back and forth between two buffers. Equivalent to `:b#`. Complements `<leader>bn`/`<leader>bp` (sequential) in `keymaps.md`. |

---

## Jumplist & changelist

| Key | Action | Notes |
|-----|--------|-------|
| `<C-o>` | Jump back to the older cursor position in the jumplist | Works across files, not just within a buffer. Populated by searches, `gg`/`G`, `%`, marks, `gF`, etc. |
| `<C-i>` | Jump forward in the jumplist | The redo counterpart to `<C-o>`. Not remapped here — see the `<tab>` caveat noted in `core/keymaps.lua`. |
| `g;` | Jump to the previous position in the changelist (older edit) | Changelist only tracks edits, unlike the jumplist. |
| `g,` | Jump to the next position in the changelist (newer edit) | |
| `` `. `` | Jump to the position of the last edit in the current buffer | |
| `` `` `` | Jump back to the position before the last jump | Toggles like `<C-^>` but for cursor position instead of buffer. |

---

## Quickfix & location list navigation

| Key | Action | Notes |
|-----|--------|-------|
| `]q` / `[q` | Next / previous quickfix entry | Quickfix list is global (one per Neovim instance). |
| `]l` / `[l` | Next / previous location list entry | Location list is per-window; populated by `<leader>q` (`vim.diagnostic.setloclist`) in `keymaps.md`. |

---

## Shifted function keys (F13-F24)

> Legacy vt220 terminal convention, inherited by xterm and (in its default,
> non-enhanced keyboard mode) Kitty: `Shift+F1`-`Shift+F12` do **not** arrive
> as a modified `<S-F1>`-`<S-F12>`, they arrive as the distinct keycodes
> `<F13>`-`<F24>` (i.e. `Shift+Fn` = `F(n+12)`). `Ctrl+F1`-`Ctrl+F12` and
> `Alt+F1`-`Alt+F12` are similarly remapped by some terminals/terminfo
> entries, but less consistently than the shift case.

| Pressed | Arrives in Neovim as |
|---------|----------------------|
| `Shift+F1` | `<F13>` |
| `Shift+F2` | `<F14>` |
| `Shift+F3` | `<F15>` |
| `Shift+F4` | `<F16>` |
| `Shift+F5` | `<F17>` |
| `Shift+F6` | `<F18>` |
| `Shift+F7` | `<F19>` |
| `Shift+F8` | `<F20>` |
| `Shift+F9` | `<F21>` |
| `Shift+F10` | `<F22>` |
| `Shift+F11` | `<F23>` |
| `Shift+F12` | `<F24>` |

**To confirm what a given terminal actually sends** before wiring up a
mapping, run this in Neovim and press the key combo:
```lua
vim.on_key(function(k) vim.schedule(function() print(vim.fn.keytrans(k)) end) end)
```
Then check `:messages`. This is how `<leader>dx`'s `<F16>` mapping in
`plugins/dap.lua` was discovered — a `<S-F4>` mapping silently never fired
because Kitty was sending `<F16>`, not a modified `<F4>`.

---

## Clipboard (yank / paste)

> `vim.o.clipboard = 'unnamedplus'` is set in `core/options.lua`, which aliases
> the unnamed register (`""`) to the system clipboard register (`"+`). This
> means plain `y`, `d`, and `p` already read/write the system clipboard —
> explicit `"+` is not required day-to-day.

| Key | Action | Notes |
|-----|--------|-------|
| `y` (visual selection) | Copy selection to the system clipboard | Because of `unnamedplus`, no `"+` prefix needed. |
| `yy` / `dd` | Copy / cut current line to the system clipboard | Same reason. |
| `p` / `P` | Paste system clipboard contents after / before cursor | Same reason. |
| `"+y` / `"+p` | Explicit yank/paste to the `+` register (system clipboard) | Same effect as plain `y`/`p` today; useful for clarity or if `unnamedplus` is ever disabled for a buffer. |
| `"*y` / `"*p` | Yank/paste to the `*` register (X11/Wayland primary selection, i.e. the middle-click buffer) | **Not** covered by `unnamedplus` — always requires the explicit `"*` prefix. Distinct buffer from `+`. |

**Terminal note:** in Kitty, clipboard access goes through OSC 52 (see the
`if vim.env.KITTY_WINDOW_ID` block in `core/options.lua`), which works over
SSH without `xclip`/`wl-clipboard` but requires the terminal to allow OSC 52
paste. Other terminals fall back to Neovim's auto-detected clipboard provider
(`wl-clipboard` on Wayland, `xclip`/`xsel` on X11).
