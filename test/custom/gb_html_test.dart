import 'package:flutter_test/flutter_test.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_html.dart';

String plain(List<GbBlock> blocks) => blocks
    .map((b) => (b.bullet ? '• ' : '') + b.spans.map((s) => s.text).join())
    .join('\n');

void main() {
  test('plain text and entities', () {
    final b = parseGbHtml(
      'Fish &amp; chips &lt;3 &quot;hi&quot; &#39;x&#39; a&nbsp;b',
    );
    expect(plain(b), 'Fish & chips <3 "hi" \'x\' a b');
  });

  test('bold, italic and links keep their style', () {
    final b = parseGbHtml(
      'Hello <b>big</b> <i>slanted</i> <a href="https://example.com/x">link</a>!',
    );
    expect(b.length, 1);
    final spans = b.single.spans;
    expect(spans.firstWhere((s) => s.text == 'big').bold, true);
    expect(spans.firstWhere((s) => s.text == 'slanted').italic, true);
    final link = spans.firstWhere((s) => s.text == 'link');
    expect(link.link, 'https://example.com/x');
    expect(spans.firstWhere((s) => s.text.startsWith('Hello')).bold, false);
  });

  test('paragraphs and line breaks make separate blocks or lines', () {
    expect(plain(parseGbHtml('<p>One</p><p>Two</p>')), 'One\nTwo');
    expect(plain(parseGbHtml('A<br>B<br/>C')), 'A\nB\nC');
  });

  test('lists become bullets', () {
    final b = parseGbHtml('<ul><li>First</li><li>Second <b>bold</b></li></ul>');
    expect(b.length, 2);
    expect(b.every((x) => x.bullet), true);
    expect(plain(b), '• First\n• Second bold');
  });

  test('headings are bold', () {
    final b = parseGbHtml('<h2>Title</h2><p>Body</p>');
    expect(b.first.spans.single.bold, true);
    expect(b.last.spans.single.bold, false);
  });

  test('unknown tags and scripts are dropped, unclosed tags do not crash', () {
    expect(
      plain(
        parseGbHtml('<script>alert(1)</script>Hi <span class="x">there</span>'),
      ),
      'Hi there',
    );
    expect(plain(parseGbHtml('<b>never closed <i>x')), 'never closed x');
    expect(plain(parseGbHtml('')), '');
  });

  test('javascript: links are not kept', () {
    final b = parseGbHtml(
      '<a href="javascript:alert(1)">bad</a> <a href="http://ok.com">ok</a>',
    );
    final spans = b.single.spans;
    expect(spans.firstWhere((s) => s.text == 'bad').link, isNull);
    expect(spans.firstWhere((s) => s.text == 'ok').link, 'http://ok.com');
  });

  test('whitespace between tags collapses', () {
    expect(plain(parseGbHtml('<p>  a \n  b  </p>\n\n<p>c</p>')), 'a b\nc');
  });
}
