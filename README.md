# leetcode-ui.nvim

A command-driven LeetCode client for Neovim. The whole interface lives in one
central window with Description, Code, Console, and Info tabs. Statistics use
the same window. See `:h leetcode-ui` for the full documentation.

## Features

- Browse problems with `mini.pick` or `vim.ui.select()`.
- Read parsed descriptions, with hints hidden by default to avoid spoilers.
- Edit solutions locally; run and submit through the LeetCode API.
- Persist code drafts and custom testcases per question.
- Format with the remote formatter when available, otherwise CLI formatters
  or LSP.
- Show progress statistics and current session information.
- Optional browser cookie import, disabled by default (see the caution below).
- No plugin-defined keymaps: map only the commands you want.

## Installation

### [vim.pack](https://neovim.io/doc/user/pack.html) (Neovim 0.12+)

```lua
vim.pack.add({
  { src = "https://github.com/231tr0n/leetcode-ui.nvim" },
  -- Optional, for the mini.pick picker backend:
  -- { src = "https://github.com/echasnovski/mini.nvim" },
})
-- require('mini.pick').setup() -- optional; enables the mini.pick backend
require("leetcode-ui").setup({})
```

### Other plugin managers

Works with any plugin manager that can clone Git repositories. `mini.pick` is
optional.

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

## Configuration

```lua
require('leetcode-ui').setup({
  lang = 'python3',
  picker = 'auto', -- 'auto', 'mini', or 'builtin'
  notifications = true,
  show_hints = false,
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

- Neovim stable (0.12 or newer; `vim.system`, `vim.uv`, `vim.lsp`).
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
- A language server such as `lua-language-server`, `clangd`, or `ruff` —
  optional; provides diagnostics and completion, plus LSP formatting when the
  server supports it.
- Optional CLI formatters: `prettier`, `black`, `clang-format`, `gofmt`,
  `rustfmt`, or `google-java-format`.

No LuaRocks or external Lua packages are required.

## License

MIT
