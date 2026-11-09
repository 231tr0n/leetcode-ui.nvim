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

T['inline styles']['quoted attributes may contain greater-than signs'] = function()
  local lines = render('<p><a href="x" title="a > b">link</a></p>')
  eq(text_of(lines), { 'link' })
  eq(spans_with_hl(lines, 'LeetCodeLink'), { 'link' })
end

T['inline styles']['inline space between tags is preserved'] = function()
  local lines = text_of(render('<p><strong>Input:</strong> <code>nums</code></p>'))
  eq(lines[1], 'Input: nums')
end

T['inline styles']['inline whitespace across source newlines stays a space'] = function()
  eq(text_of(render('<p><strong>hello</strong>\n<strong>world</strong></p>')), { 'hello world' })
  eq(text_of(render('<p><code>a</code>\n<code>b</code></p>')), { 'a b' })
end

T['inline styles']['adjacent whitespace across tags is collapsed'] = function()
  eq(text_of(render('<p>a <strong> b</strong></p>')), { 'a b' })
end

T['blocks'] = new_set()

T['blocks']['paragraphs stay on separate lines with a blank separator'] = function()
  eq(text_of(render('<p>one</p><p>two</p>')), { 'one', '', 'two' })
  eq(text_of(render('<div>one</div><div>two</div>')), { 'one', '', 'two' })
end

T['blocks']['paragraph tags inside cells and list items stay inline'] = function()
  eq(text_of(render('<table><tr><td><p>a</p></td><td>b</td></tr></table>')), { '| a | b |' })
  eq(text_of(render('<ul><li><p>a</p><p>b</p></li><li>c</li></ul>')), { '• a b', '• c' })
end

T['blocks']['container paragraphs still scope inline styles'] = function()
  local list = render('<ul><li><p><strong>a</p><p>b</p></li></ul>')
  eq(spans_with_hl(list, 'LeetCodeTitle'), { 'a' })

  local table_lines = render('<table><tr><td><p><strong>a</p><p>b</p></td></tr></table>')
  eq(spans_with_hl(table_lines, 'LeetCodeTitle'), { 'a' })
end

T['blocks']['lists and headings inside cells stay on the row'] = function()
  eq(
    text_of(render('<table><tr><td><ul><li>a</li><li>b</li></ul></td><td>c</td></tr></table>')),
    { '| • a • b | c |' }
  )
  eq(text_of(render('<table><tr><td><h3>h</h3><blockquote>q</blockquote></td></tr></table>')), { '| h q |' })
end

T['blocks']['block elements inside list items stay with the marker'] = function()
  eq(text_of(render('<ul><li><h3>head</h3>body</li><li>next</li></ul>')), { '• head body', '• next' })
  eq(text_of(render('<ul><li>a<table><tr><td>b</td></tr></table></li><li>c</li></ul>')), { '• a | b |', '• c' })
end

T['blocks']['br tags break lines'] = function()
  eq(text_of(render('<p>one<br>two</p>')), { 'one', 'two' })
  eq(text_of(render('<p>one<br/>two</p>')), { 'one', 'two' })
end

T['blocks']['pre blocks preserve blank lines'] = function()
  local lines = text_of(render('<pre>a\n\nb</pre>'))
  eq(lines, { 'a', '', 'b' })
end

T['blocks']['pre drops the decorative newline after the opening tag'] = function()
  eq(text_of(render('<pre>\ncode</pre>')), { 'code' })
  eq(text_of(render('<pre>\r\ncode</pre>')), { 'code' })
end

T['blocks']['pre preserves CRLF content without extra blank lines'] = function()
  eq(text_of(render('<pre>a\r\nb</pre>')), { 'a', 'b' })
  eq(text_of(render('<pre>a\r\n\r\nb</pre>')), { 'a', '', 'b' })
end

T['blocks']['pre inside containers keeps indentation and rows intact'] = function()
  eq(text_of(render('<ul><li><pre>\n  a\n    b</pre></li></ul>')), { '•   a', '    b' })
  eq(text_of(render('<table><tr><td><pre>\n  a\n    b</pre></td></tr></table>')), { '| a b |' })
end

