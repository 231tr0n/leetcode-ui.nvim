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

-- Strip invisible blocks and normalize superscripts and subscripts.
local function preprocess(html)
  html = html:gsub('<!%-%-.-%-%->', '')

  -- Strip invisible blocks.
  html = html:gsub('<%s*[sS][tT][yY][lL][eE][^>]->.-</%s*[sS][tT][yY][lL][eE]%s->', '')
  html = html:gsub('<%s*[sS][cC][rR][iI][pP][tT][^>]->.-</%s*[sS][cC][rR][iI][pP][tT]%s->', '')

  -- Unicode-ify simple superscripts/subscripts before anything else.
  html = html:gsub(
    '<[sS][uU][pP]>%s*([^<]-)%s*</[sS][uU][pP]>',
    function(text) return encode_script(text, sup_chars) end
  )
  html = html:gsub(
    '<[sS][uU][bB]>%s*([^<]-)%s*</[sS][uU][bB]>',
    function(text) return encode_script(text, sub_chars) end
  )

  return html
end

-- Split HTML into text and tag tokens.
local function tokenize(html)
  local tokens = {}
  local position = 1

  while true do
    local open = html:find('<', position, true)
    if open == nil then break end

    local closing = open + 1
    local quote = nil
    while closing <= #html do
      local char = html:sub(closing, closing)
      if quote ~= nil then
        if char == quote then quote = nil end
      elseif char == '"' or char == "'" then
        quote = char
      elseif char == '>' then
        break
      end
      closing = closing + 1
    end
    if closing > #html then break end

    local inner = html:sub(open + 1, closing - 1)
    local tag, attrs = inner:match('^([/%w%-]+)(.*)$')
    if tag == nil then
      -- A bare '<' is text, not a tag.
      table.insert(tokens, { text = html:sub(position, open) })
      position = open + 1
    else
      if open > position then table.insert(tokens, { text = html:sub(position, open - 1) }) end
      table.insert(tokens, { tag = tag:gsub('/$', ''):lower(), attrs = attrs })
      position = closing + 1
    end
  end

  if position <= #html then table.insert(tokens, { text = html:sub(position) }) end
  return tokens
end

