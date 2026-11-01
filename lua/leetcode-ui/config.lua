-- |leetcode-ui-config| Structure and helpers for the main |leetcode-ui| module.
--------------------------------------------------------------------------------
-- This file follows mini.nvim module conventions (see |mini.development|):
-- - All defaults live in the public `M.config` table.
-- - |leetcode-ui.setup()| performs three steps:
--     1. `H.setup_config()` validates user inputs before anything is applied.
--     2. `H.apply_config()` shallow-extends the public `M.config` with user
--        options. NOTE: nested tables are replaced whole (not deep-merged),
--        like in mini.nvim; supply the full nested table when overriding one.
--     3. `H.create_hl()` (re)applies plugin highlight groups.
-- - `H` is the private helper table; it doubles as the module return value (as
--   in mini.nvim) so sibling modules require it directly.
--------------------------------------------------------------------------------

local H = {}

-- Helper data =======================================================================================================

---LeetCode language metadata keyed by `langSlug` (the API language slug).
---
---@type table<string, table>
H.langs = {
  cpp = { lang = 'C++', slug = 'cpp', ext = 'cpp', ft = 'cpp', comment = '//' },
  java = { lang = 'Java', slug = 'java', ext = 'java', ft = 'java', comment = '//' },
  python3 = { lang = 'Python3', slug = 'python3', ext = 'py', ft = 'python', comment = '#' },
  python = { lang = 'Python', slug = 'python', ext = 'py', ft = 'python', comment = '#', alt = 'python3' },
  c = { lang = 'C', slug = 'c', ext = 'c', ft = 'c', comment = '//' },
  ['csharp'] = { lang = 'C#', slug = 'csharp', ext = 'cs', ft = 'cs', comment = '//' },
  javascript = { lang = 'JavaScript', slug = 'javascript', ext = 'js', ft = 'javascript', comment = '//' },
  typescript = { lang = 'TypeScript', slug = 'typescript', ext = 'ts', ft = 'typescript', comment = '//' },
  php = { lang = 'PHP', slug = 'php', ext = 'php', ft = 'php', comment = '//' },
  swift = { lang = 'Swift', slug = 'swift', ext = 'swift', ft = 'swift', comment = '//' },
  kotlin = { lang = 'Kotlin', slug = 'kotlin', ext = 'kt', ft = 'kotlin', comment = '//' },
  dart = { lang = 'Dart', slug = 'dart', ext = 'dart', ft = 'dart', comment = '//' },
  golang = { lang = 'Go', slug = 'golang', ext = 'go', ft = 'go', comment = '//' },
  ruby = { lang = 'Ruby', slug = 'ruby', ext = 'rb', ft = 'ruby', comment = '#' },
  scala = { lang = 'Scala', slug = 'scala', ext = 'scala', ft = 'scala', comment = '//' },
  rust = { lang = 'Rust', slug = 'rust', ext = 'rs', ft = 'rust', comment = '//' },
  racket = { lang = 'Racket', slug = 'racket', ext = 'rkt', ft = 'racket', comment = ';;' },
  erlang = { lang = 'Erlang', slug = 'erlang', ext = 'erl', ft = 'erlang', comment = '%%' },
  elixir = { lang = 'Elixir', slug = 'elixir', ext = 'ex', ft = 'elixir', comment = '#' },
  bash = { lang = 'Bash', slug = 'bash', ext = 'sh', ft = 'sh', comment = '#' },
}

---Plugin highlight groups (applied by `H.create_hl()`).
---
---@type table<string, table>
H.highlights = {
  LeetCodeOk = { fg = '#98c379' },
  LeetCodeErr = { fg = '#f14c4c' },
  LeetCodeWarn = { fg = '#e5c07b' },
  LeetCodeDim = { fg = '#5c6370' },
  LeetCodeTitle = { bold = true },
  LeetCodeCode = { fg = '#c678dd' },
  LeetCodeLink = { fg = '#81a2be', underline = true },
  LeetCodeItalic = { italic = true },
  LeetCodeEasy = { fg = '#00af87' },
  LeetCodeMedium = { fg = '#ffab28' },
  LeetCodeHard = { fg = '#ff4772' },
  LeetCodeHeader = { fg = '#61afef', bold = true },
}

