-- ============================================================
-- plugins/telescope.lua — Fuzzy finder and picker UI
--
-- Telescope is used for: file search, live grep, help tags,
-- keymaps, LSP references/definitions, recent files, and as
-- the backend for vim.ui.select() (via telescope-ui-select).
--
-- LAZY: No — telescope is used immediately on startup and its
--       vim.ui.select override must be in place before any
--       plugin calls that function.
-- ============================================================

local gh = require('core.utils').gh

local telescope_plugins = {
  { src = gh 'nvim-lua/plenary.nvim',          version = vim.version.range '*' },
  { src = gh 'nvim-telescope/telescope.nvim',  version = vim.version.range '*' },
  gh 'nvim-telescope/telescope-ui-select.nvim',  -- no tagged releases
}

-- telescope-fzf-native provides a compiled C fuzzy matcher that is
-- significantly faster than the pure-Lua default. Only built when
-- `make` is available.
if vim.fn.executable('make') == 1 then
  table.insert(telescope_plugins, gh 'nvim-telescope/telescope-fzf-native.nvim')
end

vim.pack.add(telescope_plugins)

require('telescope').setup {
  defaults = require('telescope.themes').get_ivy(),
  extensions = {
    -- Use the dropdown theme for vim.ui.select() so pickers like
    -- cmake preset selection and workdata selection look clean
    ['ui-select'] = { require('telescope.themes').get_dropdown() },
  },
}

-- Load extensions. fzf is optional (requires compiled C); warn if the build
-- is missing so the user knows they are on the slower Lua matcher.
if vim.fn.executable('make') == 1 then
  local ok = pcall(require('telescope').load_extension, 'fzf')
  if not ok then
    vim.notify(
      'telescope-fzf-native: native sorter failed to load.\n' ..
      'Falling back to Lua matcher (slower on large projects).\n' ..
      'Try deleting ~/.local/share/nvim/site/pack/core/opt/telescope-fzf-native.nvim and restarting.',
      vim.log.levels.WARN)
  end
end
pcall(require('telescope').load_extension, 'ui-select')

-- ── Keymaps ──────────────────────────────────────────────────
local builtin = require('telescope.builtin')

-- Search commands
vim.keymap.set('n', '<leader>sh', builtin.help_tags,   { desc = 'Search: help tags' })
vim.keymap.set('n', '<leader>sk', builtin.keymaps,     { desc = 'Search: keymaps' })
vim.keymap.set('n', '<leader>ss', builtin.builtin,     { desc = 'Search: telescope pickers' })
vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = 'Search: diagnostics' })
vim.keymap.set('n', '<leader>sr', builtin.resume,      { desc = 'Search: resume last picker' })
vim.keymap.set('n', '<leader>sc', builtin.commands,    { desc = 'Search: commands' })

-- Find files — shows ALL files including hidden and gitignored.
-- no_ignore=true is intentional: build/ and other gitignored dirs are
-- sometimes useful to browse. Use <leader>sg (grep) to narrow results.
vim.keymap.set('n', '<leader>sf', function()
  builtin.find_files { hidden = true, no_ignore = true }
end, { desc = 'Search: files (all, including hidden/ignored)' })

-- Grep across files
vim.keymap.set({ 'n', 'v' }, '<leader>sw', builtin.grep_string, { desc = 'Search: word under cursor' })
vim.keymap.set('n', '<leader>sg', builtin.live_grep,            { desc = 'Search: live grep' })
vim.keymap.set('n', '<leader>s/', function()
  builtin.live_grep {
    grep_open_files = true,
    prompt_title    = 'Live grep in open buffers',
  }
end, { desc = 'Search: grep in open buffers' })

