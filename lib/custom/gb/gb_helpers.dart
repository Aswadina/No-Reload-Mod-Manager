// GameBanana tab — small pure helpers (no Flutter), so they can be unit tested.

/// Page numbers to show in the pager, with `null` meaning "…".
/// Always the first and last page, and three pages around [current].
/// A gap of exactly one page shows that page instead of dots.
List<int?> pageWindow(int current, int total) {
  if (total <= 0) return [];
  if (total <= 7) return [for (var i = 1; i <= total; i++) i];

  final start = (current - 1).clamp(1, total - 2);
  final shown =
      {1, total, for (var i = start; i <= start + 2; i++) i}.toList()..sort();

  final result = <int?>[];
  for (var i = 0; i < shown.length; i++) {
    if (i > 0) {
      final gap = shown[i] - shown[i - 1];
      if (gap == 2) {
        result.add(shown[i - 1] + 1);
      } else if (gap > 2) {
        result.add(null);
      }
    }
    result.add(shown[i]);
  }
  return result;
}

/// "today", "3d ago", "2mo ago", "1y ago". Empty when the date is unknown.
String ageLabel(int? unixSeconds, {DateTime? now}) {
  if (unixSeconds == null || unixSeconds <= 0) return '';
  final then = DateTime.fromMillisecondsSinceEpoch(
    unixSeconds * 1000,
    isUtc: true,
  );
  final days = (now ?? DateTime.now()).toUtc().difference(then).inDays;
  if (days < 1) return 'today'; // also covers dates slightly in the future
  if (days < 30) return '${days}d ago';
  if (days < 365) return '${days ~/ 30}mo ago';
  return '${days ~/ 365}y ago';
}

/// 999, 1.2k, 15k, 2.5M.
String formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) {
    final k = (n / 100).round() / 10;
    return k == k.roundToDouble() ? '${k.round()}k' : '${k}k';
  }
  if (n < 1000000) {
    final k = (n / 1000).round();
    return k >= 1000 ? '1M' : '${k}k';
  }
  final m = (n / 100000).round() / 10;
  return m == m.roundToDouble() ? '${m.round()}M' : '${m}M';
}

/// The part of a group name worth searching GameBanana for:
/// "Mavuika - Nord Express" -> "Mavuika", "[WIP] Furina" -> "Furina".
String searchTermForGroup(String groupName) {
  final original = groupName.trim();
  var s = original.replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '');
  final cut = RegExp(r'\s[-–—]\s|\s*[(\[]').firstMatch(s);
  if (cut != null) s = s.substring(0, cut.start);
  s = s.trim();
  return s.isEmpty ? original : s;
}

class GbGroupCandidate {
  final String path;
  final String name;
  final bool isUi;
  const GbGroupCandidate({
    required this.path,
    required this.name,
    required this.isUi,
  });
}

class GbSuggestion {
  final GbGroupCandidate group;
  final String reason;
  const GbSuggestion({required this.group, required this.reason});
}

const _stopWords = {
  'the',
  'and',
  'mod',
  'mods',
  'skin',
  'skins',
  'outfit',
  'for',
  'with',
  'new',
  'old',
  'version',
  'pack',
  'edit',
  'remove',
  'genshin',
  'impact',
  'honkai',
  'star',
  'rail',
  'zenless',
  'zone',
  'zero',
  'wuthering',
  'waves',
  'arknights',
  'endfield',
};

Set<String> _tokens(String text) => {
  for (final t in text.toLowerCase().split(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
  ))
    if (t.length >= 3 && !_stopWords.contains(t)) t,
};

/// Groups that probably fit this mod, best first, each with a plain reason.
/// UI-category mods point to UI groups; everything else matches by name
/// against the mod's title and tags.
List<GbSuggestion> suggestGroups({
  required String modName,
  required String categoryName,
  required List<String> tags,
  required List<GbGroupCandidate> groups,
}) {
  if (categoryName.toLowerCase() == 'ui') {
    final uiGroups = [
      for (final g in groups)
        if (g.isUi) GbSuggestion(group: g, reason: 'UI mods go in a UI group'),
    ];
    if (uiGroups.isNotEmpty) return uiGroups;
  }

  final modTokens = _tokens('$modName ${tags.join(' ')}');
  final scored = <(double, int, GbSuggestion)>[];
  for (final g in groups) {
    if (g.isUi) continue;
    final groupTokens = _tokens(g.name);
    if (groupTokens.isEmpty) continue;
    final matched = groupTokens.intersection(modTokens).length;
    if (matched == 0) continue;
    scored.add((
      matched / groupTokens.length,
      matched,
      GbSuggestion(group: g, reason: 'Name matches "${g.name}"'),
    ));
  }
  scored.sort((a, b) {
    final byFraction = b.$1.compareTo(a.$1);
    return byFraction != 0 ? byFraction : b.$2.compareTo(a.$2);
  });
  return [for (final s in scored) s.$3];
}
