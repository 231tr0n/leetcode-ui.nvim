# leetcode-ui.nvim

A minimal Neovim UI for solving LeetCode problems.

## Features

- Browse and pick LeetCode problems (mini.pick or `vim.ui.select`)
- View problem descriptions with HTML parsing
- Edit and run solutions locally or against LeetCode's judge
- Submit solutions
- Cookie-based authentication from browsers or env
- Per-question drafts and stats view

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "231tr0n/leetcode-ui.nvim",
  dependencies = { "echasnovski/mini.nvim" },
  config = function()
    require("leetcode-ui").setup({})
  end,
}
```

### [vim.pack](https://neovim.io/doc/user/pack.html) (Neovim 0.12+)

```lua
vim.pack.add({
  { src = "https://github.com/echasnovski/mini.nvim" },
  { src = "https://github.com/231tr0n/leetcode-ui.nvim" },
})
require("leetcode-ui").setup({})
```

### Other plugin managers

Works with any plugin manager that can clone Git repositories. Make sure `mini.nvim` is available on your runtimepath.

## Usage

```vim
:LeetCode
:LeetCode list
:LeetCode menu
:LeetCode random
:LeetCode daily
:LeetCode stats
```

Selection is done via `vim.ui.select` when no picker is available.

## Requirements

- Neovim >= 0.9
- Python 3 (for local runner)
- Optional: `openssl`, `curl`

## License

MIT
