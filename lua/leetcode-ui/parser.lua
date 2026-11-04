--- *leetcode-ui-parser* Question HTML content to styled buffer spans
---
--- `content` HTML from the API renders to a list of lines; each line is a
--- list of `{ text, hl }` spans with highlight group names `LeetCodeHeader`,
--- `LeetCodeTitle`, `LeetCodeItalic`, `LeetCodeCode`, `LeetCodeLink`, and
--- `LeetCodeDim`.
---
--- Supported markup: headings, paragraphs, line breaks, bold and italic text,
--- nested and ordered lists, code spans and blocks, links, tables, blockquotes,
--- images (as alt text), superscripts/subscripts (via Unicode glyphs), and
--- common HTML entities.
---@tag LeetCodeParser
---@toc_entry HTML parser

local LeetCodeParser = {}

-- Helper data =======================================================================================================

local entities = {
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

local sup_chars = {
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

local sub_chars = {
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

--- Decode named, decimal, and hexadecimal HTML entities.
---
---@param s string
---@return string
LeetCodeParser.decode_entities = function(s)
  local function decode(codepoint, fallback)
    if codepoint == 0 then return '�' end
    if codepoint == nil or codepoint < 0 or codepoint > 0x10FFFF then return fallback end
    if codepoint >= 0xD800 and codepoint <= 0xDFFF then return fallback end
    local ok, char = pcall(vim.fn.nr2char, codepoint)
    return ok and char or fallback
  end

  s = s:gsub('&(#?[%w]+);', function(entity)
    local hex = entity:match('^#[xX](%x+)$')
    if hex ~= nil then return decode(tonumber(hex, 16), '&' .. entity .. ';') end

    local dec = entity:match('^#(%d+)$')
    if dec ~= nil then return decode(tonumber(dec), '&' .. entity .. ';') end

    return entities[entity] or ('&' .. entity .. ';')
  end)
  return s
end

-- Replace simple text with Unicode superscript or subscript glyphs.
local function encode_script(text, glyphs)
  local parts = {}
  for char in text:gmatch('.') do
    if char:match('%s') ~= nil then
      table.insert(parts, ' ')
    else
      table.insert(parts, glyphs[char] or char)
    end
  end
  return table.concat(parts)
end

-- Strip invisible blocks and normalize superscripts, subscripts, and breaks.
local function preprocess(html)
  html = html:gsub('<!%-%-.-%-%->', '')

  -- Strip invisible/pointless blocks.
  html = html:gsub('<%s*style[^>]->.-</%s*style%s->', '')
  html = html:gsub('<%s*script[^>]->.-</%s*script%s->', '')

  -- Unicode-ify simple superscripts/subscripts before anything else.
  html = html:gsub('<sup>%s*([^<]-)%s*</sup>', function(text) return encode_script(text, sup_chars) end)
  html = html:gsub('<sub>%s*([^<]-)%s*</sub>', function(text) return encode_script(text, sub_chars) end)

  return html
end

-- Split HTML into text and tag tokens.
local function tokenize(html)
  local tokens = {}
  local position = 1

  while true do
    local open, close, tag, attrs = html:find('<([/%w%-]+)([^>]*)>', position)
    if open == nil then break end

    if open > position then table.insert(tokens, { text = html:sub(position, open - 1) }) end

    table.insert(tokens, { tag = tag:gsub('/$', ''):lower(), attrs = attrs })
    position = close + 1
  end

  if position <= #html then table.insert(tokens, { text = html:sub(position) }) end
  return tokens
end

-- Read an HTML attribute value.
local function attr(attrs, name)
  attrs = attrs or ''
  local prefix = '%s+' .. name .. '%s*=%s*'
  return attrs:match(prefix .. '"([^"]*)"') or attrs:match(prefix .. "'([^']*)'") or attrs:match(prefix .. '([^%s>]+)')
end

-- Public API ========================================================================================================

--- Render question HTML into highlightable lines.
---
---@param content string|nil Question HTML (nil renders a placeholder line).
---@return table lines Each line is a list of `{ text, hl }` spans.
LeetCodeParser.render = function(content)
  if content == nil or vim.trim(content) == '' then return { { { text = '(no description)', hl = 'LeetCodeDim' } } } end

  local tokens = tokenize(preprocess(content))

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

  local pre_depth = 0
  local flush

  local push = function(text)
    if text == nil or text == '' then return end
    text = LeetCodeParser.decode_entities(text)
    if text == '' then return end

    text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
    for index, part in ipairs(vim.split(text, '\n', { plain = true })) do
      if index > 1 then flush(nil, pre_depth > 0) end
      if part ~= '' then table.insert(spans, { text = part, hl = current_hl() }) end
    end
  end

  flush = function(drop_blank, keep_empty)
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
    elseif keep_empty or (not drop_blank and #spans > 0) then
      -- Whitespace-only or explicitly empty content is a true blank line.
      table.insert(lines, {})
    end
    spans = {}
  end

  local ensure_blank = function()
    if #lines > 0 and #lines[#lines] ~= 0 then table.insert(lines, {}) end
  end

  local last_was_br = false
  for _, token in ipairs(tokens) do
    local tag = token.tag

    if tag == nil then
      if token.text:gsub('%s', '') ~= '' then last_was_br = false end
      local text = token.text
      local parts = vim.split(text, '\n', { plain = true })
      for index, part in ipairs(parts) do
        if index > 1 then flush(nil, pre_depth > 0) end
        push(part)
      end
    elseif tag == 'pre' then
      flush()
      pre_depth = pre_depth + 1
      table.insert(styles, 'LeetCodeCode')
    elseif tag == '/pre' then
      table.remove(styles)
      pre_depth = math.max(0, pre_depth - 1)
      flush()
      ensure_blank()
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
      ensure_blank()
      table.insert(styles, 'LeetCodeDim')
    elseif tag == '/blockquote' then
      table.remove(styles)
      flush()
      ensure_blank()
    elseif tag:find('^h%d$') ~= nil then
      flush()
      ensure_blank()
      table.insert(styles, 'LeetCodeHeader')
    elseif tag:find('^/h%d$') ~= nil then
      table.remove(styles)
      flush()
      ensure_blank()
    elseif tag == 'ul' or tag == 'ol' then
      flush(true)
      local start = tag == 'ol' and tonumber(attr(token.attrs, 'start')) or nil
      table.insert(lists, { ordered = tag == 'ol', index = math.floor(start or 1) - 1 })
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
    elseif tag == '/p' or tag == '/div' then
      flush()
      ensure_blank()
    elseif tag == 'tr' then
      flush()
      push('|')
    elseif tag == 'td' or tag == 'th' then
      push(' ')
      if tag == 'th' then table.insert(styles, 'LeetCodeTitle') end
    elseif tag == '/th' then
      table.remove(styles)
      push(' |')
    elseif tag == '/td' then
      push(' |')
    elseif tag == '/tr' then
      flush()
    elseif tag == 'br' then
      flush()
      if last_was_br then table.insert(lines, {}) end
      last_was_br = true
    elseif tag == 'img' then
      local alt = attr(token.attrs, 'alt')
      if alt ~= nil and alt ~= '' then push('[image: ' .. alt .. ']') end
    end
    -- Other unknown tags (span, font, ...) render as plain text flow.
  end

  flush()
  while #lines > 0 and #lines[#lines] == 0 do
    table.remove(lines)
  end
  return lines
end

return LeetCodeParser