-- Module design:
---Module config: all options with defaults.
---
--- # Setup ~
---
---   require('leetcode-ui').setup({
---     -- Strings: site domain and default language slug.
---     url = 'leetcode.com',
---     lang = 'golang',
---
---     -- Subset of language slugs offered in pickers. nil = all `H.langs`.
---     languages = nil,
---
---     -- Cookies: set here or via environment variables of the same name.
---     cookies = { LEETCODE_SESSION = nil, csrftoken = nil },
---
---     -- Runner: `local_runner` enables offline execution, `binaries` may
---     -- override tool paths (keyed by language slug), `runner_timeout` is in
---     -- seconds, `no_local` lists language slugs forced online.
---     local_runner = true,
---     binaries = {},
---     runner_timeout = 30,
---     no_local = {},
---
---     -- UI geometry, in lines/columns.
---     console_height = 10,
---     description_width = 60,
---
---     -- Picker: 'mini' (mini.pick), 'builtin' (vim.ui.select) or 'auto'.
---     picker = 'auto',
---
---     -- Problem list cache lifetime, in minutes.
---     cooldown = 60,
---
---     -- Hide premium-only problems from listings.
---     hide_premium = false,
---
---     -- Icons: status (problem list), case (console), stats (statistics).
---     icons = {
---       status = { solved = '✔', attempted = '✘', todo = '○', active = '◈' },
---       case = { passed = '✔', failed = '✘', unknown = '○', err = '✗' },
---       stats = { user = ' ', link = '→', stat = '≡', lang = '⌘' },
---     },
---
---     -- Buffer-local solution keymaps.
---     keys = { ... },
---   })
---
--- NOTE: nested options (`icons`, `keys`, ...) are replaced whole on setup, not
--- deep-merged; mirror the default structure and override single fields.
---
---@type table
local default_config = {
  url = 'leetcode.com',

  lang = 'python3',
  languages = nil,

  cookies = { LEETCODE_SESSION = nil, csrftoken = nil },

  -- Path to a Netscape-format cookie jar file (consumed by curl directly).
  -- When set, `cookies` is ignored and the jar supplies all session data.
  cookie_file = nil,

  -- Storage root for the problem list cache and solution drafts.
  -- Default: `stdpath('data')/leetcode-ui`.
  storage_path = nil,

  -- Automatic cookie import from browsers: 'auto' | 'firefox' | 'chrome' |
  -- 'brave' | 'edge' | 'chromium' | 'none'.
  browser = 'auto',

  -- Per-browser database path overrides, e.g.
  -- { firefox = '~/my-profile/cookies.sqlite' }.
  browser_paths = {},

  local_runner = true,
  binaries = {},
  runner_timeout = 30,
  no_local = {},

  console_height = 10,
  description_width = 60,

  picker = 'auto',
  cooldown = 60,
  hide_premium = false,

  icons = {
    status = { solved = '✔', attempted = '✘', todo = '○', active = '◈' },
    case = { passed = '✔', failed = '✘', unknown = '○', err = '✗' },
    stats = { user = '', link = '→', stat = '≡', lang = '⌘' },
  },

  keys = {
    run = '<CR>',
    submit = '<C-CR>',
    toggle_question = 'Z',
    toggle_console = 'X',
    toggle_information = 'I',
    reset_code = 'S',
    switch_language = 'L',
    close = 'Q',
  },
}

---Full option set used across the module.
---
---@type table
H.config = default_config

-- Helper functionality ==============================================================================================

