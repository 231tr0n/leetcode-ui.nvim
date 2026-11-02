--- *leetcode-ui-config* Configuration for leetcode-ui
---
--- Configuration is validated and applied by |leetcode-ui.setup()|.
---
--- Nested tables are replaced whole (not deep-merged), like in mini.nvim.
--- Supply the complete nested table when overriding one.
---
--- Options:
---
--- - `url` (`string`) - LeetCode domain used for API and web URLs.
--- - `lang` (`string`) - default solution language slug.
--- - `languages` (`table|nil`) - allow-list of language slugs for the picker.
--- - `cookies` (`table`) - `LEETCODE_SESSION` and `csrftoken` values.
--- - `cookie_file` (`string|nil`) - Netscape cookie jar consumed by curl.
--- - `storage_path` (`string|nil`) - cache and draft root.
--- - `browser` (`string`) - cookie import source: `auto`, `firefox`,
---   `epiphany`, `safari`, `chrome`, `brave`, `edge`, `chromium`, or `none`.
--- - `browser_paths` (`table`) - per-browser database path overrides.
--- - `local_runner` (`boolean`) - prefer bundled local runners for `run`.
--- - `binaries` (`table`) - executable overrides for local runners.
--- - `runner_timeout` (`number`) - local runner timeout in seconds.
--- - `no_local` (`table`) - language slugs that always run online.
--- - `float_width`, `float_height` (`number`) - central window size.
--- - `float_border` (`string|nil`) - central window border.
--- - `picker` (`string`) - `auto`, `mini`, or `builtin`.
--- - `cooldown` (`number`) - problem-list cache lifetime in minutes.
--- - `hide_premium` (`boolean`) - hide premium-only problems.
--- - `show_hints` (`boolean`) - show hints in the Description tab by default.
--- - `notifications` (`boolean`) - show informational notifications.
--- - `icons` (`table`) - status and testcase icon overrides.
---
--- Default configuration:
---
--- >lua
---   require('leetcode-ui').setup({
---     url = 'leetcode.com',
---     lang = 'python3',
---     languages = nil,
---     cookies = { LEETCODE_SESSION = nil, csrftoken = nil },
---     cookie_file = nil,
---     storage_path = nil,
---     browser = 'auto',
---     browser_paths = {},
---     local_runner = true,
---     binaries = {},
---     runner_timeout = 30,
---     no_local = {},
---     float_width = 120,
---     float_height = 36,
---     float_border = nil,
---     picker = 'auto',
---     cooldown = 60,
---     hide_premium = false,
---     show_hints = false,
---     notifications = true,
---   })
--- <
---
---@tag LeetCodeConfig
---@toc_entry Configuration

local LeetCodeConfig = {}

-- Helper data =======================================================================================================

