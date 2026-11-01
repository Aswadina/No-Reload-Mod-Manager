import 'dart:io';

import 'package:path/path.dart' as p;

// A literal "\n" or "\r" only counts as a separator when a new path starts right
// after it. Without this check, "Downloads\nahida.zip" split into "Downloads"
// and the whole Downloads folder got copied.
final _literalSeparator = RegExp(r'(?:\\[rn])+(?=[A-Za-z]:[\\/]|file:|/)');

List<String> parseDropPaths(List<dynamic> files) {
  final Set<String> results = {};
  for (var f in files) {
    String rawPath = f.path;
    // Split by newlines in case paths got merged (happens on some platforms/bugs),
    // including literal '\n' / '\r' text from Windows Chrome drops
    final lines = rawPath
        .replaceAll(_literalSeparator, '\n')
        .split(RegExp(r'[\r\n]+'));
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Handle file:// URIs
      if (line.startsWith('file:')) {
        try {
          // Decode percent-encoded characters like %20 to space
          String decoded = Uri.decodeFull(line);
          // Strip "file:" and any following forward or backward slashes
          decoded = decoded.replaceFirst(RegExp(r'^file:[\/\\]+'), '');
          // On Windows, if the path starts with a slash, strip it if followed by a drive letter (e.g. /C:/ -> C:/)
          if (Platform.isWindows &&
              decoded.startsWith('/') &&
              decoded.length > 2 &&
              decoded[2] == ':') {
            decoded = decoded.substring(1);
          }
          results.add(p.normalize(decoded));
          continue;
        } catch (_) {
          // Fallback stripping if Uri parsing fails
          line = line.replaceFirst(RegExp(r'^file:[\/\\]+'), '');
        }
      }
      results.add(p.normalize(line));
    }
  }
  return results.toList();
}
