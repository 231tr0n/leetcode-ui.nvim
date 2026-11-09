--- *leetcode-ui-config* Configuration for leetcode-ui
---
--- Configuration is validated and applied by |LeetCode.setup()|.
---
--- Each call to |LeetCode.setup()| replaces the whole configuration. Unspecified
--- options return to their defaults; values from a previous call are not
--- merged. Nested tables are replaced whole as well.
---
--- Options:
---
--- - `url` (`string`) - LeetCode domain used for API, formatter, and web URLs.
--- - `lang` (`string`) - default solution language slug.
--- - `languages` (`table|nil`) - allow-list for solution languages and
---   pickers.
--- - `cookies` (`table`) - `LEETCODE_SESSION` and `csrftoken` values.
--- - `cookie_file` (`string|nil`) - Netscape cookie jar consumed by curl.
--- - `storage_path` (`string|nil`) - cache, draft, and testcase root.
--- - `browser` (`string`) - cookie import source: `none` (default), `auto`,
---   `firefox`, `epiphany`, `safari`, `chrome`, `brave`, `edge`, or `chromium`.
--- - `browser_paths` (`table`) - per-browser database path overrides.
--- - `float_width`, `float_height` (`number`) - preferred central window
---   content size, clamped to the usable editor area. Borders are extra.
--- - `float_border` (`string|nil`) - central window border.
--- - `picker` (`string`) - `auto` (use `mini.pick` when `MiniPick` is set up),
---   `mini` (prefer it explicitly), or `builtin` (use |vim.ui.select()|).
--- - `cooldown` (`number`) - problem-list cache lifetime in minutes.
--- - `hide_premium` (`boolean`) - hide premium-only problems from pickers,
---   random selection, and completions.
--- - `show_hints` (`boolean`) - show hints in the Description tab by default.
--- - `notifications` (`boolean`) - show notifications.
--- - `icons` (`table`) - status and testcase icon overrides.
---
--- Supported language slugs: `bash`, `c`, `cpp`, `csharp`, `dart`, `elixir`,
--- `erlang`, `golang`, `java`, `javascript`, `kotlin`, `php`, `python`,
--- `python3`, `racket`, `ruby`, `rust`, `scala`, `swift`, and `typescript`.
--- The `python` slug is normalized to `python3`.
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
---     browser = 'none',
---     browser_paths = {},
---     float_width = 120,
---     float_height = 40,
---     float_border = nil,
---     picker = 'auto',
---     cooldown = 60,
---     hide_premium = false,
---     show_hints = false,
---     notifications = true,
---     icons = {
---       status = { solved = '✔', attempted = '✘', todo = '○', active = '◈' },
---       case = { passed = '✔', failed = '✘', unknown = '○', err = '✗' },
---     },
---   })
--- <
---
--- Highlight groups:
---
--- All groups except `LeetCodeCursor` are linked to existing highlight groups
--- by default, so colorschemes control them. Override any group after setup
--- with |nvim_set_hl()|:
---
--- >lua
---   require('leetcode-ui').setup({})
---   vim.api.nvim_set_hl(0, 'LeetCodeOk', { fg = '#00ff00' })
--- <
---
--- - `LeetCodeOk` -> `DiagnosticOk`
--- - `LeetCodeErr` -> `DiagnosticError`
--- - `LeetCodeWarn` -> `DiagnosticWarn`
--- - `LeetCodeDim` -> `Comment`
--- - `LeetCodeTitle` -> `Title`
--- - `LeetCodeCode` -> `Identifier`
--- - `LeetCodeLink` -> `DiagnosticInfo`
--- - `LeetCodeItalic` -> `@markup.italic`
--- - `LeetCodeEasy` -> `String`
--- - `LeetCodeMedium` -> `DiagnosticWarn`
--- - `LeetCodeHard` -> `DiagnosticError`
--- - `LeetCodeHeader` -> `@markup.heading`
--- - `LeetCodeQuestionTitle` -> `LeetCodeWinBar`
--- - `LeetCodeTab` -> `TabLine` (inactive winbar tabs)
--- - `LeetCodeTabActive` -> `PmenuSel` (active winbar tab)
--- - `LeetCodeCursorLine` -> `CursorLine`
--- - `LeetCodeCursor` - hidden cursor used in read-only tabs
--- - `LeetCodeCodeNormal` -> `Normal` (Code tab background)
--- - `LeetCodeNormalFloat` -> `NormalFloat`
--- - `LeetCodeFloatBorder` -> `FloatBorder`
--- - `LeetCodeWinBar` -> `WinBar`
--- - `LeetCodeWinBarNC` -> `WinBarNC`
---
--- Read-only tabs hide the cursor, use `LeetCodeCursorLine` for the active
--- line, and keep the `LeetCodeNormalFloat` background. The Code tab uses the
--- normal `Cursor` and `CursorLine` groups and the `LeetCodeCodeNormal`
--- background.
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

