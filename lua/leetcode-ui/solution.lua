-- |leetcode-ui-solution| Code editor buffer of a question view.
--------------------------------------------------------------------------------
-- Owns the editable code buffer: initializes from the starter snippet, loads
-- and saves drafts in |leetcode-ui-storage|, switches languages, and maps the
-- question keys onto it.
--------------------------------------------------------------------------------

-- Module design:
local H = {}

local config = require('leetcode-ui.config')
local storage = require('leetcode-ui.storage')
local buffer = require('leetcode-ui.buffer')

-- Helper data =======================================================================================================

---Vim filetype per language slug.
H.filetypes = {
  python3 = 'python',
  golang = 'go',
  mysql = 'sql',
  mssql = 'sql',
  oracle = 'sql',
  cpp = 'cpp',
  c = 'c',
  ruby = 'ruby',
  swift = 'swift',
  typescript = 'typescript',
  javascript = 'javascript',
  php = 'php',
  bash = 'sh',
  dart = 'dart',
  rust = 'rust',
  racket = 'racket',
  erlang = 'erlang',
  elixir = 'elixir',
}

-- Helper functionality =============================================================================================

---Vim filetype for a language slug.
---
---@param lang_slug string
---@return string
H.filetype = function(lang_slug) return H.filetypes[lang_slug] or lang_slug end

---Starter snippet for the view's language.
---
---@param view table Question view.
---@return string
H.snippet = function(view)
  local snippets = view.detail.snippets or {}
  local entry = snippets[view.lang]
  if entry ~= nil and entry.code ~= nil then return entry.code end
  return ''
end

---Available language slugs for the question, honoring `languages` filter.
---
---@param view table
---@return table Ordered slug list starting with the active one.
H.languages = function(view)
  local out = {}
  local preferred = config.config.languages

  for _, entry in ipairs(vim.tbl_keys(view.detail.snippets or {})) do
    if preferred == nil or vim.tbl_contains(preferred, entry) then table.insert(out, entry) end
  end

  -- Preferred first, active language pinned at the top.
  table.sort(out, function(a, b)
    local pa = preferred ~= nil and vim.tbl_indexof(preferred, a) or 999
    local pb = preferred ~= nil and vim.tbl_indexof(preferred, b) or 999
    local la = a == view.lang and 0 or (pa ~= -1 and pa or pa + 100)
    local lb = b == view.lang and 0 or (pb ~= -1 and pb or pb + 100)
    return la < lb or (la == lb and a < b)
  end)
  return out
end

---Create the code buffer (fresh or reusing an existing one) and open its split.
---
---@param view table Question view.
---@param win_opts table|nil { focus = boolean }
H.open = function(view, win_opts)
  view.code_winid = buffer.open_split(
    view.code_bufnr,
    vim.tbl_extend('force', {
      pos = 'right',
      width = math.max(vim.o.columns - (config.config.description_width + 2), 40),
      focus = true,
    }, win_opts or {})
  )

  -- Keep code buffer listed so `:b` works naturally with drafts.
  vim.api.nvim_set_option_value('buflisted', true, { buf = view.code_bufnr })
  vim.api.nvim_set_option_value('modifiable', true, { buf = view.code_bufnr })

  -- Draft persistence on churn: BufLeave, and manual `:w`.
  if vim.b[view.code_bufnr].lc_draft_enabled ~= true then
    vim.b[view.code_bufnr].lc_draft_enabled = true
    vim.api.nvim_create_autocmd({ 'BufLeave', 'BufWritePre' }, {
      buffer = view.code_bufnr,
      callback = function() H.save_draft(view) end,
    })
  end
end

---Save the typed code as a draft.
---
---@param view table|nil
H.save_draft = function(view)
  if view == nil or view.code_bufnr == nil then return end
  if not vim.api.nvim_buf_is_valid(view.code_bufnr) then return end
  local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
  storage.write_draft(view.slug, view.lang, table.concat(lines, '\n'))
end

---Typed code currently in the buffer.
---
---@param view table
---@return string
H.code = function(view)
  local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
  return table.concat(lines, '\n')
end

---Restore the starter snippet, discarding typed changes (draft too).
---
---@param view table Question view.
H.reset = function(view)
  local snippet = H.snippet(view)
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, vim.split(snippet, '\n'))
  storage.write_draft(view.slug, view.lang, nil)
end

---Swap the buffer's language, preserving the previous draft.
---
---@param view table Question view.
---@param lang_slug string
H.switch_language = function(view, lang_slug)
  if lang_slug == view.lang or (view.detail.snippets or {})[lang_slug] == nil then return end

  local current = H.code(view)
  storage.write_draft(view.slug, view.lang, current ~= H.snippet(view) and current or nil)

  view.lang = lang_slug
  local saved_draft = storage.read_draft(view.slug, view.lang)
  local content = saved_draft ~= nil and saved_draft or H.snippet(view)

  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, vim.split(content, '\n'))
  vim.api.nvim_set_option_value('filetype', H.filetype(lang_slug), { buf = view.code_bufnr })
  vim.api.nvim_buf_set_name(view.code_bufnr, ('leetcode-ui://%s.%s'):format(view.slug, lang_slug))
end

return H
