-- Environment: LuaJIT + Neovim-provided globals.
std = 'luajit'

-- Standard Neovim globals.
globals = { 'vim', 'utf8', 'MiniTest' }

-- Don't fail on long lines in tests/helpers (generated scripts)
max_line_length = false

max_comment_line_length = false
max_line_length = 120

-- Per-file overrides
files["tests/helpers.lua"] = {
  ignore = { "121" },
}
