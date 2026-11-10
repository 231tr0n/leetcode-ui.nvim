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
  rarr = '→',
  larr = '←',
  uarr = '↑',
  darr = '↓',
  harr = '↔',
  rArr = '⇒',
  lArr = '⇐',
  hArr = '⇔',
  uArr = '⇑',
  dArr = '⇓',
  crarr = '↵',
  nearr = '↗',
  nwarr = '↖',
  searr = '↘',
  swarr = '↙',
  middot = '·',
  prime = '′',
  Prime = '″',
  infin = '∞',
  sum = '∑',
  prod = '∏',
  radic = '√',
  int = '∫',
  asymp = '≈',
  equiv = '≡',
  cong = '≅',
  prop = '∝',
  forall = '∀',
  exist = '∃',
  empty = '∅',
  isin = '∈',
  notin = '∉',
  ni = '∋',
  sub = '⊂',
  sup = '⊃',
  sube = '⊆',
  supe = '⊇',
  ['and'] = '∧',
  ['or'] = '∨',
  ['not'] = '¬',
  cap = '∩',
  cup = '∪',
  there4 = '∴',
  sim = '∼',
  micro = 'µ',
  pi = 'π',
  alpha = 'α',
  beta = 'β',
  gamma = 'γ',
  delta = 'δ',
  theta = 'θ',
  lambda = 'λ',
  mu = 'μ',
  sigma = 'σ',
  phi = 'φ',
  omega = 'ω',
  Omega = 'Ω',
  Delta = 'Δ',
  ZeroWidthSpace = '',
  zwnj = '\226\128\140',
  zwj = '\226\128\141',
  ensp = ' ',
  emsp = ' ',
  thinsp = '\226\128\137',
  ['AElig'] = 'Æ',
  ['Aacute'] = 'Á',
  ['Acirc'] = 'Â',
  ['Agrave'] = 'À',
  ['Alpha'] = 'Α',
  ['Aring'] = 'Å',
  ['Atilde'] = 'Ã',
  ['Auml'] = 'Ä',
  ['Beta'] = 'Β',
  ['Ccedil'] = 'Ç',
  ['Chi'] = 'Χ',
  ['Dagger'] = '‡',
  ['ETH'] = 'Ð',
  ['Eacute'] = 'É',
  ['Ecirc'] = 'Ê',
  ['Egrave'] = 'È',
  ['Epsilon'] = 'Ε',
  ['Eta'] = 'Η',
  ['Euml'] = 'Ë',
  ['Gamma'] = 'Γ',
  ['Iacute'] = 'Í',
  ['Icirc'] = 'Î',
  ['Igrave'] = 'Ì',
  ['Iota'] = 'Ι',
  ['Iuml'] = 'Ï',
  ['Kappa'] = 'Κ',
  ['Lambda'] = 'Λ',
  ['Mu'] = 'Μ',
  ['Ntilde'] = 'Ñ',
  ['Nu'] = 'Ν',
  ['OElig'] = 'Œ',
  ['Oacute'] = 'Ó',
  ['Ocirc'] = 'Ô',
  ['Ograve'] = 'Ò',
  ['Omicron'] = 'Ο',
  ['Oslash'] = 'Ø',
  ['Otilde'] = 'Õ',
  ['Ouml'] = 'Ö',
  ['Phi'] = 'Φ',
  ['Pi'] = 'Π',
  ['Psi'] = 'Ψ',
  ['Rho'] = 'Ρ',
  ['Scaron'] = 'Š',
  ['Sigma'] = 'Σ',
  ['THORN'] = 'Þ',
  ['Tau'] = 'Τ',
  ['Theta'] = 'Θ',
  ['Uacute'] = 'Ú',
  ['Ucirc'] = 'Û',
  ['Ugrave'] = 'Ù',
  ['Upsilon'] = 'Υ',
  ['Uuml'] = 'Ü',
  ['Xi'] = 'Ξ',
  ['Yacute'] = 'Ý',
  ['Yuml'] = 'Ÿ',
  ['Zeta'] = 'Ζ',
  ['aacute'] = 'á',
  ['acirc'] = 'â',
  ['acute'] = '´',
  ['aelig'] = 'æ',
  ['agrave'] = 'à',
  ['alefsym'] = 'ℵ',
  ['ang'] = '∠',
  ['aring'] = 'å',
  ['atilde'] = 'ã',
  ['auml'] = 'ä',
  ['bdquo'] = '„',
  ['brvbar'] = '¦',
  ['ccedil'] = 'ç',
  ['cedil'] = '¸',
  ['cent'] = '¢',
  ['chi'] = 'χ',
  ['circ'] = 'ˆ',
  ['clubs'] = '♣',
  ['copy'] = '©',
  ['curren'] = '¤',
  ['dagger'] = '†',
  ['diams'] = '♦',
  ['eacute'] = 'é',
  ['ecirc'] = 'ê',
  ['egrave'] = 'è',
  ['epsilon'] = 'ε',
  ['eta'] = 'η',
  ['eth'] = 'ð',
  ['euml'] = 'ë',
  ['euro'] = '€',
  ['fnof'] = 'ƒ',
  ['frac12'] = '½',
  ['frac14'] = '¼',
  ['frac34'] = '¾',
  ['frasl'] = '⁄',
  ['hearts'] = '♥',
  ['iacute'] = 'í',
  ['icirc'] = 'î',
  ['iexcl'] = '¡',
  ['igrave'] = 'ì',
  ['image'] = 'ℑ',
  ['iota'] = 'ι',
  ['iquest'] = '¿',
  ['iuml'] = 'ï',
  ['kappa'] = 'κ',
  ['lang'] = '⟨',
  ['laquo'] = '«',
  ['lceil'] = '⌈',
  ['lfloor'] = '⌊',
  ['lowast'] = '∗',
  ['loz'] = '◊',
  ['lrm'] = '‎',
  ['lsaquo'] = '‹',
  ['macr'] = '¯',
  ['minus'] = '−',
  ['nabla'] = '∇',
  ['nsub'] = '⊄',
  ['ntilde'] = 'ñ',
  ['nu'] = 'ν',
  ['oacute'] = 'ó',
  ['ocirc'] = 'ô',
  ['oelig'] = 'œ',
  ['ograve'] = 'ò',
  ['oline'] = '‾',
  ['omicron'] = 'ο',
  ['oplus'] = '⊕',
  ['ordf'] = 'ª',
  ['ordm'] = 'º',
  ['oslash'] = 'ø',
  ['otilde'] = 'õ',
  ['otimes'] = '⊗',
  ['ouml'] = 'ö',
  ['para'] = '¶',
  ['part'] = '∂',
  ['permil'] = '‰',
  ['perp'] = '⊥',
  ['piv'] = 'ϖ',
  ['pound'] = '£',
  ['psi'] = 'ψ',
  ['rang'] = '⟩',
  ['raquo'] = '»',
  ['rceil'] = '⌉',
  ['real'] = 'ℜ',
  ['reg'] = '®',
  ['rfloor'] = '⌋',
  ['rho'] = 'ρ',
  ['rlm'] = '‏',
  ['rsaquo'] = '›',
  ['sbquo'] = '‚',
  ['scaron'] = 'š',
  ['sdot'] = '⋅',
  ['sect'] = '§',
  ['shy'] = '­',
  ['sigmaf'] = 'ς',
  ['spades'] = '♠',
  ['sup1'] = '¹',
  ['sup2'] = '²',
  ['sup3'] = '³',
  ['szlig'] = 'ß',
  ['tau'] = 'τ',
  ['thetasym'] = 'ϑ',
  ['thorn'] = 'þ',
  ['tilde'] = '˜',
  ['trade'] = '™',
  ['uacute'] = 'ú',
  ['ucirc'] = 'û',
  ['ugrave'] = 'ù',
  ['uml'] = '¨',
  ['upsih'] = 'ϒ',
  ['upsilon'] = 'υ',
  ['uuml'] = 'ü',
  ['weierp'] = '℘',
  ['xi'] = 'ξ',
  ['yacute'] = 'ý',
  ['yen'] = '¥',
  ['yuml'] = 'ÿ',
  ['zeta'] = 'ζ',
  ['AMP'] = '&',
  ['COPY'] = '©',
  ['Cedilla'] = '¸',
  ['CenterDot'] = '·',
  ['CirclePlus'] = '⊕',
  ['CircleTimes'] = '⊗',
  ['CloseCurlyDoubleQuote'] = '”',
  ['CloseCurlyQuote'] = '’',
  ['Congruent'] = '≡',
  ['Del'] = '∇',
  ['DiacriticalAcute'] = '´',
  ['DiacriticalTilde'] = '˜',
  ['Dot'] = '¨',
  ['DoubleDot'] = '¨',
  ['DoubleDownArrow'] = '⇓',
  ['DoubleLeftArrow'] = '⇐',
  ['DoubleLeftRightArrow'] = '⇔',
  ['DoubleRightArrow'] = '⇒',
  ['DoubleUpArrow'] = '⇑',
  ['DownArrow'] = '↓',
  ['Downarrow'] = '⇓',
  ['Element'] = '∈',
  ['Exists'] = '∃',
  ['ForAll'] = '∀',
  ['GT'] = '>',
  ['GreaterEqual'] = '≥',
  ['Ifr'] = 'ℑ',
  ['Im'] = 'ℑ',
  ['Implies'] = '⇒',
  ['Integral'] = '∫',
  ['LT'] = '<',
  ['LeftArrow'] = '←',
  ['LeftCeiling'] = '⌈',
  ['LeftFloor'] = '⌊',
  ['LeftRightArrow'] = '↔',
  ['Leftarrow'] = '⇐',
  ['Leftrightarrow'] = '⇔',
  ['LowerLeftArrow'] = '↙',
  ['LowerRightArrow'] = '↘',
  ['NotElement'] = '∉',
  ['NotEqual'] = '≠',
  ['OpenCurlyDoubleQuote'] = '“',
  ['OpenCurlyQuote'] = '‘',
  ['OverBar'] = '‾',
  ['PartialD'] = '∂',
  ['PlusMinus'] = '±',
  ['Product'] = '∏',
  ['Proportional'] = '∝',
  ['QUOT'] = '"',
  ['REG'] = '®',
  ['Re'] = 'ℜ',
  ['ReverseElement'] = '∋',
  ['Rfr'] = 'ℜ',
  ['RightArrow'] = '→',
  ['RightCeiling'] = '⌉',
  ['RightFloor'] = '⌋',
  ['Rightarrow'] = '⇒',
  ['ShortDownArrow'] = '↓',
  ['ShortLeftArrow'] = '←',
  ['ShortRightArrow'] = '→',
  ['ShortUpArrow'] = '↑',
  ['Sqrt'] = '√',
  ['SubsetEqual'] = '⊆',
  ['SuchThat'] = '∋',
  ['Sum'] = '∑',
  ['Superset'] = '⊃',
  ['SupersetEqual'] = '⊇',
  ['TRADE'] = '™',
  ['Therefore'] = '∴',
  ['Tilde'] = '∼',
  ['TildeFullEqual'] = '≅',
  ['TildeTilde'] = '≈',
  ['UpArrow'] = '↑',
  ['UpTee'] = '⊥',
  ['Uparrow'] = '⇑',
  ['UpperLeftArrow'] = '↖',
  ['UpperRightArrow'] = '↗',
  ['Upsi'] = 'ϒ',
  ['aleph'] = 'ℵ',
  ['angle'] = '∠',
  ['angst'] = 'Å',
  ['ap'] = '≈',
  ['approx'] = '≈',
  ['bot'] = '⊥',
  ['bottom'] = '⊥',
  ['bullet'] = '•',
  ['centerdot'] = '·',
  ['circledR'] = '®',
  ['clubsuit'] = '♣',
  ['ddagger'] = '‡',
  ['diamondsuit'] = '♦',
  ['die'] = '¨',
  ['div'] = '÷',
  ['downarrow'] = '↓',
  ['emptyset'] = '∅',
  ['emptyv'] = '∅',
  ['epsi'] = 'ε',
  ['geq'] = '≥',
  ['half'] = '½',
  ['heartsuit'] = '♥',
  ['iff'] = '⇔',
  ['imagpart'] = 'ℑ',
  ['in'] = '∈',
  ['isinv'] = '∈',
  ['ldquor'] = '„',
  ['leftarrow'] = '←',
  ['leftrightarrow'] = '↔',
  ['leq'] = '≤',
  ['lozenge'] = '◊',
  ['lsquor'] = '‚',
  ['mldr'] = '…',
  ['nearrow'] = '↗',
  ['niv'] = '∋',
  ['notinva'] = '∉',
  ['nwarrow'] = '↖',
  ['ohm'] = 'Ω',
  ['pm'] = '±',
  ['propto'] = '∝',
  ['rdquor'] = '”',
  ['realpart'] = 'ℜ',
  ['rightarrow'] = '→',
  ['rsquor'] = '’',
  ['searrow'] = '↘',
  ['sigmav'] = 'ς',
  ['slarr'] = '←',
  ['spadesuit'] = '♠',
  ['srarr'] = '→',
  ['strns'] = '¯',
  ['subset'] = '⊂',
  ['subseteq'] = '⊆',
  ['supset'] = '⊃',
  ['supseteq'] = '⊇',
  ['swarrow'] = '↙',
  ['therefore'] = '∴',
  ['thetav'] = 'ϑ',
  ['thickapprox'] = '≈',
  ['thicksim'] = '∼',
  ['thkap'] = '≈',
  ['thksim'] = '∼',
  ['uparrow'] = '↑',
  ['upsi'] = 'υ',
  ['varnothing'] = '∅',
  ['varpi'] = 'ϖ',
  ['varpropto'] = '∝',
  ['varsigma'] = 'ς',
  ['vartheta'] = 'ϑ',
  ['vee'] = '∨',
  ['vprop'] = '∝',
  ['wedge'] = '∧',
  ['wp'] = '℘',
  ['ast'] = '*',
  ['because'] = '∵',
  ['check'] = '✓',
  ['cross'] = '✗',
  ['dollar'] = '$',
  ['ell'] = 'ℓ',
  ['frac13'] = '⅓',
  ['frac15'] = '⅕',
  ['frac16'] = '⅙',
  ['frac18'] = '⅛',
  ['frac23'] = '⅔',
  ['frac25'] = '⅖',
  ['frac35'] = '⅗',
  ['frac38'] = '⅜',
  ['frac45'] = '⅘',
  ['frac56'] = '⅚',
  ['frac58'] = '⅝',
  ['frac78'] = '⅞',
  ['hbar'] = 'ℏ',
  ['horbar'] = '―',
  ['langle'] = '⟨',
  ['mapsto'] = '↦',
  ['nldr'] = '‥',
  ['num'] = '#',
  ['percnt'] = '%',
  ['rangle'] = '⟩',
  ['rightleftharpoons'] = '⇌',
  ['setminus'] = '∖',
  ['star'] = '☆',
  ['starf'] = '★',
  ['updownarrow'] = '↕',
  ['varepsilon'] = 'ϵ',
  ['varkappa'] = 'ϰ',
  ['varphi'] = 'ϕ',
  ['varrho'] = 'ϱ',
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