-- Multi-word AND search: find files containing ALL of the given words,
-- not necessarily on the same line. Implemented by intersecting
-- `rg -l` file lists (one pass per word). Words are matched literally
-- (no regex) and case-insensitively. Results open in a file picker
-- with preview.
--
-- Query syntax:  basin residue      both words, anywhere (substring)
--                "basin" residue    "basin" as a whole word only, so
--                                   basin_module does not count
--                basin !hru         has basin, does NOT contain hru
vim.keymap.set('n', '<leader>sa', function()
  vim.ui.input({ prompt = 'Files with ALL of ("w"=whole word, !w=exclude): ' }, function(input)
    if not input or input == '' then return end

    -- Parse tokens: word → substring the file must contain;
    -- "word" → whole-word match; !word / !"word" → must NOT contain.
    local includes, excludes = {}, {}
    for _, tok in ipairs(vim.split(input, '%s+', { trimempty = true })) do
      local exclude = tok:sub(1, 1) == '!'
      if exclude then tok = tok:sub(2) end
      local quoted = tok:match('^"(.*)"$')
      if (quoted or tok) ~= '' then
        table.insert(exclude and excludes or includes,
          { text = quoted or tok, word = quoted ~= nil })
      end
    end
    if #includes == 0 then return end

    -- Commands are passed as argv lists (no shell), so filenames with
    -- spaces or special characters need no escaping. rg exit code 1
    -- just means "nothing matched"; only >=2 is a real error.
    local function rg_files(list_flag, term, file_list)
      local cmd = { 'rg', list_flag, '--fixed-strings', '--ignore-case' }
      if term.word then table.insert(cmd, '--word-regexp') end
      vim.list_extend(cmd, { '--', term.text })
      if file_list then vim.list_extend(cmd, file_list) end
      local out = vim.fn.systemlist(cmd)
      return vim.v.shell_error < 2 and out or {}
    end

    local files = rg_files('--files-with-matches', includes[1])
    for i = 2, #includes do
      if #files == 0 then break end
      files = rg_files('--files-with-matches', includes[i], files)
    end
    for _, term in ipairs(excludes) do
      if #files == 0 then break end
      files = rg_files('--files-without-match', term, files)
    end
    table.sort(files)

    if #files == 0 then
      vim.notify('No files match: ' .. input, vim.log.levels.INFO)
      return
    end

    -- Highlight/jump patterns for the include terms.
    -- \c = ignore case, \V = very nomagic (literal), \< \> = word bounds
    local patterns = {}
    for _, term in ipairs(includes) do
      local lit = vim.fn.escape(term.text, '\\')
      table.insert(patterns,
        term.word and ('\\c\\V\\<' .. lit .. '\\>') or ('\\c\\V' .. lit))
    end

    local conf = require('telescope.config').values

    -- Custom previewer: same file preview as file_previewer, but with
    -- every search word highlighted (window-local matches, so they
    -- apply to whichever file the preview window shows).
    local previewer = require('telescope.previewers').new_buffer_previewer {
      title = 'Preview (matches highlighted)',
      get_buffer_by_name = function(_, entry) return entry.path or entry.value end,
      define_preview = function(self, entry)
        conf.buffer_previewer_maker(entry.path or entry.value, self.state.bufnr, {
          bufname = self.state.bufname,
          winid   = self.state.winid,
          -- Runs after the file content is loaded into the preview
          -- buffer: jump to the first line matching any search word.
          callback = function()
            local winid = self.state.winid
            if winid and vim.api.nvim_win_is_valid(winid) then
              vim.api.nvim_win_call(winid, function()
                vim.fn.cursor(1, 1)
                if vim.fn.search(table.concat(patterns, '\\|'), 'cW') > 0 then
                  vim.cmd 'normal! zz'
                end
              end)
            end
          end,
        })
        local winid = self.state.winid
        if winid and vim.api.nvim_win_is_valid(winid) then
          vim.fn.clearmatches(winid)
          for _, pattern in ipairs(patterns) do
            vim.fn.matchadd('Search', pattern, 10, -1, { window = winid })
          end
        end
      end,
    }

    require('telescope.pickers').new(require('telescope.themes').get_ivy(), {
      prompt_title = 'Files matching: ' .. input,
      finder       = require('telescope.finders').new_table {
        results    = files,
        entry_maker = require('telescope.make_entry').gen_from_file {},
      },
      sorter       = conf.file_sorter {},
      previewer    = previewer,
      attach_mappings = function(_, map)
        -- Jump between highlighted matches inside the preview window,
        -- like n/N after a / search (wraps around). <C-s>/<C-a> work
        -- while typing in the prompt; n/N work after <Esc> (the
        -- prompt's normal mode).
        local function jump(flags)
          return function(prompt_bufnr)
            local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
            local winid = picker.previewer
              and picker.previewer.state and picker.previewer.state.winid
            if winid and vim.api.nvim_win_is_valid(winid) then
              vim.api.nvim_win_call(winid, function()
                if vim.fn.search(table.concat(patterns, '\\|'), flags) > 0 then
                  vim.cmd 'normal! zz'
                end
              end)
            end
          end
        end
        map({ 'i', 'n' }, '<C-s>', jump '')   -- next match
        map({ 'i', 'n' }, '<C-a>', jump 'b')  -- previous match
        map('n', 'n', jump '')
        map('n', 'N', jump 'b')
        return true
      end,
    }):find()
  end)
end, { desc = 'Search: files containing ALL words ("w"=whole word, !w=exclude)' })

-- Recent files (replaces the separate recent-files.lua vim.ui.select picker)
vim.keymap.set('n', '<leader>rf', builtin.oldfiles, { desc = 'Recent files' })

-- Current buffer fuzzy search
vim.keymap.set('n', '<leader>/', function()
  builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
    winblend  = 10,
    previewer = false,
  })
end, { desc = 'Search: fuzzy in current buffer' })

-- Search Neovim config files
vim.keymap.set('n', '<leader>sn', function()
  builtin.find_files { cwd = vim.fn.stdpath('config') }
end, { desc = 'Search: Neovim config files' })

-- Buffer list
vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = 'Find open buffers' })

-- ── LSP pickers (attached per buffer on LspAttach) ───────────
-- These use Telescope pickers instead of the default quickfix list
-- so you get fuzzy search, preview, and consistent UI.
-- NOTE: gd/gr/gD are NOT mapped here globally — fortran-tools.lua
-- sets buffer-local versions for Fortran files only, and the
-- kickstart LSP section in lsp.lua sets grn/gra/grD globally.
vim.api.nvim_create_autocmd('LspAttach', {
  group    = vim.api.nvim_create_augroup('telescope-lsp-attach', { clear = true }),
  callback = function(ev)
    local buf = ev.buf
    vim.keymap.set('n', 'grr', builtin.lsp_references,              { buffer = buf, desc = 'LSP: references (telescope)' })
    vim.keymap.set('n', 'gri', builtin.lsp_implementations,         { buffer = buf, desc = 'LSP: implementations' })
    vim.keymap.set('n', 'grd', builtin.lsp_definitions,             { buffer = buf, desc = 'LSP: definitions' })
    vim.keymap.set('n', 'gO',  builtin.lsp_document_symbols,        { buffer = buf, desc = 'LSP: document symbols' })
    vim.keymap.set('n', 'gW',  builtin.lsp_dynamic_workspace_symbols, { buffer = buf, desc = 'LSP: workspace symbols' })
    vim.keymap.set('n', 'grt', builtin.lsp_type_definitions,        { buffer = buf, desc = 'LSP: type definition' })
  end,
})
