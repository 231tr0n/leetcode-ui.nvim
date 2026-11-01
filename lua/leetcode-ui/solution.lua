--- *leetcode-ui-solution* Code editor buffer of a question view
---
---@tag LeetCodeSolution
---

-- |leetcode-ui-solution| Code editor buffer of a question view.
-- Owns the editable code buffer: initializes from the starter snippet, loads
-- and saves drafts in |leetcode-ui-storage|, switches languages, and maps the
-- question keys onto it.

-- Module design:
local LeetCodeSolution = {}

local config = require('leetcode-ui.config')
local storage = require('leetcode-ui.storage')
-- Helper data =======================================================================================================

-- Helper functionality =============================================================================================

LeetCodeSolution.filetype = function(lang_slug)
  local info = config.get_lang(lang_slug)
  if info ~= nil and info.ft ~= nil then return info.ft end
  return lang_slug
end

LeetCodeSolution.snippet = function(view)
  local snippets = view.detail.snippets or {}
  local entry = snippets[view.lang]
  if entry ~= nil and entry.code ~= nil then return entry.code end
  return ''
end

LeetCodeSolution.languages = function(view)
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

LeetCodeSolution.open = function(view, _opts)
  -- The code buffer is already displayed in the question window; only apply
  -- buffer options and draft persistence here.
  vim.api.nvim_set_option_value('buflisted', true, { buf = view.code_bufnr })
  vim.api.nvim_set_option_value('modifiable', true, { buf = view.code_bufnr })

  -- Draft persistence on churn: BufLeave, and manual `:w`.
  if vim.b[view.code_bufnr].lc_draft_enabled ~= true then
    vim.b[view.code_bufnr].lc_draft_enabled = true
    vim.api.nvim_create_autocmd({ 'BufLeave', 'BufWritePre' }, {
      buffer = view.code_bufnr,
      callback = function() LeetCodeSolution.save_draft(view) end,
    })
  end
end

LeetCodeSolution.save_draft = function(view)
  if view == nil or view.code_bufnr == nil then return end
  if not vim.api.nvim_buf_is_valid(view.code_bufnr) then return end
  local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
  storage.write_draft(view.slug, view.lang, table.concat(lines, '\n'))
end

LeetCodeSolution.code = function(view)
  local lines = vim.api.nvim_buf_get_lines(view.code_bufnr, 0, -1, false)
  return table.concat(lines, '\n')
end

---Format the typed code using an available LSP/formatter.
---
---@param view table Question view.
LeetCodeSolution.format = function(view)
  if view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then return end
  local ok = pcall(vim.lsp.buf.format, { bufnr = view.code_bufnr, async = false })
  if not ok then vim.notify('(leetcode-ui) No formatter available for this buffer', vim.log.levels.WARN) end
  LeetCodeSolution.save_draft(view)
end

---Restore the starter snippet, discarding typed changes (draft too).
---
---@param view table Question view.
LeetCodeSolution.reset = function(view)
  local snippet = LeetCodeSolution.snippet(view)
  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, vim.split(snippet, '\n'))
  storage.write_draft(view.slug, view.lang, nil)
end

LeetCodeSolution.switch_language = function(view, lang_slug)
  if lang_slug == view.lang or (view.detail.snippets or {})[lang_slug] == nil then return end

  local current = LeetCodeSolution.code(view)
  storage.write_draft(view.slug, view.lang, current ~= LeetCodeSolution.snippet(view) and current or nil)

  view.lang = lang_slug
  local saved_draft = storage.read_draft(view.slug, view.lang)
  local content = saved_draft ~= nil and saved_draft or LeetCodeSolution.snippet(view)

  vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, vim.split(content, '\n'))
  vim.api.nvim_set_option_value('filetype', LeetCodeSolution.filetype(lang_slug), { buf = view.code_bufnr })
  vim.api.nvim_buf_set_name(view.code_bufnr, ('leetcode-ui://%s.%s'):format(view.slug, lang_slug))
end

return LeetCodeSolution
