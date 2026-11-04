// "UI groups" — importing loose mods, the file side (no Flutter code).
// The dialog is in ui_group_import.dart.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// Mod folders sitting directly in the game's Mods folder, outside the
/// managed folder. Folders starting with "disabled" are left alone.
Future<List<String>> listLooseModFolders(
  String modsPath,
  String managedFolderName,
) async {
  final folders = <String>[];
  await for (final e in Directory(modsPath).list(followLinks: false)) {
    if (e is! Directory) continue;
    final name = p.basename(e.path);
    if (name == managedFolderName) continue;
    if (name.toLowerCase().startsWith('disabled')) continue;
    folders.add(e.path);
  }
  folders.sort(
    (a, b) => compareNatural(
      p.basename(a).toLowerCase(),
      p.basename(b).toLowerCase(),
    ),
  );
  return folders;
}

/// Moves each folder into [targetGroupPath]. A name that is already taken gets
/// `_1`, `_2`, ... so nothing is ever overwritten. Returns how many moved.
Future<int> importModFolders(
  List<String> folders,
  String targetGroupPath,
) async {
  var moved = 0;
  for (final folder in folders) {
    try {
      await moveFolderInto(folder, targetGroupPath);
      moved++;
    } catch (_) {
      // Leave this folder where it was and carry on with the others.
    }
  }
  return moved;
}

/// Moves [folder] into [targetDir] under a name that is not taken yet, and
/// returns the new path. Creates [targetDir] if needed. Throws on failure.
Future<String> moveFolderInto(String folder, String targetDir) async {
  await Directory(targetDir).create(recursive: true);
  final target = await _freeTarget(p.join(targetDir, p.basename(folder)));
  try {
    await Directory(folder).rename(target);
  } on FileSystemException {
    // Different drive: rename cannot cross drives, so copy then delete.
    await _copyDir(Directory(folder), Directory(target));
    await Directory(folder).delete(recursive: true);
  }
  return target;
}

Future<String> _freeTarget(String target) async {
  if (!await Directory(target).exists()) return target;
  var i = 1;
  while (await Directory('${target}_$i').exists()) {
    i++;
  }
  return '${target}_$i';
}

Future<void> _copyDir(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final e in from.list(followLinks: false)) {
    final dest = p.join(to.path, p.basename(e.path));
    if (e is Directory) {
      await _copyDir(e, Directory(dest));
    } else if (e is File) {
      await e.copy(dest);
    }
  }
}