local invisible_chars = {
  '\226\128\139', -- U+200B zero-width space
  '\226\129\160', -- U+2060 word joiner
  '\239\187\191', -- U+FEFF byte-order mark
  '\194\173', -- U+00AD soft hyphen
}

local function strip_invisible(s)
  for _, char in ipairs(invisible_chars) do
    s = s:gsub(char, '')
  end
  return s
end

--- Remove invisible layout-control characters from text.
---
---@param s string
---@return string
LeetCodeParser.strip_invisible = function(s) return strip_invisible(s) end

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
  return strip_invisible(s)
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
  local function encode_entity_script(text, glyphs)
    local decoded = LeetCodeParser.decode_entities(text)
    decoded = decoded:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
    return encode_script(decoded, glyphs)
  end
  html = html:gsub(
    '<[sS][uU][pP]>%s*([^<]-)%s*</[sS][uU][pP]>',
    function(text) return encode_entity_script(text, sup_chars) end
  )
  html = html:gsub(
    '<[sS][uU][bB]>%s*([^<]-)%s*</[sS][uU][bB]>',
    function(text) return encode_entity_script(text, sub_chars) end
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
  local function snapshot_structure()
    return { lists = #lists, pre_depth = pre_depth, strip_pre_newline = strip_pre_newline }
  end
  local function restore_structure(snapshot)
    while #lists > snapshot.lists do
      table.remove(lists)
    end
    pre_depth = snapshot.pre_depth
    strip_pre_newline = snapshot.strip_pre_newline
  end
  local function begin_block(tag, depth)
    last_was_br = false
    local floor = styles[#styles] and styles[#styles].id or 0
    table.insert(blocks, { tag = tag, floor = floor, depth = depth, snapshot = snapshot_structure() })
  end
  local function end_block(tag, depth)
    for index = #blocks, 1, -1 do
      local block = blocks[index]
      if block.tag == tag and (depth == nil or block.depth == depth) then
        local forced = index < #blocks
        local floor = block.floor
        while #styles > 0 and styles[#styles].id > floor do
          table.remove(styles)
        end
        local removed_pre = false
        for position = #blocks, index, -1 do
          if blocks[position].tag == 'pre' then removed_pre = true end
          table.remove(blocks, position)
        end
        if forced and block.snapshot ~= nil then restore_structure(block.snapshot) end
        if removed_pre or tag == 'pre' then
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
      if LeetCodeParser.decode_entities(token.text):gsub('%s', '') ~= '' then last_was_br = false end
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
        if #lists == 0 then
          ensure_blank()
        else
          local top = lists[#lists]
          push(('    '):rep(math.max(#lists - 1, 0)) .. (' '):rep(top.marker_width or 2))
        end
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
    elseif tag == 'hr' then
      if in_container() then
        ensure_space()
      else
        flush()
        ensure_blank()
      end
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
          value = math.floor(value)
          if value >= 0 and value <= 999999999 then start = value end
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
      if not cell_open and #lists > 0 then
        local top = lists[#lists]
        push(('    '):rep(#lists - 1) .. (' '):rep(top.marker_width or 2))
      elseif not cell_open then
        ensure_blank()
      end
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
        local marker = top.ordered and ('%d.'):format(math.min(top.index, 999999999)) or '•'
        top.marker_width = (top.ordered and #marker or 1) + 1
        push(indent)
        push(marker)
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
        strip_leading = false
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

local function markdown_escape(text) return (text:gsub('([\\`*_%[%]|<>~#&!])', '\\%1')) end

--- Escape text for Markdown.
---
---@param text any
---@return string
LeetCodeParser.markdown_escape = function(text) return markdown_escape(tostring(text or '')) end

local function markdown_url(url)
  url = LeetCodeParser.decode_entities(url or '')
  return (
    url:gsub('%s', '%%20'):gsub('%(', '%%28'):gsub('%)', '%%29'):gsub('|', '%%7C'):gsub('<', '%%3C'):gsub('>', '%%3E')
  )
end

--- Convert question HTML into Markdown.
---
--- Supports the same tags as |LeetCodeParser.render()| where Markdown has an
--- equivalent representation.
---
---@param content string|nil Question HTML.
---@return string markdown
LeetCodeParser.markdown = function(content)
  if content == nil or vim.trim(content) == '' then return '_No description._' end

  local tokens = tokenize(preprocess(content))
  local lines, current, styles, blocks, lists = {}, '', {}, {}, {}
  local pre_depth, pre_text, strip_pre_newline, pre_in_table = 0, '', false, false
  local quote_depth = 0
  local quote_prefixes = {}
  local in_table, table_rows, table_row, table_cell = false, {}, nil, nil
  local list_continuation, last_was_br = nil, false

  local function current_text()
    if in_table and table_cell ~= nil then return table_cell end
    return current
  end

  local function set_current_text(value)
    if in_table and table_cell ~= nil then
      table_cell = value
    else
      current = value
    end
  end

  local function append(text)
    if in_table and table_cell ~= nil then
      table_cell = table_cell .. text
    else
      current = current .. text
    end
  end

  local function in_code()
    for index = #styles, 1, -1 do
      if styles[index].tag == 'code' then return true end
    end
    return false
  end

  local function ensure_space()
    local text = current_text()
    if text == '' or text:match('%s$') ~= nil then return end
    append(' ')
  end

  local line_prefix

  local function flush()
    local text = current:gsub('%s+$', '')
    if text ~= '' then table.insert(lines, line_prefix(text) .. text) end
    current = ''
  end

  local function blank_line()
    if quote_depth == 0 then return '' end
    local prefix = ''
    for _, indent in ipairs(quote_prefixes) do
      prefix = prefix .. indent .. '> '
    end
    return (prefix:gsub('%s+$', ''))
  end

  local function ensure_blank()
    if #lines == 0 then return end
    local last = lines[#lines]
    if last ~= '' and last:match('^[%s>]+$') == nil then table.insert(lines, blank_line()) end
  end

  local function quote_prefix_text()
    local prefix = ''
    for _, indent in ipairs(quote_prefixes) do
      prefix = prefix .. indent .. '> '
    end
    return prefix
  end

  line_prefix = function(text, always_list)
    local quote = quote_prefix_text()
    local list = ''
    local marker_line = false
    if text ~= nil then
      marker_line = text:match('^[-+]%s') ~= nil
        or text:match('^[-+]$') ~= nil
        or text:match('^%d+[.)]%s') ~= nil
        or text:match('^%d+[.)]$') ~= nil
        or text:match('^%s') ~= nil
    end
    if list_continuation ~= nil and (always_list or not marker_line) then
      if quote == '' or quote_prefixes[#quote_prefixes] ~= list_continuation then list = list_continuation end
    end
    if quote ~= '' then return quote .. list end
    return list
  end

  local function prefix_line(line) return line_prefix(nil, true) .. line end

  local function close_style(style)
    if style == nil then return end
    if style.tag == 'a' then
      append('](' .. markdown_url(style.href) .. ')')
      return
    end
    if style.tag == 'code' then
      local text = current_text()
      local code_content = text:sub(style.start):gsub('^%s+', ''):gsub('%s+$', '')
      if code_content == '' then return end
      local longest = 0
      for run in code_content:gmatch('`+') do
        longest = math.max(longest, #run)
      end
      local fence = string.rep('`', longest + 1)
      local pad = ''
      if code_content:sub(1, 1) == '`' or code_content:sub(-1) == '`' then pad = ' ' end
      set_current_text(text:sub(1, style.start - 1) .. fence .. pad .. code_content .. pad .. fence)
      return
    end
    if style.marker == nil then return end
    local text = current_text()
    local trailing = text:match('%s+$')
    if trailing ~= nil then
      text = text:sub(1, #text - #trailing)
      set_current_text(text)
    end
    if text:sub(-#style.marker) == style.marker then
      set_current_text(text:sub(1, #text - #style.marker))
    else
      append(style.marker)
    end
    if trailing ~= nil then append(trailing) end
  end

  local function push_style(style)
    local enclosing = styles[#styles]
    if enclosing ~= nil then enclosing.just_opened = false end
    style.just_opened = style.marker ~= nil
    table.insert(styles, style)
  end

  local function pop_style(tags)
    for index = #styles, 1, -1 do
      if vim.tbl_contains(tags, styles[index].tag) then
        local style = table.remove(styles, index)
        close_style(style)
        return style
      end
    end
  end

  local finish_row, render_table

  local function snapshot_structure()
    return {
      lists = #lists,
      list_continuation = list_continuation,
      quote_depth = quote_depth,
      quote_prefixes = #quote_prefixes,
      in_table = in_table,
      table_rows = table_rows,
      table_row = table_row,
      pre_depth = pre_depth,
      pre_text = pre_text,
      pre_in_table = pre_in_table,
      strip_pre_newline = strip_pre_newline,
    }
  end

  local function restore_structure(snapshot)
    while #lists > snapshot.lists do
      table.remove(lists)
    end
    list_continuation = snapshot.list_continuation
    quote_depth = snapshot.quote_depth
    while #quote_prefixes > snapshot.quote_prefixes do
      table.remove(quote_prefixes)
    end
    in_table = snapshot.in_table
    table_rows = snapshot.table_rows
    table_row = snapshot.table_row
    pre_depth = snapshot.pre_depth
    pre_text = snapshot.pre_text
    pre_in_table = snapshot.pre_in_table
    strip_pre_newline = snapshot.strip_pre_newline
  end

  local function begin_block(tag, depth)
    last_was_br = false
    table.insert(blocks, { tag = tag, floor = #styles, depth = depth, snapshot = snapshot_structure() })
  end

  local function end_block(tag, depth)
    for index = #blocks, 1, -1 do
      local block = blocks[index]
      if block.tag == tag and (depth == nil or block.depth == depth) then
        local forced = index < #blocks
        local removed_table = false
        for position = index, #blocks do
          if blocks[position].tag == 'table' then removed_table = true end
        end
        if forced and removed_table and in_table then
          if finish_row ~= nil then finish_row() end
          if render_table ~= nil then render_table() end
        end
        for position = #styles, block.floor + 1, -1 do
          close_style(table.remove(styles, position))
        end
        local removed_pre = false
        for position = #blocks, index, -1 do
          if blocks[position].tag == 'pre' then removed_pre = true end
          table.remove(blocks, position)
        end
        if forced and block.snapshot ~= nil then restore_structure(block.snapshot) end
        if removed_pre or tag == 'pre' then
          pre_depth, strip_pre_newline, pre_text, pre_in_table = 0, false, '', false
        end
        last_was_br = false
        return
      end
    end
  end

  local function inline_text(text)
    local code = in_code()
    if not code then text = text:gsub('%s+', ' ') end
    local existing = current_text()
    if code then
      if in_table then text = text:gsub('|', '\\|') end
    else
      text = markdown_escape(text)
    end
    if text:gsub('%s', '') == '' then
      if existing == '' or existing:match('%s$') ~= nil then return '' end
      return ' '
    end

    local pending = styles[#styles]
    if pending ~= nil and pending.just_opened then
      if text:match('^%s') ~= nil then
        if existing ~= '' and existing ~= pending.marker and existing:match('%s$') == nil then
          local before = existing:sub(1, #existing - #pending.marker)
          set_current_text(before .. ' ' .. pending.marker)
        end
        text = text:gsub('^%s+', '')
      end
      pending.just_opened = false
    end
    if text:match('^%s') ~= nil and (existing == '' or existing:match('%s$') ~= nil) then
      text = text:gsub('^%s+', '')
    end
    local at_line_start = existing:match('^%s*$') ~= nil
      or existing:match('^%s*[-+]%s$') ~= nil
      or existing:match('^%s*%d+[.)]%s$') ~= nil
    if at_line_start and not code then
      text = text:gsub('^([-+])%s', '\\%1 ')
      text = text:gsub('^(%d+)([.)])%s', '%1\\%2 ')
      text = text:gsub('^(%-+)$', '\\%1')
      text = text:gsub('^(=+)$', '\\%1')
      text = text:gsub('^([-+])$', '\\%1')
    end
    return text
  end

  render_table = function()
    if #table_rows == 0 then
      in_table = false
      return
    end
    local columns = 0
    for _, row in ipairs(table_rows) do
      columns = math.max(columns, #row)
    end
    local function row_line(row)
      local cells = {}
      for index = 1, columns do
        cells[index] = (row[index] or ''):gsub('[\r\n]+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
      end
      return '| ' .. table.concat(cells, ' | ') .. ' |'
    end
    table.insert(lines, prefix_line(row_line(table_rows[1])))
    local separator = {}
    for index = 1, columns do
      separator[index] = '---'
    end
    table.insert(lines, prefix_line('| ' .. table.concat(separator, ' | ') .. ' |'))
    for index = 2, #table_rows do
      table.insert(lines, prefix_line(row_line(table_rows[index])))
    end
    if #lists == 0 and quote_depth == 0 then ensure_blank() end
    in_table = false
  end

  finish_row = function()
    if table_cell ~= nil then
      table_row = table_row or {}
      table.insert(table_row, table_cell)
      table_cell = nil
    end
    if table_row ~= nil and #table_row > 0 then table.insert(table_rows, table_row) end
    table_row = nil
  end

  local function close_list_item()
    end_block('li', #lists)
    flush()
    list_continuation = nil
  end

  local function finish_pre()
    pre_depth = math.max(0, pre_depth - 1)
    local in_cell = pre_in_table
    local text = pre_text
    end_block('pre')
    if in_cell then
      if table_cell ~= nil then
        ensure_space()
        table_cell = table_cell .. inline_text(text)
        ensure_space()
      end
    else
      local fence, longest = '```', 2
      for run in text:gmatch('`+') do
        longest = math.max(longest, #run)
      end
      if longest >= 3 then fence = string.rep('`', longest + 1) end
      table.insert(lines, prefix_line(fence))
      local code = text:gsub('\n$', '')
      if code ~= '' then
        for _, line in ipairs(vim.split(code, '\n', { plain = true })) do
          table.insert(lines, prefix_line(line))
        end
      end
      table.insert(lines, prefix_line(fence))
      if #lists == 0 then ensure_blank() end
    end
    pre_text = ''
  end

  local structural_closes = {
    ['/td'] = true,
    ['/th'] = true,
    ['/tr'] = true,
    ['/table'] = true,
    ['/li'] = true,
    ['/ul'] = true,
    ['/ol'] = true,
    ['/blockquote'] = true,
    ['/p'] = true,
    ['/div'] = true,
    ['/h1'] = true,
    ['/h2'] = true,
    ['/h3'] = true,
    ['/h4'] = true,
    ['/h5'] = true,
    ['/h6'] = true,
  }

  for _, token in ipairs(tokens) do
    local tag = token.tag
    if pre_depth > 0 and tag ~= nil and tag ~= '/pre' and structural_closes[tag] then finish_pre() end

    if tag == nil then
      local raw = LeetCodeParser.decode_entities(token.text):gsub('\r\n', '\n'):gsub('\r', '\n')
      if pre_depth > 0 then
        if strip_pre_newline then
          strip_pre_newline = false
          raw = raw:gsub('^\n', '')
        end
        pre_text = pre_text .. raw
      elseif in_table then
        if table_cell ~= nil then table_cell = table_cell .. inline_text(raw) end
      else
        if raw:gsub('%s', '') ~= '' then last_was_br = false end
        append(inline_text(raw))
      end
    elseif tag == '/pre' then
      if pre_depth > 0 then finish_pre() end
    elseif pre_depth > 0 then
      if tag == 'br' then pre_text = pre_text .. '\n' end
    elseif tag == 'pre' then
      pre_in_table = in_table
      pre_depth = pre_depth + 1
      pre_text, strip_pre_newline = '', true
      if not in_table then
        flush()
        if #lists == 0 then ensure_blank() end
      end
      begin_block('pre')
    elseif tag == 'code' then
      push_style({ tag = 'code', start = #current_text() + 1 })
    elseif tag == '/code' then
      pop_style({ 'code' })
    elseif tag == 'strong' or tag == 'b' then
      append('**')
      push_style({ tag = 'strong', marker = '**' })
    elseif tag == '/strong' or tag == '/b' then
      pop_style({ 'strong' })
    elseif tag == 'em' or tag == 'i' then
      append('*')
      push_style({ tag = 'em', marker = '*' })
    elseif tag == '/em' or tag == '/i' then
      pop_style({ 'em' })
    elseif tag == 'a' then
      append('[')
      push_style({ tag = 'a', href = attr(token.attrs, 'href') })
    elseif tag == '/a' then
      pop_style({ 'a' })
    elseif tag == 'img' then
      local alt = LeetCodeParser.decode_entities(attr(token.attrs, 'alt') or ''):gsub('%s+', ' ')
      local src = attr(token.attrs, 'src')
      if src ~= nil and src ~= '' then
        append('![' .. markdown_escape(alt) .. '](' .. markdown_url(src) .. ')')
        last_was_br = false
      elseif alt ~= '' then
        append('[image: ' .. markdown_escape(alt) .. ']')
        last_was_br = false
      end
    elseif tag == 'p' or tag == 'div' then
      if in_table or #lists > 0 then
        begin_block(tag)
        ensure_space()
      else
        flush()
        ensure_blank()
        begin_block(tag)
      end
    elseif tag == '/p' or tag == '/div' then
      if in_table or #lists > 0 then
        end_block(tag:sub(2))
        ensure_space()
      else
        end_block(tag:sub(2))
        flush()
        ensure_blank()
      end
    elseif tag:find('^h%d$') ~= nil then
      if in_table or #lists > 0 then
        begin_block('heading')
        ensure_space()
        append('**')
        push_style({ tag = 'heading', marker = '**' })
      else
        flush()
        ensure_blank()
        begin_block('heading')
        local level = tonumber(tag:sub(2)) or 1
        append(string.rep('#', level) .. ' ')
      end
    elseif tag:find('^/h%d$') ~= nil then
      end_block('heading')
      if in_table or #lists > 0 then
        ensure_space()
      else
        flush()
        ensure_blank()
      end
    elseif tag == 'br' then
      if in_table or #lists > 0 then
        ensure_space()
      elseif last_was_br then
        table.insert(lines, blank_line())
        last_was_br = false
      elseif current:gsub('%s', '') ~= '' then
        current = current:gsub('%s+$', '') .. '\\'
        flush()
        last_was_br = true
      end
    elseif tag == 'ul' or tag == 'ol' then
      flush()
      ensure_blank()
      begin_block(tag)
      local parent = lists[#lists]
      local indent = parent and (parent.indent + math.max(parent.marker_width, 4)) or 0
      local start = 1
      if tag == 'ol' then
        local value = tonumber(LeetCodeParser.decode_entities(attr(token.attrs, 'start') or ''))
        if value ~= nil and value == value and value ~= math.huge and value ~= -math.huge then
          value = math.floor(value)
          if value >= 0 and value <= 999999999 then start = value end
        end
      end
      table.insert(lists, { ordered = tag == 'ol', index = start - 1, indent = indent, marker_width = 2 })
    elseif tag == '/ul' or tag == '/ol' then
      local depth = #lists
      end_block(tag:sub(2))
      if depth > 0 and #lists >= depth then table.remove(lists) end
      flush()
      list_continuation = nil
      if in_table then
        ensure_space()
      elseif #lists > 0 then
        list_continuation = string.rep(' ', lists[#lists].indent + lists[#lists].marker_width)
      else
        ensure_blank()
      end
    elseif tag == 'li' then
      close_list_item()
      if in_table then ensure_space() end
      begin_block('li', #lists)
      local top = lists[#lists]
      if top ~= nil then
        top.index = top.index + 1
        local marker = top.ordered and ('%d. '):format(math.min(top.index, 999999999)) or '- '
        top.marker_width = #marker
        append(string.rep(' ', top.indent) .. marker)
        list_continuation = string.rep(' ', top.indent + top.marker_width)
      end
    elseif tag == '/li' then
      close_list_item()
      if in_table then ensure_space() end
    elseif tag == 'blockquote' then
      if in_table then
        ensure_space()
      else
        flush()
        ensure_blank()
      end
      begin_block('blockquote')
      table.insert(quote_prefixes, list_continuation or '')
      quote_depth = quote_depth + 1
    elseif tag == '/blockquote' then
      end_block('blockquote')
      if in_table then
        ensure_space()
      else
        flush()
      end
      quote_depth = math.max(0, quote_depth - 1)
      table.remove(quote_prefixes)
      if not in_table then ensure_blank() end
    elseif tag == 'table' then
      flush()
      if #lists == 0 and quote_depth == 0 then ensure_blank() end
      begin_block('table')
      in_table, table_rows, table_row, table_cell = true, {}, nil, nil
    elseif tag == 'tr' then
      end_block('th')
      end_block('td')
      end_block('tr')
      finish_row()
      table_row = {}
    elseif tag == 'td' or tag == 'th' then
      if table_cell ~= nil then
        table_row = table_row or {}
        table.insert(table_row, table_cell)
      end
      table_row = table_row or {}
      table_cell = ''
      begin_block(tag)
    elseif tag == '/td' or tag == '/th' then
      end_block(tag:sub(2))
      if table_row ~= nil and table_cell ~= nil then table.insert(table_row, table_cell) end
      table_cell = nil
    elseif tag == '/tr' then
      end_block('th')
      end_block('td')
      end_block('tr')
      finish_row()
    elseif tag == '/table' then
      end_block('th')
      end_block('td')
      end_block('tr')
      finish_row()
      end_block('table')
      render_table()
      table_rows, table_row, table_cell = {}, nil, nil
    elseif tag == 'hr' then
      if in_table then
        ensure_space()
      else
        flush()
        if #lists == 0 and quote_depth == 0 then ensure_blank() end
        table.insert(lines, prefix_line('***'))
        if #lists == 0 and quote_depth == 0 then ensure_blank() end
      end
    end
  end

  if pre_depth > 0 then finish_pre() end
  finish_row()
  if in_table then render_table() end
  flush()
  while #lines > 0 and (lines[#lines] == '' or lines[#lines]:match('^[%s>]+$') ~= nil) do
    table.remove(lines)
  end
  return table.concat(lines, '\n')
end
return LeetCodeParser