T['blocks']['pre inside containers is separated from adjacent text'] = function()
  eq(text_of(render('<ul><li><strong>Example:</strong><pre>x = 1</pre></li></ul>')), { '• Example: x = 1' })
  eq(text_of(render('<table><tr><td><strong>Input</strong><pre>x = 1</pre></td></tr></table>')), { '| Input x = 1 |' })
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

T['lists']['indented item contents use one padding space'] = function()
  eq(text_of(render('<ul>\n  <li>\n    item\n  </li>\n</ul>')), { '• item' })
end

T['lists']['line breaks inside list items stay with the marker'] = function()
  eq(text_of(render('<ul><li>a<br>b</li></ul>')), { '• a b' })
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
  eq(text_of(render('<ol START="3"><li>a</li></ol>'))[1], '3. a')
  eq(text_of(render('<ol start="&#51;"><li>a</li></ol>'))[1], '3. a')
  eq(text_of(render('<ol start="2.7"><li>a</li></ol>'))[1], '2. a')
  eq(text_of(render('<ol start="1e400"><li>a</li></ol>'))[1], '1. a')
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

T['tables and images']['indented table markup does not add blank lines'] = function()
  local lines = text_of(render('<table>\n  <tr><td>a</td></tr>\n  <tr><td>b</td></tr>\n</table>'))
  eq(lines, { '| a |', '| b |' })
end

T['tables and images']['indented cells use single padding spaces'] = function()
  local lines = text_of(render('<table>\n  <tr>\n    <th>Input</th>\n    <td>Output</td>\n  </tr>\n</table>'))
  eq(lines, { '| Input | Output |' })
end

T['tables and images']['line breaks inside cells stay on the row'] = function()
  eq(text_of(render('<table><tr><td>a<br>b</td><td>c</td></tr></table>')), { '| a b | c |' })
end

T['tables and images']['indented cell contents use one padding space'] = function()
  eq(text_of(render('<table>\n  <tr>\n    <td>\n      Hello\n    </td>\n  </tr>\n</table>')), { '| Hello |' })
end

T['tables and images']['text and breaks in cells do not double padding'] = function()
  eq(text_of(render('<table><tr><td>a<br>b</td></tr></table>')), { '| a b |' })
  eq(text_of(render('<table><tr><td><br>b</td></tr></table>')), { '| b |' })
  eq(text_of(render('<table><tr><td><pre>a</pre> b</td></tr></table>')), { '| a b |' })
end

T['tables and images']['table cells close implicit header styles'] = function()
  local lines = render('<table><tr><th>h<td>x</td></tr><tr><td>y</td></tr></table>')
  eq(text_of(lines), { '| h | x |', '| y |' })
  eq(spans_with_hl(lines, 'LeetCodeTitle'), { 'h' })
end

T['tables and images']['tables are separated from following prose'] = function()
  eq(text_of(render('<table><tr><td>a</td></tr></table><p>after</p>')), { '| a |', '', 'after' })
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
  eq(text_of(render('<p><img alt="a > b"/></p>'))[1], '[image: a > b]')
  eq(text_of(render('<p><img ALT="case"/></p>'))[1], '[image: case]')
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

T['robustness']['newline entities stay inside cells and list items'] = function()
  eq(text_of(render('<table><tr><td>a&#10;b</td><td>c</td></tr></table>')), { '| a b | c |' })
  eq(text_of(render('<ul><li>a&#10;b</li></ul>')), { '• a b' })
  eq(text_of(render('<table><tr><td>&#10;X</td><td>Y</td></tr></table>')), { '| X | Y |' })
  eq(text_of(render('<ul><li>&#10;X</li></ul>')), { '• X' })
end

T['robustness']['literal less-than signs are preserved'] = function()
  eq(text_of(render('<p>1 < 2 > 1</p>')), { '1 < 2 > 1' })
  eq(text_of(render('<p>a < b</p>')), { 'a < b' })
end

T['robustness']['image text clears consecutive break state'] = function()
  eq(text_of(render('<p>a<br><img alt="x"><br>b</p>')), { 'a', '[image: x]', 'b' })
end

T['robustness']['empty table rows are skipped'] = function()
  eq(text_of(render('<table><tr><td>a</td></tr><tr></tr><tr><td>b</td></tr></table>')), { '| a |', '| b |' })
end

