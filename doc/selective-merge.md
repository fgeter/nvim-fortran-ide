# Selective Branch Merge Workflow

How to merge a branch into `main` while excluding specific unwanted changes,
without risking those changes silently reappearing the next time someone
merges the same branch. Built for (but not specific to) the
`fg_swatplus_main_data_update` → `main` merge in `swatplus_fg_fork`.

---

## Why not just merge file-by-file with `git checkout`?

Hand-copying content from another branch (`git checkout <branch> -- file`,
or manually editing files without an actual merge commit) does **not**
protect you later. Git has no record that those changes were considered and
rejected — the branch never becomes an ancestor of `main`. A future
`git merge <branch>` will still do a full three-way diff against the
original common ancestor, and for every region you skipped, `main` looks
unchanged relative to that ancestor while the branch differs — so Git
reapplies the branch's version **silently, with no conflict**, undoing your
exclusion.

The fix: merge for real (a genuine two-parent merge commit), then trim
what you don't want in follow-up commits. Once the branch tip is an
ancestor of `main`, a later `git merge` of the same tip is a no-op
("Already up to date"). If new commits are added to the branch later, a
future merge will correctly respect your trims (three-way merge sees
"you changed it, they didn't" for anything you touched) and only conflict
if the branch changes the same lines again — which is the right outcome.

---

## Workflow

1. **Create a disposable staging branch off `main`.**
   ```
   git checkout -b staging-merge
   ```
   If anything goes wrong below, delete this branch and start over —
   `main` is never touched until the final step.

2. **Merge the whole branch, favoring its changes on conflicts.**
   ```
   git merge -X theirs fg_swatplus_main_data_update
   ```
   `-X theirs` only affects hunks that *actually conflict* (both sides
   changed the same lines) — it auto-resolves those in favor of the
   incoming branch instead of stopping for manual markers. It does **not**
   affect rename/rename, rename/delete, or modify/delete conflicts — Git
   still flags those for a manual decision since there's no content to
   pick from cleanly. Resolve each remaining one in favor of the incoming
   branch:
   - **Theirs deleted the file, you modified it (`modify/delete`)** — take
     the deletion: `git rm <path>`
   - **Rename/rename** (both sides renamed the same file, to different
     destinations) — keep the incoming branch's destination, drop yours:
     `git rm <your-destination>` then `git add <their-destination>`
   - A rename/rename conflict also leaves the *original* pre-rename path
     flagged as `both deleted` even though it's already gone from the
     working tree — clear it the same way: `git rm <original-path>`

   Check `git status` until "Unmerged paths" disappears, then:
   ```
   git commit
   ```
   (accept the default merge commit message). This is the real merge
   commit — the one that makes the branch an ancestor of `staging-merge`.

3. **Get the full list of files the merge touched**, before starting to
   review anything: press `<leader>gq` in Neovim, accept the defaults
   (`HEAD^1` for base, `HEAD` for target) — this is the pre-merge vs.
   post-merge diff. It loads every changed file into the quickfix list
   and opens it.

4. **Walk the list, file by file**, trimming what you don't want:
   - `:cnext` / `:cprev` to move through the quickfix list
   - `<leader>gf` on a file → pick **"Type a ref…"** → `HEAD^1` — opens a
     side-by-side diff (your file on the left, the pre-merge version on
     the right, read-only)
   - `]c` / `[c` to jump between differing hunks
   - `do` / `dp` to pull a whole hunk from one side to the other (see
     [do/dp direction](#dodp-direction) below)
   - For a change smaller than a whole hunk, visually select the exact
     lines on the right (pre-merge) side, yank, and paste them over the
     corresponding lines on the left
   - `<leader>gn` — "I'm done with this file": saves it, closes the
     comparison pane, cleans up its buffer, advances the quickfix list,
     and **automatically reopens the diff against `HEAD^1` on the next
     file** — no re-prompting per file. It also auto-detects and skips
     binary files (e.g. `.png`) with a notification, since there are no
     text hunks to selectively pull from them; handle those manually
     outside this workflow if their content needs a decision.

5. **Commit the trims** once you're through the list:
   ```
   git commit -am "Trim unwanted content from merge"
   ```
   One commit for everything, or one per file — doesn't matter, since the
   ancestor relationship was already locked in by the merge commit in
   step 2.

6. **Merge the vetted result into `main`.**
   ```
   git checkout main
   git merge staging-merge
   ```
   A real (non-squash) merge, so the ancestor chain is preserved.

---

## Aborting and starting over

If the merge in step 2 goes wrong before you've committed it:
```
git merge --abort          # or, if that doesn't fully clear it:
git reset --merge          # or, as a last resort:
git reset --hard HEAD
```
`git checkout main` will refuse with "you need to resolve your current
index first" if you try to switch branches before fully clearing the
merge state — resolve or abort first, then switch.

Once you're back on `main`:
```
git branch -D staging-merge
```
and start again from step 1. Nothing on `main` was ever at risk.

---

## do/dp direction

- `:diffput` (`dp`) copies the hunk under the cursor **from the window
  you're in → into the other window**.
- `:diffget` (`do`) copies the hunk **from the other window → into the
  window you're in**.

So to reject a change the merge brought in: put the cursor on that hunk in
the **right** (`HEAD^1`, pre-merge) window and press `dp` — it pushes the
old content into your file on the left. Equivalently, put the cursor on
the left window and press `do` — same result, whichever side is more
convenient given where your cursor already is.

Only the left window is writable; the right one is read-only scratch and
can't be accidentally edited. Don't `:wq` it — there's nothing to write.
Close it with `:q` (or just use `<leader>gn`, which handles this for you).

---

## Keymaps used

| Key | Action | Plugin |
|-----|--------|--------|
| `<leader>gf` | Diff current file against a branch, or a typed ref (e.g. `HEAD^1`) | `plugins/git.lua` |
| `<leader>gq` | Load files changed between two refs (default `HEAD^1`..`HEAD`) into the quickfix list | `plugins/git.lua` |
| `<leader>gn` | Save + close this file's diff + advance quickfix + reopen diff on the next file (skips binaries) | `plugins/git.lua` |
| `<leader>gm` | Merge a branch (used for the final `main` merge, or interactively instead of typing `git merge`) | `plugins/git.lua` |
| `<leader>gd` | Delete a branch (used to discard `staging-merge` after aborting) | `plugins/git.lua` |

See `doc/keymaps.md` for the full reference.
