--- *LeetCodeParser*
---
---@tag LeetCodeParser

-- |leetcode-ui-parser| Question HTML content to styled buffer spans.
-- `content` HTML from the API renders to a list of lines; each line is a list
-- of `{ text, hl }` spans with highlight group names:
--   LeetCodeHeader, LeetCodeTitle (bold), LeetCodeItalic, LeetCodeCode,
--   LeetCodeLink, LeetCodeDim.
--
-- Supported markup: headings, paragraphs, nested/ordered lists, code spans and
-- blocks, links, tables, blockquotes, superscripts/subscripts (via Unicode
-- glyphs), and common HTML entities.

-- Module design:
local LeetCodeParser = {}

-- Helper data =======================================================================================================

LeetCodeParser.entities = {
  nbsp = ' ',
  lt = '<',
  gt = '>',
  amp = '&',
  quot = '"',
  apos = "'",
  bull = '•',
  mdash = '—',
  ndash = '–',
  ldquo = '“',
  rdquo = '”',
  lsquo = '‘',
  rsquo = '’',
  hellip = '…',
  plusmn = '±',
  times = '×',
  divide = '÷',
  deg = '°',
  le = '≤',
  ge = '≥',
  ne = '≠',
}

LeetCodeParser.sup_chars = {
  ['0'] = '⁰',
  ['1'] = '¹',
  ['2'] = '²',
  ['3'] = '³',
  ['4'] = '⁴',
  ['5'] = '⁵',
  ['6'] = '⁶',
  ['7'] = '⁷',
  ['8'] = '⁸',
  ['9'] = '⁹',
  ['+'] = '⁺',
  ['-'] = '⁻',
  ['='] = '⁼',
  ['('] = '⁽',
  [')'] = '⁾',
  n = 'ⁿ',
  i = 'ⁱ',
  x = 'ˣ',
}

LeetCodeParser.sub_chars = {
  ['0'] = '₀',
  ['1'] = '₁',
  ['2'] = '₂',
  ['3'] = '₃',
  ['4'] = '₄',
  ['5'] = '₅',
  ['6'] = '₆',
  ['7'] = '₇',
  ['8'] = '₈',
  ['9'] = '₉',
  ['+'] = '₊',
  ['-'] = '₋',
  ['='] = '₌',
  ['('] = '₍',
  [')'] = '₎',
  n = 'ₙ',
  i = 'ᵢ',
  x = 'ₓ',
}

-- Helper functionality ==============================================================================================

LeetCodeParser.decode_entities = function(s)
  local utf8_char = (type(utf8) == 'table' and utf8.char) or string.char
  s = s:gsub('&#x(%x+);', function(hex) return utf8_char(tonumber(hex, 16) or 0) end)
  s = s:gsub('&#(%d+);', function(dec) return utf8_char(tonumber(dec) or 0) end)
  s = s:gsub('&([%w]+);', function(name) return LeetCodeParser.entities[name] or ('&' .. name .. ';') end)
  return s
end

LeetCodeParser.encode_script = function(text, glyphs)
  local parts = {}
  for char in text:gmatch('[%w%-%+%=%(%)%%]') do
    table.insert(parts, glyphs[char] or char)
  end
  return table.concat(parts)
end

LeetCodeParser.preprocess = function(html)
  -- Strip invisible/pointless blocks.
  html = html:gsub('<%s*style[^>]->.-</%s*style%s->', '')
  html = html:gsub('<%s*script[^>]->.-</%s*script%s->', '')

  -- Unicode-ify simple superscripts/subscripts before anything else.
  html = html:gsub(
    '<sup>%s*([^<]-)%s*</sup>',
    function(text) return LeetCodeParser.encode_script(text, LeetCodeParser.sup_chars) end
  )
  html = html:gsub(
    '<sub>%s*([^<]-)%s*</sub>',
    function(text) return LeetCodeParser.encode_script(text, LeetCodeParser.sub_chars) end
  )

  -- Break markers.
  html = html:gsub('<%s*br%s*/?>', '\n')

  return html
end

LeetCodeParser.tokenize = function(html)
  local tokens = {}
  local position = 1

  while true do
    local open, close, tag, attrs = html:find('<([/%w%-]+)([^>]*)>', position)
    if open == nil then break end

    if open > position then table.insert(tokens, { text = html:sub(position, open - 1) }) end

    table.insert(tokens, { tag = tag:lower(), attrs = attrs })
    position = close + 1
  end

  if position <= #html then table.insert(tokens, { text = html:sub(position) }) end
  return tokens
end