T['robustness']['source newlines in normal text collapse to spaces'] = function()
  eq(text_of(render('<p>hello\nworld</p>')), { 'hello world' })
  eq(text_of(render('<p>hello\n  world</p>')), { 'hello world' })
end

T['robustness']['line boundaries do not keep stray spaces'] = function()
  eq(text_of(render('<p>a<br>\n  b</p>')), { 'a', 'b' })
  eq(text_of(render('<p>a </p><p>b</p>')), { 'a', '', 'b' })
end

T['robustness']['unbalanced inline tags do not leak styles'] = function()
  local lines = render('<p><strong><em>x</strong>y</em>z</p>')
  eq(table.concat(text_of(lines), ''), 'xyz')
  eq(spans_with_hl(lines, 'LeetCodeTitle'), {})
end

T['robustness']['block closes drop inline styles opened inside them'] = function()
  local lines = render('<pre><strong>a</pre>b')
  eq(table.concat(text_of(lines), ''), 'ab')
  eq(spans_with_hl(lines, 'LeetCodeTitle'), { 'a' })
  eq(spans_with_hl(lines, 'LeetCodeCode'), {})
end

T['robustness']['paragraphs and list items drop unclosed inline styles'] = function()
  local paragraph = render('<p><strong>a</p><p>b</p>')
  eq(table.concat(text_of(paragraph), ''), 'ab')
  eq(spans_with_hl(paragraph, 'LeetCodeTitle'), { 'a' })

  local list = render('<ul><li><strong>a</li><li>b</li></ul>')
  eq(table.concat(text_of(list), ''), '• a• b')
  eq(spans_with_hl(list, 'LeetCodeTitle'), { 'a' })
end

T['robustness']['table rows drop unclosed inline styles'] = function()
  local lines = render('<table><tr><td><strong>a</td></tr><tr><td>b</td></tr></table>')
  eq(table.concat(text_of(lines), ''), '| a || b |')
  eq(spans_with_hl(lines, 'LeetCodeTitle'), { 'a' })
end

T['robustness']['nested lists keep their style scope'] = function()
  local lines = render('<ul><li>a<ul><li>b</li></ul><strong>c</li></ul><p>d</p>')
  eq(spans_with_hl(lines, 'LeetCodeTitle'), { 'c' })
end

T['robustness']['unclosed pre blocks do not corrupt following table rows'] = function()
  local lines = render('<table>\n<tr><td><pre>a</td><td>b</td></tr>\n<tr><td>c</td></tr></table>')
  eq(text_of(lines), { '| a | b |', '| c |' })
end

T['robustness']['tabs at line boundaries are trimmed'] = function()
  eq(text_of(render('<p>a</p>\t<p>b</p>')), { 'a', '', 'b' })
  eq(text_of(render('<p>a<br>\t b</p>')), { 'a', 'b' })
end

T['robustness']['break state resets between paragraphs'] = function()
  eq(text_of(render('<p>a<br></p><p><br>x</p>')), { 'a', '', 'x' })
end

T['robustness']['out-of-order inline closes do not leak inner styles'] = function()
  local lines = render('<em><p><strong>x</em></p>y')
  eq(table.concat(text_of(lines), '\n'), 'x\n\ny')
  eq(spans_with_hl(lines, 'LeetCodeTitle'), { 'x' })
  eq(spans_with_hl(lines, 'LeetCodeItalic'), {})
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

T['robustness']['superscript tags are case-insensitive'] = function()
  eq(text_of(render('<p>x<SUP>2</SUP></p>')), { 'x²' })
end

T['robustness']['style and script blocks dropped'] = function()
  local lines = text_of(render('<style>.x{color:red}</style><p>ok</p><script>var a=1;</script>'))
  eq(table.concat(lines, ''), 'ok')
  eq(text_of(render('<STYLE>.x{color:red}</STYLE><p>ok</p>')), { 'ok' })
  eq(text_of(render('<SCRIPT>var a=1;</SCRIPT><p>ok</p>')), { 'ok' })
end

T['real content'] = new_set()

T['real content']['two-sum fixture renders sanely'] = function()
  -- Raw HTML capture; only the `content` field is consumed here.
  local dir = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
  local path = vim.fs.joinpath(dir, 'fixtures', 'two-sum.json')
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