---Validate user inputs before applying anything.
---
---@param config table User configuration to validate.
---@private
H.setup_config = function(config)
  vim.validate({
    url = { config.url, 'string' },
    lang = { config.lang, 'string' },
    languages = { config.languages, 'table', true },
    cookies = { config.cookies, 'table' },
    cookie_file = { config.cookie_file, 'string', true },
    storage_path = { config.storage_path, 'string', true },
    browser = { config.browser, 'string' },
    browser_paths = { config.browser_paths, 'table' },
    local_runner = { config.local_runner, 'boolean' },
    binaries = { config.binaries, 'table' },
    runner_timeout = { config.runner_timeout, 'number' },
    no_local = { config.no_local, 'table' },
    console_height = { config.console_height, 'number' },
    description_width = { config.description_width, 'number' },
    picker = { config.picker, 'string' },
    cooldown = { config.cooldown, 'number' },
    hide_premium = { config.hide_premium, 'boolean' },
    icons = { config.icons, 'table' },
    keys = { config.keys, 'table' },
  })

  if H.langs[config.lang] == nil then H.error(('Unknown default language `%s`.'):format(config.lang)) end

  if not vim.tbl_contains({ 'auto', 'mini', 'builtin' }, config.picker) then
    H.error(('Unknown picker `%s`. Use one of "auto", "mini", "builtin".'):format(config.picker))
  end

  if not vim.tbl_contains({ 'auto', 'firefox', 'chrome', 'brave', 'edge', 'chromium', 'none' }, config.browser) then
    H.error(
      ('Unknown browser `%s`. Use one of "auto", "firefox", "chrome", "brave", "edge", "chromium", "none".'):format(
        config.browser
      )
    )
  end

  for slug, info in pairs(config.icons.status) do
    if type(info) ~= 'string' then H.error(('`icons.status["%s"]` should be a string.'):format(slug)) end
  end
  local known_keys = {
    run = true,
    submit = true,
    toggle_question = true,
    toggle_console = true,
    toggle_information = true,
    reset_code = true,
    switch_language = true,
    close = true,
  }
  for name, value in pairs(config.keys) do
    if not known_keys[name] then H.error(('Unknown `keys.%s` option.'):format(name)) end
    if type(value) ~= 'string' then H.error(('`keys.%s` should be a string.'):format(name)) end
  end
end

---Shallow-apply user configuration (mini.nvim style).
---
---@param config table User configuration.
---@private
H.apply_config = function(config)
  H.config = vim.tbl_extend('force', H.config, config)

  -- Normalize alias slugs ('python' -> 'python3' style) once.
  if H.config.lang ~= nil and H.langs[H.config.lang] ~= nil then
    local info = H.langs[H.config.lang]
    H.config.lang = info.alt ~= nil and info.alt or info.slug
  end
end

---Apply highlight groups for the plugin.
---
---@private
H.create_hl = function()
  for name, spec in pairs(H.highlights) do
    pcall(vim.api.nvim_set_hl, 0, name, spec)
  end
end

---Error out either as |vim.notify()| or as a Lua error.
---
---@param msg string
---@param notify boolean|nil
---@return string
H.error = function(msg, notify)
  msg = ('(leetcode-ui) %s'):format(msg)
  if notify ~= nil and notify then
    vim.notify(msg, vim.log.levels.ERROR)
    return msg
  end
  error(msg, 0)
end

---Set up |leetcode-ui| configuration.
---
--- # Setup ~
---
---   require('leetcode-ui').setup({
---     lang = 'golang',
---     cookies = { LEETCODE_SESSION = 'eyJ...' },
---   })
---
--- # Default config ~
---
---   All options and their defaults are documented above |leetcode-ui.setup()|.
---
---@param opts table|nil User configuration.
H.setup = function(opts)
  opts = opts or {}

  -- Validate the effective configuration (defaults merged over user inputs),
  -- then shallow-apply the user overrides on top.
  local merged = vim.tbl_extend('force', H.config, opts)
  H.setup_config(merged)
  H.apply_config(opts)
  H.create_hl()

  H.is_setup = true
end

---Fetch LeetCode language metadata.
---
---@param slug string LeetCode language slug, like 'cpp'.
---@return table|nil Language info (`H.langs[slug]`) or nil if unknown.
H.get_lang = function(slug) return H.langs[slug] end

---Whether `slug` is among the configured picker languages.
---
---@param slug string
---@return boolean
H.lang_enabled = function(slug)
  local languages = H.config.languages
  if languages == nil then return H.langs[slug] ~= nil end

  for _, enabled in ipairs(languages) do
    if enabled == slug then return true end
  end
  return false
end

return H
