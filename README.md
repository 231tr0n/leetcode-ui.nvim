# leetcode-ui.nvim

A command-driven LeetCode client for Neovim. The whole interface lives in one
central window with Description, Code, Console, and Info tabs. Statistics use
the same window.

## Features

- Browse problems with `mini.pick` or `vim.ui.select()`.
- Read parsed descriptions and hints, hidden by default to avoid spoilers.
- Edit, run, and submit solutions through the LeetCode API.
- Persist code drafts and custom testcases per question.
- Format with LeetCode's formatter, then fall back to local CLI formatters or LSP.
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
```

`:LeetCode` and `:LeetCode list` both open the problem list. See
`:LeetCode help` or `:h leetcode-ui-commands` for the full list. Map the
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
:LeetCode question hints show
:LeetCode question run 2
:LeetCode question submit
:LeetCode question language golang
:LeetCode question case add [2,7,11,15]\n9
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

## Development

Development dependencies: Neovim, StyLua, Luacheck, LuaLS, Node/Prettier, and
mini.nvim. Common tasks are exposed through the Makefile:

```sh
make bootstrap-mini             # clone mini.nvim if missing
make deps                       # report missing tools
make test                       # run the full test suite
make test-file FILE=tests/test_commands.lua
make format                     # format Lua and Markdown
make check                      # formatting, lint, tests, and docs checks
make docs                       # regenerate doc/leetcode-ui.txt
```

## Requirements

Runtime:

- Neovim >= 0.10 (`vim.system`, `vim.uv`, `vim.lsp`).
- `curl` — required for all LeetCode API and remote formatting requests.
- `python3` with `sqlite3` — required only when browser cookie import is
  enabled (`browser = 'auto'` or a specific browser).
- `openssl` — optional; required for Chromium-family `v10` cookie decryption.
- `secret-tool` on Linux or `security` on macOS — optional; used for
  Chromium-family `v11+` keyring-protected cookies.
- `mini.nvim` — optional; provides the `mini.pick` picker when available.
- A language server (e.g. `pyright`) — optional; provides diagnostics,
  completion, and LSP formatting in the code buffer.
- Optional CLI formatters: `prettier`, `black`, `clang-format`, `gofmt`,
  `rustfmt`, or `google-java-format`.

No LuaRocks or external Lua packages are required.

## License

MIT
