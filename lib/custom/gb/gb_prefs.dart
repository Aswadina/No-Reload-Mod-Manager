// GameBanana tab — small things we remember between runs (per game).

import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GbPrefs {
  static String _k(String game, String what) => 'gb_${what}_$game';

  /// Sort and category last used for [game].
  static Future<(GbSort, int?)> loadBrowse(String game) async {
    try {
      final p = await SharedPreferences.getInstance();
      final sortName = p.getString(_k(game, 'sort'));
      final sort = GbSort.values.firstWhere(
        (s) => s.name == sortName,
        orElse: () => GbSort.newest,
      );
      final cat = p.getInt(_k(game, 'cat'));
      return (sort, cat);
    } catch (_) {
      return (GbSort.newest, null);
    }
  }

  static Future<void> saveBrowse(String game, GbSort sort, int? category) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_k(game, 'sort'), sort.name);
      if (category == null) {
        await p.remove(_k(game, 'cat'));
      } else {
        await p.setInt(_k(game, 'cat'), category);
      }
    } catch (_) {}
  }

  /// The group last used for a mod in [category] (a group folder path).
  static Future<String?> lastGroupFor(String game, String category) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_k(game, 'group_${category.toLowerCase()}'));
    } catch (_) {
      return null;
    }
  }

  /// Remembers [groupPath] for [category] and adds it to the recent list.
  static Future<void> rememberGroup(
    String game,
    String category,
    String groupPath,
  ) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_k(game, 'group_${category.toLowerCase()}'), groupPath);
      final recents = [
        groupPath,
        ...(p.getStringList(_k(game, 'recent')) ?? []).where((x) => x != groupPath),
      ].take(5).toList();
      await p.setStringList(_k(game, 'recent'), recents);
    } catch (_) {}
  }

  /// Most recently used group paths, newest first (at most 5).
  static Future<List<String>> recentGroups(String game) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getStringList(_k(game, 'recent')) ?? [];
    } catch (_) {
      return [];
    }
  }
}
