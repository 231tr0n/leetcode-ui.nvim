-- Tests for leetcode-ui.parser (HTML -> styled spans).

local helpers = dofile('tests/helpers.lua')
local eq = helpers.eq
local new_set = helpers.new_set

local T = new_set()

local render = function(html) return helpers.mod('parser').render(html) end

local text_of = function(lines) return helpers.mod('buffer').spans_to_texts(lines) end

--- Find spans by highlight group across all lines.
local spans_with_hl = function(lines, hl)
  local out = {}
  for _, line in ipairs(lines) do
    for _, span in ipairs(line) do
      if span.hl == hl then table.insert(out, span.text) end
    end
  end
  return out
end

T['entities'] = new_set()

T['entities']['named entities'] = function()
  eq(helpers.mod('parser').decode_entities('&lt;p&gt; &amp; &quot;x&quot; &nbsp;'), '<p> & "x"  ')
end

T['entities']['decimal and hex entities'] = function()
  local parser = helpers.mod('parser')
  eq(parser.decode_entities('&#65;&#x42;&#67;'), 'ABC')
  eq(parser.decode_entities('&#8804;'), '≤')
  eq(parser.decode_entities('&#x110000;'), '&#x110000;')
  eq(parser.decode_entities('&#0;'), '�')
end

T['entities']['unknown entities are kept verbatim'] = function()
  eq(helpers.mod('parser').decode_entities('&unknown; &amp;'), '&unknown; &')
end

T['entities']['entities are decoded in a single pass'] = function()
  local parser = helpers.mod('parser')
  eq(parser.decode_entities('&#38;lt;'), '&lt;')
  eq(parser.decode_entities('&amp;#65;'), '&#65;')
  eq(parser.decode_entities('&#x26;lt;'), '&lt;')
  eq(parser.decode_entities('&#X41;'), 'A')
end

T['superscript'] = new_set()

T['superscript']['digits become unicode glyphs'] = function()
  local lines = text_of(render('<p>10<sup>4</sup> and x<sub>i</sub></p>'))
  eq(lines[1], '10⁴ and xᵢ')
end

T['superscript']['exponent expressions'] = function()
  local lines = text_of(render('<p>2<sup>n-1</sup></p>'))
  eq(lines[1], '2ⁿ⁻¹')
end

T['superscript']['unsupported characters are preserved'] = function()
  eq(text_of(render('<p>2<sup>2.5</sup></p>'))[1], '2².⁵')
end

T['superscript']['spaces are preserved'] = function()
  local text = text_of(render('<p>x<sup>a b</sup></p>'))[1]
  eq(text, 'xa b')
end

T['inline styles'] = new_set()

T['inline styles']['strong/em/code map to groups'] = function()
  local lines = render('<p>a <strong>b</strong> <em>c</em> <code>d</code></p>')
  eq(spans_with_hl(lines, 'LeetCodeTitle'), { 'b' })
  eq(spans_with_hl(lines, 'LeetCodeItalic'), { 'c' })
  eq(spans_with_hl(lines, 'LeetCodeCode'), { 'd' })
end

T['inline styles']['links become LeetCodeLink'] = function()
  local lines = render('<p><a href="https://example.com">site</a></p>')
  eq(spans_with_hl(lines, 'LeetCodeLink'), { 'site' })
end

T['inline styles']['inline space between tags is preserved'] = function()
  local lines = text_of(render('<p><strong>Input:</strong> <code>nums</code></p>'))
  eq(lines[1], 'Input: nums')
end

T['blocks'] = new_set()

T['blocks']['paragraphs stay on separate lines with a blank separator'] = function()
  eq(text_of(render('<p>one</p><p>two</p>')), { 'one', '', 'two' })
  eq(text_of(render('<div>one</div><div>two</div>')), { 'one', '', 'two' })
end

T['blocks']['br tags break lines'] = function()
  eq(text_of(render('<p>one<br>two</p>')), { 'one', 'two' })
  eq(text_of(render('<p>one<br/>two</p>')), { 'one', 'two' })
end

T['blocks']['pre blocks preserve blank lines'] = function()
  local lines = text_of(render('<pre>a\n\nb</pre>'))
  eq(lines, { 'a', '', 'b' })
end