LeetCodeConfig.langs = {
  cpp = { lang = 'C++', slug = 'cpp', ft = 'cpp' },
  java = { lang = 'Java', slug = 'java', ft = 'java' },
  python3 = { lang = 'Python3', slug = 'python3', ft = 'python' },
  python = { lang = 'Python', slug = 'python', ft = 'python', alt = 'python3' },
  c = { lang = 'C', slug = 'c', ft = 'c' },
  ['csharp'] = { lang = 'C#', slug = 'csharp', ft = 'cs' },
  javascript = { lang = 'JavaScript', slug = 'javascript', ft = 'javascript' },
  typescript = { lang = 'TypeScript', slug = 'typescript', ft = 'typescript' },
  php = { lang = 'PHP', slug = 'php', ft = 'php' },
  swift = { lang = 'Swift', slug = 'swift', ft = 'swift' },
  kotlin = { lang = 'Kotlin', slug = 'kotlin', ft = 'kotlin' },
  dart = { lang = 'Dart', slug = 'dart', ft = 'dart' },
  golang = { lang = 'Go', slug = 'golang', ft = 'go' },
  ruby = { lang = 'Ruby', slug = 'ruby', ft = 'ruby' },
  scala = { lang = 'Scala', slug = 'scala', ft = 'scala' },
  rust = { lang = 'Rust', slug = 'rust', ft = 'rust' },
  racket = { lang = 'Racket', slug = 'racket', ft = 'racket' },
  erlang = { lang = 'Erlang', slug = 'erlang', ft = 'erlang' },
  elixir = { lang = 'Elixir', slug = 'elixir', ft = 'elixir' },
  bash = { lang = 'Bash', slug = 'bash', ft = 'sh' },
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

local default_config = {
  -- LeetCode domain used for API and web URLs.
  url = 'leetcode.com',

  -- Default solution language (a key of `LeetCodeConfig.langs`).
  lang = 'python3',

  -- Optional allow-list of language slugs shown by the language picker.
  languages = nil,

  -- Cookie values used when `cookie_file` is not set.
  cookies = { LEETCODE_SESSION = nil, csrftoken = nil },

  -- Netscape-format cookie jar consumed by curl directly.
  cookie_file = nil,

  -- Storage root for the problem-list cache and solution drafts.
  -- Defaults to `stdpath('data')/leetcode-ui`.
  storage_path = nil,

  -- Automatic cookie import from browsers: 'auto', 'firefox', 'epiphany',
  -- 'safari', 'chrome', 'brave', 'edge', 'chromium', or 'none'.
  browser = 'auto',

  -- Per-browser database path overrides, e.g. { firefox = '~/profile/cookies.sqlite' }.
  browser_paths = {},

  -- Whether to prefer the bundled local runners for `:LeetCode run`.
  local_runner = true,

  -- Executable overrides for local runners, e.g. { python3 = '/usr/bin/python3' }.
  binaries = {},

  -- Local runner timeout in seconds.
  runner_timeout = 30,

  -- Language slugs that should always run online.
  no_local = {},

  -- Central UI window geometry.
  float_width = 120,
  float_height = 36,
  float_border = nil,

  -- Picker backend: 'auto', 'mini', or 'builtin'.
  picker = 'auto',

  -- Problem-list cache lifetime in minutes.
  cooldown = 60,

  -- Whether to hide premium-only problems from the picker.
  hide_premium = false,

  -- Whether to show question hints by default.
  show_hints = false,

  -- Whether to show informational notifications.
  notifications = true,

  icons = {
    status = { solved = '✔', attempted = '✘', todo = '○', active = '◈' },
    case = { passed = '✔', failed = '✘', unknown = '○', err = '✗', ran = '▶' },
  },
}

LeetCodeConfig.config = vim.deepcopy(default_config)

--- Reset the public config table back to defaults (used by tests).
LeetCodeConfig.reset = function() LeetCodeConfig.config = vim.deepcopy(default_config) end

-- Helper functionality =============================================================================================

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
    float_width = { config.float_width, 'number' },
    float_height = { config.float_height, 'number' },
    float_border = { config.float_border, 'string', true },
    picker = { config.picker, 'string' },
    cooldown = { config.cooldown, 'number' },
    hide_premium = { config.hide_premium, 'boolean' },
    show_hints = { config.show_hints, 'boolean' },
    notifications = { config.notifications, 'boolean' },
    icons = { config.icons, 'table' },
  })

  if LeetCodeConfig.langs[config.lang] == nil then
    LeetCodeConfig.error(('Unknown default language `%s`.'):format(config.lang))
  end

  if not vim.tbl_contains({ 'auto', 'mini', 'builtin' }, config.picker) then
    LeetCodeConfig.error(('Unknown picker `%s`. Use one of "auto", "mini", "builtin".'):format(config.picker))
  end

  local browsers = { 'auto', 'firefox', 'epiphany', 'safari', 'chrome', 'brave', 'edge', 'chromium', 'none' }
  if not vim.tbl_contains(browsers, config.browser) then
    LeetCodeConfig.error(('Unknown browser `%s`. Use one of %s.'):format(config.browser, table.concat(browsers, ', ')))
  end

  for _, group in ipairs({ 'status', 'case' }) do
    local icons = config.icons[group]
    if type(icons) ~= 'table' then LeetCodeConfig.error(('`icons.%s` should be a table.'):format(group)) end
    for name, value in pairs(icons) do
      if type(value) ~= 'string' then
        LeetCodeConfig.error(('`icons.%s.%s` should be a string.'):format(group, name))
      end
    end
  end

  for _, slug in ipairs(config.languages or {}) do
    if LeetCodeConfig.langs[slug] == nil then
      LeetCodeConfig.error(('Unknown language `%s` in `languages`.'):format(tostring(slug)))
    end
  end
end

LeetCodeConfig.apply_config = function(config)
  LeetCodeConfig.config = vim.tbl_extend('force', vim.deepcopy(default_config), config or {})

  local lang = LeetCodeConfig.config.lang
  local info = LeetCodeConfig.langs[lang]
  if info ~= nil and info.alt ~= nil then LeetCodeConfig.config.lang = info.alt end
end

LeetCodeConfig.create_hl = function()
  for name, spec in pairs(LeetCodeConfig.highlights) do
    pcall(vim.api.nvim_set_hl, 0, name, spec)
  end
end

--- Raise a configuration error.
---
---@param msg string
LeetCodeConfig.error = function(msg) error(('(leetcode-ui) %s'):format(msg), 0) end

--- Set up |leetcode-ui| configuration.
---
---@param opts table|nil User configuration.
LeetCodeConfig.setup = function(opts)
  local merged = vim.tbl_extend('force', vim.deepcopy(default_config), opts or {})
  LeetCodeConfig.setup_config(merged)
  LeetCodeConfig.apply_config(merged)
  LeetCodeConfig.create_hl()

  if LeetCodeConfig._hl_autocmd == nil then
    LeetCodeConfig._hl_autocmd = vim.api.nvim_create_autocmd('ColorScheme', {
      callback = function() LeetCodeConfig.create_hl() end,
    })
  end

  LeetCodeConfig.is_setup = true
end

--- Fetch LeetCode language metadata.
---
---@param slug string
---@return table|nil
LeetCodeConfig.get_lang = function(slug) return LeetCodeConfig.langs[slug] end

--- Whether `slug` is among the configured picker languages.
---
---@param slug string
---@return boolean
LeetCodeConfig.lang_enabled = function(slug)
  local info = LeetCodeConfig.langs[slug]
  if info == nil then return false end
  local canonical = info.alt or info.slug

  local languages = LeetCodeConfig.config.languages
  if languages == nil then return true end

  for _, enabled in ipairs(languages) do
    local enabled_info = LeetCodeConfig.langs[enabled]
    local enabled_slug = enabled_info ~= nil and (enabled_info.alt or enabled_info.slug) or enabled
    if enabled_slug == canonical then return true end
  end
  return false
end

return LeetCodeConfig