LeetCodeConfig.difficulty_highlights = {
  Easy = 'LeetCodeEasy',
  Medium = 'LeetCodeMedium',
  Hard = 'LeetCodeHard',
}

LeetCodeConfig.highlights = {
  LeetCodeOk = { link = 'DiagnosticOk' },
  LeetCodeErr = { link = 'DiagnosticError' },
  LeetCodeWarn = { link = 'DiagnosticWarn' },
  LeetCodeDim = { link = 'Comment' },
  LeetCodeTitle = { link = 'Title' },
  LeetCodeCode = { link = 'Identifier' },
  LeetCodeLink = { link = 'DiagnosticInfo' },
  LeetCodeItalic = { link = '@markup.italic' },
  LeetCodeEasy = { link = 'String' },
  LeetCodeMedium = { link = 'DiagnosticWarn' },
  LeetCodeHard = { link = 'DiagnosticError' },
  LeetCodeHeader = { link = '@markup.heading' },
  LeetCodeQuestionTitle = { link = 'LeetCodeWinBar' },
  LeetCodeTab = { link = 'TabLine' },
  LeetCodeTabActive = { link = 'PmenuSel' },
  LeetCodeCursor = { blend = 100, nocombine = true },
  LeetCodeCursorLine = { link = 'CursorLine' },
  LeetCodeCodeNormal = { link = 'Normal' },
  LeetCodeNormalFloat = { link = 'NormalFloat' },
  LeetCodeFloatBorder = { link = 'FloatBorder' },
  LeetCodeWinBar = { link = 'WinBar' },
  LeetCodeWinBarNC = { link = 'WinBarNC' },
}

local default_config = {
  -- LeetCode domain used for API, formatter, and web URLs.
  url = 'leetcode.com',

  -- Default solution language (a key of `LeetCodeConfig.langs`).
  lang = 'python3',

  -- Optional allow-list used for default and picker language selection.
  languages = nil,

  -- Cookie values used when `cookie_file` is not set.
  cookies = { LEETCODE_SESSION = nil, csrftoken = nil },

  -- Netscape-format cookie jar consumed by curl directly.
  cookie_file = nil,

  -- Storage root for the problem-list cache, solution drafts, and testcases.
  -- Defaults to `stdpath('data')/leetcode-ui`.
  storage_path = nil,

  -- Browser cookie import is disabled by default. Enable with 'auto' or a
  -- specific browser: 'firefox', 'epiphany', 'safari', 'chrome', 'brave',
  -- 'edge', or 'chromium'.
  browser = 'none',

  -- Per-browser database path overrides, e.g. { firefox = '~/profile/cookies.sqlite' }.
  browser_paths = {},

  -- Central UI window geometry.
  float_width = 120,
  float_height = 40,
  float_border = nil,

  -- Picker backend: 'auto', 'mini', or 'builtin'.
  picker = 'auto',

  -- Problem-list cache lifetime in minutes.
  cooldown = 60,

  -- Whether to hide premium-only problems from pickers, random selection, and
  -- completions.
  hide_premium = false,

  -- Whether to show question hints by default.
  show_hints = false,

  -- Whether to show notifications.
  notifications = true,

  icons = {
    status = { solved = '✔', attempted = '✘', todo = '○', active = '◈' },
    case = { passed = '✔', failed = '✘', unknown = '○', err = '✗' },
  },
}

-- Fallbacks for standard groups introduced after the oldest supported Neovim.
LeetCodeConfig.highlight_fallbacks = {
  DiagnosticOk = 'String',
  ['@markup.heading'] = 'Title',
  ['@markup.italic'] = 'Comment',
}

LeetCodeConfig.config = vim.deepcopy(default_config)
LeetCodeConfig.url_epoch = 0
LeetCodeConfig.auth_epoch = 0

local highlight_autocmd = nil

-- Helper functionality =============================================================================================

