--- *leetcode-ui-format* Generic formatting entry point
---
--- Every formatting path calls `LeetCodeFormat.format(text, filetype)`. The
--- function is supplied by the user through `formatter` in |LeetCode.setup()|
--- and returns formatted text or nil.
---
--- Callers fall back to their built-in behavior when the formatter returns nil:
--- the LeetCode API for code, or the original text for read-only content.
---@tag LeetCodeFormat
---@toc_entry Formatting

local LeetCodeFormat = {}

local config = require('leetcode-ui.config')
local log = require('leetcode-ui.log')

-- Public API ========================================================================================================

--- Normalize formatter output: LF line endings and no trailing blank lines.
---@private
---@param text string
---@return string|nil
LeetCodeFormat.normalize = function(text)
  if type(text) ~= 'string' then return nil end
  text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
  local lines = vim.split(text, '\n', { plain = true })
  while #lines > 0 and lines[#lines]:match('^%s*$') do
    table.remove(lines)
  end
  text = table.concat(lines, '\n')
  if not text:match('%S') then return nil end
  return text
end

--- Format text using the configured formatter.
---
--- The formatter receives `(text, filetype)` and returns formatted text or nil.
---
---@param text string
---@param filetype string
---@return string|nil
LeetCodeFormat.format = function(text, filetype)
  if type(text) ~= 'string' or text == '' then return nil end
  local formatter = config.config.formatter
  if type(formatter) ~= 'function' then return nil end
  local ok, result = pcall(formatter, text, filetype or 'markdown')
  if not ok then
    log.warn('Formatter failed: ' .. tostring(result))
    return nil
  end
  return LeetCodeFormat.normalize(result)
end

return LeetCodeFormat
