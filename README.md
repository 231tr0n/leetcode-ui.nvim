# leetcode-ui.nvim

A minimal Neovim UI for solving LeetCode problems.

## Features

- Browse and pick LeetCode problems (mini.pick or vim.ui.select)
- View problem descriptions with HTML parsing
- Edit and run solutions locally or against LeetCode's judge
- Submit solutions
- Cookie-based authentication from browsers or env
- Per-question drafts and stats view

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "231tr0n/leetcode-ui.nvim",
  dependencies = { "echasnovski/mini.nvim" },
  config = function()
    require("leetcode-ui").setup({})
  end,
}
```

## Usage

```vim
:LeetCode
:LeetCode list
:LeetCode menu
:LeetCode random
:LeetCode daily
:LeetCode stats
```

## Requirements

- Neovim >= 0.9
- Python 3 (for local runner)
- Optional: `openssl`, `curl`

## License

MIT
