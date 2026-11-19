// GameBanana tab — turns a mod description (HTML) into styled blocks of text.
// No Flutter here, so it is unit tested. It understands only what descriptions
// really use: bold, italic, links, headings, paragraphs, line breaks and lists.
// Everything else is dropped, and only http(s) links are kept.

class GbSpan {
  final String text;
  final bool bold;
  final bool italic;
  final String? link;
  const GbSpan(this.text, {this.bold = false, this.italic = false, this.link});
}

class GbBlock {
  final bool bullet;
  final List<GbSpan> spans;
  const GbBlock({required this.bullet, required this.spans});
}

final _tag = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>|([^<]+)|<');
final _href = RegExp(r'''href\s*=\s*["']([^"']*)["']''', caseSensitive: false);

List<GbBlock> parseGbHtml(String html) {
  final cleaned = html.replaceAll(
    RegExp(
      r'<(script|style)[^>]*>.*?</\1>',
      caseSensitive: false,
      dotAll: true,
    ),
    '',
  );

  final blocks = <GbBlock>[];
  var spans = <GbSpan>[];
  var bullet = false;
  var bold = 0;
  var italic = 0;
  final links = <String?>[];

  void flush() {
    // Trim the outer whitespace of the block, then drop empty pieces.
    if (spans.isNotEmpty) {
      final first = spans.first;
      spans[0] = GbSpan(
        first.text.trimLeft(),
        bold: first.bold,
        italic: first.italic,
        link: first.link,
      );
      final last = spans.last;
      spans[spans.length - 1] = GbSpan(
        last.text.trimRight(),
        bold: last.bold,
        italic: last.italic,
        link: last.link,
      );
    }
    final kept = [
      for (final s in spans)
        if (s.text.isNotEmpty) s,
    ];
    if (kept.isNotEmpty) blocks.add(GbBlock(bullet: bullet, spans: kept));
    spans = [];
    bullet = false;
  }

  for (final m in _tag.allMatches(cleaned)) {
    final text = m.group(4);
    if (text != null) {
      final collapsed = text.replaceAll(RegExp(r'\s+'), ' ');
      if (collapsed == ' ' && spans.isEmpty) continue;
      spans.add(
        GbSpan(
          _decode(collapsed),
          bold: bold > 0,
          italic: italic > 0,
          link: links.isEmpty ? null : links.last,
        ),
      );
      continue;
    }
    final name = m.group(2)?.toLowerCase();
    if (name == null) continue; // a stray "<"
    final closing = m.group(1) == '/';

    switch (name) {
      case 'b' || 'strong':
        closing ? bold = (bold - 1).clamp(0, 99) : bold++;
      case 'i' || 'em':
        closing ? italic = (italic - 1).clamp(0, 99) : italic++;
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        flush();
        closing ? bold = (bold - 1).clamp(0, 99) : bold++;
      case 'a':
        if (closing) {
          if (links.isNotEmpty) links.removeLast();
        } else {
          final href = _href.firstMatch(m.group(3) ?? '')?.group(1);
          final ok =
              href != null &&
              RegExp(r'^https?://', caseSensitive: false).hasMatch(href);
          links.add(ok ? _decode(href) : null);
        }
      case 'li':
        flush();
        if (!closing) bullet = true;
      case 'br' ||
          'p' ||
          'div' ||
          'ul' ||
          'ol' ||
          'tr' ||
          'table' ||
          'blockquote':
        flush();
      default:
        break; // span, img, font, u, ... : keep the text, ignore the tag
    }
  }
  flush();
  return blocks;
}

String _decode(String s) =>
    s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x')) {
        return String.fromCharCode(int.parse(e.substring(2), radix: 16));
      }
      if (e.startsWith('#')) {
        return String.fromCharCode(int.parse(e.substring(1)));
      }
      return switch (e) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        'nbsp' => ' ',
        _ => m.group(0)!,
      };
    });
