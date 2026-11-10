# leetcode-ui.nvim

A command-driven LeetCode client for Neovim. The whole interface lives in one
central window with Description, Code, Console, and Info tabs. Statistics use
the same window. See `:h leetcode-ui` for the full documentation.

## Features

- Browse problems with `mini.pick` or `vim.ui.select()`.
- Read parsed descriptions, with hints hidden by default to avoid spoilers.
- Edit solutions locally; run and submit through the LeetCode API.
- Persist code drafts and custom testcases per question.
- Format code through the LeetCode API or a user-provided formatter.
- Show progress statistics and current session information.
- Show inline progress while the problem list loads.
- Render Description, Info, Statistics, and Help as Markdown when
  `render-markdown.nvim` is loaded and enabled.
- Optional browser cookie import, disabled by default (see the caution below).
- No plugin-defined keymaps: map only the commands you want.

## Installation

### [vim.pack](https://neovim.io/doc/user/pack.html) (Neovim 0.12+)

```lua
vim.pack.add({
  { src = "https://github.com/231tr0n/leetcode-ui.nvim" },
  -- Optional, for the mini.pick picker backend:
  -- { src = "https://github.com/echasnovski/mini.nvim" },
  -- Optional, for Markdown rendering:
  -- { src = "https://github.com/MeanderingProgrammer/render-markdown.nvim" },
})
-- require('mini.pick').setup() -- optional; enables the mini.pick backend
-- require('render-markdown').setup({}) -- optional; renders Markdown views
require("leetcode-ui").setup({})
```

### Other plugin managers

Works with any plugin manager that can clone Git repositories. `mini.pick` and
`render-markdown.nvim` are optional.

## Usage

```vim
:LeetCode list
:LeetCode list Hard
:LeetCode daily
:LeetCode random Easy
:LeetCode open two-sum
:LeetCode stats
:LeetCode session
:LeetCode refresh
:LeetCode help
```

`:LeetCode` and `:LeetCode list` both open the problem list. See
`:LeetCode help` or `:h LeetCode` for the full list. Map the
commands you use:

```lua
vim.keymap.set('n', '<leader>ll', '<cmd>LeetCode list<cr>', { desc = 'LeetCode: list' })
vim.keymap.set('n', '<leader>lr', '<cmd>LeetCode question run<cr>', { desc = 'LeetCode: run' })
vim.keymap.set('n', '<leader>ls', '<cmd>LeetCode question submit<cr>', { desc = 'LeetCode: submit' })
vim.keymap.set('n', '<leader>lx', '<cmd>LeetCode question close<cr>', { desc = 'LeetCode: close' })
```

Question-window actions live under `:LeetCode question`:

```vim
:LeetCode question description
:LeetCode question code
:LeetCode question console
:LeetCode question info
:LeetCode question next
:LeetCode question prev
:LeetCode question hints show
:LeetCode question hints hide
:LeetCode question run 2
:LeetCode question submit
:LeetCode question reset
:LeetCode question format
:LeetCode question language golang
:LeetCode question case add [2,7,11,15]\n9
:LeetCode question case edit 2 [0]\n0
:LeetCode question case delete 2
:LeetCode question case next
:LeetCode question case prev
:LeetCode question case reset
:LeetCode question close
```

## Formatting

Formatting is exposed through one optional function:

```lua
require('leetcode-ui').setup({
  formatter = function(text, filetype)
    -- Return formatted text, or nil to leave the built-in behavior.
  end,
})
```

The same function handles every formatting path. It receives `text` and
`filetype`:

- `markdown` — generated Markdown for Description, Info, Statistics, and Help.
- `html` — raw Description and hint HTML before conversion.
- A solution filetype such as `python`, `go`, or `javascript` — code editor.

Return a formatted string, or `nil`:

- Markdown/HTML keep their original text.
- Code falls back to the LeetCode API. Built-in remote formatting supports
  C, C++, Go, Java, Python 3, and Swift (`c`, `cpp`, `golang`, `java`,
  `python3`, `swift`). Other languages require a user-provided formatter.

The plugin does not run local CLI formatters or Neovim LSP clients. Code uses
LeetCode's remote formatter for the languages it supports; other languages
require a user-provided formatter. There is no `prettier` option.

The only formatting command is:

```vim
:LeetCode question format
```

It formats the current code editor. Read-only Markdown/HTML is formatted
automatically whenever it is rendered.

### Formatter examples

Use Prettier for Markdown and HTML, and leave code to the LeetCode API:

