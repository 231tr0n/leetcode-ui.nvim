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
local net = require('leetcode-ui.net')
local auth = require('leetcode-ui.auth')
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

  local index_of = function(list, value)
    if list == nil then return -1 end
    for i, item in ipairs(list) do
      if item == value then return i end
    end
    return -1
  end

  for _, entry in ipairs(vim.tbl_keys(view.detail.snippets or {})) do
    if preferred == nil or vim.tbl_contains(preferred, entry) then table.insert(out, entry) end
  end

  -- Preferred first, active language pinned at the top.
  table.sort(out, function(a, b)
    local pa = preferred ~= nil and index_of(preferred, a) or 999
    local pb = preferred ~= nil and index_of(preferred, b) or 999
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
  if view == nil or view.busy then return end
  if view.code_bufnr == nil or not vim.api.nvim_buf_is_valid(view.code_bufnr) then return end
  view.busy = true

  local code = LeetCodeSolution.code(view)
  local formatted = nil

  local lsp_names = {
    python3 = { 'py3' },
    python = { 'py3' },
    cpp = { 'cpp' },
    c = { 'c' },
    java = { 'java' },
    golang = { 'go' },
    go = { 'go' },
    swift = { 'swift' },
  }
  local candidates = lsp_names[view.lang] or { view.lang }

  -- Try LeetCode's own LSP formatting endpoint first.
  for _, name in ipairs(candidates) do
    local res, err = net.request({
      url = ('https://lsp-%s.leetcode.com/format'):format(name),
      method = 'POST',
      headers = auth.headers({ 'Content-Type: application/json' }),
      body = vim.json.encode({ code = code, tabSize = 4, insertSpaces = true }),
      cookie_file = auth.cookie_file(),
      timeout = 15,
    })
    if
      err == nil
      and res ~= nil
      and res.status == 200
      and type(res.body) == 'string'
      and not res.body:match('^%s*<')
    then
      local ok, decoded = pcall(vim.json.decode, res.body)
      if ok and type(decoded) == 'table' then
        formatted = decoded.code or decoded.formattedCode or decoded.formatted_code or decoded.data
      end
      if formatted == nil and #res.body > 0 then formatted = res.body end
      if type(formatted) == 'string' and formatted ~= '' then break end
    end
  end

  -- Fall back to a local CLI formatter when available.
  local cli_formatters = {
    javascript = { 'prettier', '--stdin-filepath', 'x.js' },
    typescript = { 'prettier', '--stdin-filepath', 'x.ts' },
    python3 = { 'black', '-' },
    python = { 'black', '-' },
    cpp = { 'clang-format' },
    c = { 'clang-format' },
    golang = { 'gofmt' },
    go = { 'gofmt' },
    rust = { 'rustfmt', '--emit', 'stdout' },
    java = { 'google-java-format', '-' },
  }
  local cmd = cli_formatters[view.lang]
  if cmd ~= nil and vim.fn.executable(cmd[1]) == 1 then
    local out = vim.system(cmd, { text = true, stdin = code }):wait()
    if out.code == 0 and type(out.stdout) == 'string' and out.stdout ~= '' then
      vim.api.nvim_buf_set_lines(view.code_bufnr, 0, -1, true, vim.split(out.stdout, '\n'))
      LeetCodeSolution.save_draft(view)
      view.busy = false
      pcall(vim.api.nvim_set_current_win, view.winid)
      return
    end
  end

  -- Fall back to an attached LSP formatter.
  local ok = pcall(vim.lsp.buf.format, { bufnr = view.code_bufnr, async = false })
  if not ok then vim.notify('(leetcode-ui) No formatter available for this buffer', vim.log.levels.WARN) end
  view.busy = false
  LeetCodeSolution.save_draft(view)
  pcall(vim.api.nvim_set_current_win, view.winid)
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