local function validate(config)
  vim.validate({
    url = { config.url, 'string' },
    lang = { config.lang, 'string' },
    languages = { config.languages, 'table', true },
    cookies = { config.cookies, 'table' },
    cookie_file = { config.cookie_file, 'string', true },
    storage_path = { config.storage_path, 'string', true },
    browser = { config.browser, 'string' },
    browser_paths = { config.browser_paths, 'table' },
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

  local optional_keys = { languages = true, cookie_file = true, storage_path = true, float_border = true }
  for key in pairs(config) do
    if default_config[key] == nil and not optional_keys[key] then
      LeetCodeConfig.error(('Unknown option `%s`.'):format(tostring(key)))
    end
  end

  if
    not config.url:match('^[%w%-%.]+$')
    or config.url:sub(1, 1) == '.'
    or config.url:sub(-1) == '.'
    or config.url:find('..', 1, true) ~= nil
  then
    LeetCodeConfig.error('`url` should be a bare host like "leetcode.com".')
  end
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

  local known_cookies = { LEETCODE_SESSION = true, csrftoken = true }
  for name, value in pairs(config.cookies) do
    if not known_cookies[name] then LeetCodeConfig.error(('Unknown cookie `%s`.'):format(tostring(name))) end
    if value ~= nil and type(value) ~= 'string' then
      LeetCodeConfig.error(('`cookies.%s` should be a string or nil.'):format(name))
    end
  end

  local known_browsers = {
    firefox = true,
    epiphany = true,
    safari = true,
    chrome = true,
    brave = true,
    edge = true,
    chromium = true,
  }
  for browser, path in pairs(config.browser_paths) do
    if not known_browsers[browser] then
      LeetCodeConfig.error(('Unknown browser in `browser_paths`: `%s`.'):format(tostring(browser)))
    end
    if type(path) ~= 'string' then
      LeetCodeConfig.error(('`browser_paths.%s` should be a string.'):format(tostring(browser)))
    end
  end

  for group, defaults in pairs(default_config.icons) do
    local icons = config.icons[group]
    if type(icons) ~= 'table' then LeetCodeConfig.error(('`icons.%s` should be a table.'):format(group)) end
    for name in pairs(defaults) do
      if type(icons[name]) ~= 'string' then
        LeetCodeConfig.error(('`icons.%s.%s` should be a string.'):format(group, name))
      end
    end
    for name in pairs(icons) do
      if defaults[name] == nil then LeetCodeConfig.error(('Unknown icon `icons.%s.%s`.'):format(group, name)) end
    end
  end
  for group in pairs(config.icons) do
    if default_config.icons[group] == nil then
      LeetCodeConfig.error(('Unknown icon group `icons.%s`.'):format(group))
    end
  end

  for _, name in ipairs({ 'float_width', 'float_height' }) do
    local value = config[name]
    if value < 1 or value % 1 ~= 0 then LeetCodeConfig.error(('`%s` should be a positive integer.'):format(name)) end
  end
  if config.cooldown < 0 or config.cooldown == math.huge or config.cooldown ~= config.cooldown then
    LeetCodeConfig.error('`cooldown` should be a finite, non-negative number.')
  end

  if config.languages ~= nil then
    if #config.languages == 0 or not (vim.islist or vim.tbl_islist)(config.languages) then
      LeetCodeConfig.error('`languages` should be a non-empty list.')
    end
    for _, slug in ipairs(config.languages) do
      if type(slug) ~= 'string' then
        LeetCodeConfig.error('`languages` should only contain strings.')
      elseif LeetCodeConfig.langs[slug] == nil then
        LeetCodeConfig.error(('Unknown language `%s` in `languages`.'):format(slug))
      end
    end
  end
end

local function apply(config)
  if LeetCodeConfig.config.url ~= config.url then LeetCodeConfig.url_epoch = (LeetCodeConfig.url_epoch or 0) + 1 end
  LeetCodeConfig.config = vim.deepcopy(config)
  local info = LeetCodeConfig.langs[LeetCodeConfig.config.lang]
  if info ~= nil and info.alt ~= nil then LeetCodeConfig.config.lang = info.alt end
end

--- Apply the configured highlight groups.
LeetCodeConfig.create_hl = function()
  for name, spec in pairs(LeetCodeConfig.highlights) do
    local resolved = spec
    if spec.link ~= nil and vim.fn.hlexists(spec.link) == 0 then
      local fallback = LeetCodeConfig.highlight_fallbacks[spec.link]
      if fallback ~= nil and vim.fn.hlexists(fallback) == 1 then resolved = { link = fallback } end
    end
    resolved = vim.tbl_extend('force', { default = true }, resolved)
    pcall(vim.api.nvim_set_hl, 0, name, resolved)
  end
end

--- Raise a configuration error.
---
---@param msg string
LeetCodeConfig.error = function(msg) error(('(leetcode-ui) %s'):format(msg), 0) end

local function prepare(opts)
  if opts ~= nil and type(opts) ~= 'table' then LeetCodeConfig.error('`opts` should be a table or nil.') end
  local merged = vim.tbl_extend('force', vim.deepcopy(default_config), opts or {})
  validate(merged)
  return merged
end

--- Validate and fill defaults for a setup table.
---
---@param opts table|nil User configuration.
---@return table prepared
LeetCodeConfig.prepare = function(opts) return prepare(opts) end

--- Set up |leetcode-ui| configuration.
---
---@param opts table|nil User configuration.
---@param prepared table|nil Already validated configuration.
LeetCodeConfig.setup = function(opts, prepared)
  local merged = prepared or prepare(opts)
  apply(merged)
  LeetCodeConfig.create_hl()

  if highlight_autocmd == nil then
    highlight_autocmd = vim.api.nvim_create_autocmd('ColorScheme', {
      group = vim.api.nvim_create_augroup('LeetCodeUiHighlights', {}),
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

--- Whether `slug` is in the configured language allow-list.
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