T['blocks']['pre block code highlighting'] = function()
  local lines = render('<pre>Input: x = 1\nOutput: 2</pre>')
  local code = spans_with_hl(lines, 'LeetCodeCode')
  eq(#code > 0, true)
  eq(helpers.contains(table.concat(code), 'Input: x = 1'), true)
end

T['blocks']['blockquote becomes dim'] = function()
  local lines = render('<blockquote><p>note</p></blockquote>')
  eq(spans_with_hl(lines, 'LeetCodeDim'), { 'note' })
end

T['blocks']['headings become header group'] = function()
  local lines = render('<h3>Title</h3>')
  eq(spans_with_hl(lines, 'LeetCodeHeader'), { 'Title' })
end

T['lists'] = new_set()

T['lists']['unordered list bullets'] = function()
  local lines = text_of(render('<ul>\n<li>a</li>\n<li>b</li>\n</ul>'))
  eq(lines[1], '• a')
  eq(lines[2], '• b')
  eq(#lines, 2)
end

T['lists']['ordered list numbering'] = function()
  local lines = text_of(render('<ol><li>a</li><li>b</li></ol>'))
  eq(lines[1], '1. a')
  eq(lines[2], '2. b')
end

T['lists']['ordered lists honour the start attribute'] = function()
  local lines = text_of(render('<ol start="3"><li>a</li><li>b</li></ol>'))
  eq(lines[1], '3. a')
  eq(lines[2], '4. b')
end

T['lists']['nested indentation'] = function()
  local lines = text_of(render('<ul><li>a<ul><li>b</li></ul></li></ul>'))
  eq(lines[1], '• a')
  eq(lines[2], '    • b')
end

T['tables and images'] = new_set()

T['tables and images']['table cells separated by pipes'] = function()
  local lines = text_of(render('<table><tr><td>a</td><td>b</td></tr></table>'))
  eq(lines[1], '| a | b |')
end

T['tables and images']['header cells use the title highlight'] = function()
  local lines = render('<table><tr><th>head</th><td>cell</td></tr></table>')
  eq(text_of(lines)[1], '| head | cell |')
  eq(lines[1][3].text, 'head')
  eq(lines[1][3].hl, 'LeetCodeTitle')
end

T['tables and images']['image alt entities are decoded once'] = function()
  eq(text_of(render('<p><img alt="&amp;lt;"/></p>'))[1], '[image: &lt;]')
end

T['tables and images']['image alt text rendered'] = function()
  local lines = text_of(render('<p><img src="x.png" alt="diagram"/></p>'))
  eq(lines[1], '[image: diagram]')

  eq(text_of(render("<p><img alt='single'/></p>"))[1], '[image: single]')
  eq(text_of(render('<p><img alt=unquoted></p>'))[1], '[image: unquoted]')
  eq(text_of(render('<p><img data-alt="wrong" alt="right"/></p>'))[1], '[image: right]')
  eq(text_of(render('<p><img alt="a&amp;b"/></p>'))[1], '[image: a&b]')
  eq(text_of(render('<p>a<img alt=""/>b</p>'))[1], 'ab')
end

T['robustness'] = new_set()

T['robustness']['consecutive breaks create blank lines'] = function()
  eq(text_of(render('<p>a<br>b</p>')), { 'a', 'b' })
  eq(text_of(render('<p>a<br><br>b</p>')), { 'a', '', 'b' })
end

T['robustness']['ordered lists honour a zero start'] = function()
  local lines = text_of(render('<ol start="0"><li>a</li><li>b</li></ol>'))
  eq(lines, { '0. a', '1. b' })
end

T['robustness']['newline entities become line breaks'] = function()
  eq(text_of(render('<p>line&#10;two</p>')), { 'line', 'two' })
  eq(text_of(render('<pre>a&#10;&#10;b</pre>')), { 'a', '', 'b' })
end

T['robustness']['nil and whitespace content use the placeholder'] = function()
  eq(render(nil)[1][1].text, '(no description)')
  eq(render('   \n\t')[1][1].text, '(no description)')
end

T['robustness']['no raw tags leak into text'] = function()
  local html = '<div><p>a</p><ul><li>b</li></ul><pre>c</pre><span>d</span></div>'
  for _, line in ipairs(text_of(render(html))) do
    eq(line:find('</?%a'), nil, 'leaked tag in: ' .. line)
    eq(line:find('<!%-%-', 1, false), nil, 'leaked comment in: ' .. line)
  end
end

T['robustness']['no whitespace-only noise lines between list items'] = function()
  local lines = text_of(render('<ul>\n\t<li>a</li>\n\t<li>b</li>\n</ul>'))
  eq(#lines, 2)
end

T['robustness']['HTML comments are dropped'] = function()
  eq(text_of(render('<!-- <p>hidden</p> --><p>visible</p>')), { 'visible' })
end

T['robustness']['style and script blocks dropped'] = function()
  local lines = text_of(render('<style>.x{color:red}</style><p>ok</p><script>var a=1;</script>'))
  eq(table.concat(lines, ''), 'ok')
end

T['real content'] = new_set()

T['real content']['two-sum fixture renders sanely'] = function()
  -- Raw HTML capture; only the `content` field is consumed here.
  local path = 'tests/fixtures/two-sum.json'
  local data = vim.json.decode(table.concat(vim.fn.readfile(path), '\n')).data.question
  local lines = render(data.content)
  local texts = text_of(lines)
  eq(#texts > 20, true)
  eq(helpers.contains(texts[1], 'two numbers'), true)
  -- Constraints bullets present, superscripts converted.
  local joined = table.concat(texts, '\n')
  eq(helpers.contains(joined, '10⁴'), true)
  eq(helpers.contains(joined, '• Only one valid answer exists.'), true)
end

return T
