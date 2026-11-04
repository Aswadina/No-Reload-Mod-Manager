// GameBanana tab — remembers where an installed mod came from.
//
// A small file `gbsource.json` sits inside the mod folder, so it follows the
// folder if it is moved or renamed (same idea as `uikey` in UI groups).

import 'dart:convert';
import 'dart:io';

import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:path/path.dart' as p;

const String gbSourceFileName = 'gbsource.json';

class GbSource {
  final int modId;
  final int fileId;

  /// When GameBanana says this file was added (unix seconds).
  final int fileDate;

  /// The mod's "last updated" stamp when we downloaded it (unix seconds).
  final int? modDateUpdated;
  final String downloadedAt;

  const GbSource({
    required this.modId,
    required this.fileId,
    required this.fileDate,
    required this.modDateUpdated,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() => {
    'modId': modId,
    'fileId': fileId,
    'fileDate': fileDate,
    'modDateUpdated': modDateUpdated,
    'downloadedAt': downloadedAt,
  };

  static GbSource? fromJson(Object? j) {
    if (j is! Map) return null;
    final modId = j['modId'];
    final fileId = j['fileId'];
    final fileDate = j['fileDate'];
    if (modId is! int || fileId is! int || fileDate is! int) return null;
    final updated = j['modDateUpdated'];
    return GbSource(
      modId: modId,
      fileId: fileId,
      fileDate: fileDate,
      modDateUpdated: updated is int ? updated : null,
      downloadedAt: j['downloadedAt'] is String ? j['downloadedAt'] : '',
    );
  }
}

class InstalledGbMod {
  final String modPath;
  final GbSource source;
  const InstalledGbMod({required this.modPath, required this.source});
}

Future<GbSource?> readGbSource(String modPath) async {
  try {
    final text = await File(p.join(modPath, gbSourceFileName)).readAsString();
    return GbSource.fromJson(jsonDecode(text));
  } catch (_) {
    return null;
  }
}

Future<void> writeGbSource(String modPath, GbSource source) => File(
  p.join(modPath, gbSourceFileName),
).writeAsString(const JsonEncoder.withIndent('  ').convert(source.toJson()));

/// Mods that came from GameBanana, by mod id. Looks one folder deep
/// (managed folder -> group -> mod), like the rest of NRMM.
Future<Map<int, InstalledGbMod>> scanInstalled(String managedPath) async {
  final found = <int, InstalledGbMod>{};
  final root = Directory(managedPath);
  if (!await root.exists()) return found;
  await for (final group in root.list(followLinks: false)) {
    if (group is! Directory) continue;
    await for (final mod in group.list(followLinks: false)) {
      if (mod is! Directory) continue;
      final source = await readGbSource(mod.path);
      if (source != null) {
        found.putIfAbsent(
          source.modId,
          () => InstalledGbMod(modPath: mod.path, source: source),
        );
      }
    }
  }
  return found;
}

/// Cheap check for the grid: needs no extra request. If GameBanana did not
/// send an "updated" date for this mod, we say nothing (the dialog checks exactly).
bool hasUpdateForCard(InstalledGbMod installed, GbMod mod) {
  final seen = installed.source.modDateUpdated;
  final now = mod.dateUpdated;
  return seen != null && now != null && now > seen;
}

/// Exact check, using the mod's file list. Never uses the version text.
bool hasUpdateExact(GbSource source, GbModDetails details) {
  final newest = details.newestFile;
  return newest != null &&
      newest.id != source.fileId &&
      newest.dateAdded > source.fileDate;
}