-- Read an HTML attribute value (attribute names are case-insensitive).
local function attr(attrs, name)
  attrs = attrs or ''
  local position = 1
  while true do
    local _, name_end, raw_name = attrs:find('([%w_:%-]+)%s*=%s*', position)
    if raw_name == nil then return nil end

    local value_start = name_end + 1
    local quote = attrs:sub(value_start, value_start)
    local value, next_position
    if quote == '"' or quote == "'" then
      local close = attrs:find(quote, value_start + 1, true)
      if close == nil then return nil end
      value = attrs:sub(value_start + 1, close - 1)
      next_position = close + 1
    else
      local _, value_end = attrs:find('^[^%s>]+', value_start)
      if value_end == nil then return nil end
      value = attrs:sub(value_start, value_end)
      next_position = value_end + 1
    end

    if raw_name:lower() == name then return value end
    position = next_position
  end
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
  local cell_open = false
  local row_open = false
  local last_was_br = false
  local strip_leading = false
  local style_id = 0

  local function push_style(tag, hl)
    style_id = style_id + 1
    table.insert(styles, { tag = tag, hl = hl, id = style_id })
  end

  local function pop_style(tags)
    for index = #styles, 1, -1 do
      local style = styles[index]
      if style ~= nil and vim.tbl_contains(tags, style.tag) then
        table.remove(styles, index)
        return
      end
    end
  end

  -- Track block depth so closing a block also discards inline styles opened
  -- inside it, even if their own closing tags are missing.
  local pre_depth = 0
  local strip_pre_newline = false
  local blocks = {}
  local function begin_block(tag, depth)
    last_was_br = false
    local floor = styles[#styles] and styles[#styles].id or 0
    table.insert(blocks, { tag = tag, floor = floor, depth = depth })
  end
  local function end_block(tag, depth)
    for index = #blocks, 1, -1 do
      local block = blocks[index]
      if block.tag == tag and (depth == nil or block.depth == depth) then
        local floor = block.floor
        while #styles > 0 and styles[#styles].id > floor do
          table.remove(styles)
        end
        for position = #blocks, index, -1 do
          if blocks[position].tag == 'pre' then
            pre_depth = 0
            strip_pre_newline = false
          end
          table.remove(blocks, position)
        end
        if tag == 'pre' then
          pre_depth = 0
          strip_pre_newline = false
        end
        last_was_br = false
        return
      end
    end
  end

  local function in_container() return cell_open or #lists > 0 end

  local current_hl = function()
    local style = styles[#styles]
    return style ~= nil and style.hl or nil
  end

  local function ensure_space()
    if #spans == 0 then return end
    local last = spans[#spans]
    if last.text ~= '' and last.text:match('%s$') == nil then table.insert(spans, { text = ' ', hl = current_hl() }) end
  end

  local flush

  local function trim_trailing_spans()
    while #spans > 0 do
      local last = spans[#spans]
      last.text = last.text:gsub('%s+$', '')
      if last.text == '' then
        table.remove(spans)
      else
        break
      end
    end
  end

  local push = function(text)
    if text == nil or text == '' then return end
    text = LeetCodeParser.decode_entities(text)
    if text == '' then return end

    text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
    if cell_open or (pre_depth == 0 and #lists > 0) then
      text = text:gsub('%s*\n%s*', ' ')
      if #spans > 0 and spans[#spans].text:match('%s$') ~= nil then text = text:gsub('^ +', '') end
    end
    for index, part in ipairs(vim.split(text, '\n', { plain = true })) do
      if index > 1 then flush(pre_depth > 0) end
      if index > 1 and pre_depth == 0 then part = part:gsub('^%s+', '') end
      if part ~= '' then table.insert(spans, { text = part, hl = current_hl() }) end
    end
  end

  flush = function(keep_empty)
    if not keep_empty then trim_trailing_spans() end

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
    elseif keep_empty then
      -- Explicitly preserved empty content (used inside <pre>).
      table.insert(lines, {})
    end
    spans = {}
  end

  local ensure_blank = function()
    if #lines > 0 and #lines[#lines] ~= 0 then table.insert(lines, {}) end
  end

  for _, token in ipairs(tokens) do
    local tag = token.tag

    if tag == nil then
      if token.text:gsub('%s', '') ~= '' then last_was_br = false end
      local text = token.text:gsub('\r\n', '\n'):gsub('\r', '\n')
      if strip_pre_newline then
        strip_pre_newline = false
        text = text:gsub('^\r?\n', '')
      elseif pre_depth == 0 then
        -- Collapse source newlines in normal text while preserving a single
        -- space between adjacent inline elements.
        text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
        if text:gsub('%s', '') == '' then
          if text:find('\n') ~= nil then text = ' ' end
        else
          text = text:gsub('%s*\n%s*', ' ')
        end
        if #spans == 0 then text = text:gsub('^%s+', '') end
      end
      if pre_depth > 0 and cell_open then text = text:gsub('\r\n', '\n'):gsub('\r', '\n'):gsub('%s*\n%s*', ' ') end
      if
        pre_depth == 0
        and text ~= ''
        and #spans > 0
        and spans[#spans].text:match('%s$') ~= nil
        and text:match('^%s') ~= nil
      then
        text = text:gsub('^%s+', '')
      end
      if strip_leading and pre_depth == 0 then
        if text:gsub('%s', '') == '' then
          text = ''
        else
          text = text:gsub('^%s+', '')
          strip_leading = false
        end
      end
      local parts = vim.split(text, '\n', { plain = true })
      for index, part in ipairs(parts) do
        if index > 1 then flush(pre_depth > 0) end
        push(part)
      end
    elseif tag == 'pre' then
      if in_container() then
        ensure_space()
      else
        flush()
      end
      pre_depth = pre_depth + 1
      strip_pre_newline = true
      strip_leading = false
      begin_block('pre')
      push_style('pre', 'LeetCodeCode')
    elseif tag == '/pre' then
      local in_cell = cell_open
      end_block('pre')
      if in_cell then ensure_space() end
      if not in_cell then
        flush()
        if #lists == 0 then ensure_blank() end
      end
    elseif tag == 'code' then
      push_style('code', 'LeetCodeCode')
    elseif tag == '/code' then
      pop_style({ 'code' })
    elseif tag == 'strong' or tag == 'b' then
      push_style(tag, 'LeetCodeTitle')
    elseif tag == '/strong' or tag == '/b' then
      pop_style({ 'strong', 'b' })
    elseif tag == 'em' or tag == 'i' then
      push_style(tag, 'LeetCodeItalic')
    elseif tag == '/em' or tag == '/i' then
      pop_style({ 'em', 'i' })
    elseif tag == 'a' then
      push_style('a', 'LeetCodeLink')
    elseif tag == '/a' then
      pop_style({ 'a' })
    elseif tag == 'blockquote' then
      if in_container() then
        ensure_space()
      else
        flush()
        ensure_blank()
      end
      begin_block('blockquote')
      push_style('blockquote', 'LeetCodeDim')
    elseif tag == '/blockquote' then
      end_block('blockquote')
      if in_container() then
        ensure_space()
      else
        flush()
        ensure_blank()
      end
    elseif tag:find('^h%d$') ~= nil then
      if in_container() then
        ensure_space()
      else
        flush()
        ensure_blank()
      end
      begin_block(tag)
      push_style(tag, 'LeetCodeHeader')
    elseif tag:find('^/h%d$') ~= nil then
      end_block(tag:sub(2))
      if in_container() then
        ensure_space()
      else
        flush()
        ensure_blank()
      end
    elseif tag == 'p' or tag == 'div' then
      if in_container() then
        if tag == 'p' then end_block('p') end
        ensure_space()
        begin_block(tag)
      else
        if tag == 'p' then end_block('p') end
        flush()
        begin_block(tag)
      end
    elseif tag == 'ul' or tag == 'ol' then
      if cell_open then
        ensure_space()
      else
        flush()
      end
      begin_block(tag)
      local start
      if tag == 'ol' then
        local raw = LeetCodeParser.decode_entities(attr(token.attrs, 'start') or '')
        local value = tonumber(raw)
        if value ~= nil and value == value and value ~= math.huge and value ~= -math.huge then
          start = math.floor(value)
        end
      end
      table.insert(lists, { ordered = tag == 'ol', index = (start or 1) - 1 })
    elseif tag == '/ul' or tag == '/ol' then
      end_block('li', #lists)
      end_block(tag:sub(2))
      if cell_open then
        ensure_space()
      else
        flush()
      end
      table.remove(lists)
      if not cell_open and #lists == 0 then ensure_blank() end
    elseif tag == 'li' then
      end_block('li', #lists)
      if cell_open then
        ensure_space()
      else
        flush()
      end
      begin_block('li', #lists)
      local top = lists[#lists]
      if top ~= nil then
        top.index = top.index + 1
        local indent = ('    '):rep(math.max(#lists - 1, 0))
        push(indent)
        push(top.ordered and ('%d.'):format(top.index) or '•')
        push(' ')
        strip_leading = true
      end
    elseif tag == '/li' then
      end_block('li', #lists)
      if cell_open then
        ensure_space()
      else
        flush()
      end
    elseif tag == '/p' or tag == '/div' then
      if in_container() then
        end_block(tag:sub(2))
        ensure_space()
      else
        end_block(tag:sub(2))
        flush()
        ensure_blank()
      end
    elseif tag == 'table' then
      if in_container() then
        ensure_space()
      else
        flush()
      end
      begin_block('table')
    elseif tag == 'tr' then
      end_block('th')
      end_block('td')
      end_block('tr')
      if cell_open then
        push(' |')
        cell_open = false
      end
      if in_container() then
        ensure_space()
      else
        flush()
      end
      begin_block('tr')
      row_open = true
    elseif tag == 'td' or tag == 'th' then
      end_block('th')
      end_block('td')
      if row_open then
        if not in_container() then trim_trailing_spans() end
        push('|')
        row_open = false
      end
      if cell_open then push(' |') end
      trim_trailing_spans()
      push(' ')
      begin_block(tag)
      cell_open = true
      strip_leading = true
      if tag == 'th' then push_style('th', 'LeetCodeTitle') end
    elseif tag == '/th' then
      end_block('th')
      trim_trailing_spans()
      if cell_open then
        push(' |')
        cell_open = false
      end
    elseif tag == '/td' then
      end_block('td')
      trim_trailing_spans()
      if cell_open then
        push(' |')
        cell_open = false
      end
    elseif tag == '/tr' then
      end_block('th')
      end_block('td')
      end_block('tr')
      row_open = false
      trim_trailing_spans()
      if cell_open then
        push(' |')
        cell_open = false
      end
      if in_container() then
        ensure_space()
      else
        flush()
      end
    elseif tag == '/table' then
      end_block('th')
      end_block('td')
      end_block('tr')
      end_block('table')
      row_open = false
      trim_trailing_spans()
      if cell_open then
        push(' |')
        cell_open = false
      end
      if in_container() then
        ensure_space()
      else
        flush()
        ensure_blank()
      end
    elseif tag == 'br' then
      if cell_open then
        ensure_space()
        strip_leading = true
      elseif #lists > 0 and pre_depth == 0 then
        ensure_space()
        strip_leading = true
      else
        flush()
        if last_was_br then table.insert(lines, {}) end
        last_was_br = true
      end
    elseif tag == 'img' then
      local alt = attr(token.attrs, 'alt')
      if alt ~= nil and alt ~= '' then
        push('[image: ' .. alt .. ']')
        last_was_br = false
      end
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
