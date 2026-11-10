-- Tests for leetcode-ui.format.
local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set({
  hooks = {
    pre_case = function() helpers.setup() end,
  },
})

T['format'] = new_set()

T['format']['uses the configured formatter for every filetype'] = function()
  local seen = {}
  helpers.configure({
    formatter = function(text, filetype)
      table.insert(seen, filetype)
      return filetype .. ': ' .. text
    end,
  })
  local formatter = require('leetcode-ui.format')
  eq(formatter.format('a', 'markdown'), 'markdown: a')
  eq(formatter.format('b', 'html'), 'html: b')
  eq(formatter.format('c', 'python'), 'python: c')
  eq(seen, { 'markdown', 'html', 'python' })
end

T['format']['returns nil when no formatter is configured'] = function()
  eq(require('leetcode-ui.format').format('x', 'markdown'), nil)
end

T['format']['returns nil when the formatter returns nil or raises'] = function()
  local formatter = require('leetcode-ui.format')
  helpers.configure({ formatter = function() return nil end })
  eq(formatter.format('x', 'markdown'), nil)
  helpers.configure({ formatter = function() error('boom') end })
  eq(formatter.format('x', 'markdown'), nil)
end

T['format']['normalizes output and defaults the filetype'] = function()
  local formatter = require('leetcode-ui.format')
  local seen = nil
  helpers.configure({
    formatter = function(text, filetype)
      seen = filetype
      return text .. '\n\n'
    end,
  })
  ---@diagnostic disable-next-line: missing-parameter
  eq(formatter.format('x'), 'x')
  eq(seen, 'markdown')
  helpers.configure({ formatter = function() return '' end })
  eq(formatter.format('x', 'markdown'), nil)
end

T['format']['passes exactly two arguments'] = function()
  local count = nil
  helpers.configure({
    formatter = function(...)
      count = select('#', ...)
      return 'ok'
    end,
  })
  eq(require('leetcode-ui.format').format('x', 'markdown'), 'ok')
  eq(count, 2)
end

T['format']['rejects whitespace and non-string output'] = function()
  local formatter = require('leetcode-ui.format')
  helpers.configure({ formatter = function() return '  \n\n' end })
  eq(formatter.format('x', 'markdown'), nil)
  helpers.configure({ formatter = function() return 123 end })
  eq(formatter.format('x', 'markdown'), nil)
  ---@diagnostic disable-next-line: param-type-mismatch
  eq(formatter.format(123, 'markdown'), nil)
end

T['format']['normalizes line endings and trailing blank lines'] = function()
  local formatter = require('leetcode-ui.format')
  eq(formatter.normalize('a\r\nb\r\n\r\n'), 'a\nb')
  eq(formatter.normalize('a\rb'), 'a\nb')
  eq(formatter.normalize('a\n \n\t\n'), 'a')
  eq(formatter.normalize('  \n\t'), nil)
  ---@diagnostic disable-next-line: param-type-mismatch
  eq(formatter.normalize(nil), nil)
  eq(formatter.normalize('\na\n\nb'), '\na\n\nb')
end

T['format']['empty text'] = function() eq(require('leetcode-ui.format').format('', 'markdown'), nil) end

return T