LeetCodeParser.attr = function(attrs, name) return ((attrs or ''):match('%s*' .. name .. '%s*=%s*"([^"]*)"')) end

-- Public API ========================================================================================================

---Render question HTML into highlightable lines.
---
---@param content string|nil Question HTML (nil renders a placeholder line).
---@return table lines Each line is a list of `{ text, hl }` spans.
LeetCodeParser.render = function(content)
  if content == nil or content == '' then return { { { text = '(no description)', hl = 'LeetCodeDim' } } } end

  local tokens = LeetCodeParser.tokenize(LeetCodeParser.preprocess(content))

  local lines = {}
  local spans = {}
  local styles = {}
  local lists = {}

  local current_hl = function()
    local n = #styles
    while n > 0 and styles[n] == nil do
      n = n - 1
    end
    return n > 0 and styles[n] or nil
  end

  local push = function(text)
    if text == nil or text == '' then return end
    text = LeetCodeParser.decode_entities(text)
    if text == '' then return end
    table.insert(spans, { text = text, hl = current_hl() })
  end

  local flush = function(drop_ws)
    local visible = false
    for _, span in ipairs(spans) do
      if span.text:gsub('%s', '') ~= '' then
        visible = true
        break
      end
    end

    if visible then
      local line = {}
      for _, span in ipairs(spans) do
        table.insert(line, { text = span.text, hl = span.hl })
      end
      table.insert(lines, line)
    elseif not drop_ws and #spans > 0 then
      -- Whitespace-only content renders as a true blank line.
      table.insert(lines, {})
    end
    spans = {}
  end

  local blank = function() table.insert(lines, {}) end

  for _, token in ipairs(tokens) do
    local tag = token.tag

    if tag == nil then
      local text = token.text
      local parts = vim.split(text, '\n')
      for index, part in ipairs(parts) do
        if index > 1 then flush() end
        push(part)
      end
    elseif tag == 'pre' then
      flush()
      table.insert(styles, 'LeetCodeCode')
    elseif tag == '/pre' then
      table.remove(styles)
      flush()
      blank()
    elseif tag == 'code' then
      table.insert(styles, 'LeetCodeCode')
    elseif tag == '/code' then
      table.remove(styles)
    elseif tag == 'strong' or tag == 'b' then
      table.insert(styles, 'LeetCodeTitle')
    elseif tag == '/strong' or tag == '/b' then
      table.remove(styles)
    elseif tag == 'em' or tag == 'i' then
      table.insert(styles, 'LeetCodeItalic')
    elseif tag == '/em' or tag == '/i' then
      table.remove(styles)
    elseif tag == 'a' then
      table.insert(styles, 'LeetCodeLink')
    elseif tag == '/a' then
      table.remove(styles)
    elseif tag == 'blockquote' then
      flush()
      blank()
      table.insert(styles, 'LeetCodeDim')
    elseif tag == '/blockquote' then
      table.remove(styles)
      flush()
      blank()
    elseif tag:find('^h%d$') ~= nil then
      flush()
      blank()
      table.insert(styles, 'LeetCodeHeader')
    elseif tag:find('^/h%d$') ~= nil then
      table.remove(styles)
      flush()
      blank()
    elseif tag == 'ul' or tag == 'ol' then
      flush(true)
      table.insert(lists, { ordered = tag == 'ol', index = 0 })
    elseif tag == '/ul' or tag == '/ol' then
      flush(true)
      table.remove(lists)
    elseif tag == 'li' then
      flush(true)
      local top = lists[#lists]
      if top ~= nil then
        top.index = top.index + 1
        local indent = ('    '):rep(math.max(#lists - 1, 0))
        push(indent)
        push(top.ordered and ('%d.'):format(top.index) or '•')
        push(' ')
      end
    elseif tag == 'tr' then
      flush()
    elseif tag == 'td' or tag == 'th' then
      push('   ')
      push('|')
      push('   ')
    elseif tag == '/tr' then
      push('|')
      flush()
    elseif tag == 'img' then
      local alt = LeetCodeParser.attr(token.attrs, 'alt')
      if alt ~= nil and alt ~= '' then push('[image: ' .. alt .. ']') end
    end
    -- Unknown tags (p, div, span, font, ...) render as plain text flow.
  end

  flush()
  return lines
end

---Overall character count of rendered lines (used for pane sizing).
---
---@param lines table
---@return number
LeetCodeParser.measure = function(lines)
  local width = 0
  for _, line in ipairs(lines) do
    local chars = 0
    for _, span in ipairs(line) do
      chars = chars + vim.fn.strchars(span.text)
    end
    width = math.max(width, chars)
  end
  return width
end

return LeetCodeParser
