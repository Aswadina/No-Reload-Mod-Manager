// "Load only equipped mod" — the file side.
//
// 3DMigoto skips any .ini whose name starts with "DISABLED". To keep a mod
// from loading we rename its .ini files with our own prefix, and to bring it
// back we strip that prefix. Mod folders are never renamed, so slot numbers
// (which come from folder order) stay stable.
//
// This file has no Flutter/UI code so it can be unit tested on its own.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Prefix we add to hide an ini. Only files with exactly this prefix are ever
/// restored, so inis the mod author disabled on purpose are never touched.
const String hiddenIniPrefix = 'DISABLED_NRMM_';

const String _loadModeFileName = 'loadmode';
const String _equippedFileName = 'equippedmod';

enum GroupLoadMode {
  /// Follow the global setting for this game.
  inherit,

  /// Only the equipped mod's inis stay active.
  onlyEquipped,

  /// Classic no-reload behaviour: every mod is loaded.
  loadAll,
}

bool isOnlyEquipped(GroupLoadMode mode, {required bool globalOn}) {
  switch (mode) {
    case GroupLoadMode.inherit:
      return globalOn;
    case GroupLoadMode.onlyEquipped:
      return true;
    case GroupLoadMode.loadAll:
      return false;
  }
}

// Same \\?\ long-path workaround the rest of the app uses on Windows.
String _long(String path) =>
    Platform.isWindows ? r'\\?\' + path.replaceFirst(r'\\?\', '') : path;
String _short(String path) => path.replaceFirst(r'\\?\', '');

Future<List<File>> _iniFiles(String folder) async {
  final dir = Directory(_long(folder));
  if (!await dir.exists()) return [];
  final files = <File>[];
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is File && e.path.toLowerCase().endsWith('.ini')) files.add(e);
  }
  return files;
}

/// Hides every ini in [modPath] that 3DMigoto would currently load.
/// Returns how many files were renamed.
Future<int> hideModInis(String modPath) async {
  int renamed = 0;
  for (final file in await _iniFiles(modPath)) {
    final relative = p.relative(_short(file.path), from: _short(modPath));
    final segments = p.split(relative);
    // Already skipped by 3DMigoto (author-disabled file or folder, or ours).
    if (segments.any((s) => s.toLowerCase().startsWith('disabled'))) continue;
    if (p.basename(relative).toLowerCase() == 'desktop.ini') continue;

    final target = p.join(p.dirname(file.path), '$hiddenIniPrefix${p.basename(file.path)}');
    if (await File(target).exists()) continue;
    try {
      await file.rename(target);
      renamed++;
    } catch (_) {}
  }
  return renamed;
}

/// Restores every ini we hid under [folder] (a mod, a group, or the whole
/// managed folder). Never overwrites an existing file.
/// Returns how many files were renamed.
Future<int> unhideModInis(String folder) async {
  int renamed = 0;
  for (final file in await _iniFiles(folder)) {
    final name = p.basename(file.path);
    if (!name.startsWith(hiddenIniPrefix)) continue;

    final target = p.join(p.dirname(file.path), name.substring(hiddenIniPrefix.length));
    if (await File(target).exists()) continue;
    try {
      await file.rename(target);
      renamed++;
    } catch (_) {}
  }
  return renamed;
}

/// Makes the inis in one group match its load mode.
/// [equippedFolder] is the equipped mod's folder name, or '' for "None".
/// Returns how many files were renamed (0 means no reload is needed).
Future<int> applyGroupVisibility(
  String groupPath, {
  required bool onlyEquipped,
  required String equippedFolder,
}) async {
  final dir = Directory(groupPath);
  if (!await dir.exists()) return 0;

  int renamed = 0;
  await for (final e in dir.list(followLinks: false)) {
    if (e is! Directory) continue;
    final name = p.basename(e.path);
    // User-disabled mod folders are already skipped by 3DMigoto.
    if (name.toLowerCase().startsWith('disabled')) continue;

    if (!onlyEquipped || name == equippedFolder) {
      renamed += await unhideModInis(e.path);
    } else {
      renamed += await hideModInis(e.path);
    }
  }
  return renamed;
}

Future<GroupLoadMode> readGroupLoadMode(String groupPath) async {
  try {
    final file = File(p.join(groupPath, _loadModeFileName));
    if (!await file.exists()) return GroupLoadMode.inherit;
    final text = (await file.readAsString()).trim();
    return GroupLoadMode.values.firstWhere(
      (m) => m.name == text,
      orElse: () => GroupLoadMode.inherit,
    );
  } catch (_) {
    return GroupLoadMode.inherit;
  }
}

Future<void> writeGroupLoadMode(String groupPath, GroupLoadMode mode) async {
  final file = File(p.join(groupPath, _loadModeFileName));
  if (mode == GroupLoadMode.inherit) {
    if (await file.exists()) await file.delete();
  } else {
    await file.writeAsString(mode.name);
  }
}

/// The equipped mod's folder name, '' for "None", or null if never recorded.
Future<String?> readEquippedMod(String groupPath) async {
  try {
    final file = File(p.join(groupPath, _equippedFileName));
    if (!await file.exists()) return null;
    return (await file.readAsString()).trim();
  } catch (_) {
    return null;
  }
}

Future<void> writeEquippedMod(String groupPath, String folderName) async {
  await File(p.join(groupPath, _equippedFileName)).writeAsString(folderName);
}