```lua
require('leetcode-ui').setup({
  formatter = function(text, filetype)
    if filetype == 'markdown' or filetype == 'html' then
      local file = filetype == 'html' and 'x.html' or 'x.md'
      local out = vim.fn.system({ 'prettier', '--stdin-filepath', file }, text)
      if vim.v.shell_error == 0 then return out end
    end
    return nil
  end,
})
```

Use a language-specific command for code:

```lua
require('leetcode-ui').setup({
  formatter = function(text, filetype)
    local command
    if filetype == 'python' then
      command = { 'ruff', 'format', '-' }
    elseif filetype == 'javascript' or filetype == 'typescript' then
      local ext = filetype == 'typescript' and 'ts' or 'js'
      command = { 'prettier', '--stdin-filepath', 'x.' .. ext }
    end
    if command == nil then return nil end -- use the LeetCode API
    local out = vim.fn.system(command, text)
    if vim.v.shell_error == 0 then return out end
    return nil
  end,
})
```

Use a custom Markdown formatter while leaving other filetypes to the defaults:

```lua
require('leetcode-ui').setup({
  formatter = function(text, filetype)
    if filetype == 'markdown' then return my_markdown_formatter(text) end
    return nil
  end,
})
```

## Configuration

```lua
require('leetcode-ui').setup({
  lang = 'python3',
  picker = 'auto', -- 'auto', 'mini', or 'builtin'
  notifications = true,
  show_hints = false,
  markdown = true, -- Markdown Description/Info/Stats/Help when render-markdown.nvim is loaded and enabled
  cooldown = 1440, -- problem-list cache lifetime in minutes (one day)
  -- window = {
  --   config = { width = 100, height = 30, border = 'rounded' },
  --   -- or: config = function() return { width = 100, height = 30 } end
  -- },
  -- formatter = function(text, filetype) return nil end,
  -- cookies = { LEETCODE_SESSION = '...', csrftoken = '...' },
  -- cookie_file = '~/.config/leetcode/cookies.txt',
  -- browser = 'auto', -- opt in to browser cookie import
})
```

See `:h leetcode-ui-config` for every option and the default configuration.
When `cookie_file` is unset, cookies resolve from `cookies`, then the
`LEETCODE_SESSION` and `CSRFTOKEN` environment variables, then supported
browsers when `browser` import is enabled. With `picker = 'auto'`,
`mini.pick` is used when `MiniPick` is already set up; otherwise the picker is
`vim.ui.select()`. Set `picker = 'mini'` to explicitly prefer `mini.pick`
(with a builtin fallback and warning when unavailable).

## Browser cookie caution

Browser import is disabled by default. When enabled, the plugin reads LeetCode
cookies from your browser's on-disk database and may decrypt them with system
keyring tools and OpenSSL. These cookies grant access to your LeetCode
account; prefer `cookie_file` or environment variables when possible.
Linux is the tested Chromium decryption path; macOS uses the Keychain and
PBKDF2 and is covered by mocked unit tests, not a native macOS CI runner.
Encrypted Chromium cookies on Windows are not supported.

## Development

Development dependencies: Git, Neovim, StyLua, Luacheck, LuaLS,
Node/Prettier, curl, OpenSSL, and mini.nvim. Browser fixture tests also
require `python3` with `sqlite3`. Common tasks are exposed through the
Makefile:

```sh
make bootstrap-mini             # clone mini.nvim if missing
make deps                       # report missing tools
make test                       # run the full test suite
make test-file FILE=tests/test_commands.lua
make format                     # format Lua and other supported files
make check                      # formatting, lint, tests, and docs checks
make docs                       # regenerate help text and tags
```

## Requirements

Runtime:

- Neovim stable (0.12 or newer; `vim.system`, `vim.uv`).
- `curl` — required for all LeetCode API and remote formatting requests.
- `python3` — required only when browser cookie import is enabled
  (`browser = 'auto'` or a specific browser); SQLite-backed browsers also need
  the `sqlite3` module.
- `openssl` — optional; required for supported Chromium-family `v10` and `v11`
  cookie decryption.
- `secret-tool` on Linux or `security` on macOS — optional; used for
  Chromium-family keyring-protected cookies (Linux `v11`, macOS `v10`/`v11`).
- `mini.nvim` — optional; run `require('mini.pick').setup()` to use it, and
  set `picker = 'mini'` to prefer it explicitly. `mini.clue` triggers are
  enabled inside the central window when it is set up.
- `render-markdown.nvim` — optional; renders Markdown views in the central
  window when it is loaded and enabled. It requires the `markdown` and
  `markdown_inline` treesitter parsers.
- A language server such as `lua-language-server`, `clangd`, or `ruff` —
  optional; provides diagnostics and completion.

No LuaRocks or external Lua packages are required.

## License

MIT
