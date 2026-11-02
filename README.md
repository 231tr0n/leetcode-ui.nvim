# leetcode-ui.nvim

A command-driven LeetCode client for Neovim. The whole interface lives in one
central window with Description, Code, Console, and Info tabs. Statistics use
the same window.

## Features

- Browse problems with `mini.pick` or `vim.ui.select()`.
- Read parsed descriptions and hints, hidden by default to avoid spoilers.
- Edit, run, and submit solutions with per-language drafts.
- Run solutions locally with the bundled Python 3 harness.
- Show progress statistics and current session information.
- Import session cookies from Firefox, Chromium-family browsers, Epiphany, or Safari.
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
  local_runner = true,
  picker = 'auto', -- 'auto', 'mini', or 'builtin'
  notifications = true,
  show_hints = false,
  -- cookies = { LEETCODE_SESSION = '...', csrftoken = '...' },
  -- cookie_file = '~/.config/leetcode/cookies.txt',
})
```

See `:h leetcode-ui-config` for every option and the default configuration.

## Requirements

- Neovim >= 0.10
- Python 3 (for the local runner)
- Optional: `openssl`, `curl`, `mini.nvim`

## License

MIT
