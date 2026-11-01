--- *leetcode-ui-config* Configuration for leetcode-ui
---
---@tag LeetCodeConfig
---

-- |leetcode-ui-config| Structure and helpers for the main |leetcode-ui| module.
-- This file follows mini.nvim module conventions (see |mini.development|):
-- - All defaults live in the public `M.config` table.
-- - |leetcode-ui.setup()| performs three steps:
--     1. `LeetCodeConfig.setup_config()` validates user inputs before anything is applied.
--     2. `LeetCodeConfig.apply_config()` shallow-extends the public `M.config` with user
--        options. NOTE: nested tables are replaced whole (not deep-merged),
--        like in mini.nvim; supply the full nested table when overriding one.
--     3. `LeetCodeConfig.create_hl()` (re)applies plugin highlight groups.
-- - `LeetCodeConfig` is the private helper table; it doubles as the module return value (as
--   in mini.nvim) so sibling modules require it directly.

local LeetCodeConfig = {}

-- Helper data =======================================================================================================

LeetCodeConfig.langs = {
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

LeetCodeConfig.highlights = {
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

  -- Floating window geometry.
  float_width = 100,
  float_height = 30,
  float_border = nil,

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
    toggle_question = 'D',
    toggle_code = 'C',
    toggle_console = 'X',
    toggle_information = 'I',
    reset_code = '<F2>',
    format_code = '<F3>',
    switch_language = '<F4>',
    add_test = '<F5>',
    delete_test = '<F7>',
    edit_test = '<F8>',
    next_case = '<F9>',
    prev_case = '<F10>',
    close = '<F6>',
  },
}

LeetCodeConfig.config = default_config

---Reset the public config table back to defaults (used by tests).
LeetCodeConfig.reset = function() LeetCodeConfig.config = vim.deepcopy(default_config) end

-- Helper functionality ==============================================================================================

LeetCodeConfig.setup_config = function(config)
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
    float_width = { config.float_width, 'number' },
    float_height = { config.float_height, 'number' },
    float_border = { config.float_border, 'string', true },
    picker = { config.picker, 'string' },
    cooldown = { config.cooldown, 'number' },
    hide_premium = { config.hide_premium, 'boolean' },
    icons = { config.icons, 'table' },
    keys = { config.keys, 'table' },
  })

  if LeetCodeConfig.langs[config.lang] == nil then
    LeetCodeConfig.error(('Unknown default language `%s`.'):format(config.lang))
  end

  if not vim.tbl_contains({ 'auto', 'mini', 'builtin' }, config.picker) then
    LeetCodeConfig.error(('Unknown picker `%s`. Use one of "auto", "mini", "builtin".'):format(config.picker))
  end

  if
    not vim.tbl_contains(
      { 'auto', 'firefox', 'epiphany', 'safari', 'chrome', 'brave', 'edge', 'chromium', 'none' },
      config.browser
    )
  then
    LeetCodeConfig.error(
      (
        'Unknown browser `%s`. Use one of "auto", "firefox", "epiphany", '
        .. '"safari", "chrome", "brave", "edge", "chromium", "none".'
      ):format(config.browser)
    )
  end

  for slug, info in pairs(config.icons.status) do
    if type(info) ~= 'string' then LeetCodeConfig.error(('`icons.status["%s"]` should be a string.'):format(slug)) end
  end
  local known_keys = {
    run = true,
    submit = true,
    toggle_question = true,
    toggle_code = true,
    toggle_console = true,
    toggle_information = true,
    reset_code = true,
    format_code = true,
    switch_language = true,
    add_test = true,
    delete_test = true,
    edit_test = true,
    next_case = true,
    prev_case = true,
    close = true,
  }
  for name, value in pairs(config.keys) do
    if not known_keys[name] then LeetCodeConfig.error(('Unknown `keys.%s` option.'):format(name)) end
    if type(value) ~= 'string' then LeetCodeConfig.error(('`keys.%s` should be a string.'):format(name)) end
  end
end

LeetCodeConfig.apply_config = function(config)
  LeetCodeConfig.config = vim.tbl_extend('force', LeetCodeConfig.config, config)

  -- Normalize alias slugs ('python' -> 'python3' style) once.
  if LeetCodeConfig.config.lang ~= nil and LeetCodeConfig.langs[LeetCodeConfig.config.lang] ~= nil then
    local info = LeetCodeConfig.langs[LeetCodeConfig.config.lang]
    LeetCodeConfig.config.lang = info.alt ~= nil and info.alt or info.slug
  end
end

LeetCodeConfig.create_hl = function()
  for name, spec in pairs(LeetCodeConfig.highlights) do
    pcall(vim.api.nvim_set_hl, 0, name, spec)
  end
end

---Error out either as |vim.notify()| or as a Lua error.
---
---@param msg string
---@param notify boolean|nil
---@return string
LeetCodeConfig.error = function(msg, notify)
  msg = ('(leetcode-ui) %s'):format(msg)
  if notify ~= nil and notify then
    vim.notify(msg, vim.log.levels.ERROR)
    return msg
  end
  error(msg, 0)
end

---Set up |leetcode-ui| configuration.
---
---@param opts table|nil User configuration.
LeetCodeConfig.setup = function(opts)
  opts = opts or {}

  -- Validate the effective configuration (defaults merged over user inputs),
  -- then shallow-apply the user overrides on top.
  local merged = vim.tbl_extend('force', LeetCodeConfig.config, opts)
  LeetCodeConfig.setup_config(merged)
  LeetCodeConfig.apply_config(opts)
  LeetCodeConfig.create_hl()

  LeetCodeConfig.is_setup = true
end

---Fetch LeetCode language metadata.
---
---@param slug string
---@return table|nil
LeetCodeConfig.get_lang = function(slug) return LeetCodeConfig.langs[slug] end

---Whether `slug` is among the configured picker languages.
---
---@param slug string
---@return boolean
LeetCodeConfig.lang_enabled = function(slug)
  local languages = LeetCodeConfig.config.languages
  if languages == nil then return LeetCodeConfig.langs[slug] ~= nil end

  for _, enabled in ipairs(languages) do
    if enabled == slug then return true end
  end
  return false
end

return LeetCodeConfig
