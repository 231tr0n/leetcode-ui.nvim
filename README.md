# leetcode-ui.nvim

A minimal Neovim UI for solving LeetCode problems.

## Features

- Browse and pick LeetCode problems (uses `vim.ui.select` by default; `mini.pick` is optional as a faster UI)
- View problem descriptions with HTML parsing
- Edit and run solutions locally or against LeetCode's judge
- Submit solutions
- Cookie-based authentication from browsers or env
- Per-question drafts and stats view

## Installation

### [vim.pack](https://neovim.io/doc/user/pack.html) (Neovim 0.12+)

```lua
vim.pack.add({
  { src = "https://github.com/231tr0n/leetcode-ui.nvim" }, -- optional: { src = "https://github.com/echasnovski/mini.nvim" } for mini.pick
})
require("leetcode-ui").setup({})
```

### Other plugin managers

Works with any plugin manager that can clone Git repositories. `mini.pick` is optional.

## Usage

```vim
:LeetCode
:LeetCode list
:LeetCode random
:LeetCode daily
:LeetCode stats
```

Selection is done via `vim.ui.select`. If `mini.pick` is installed, you can override `vim.ui.select` with it via `mini.pick.ui_select()` if desired. Multi-select is not currently required, so the picker can rely on `vim.ui.select` alone.

## Requirements

- Neovim >= 0.9
- Python 3 (for local runner)
- Optional: `openssl`, `curl`

## License

MIT
