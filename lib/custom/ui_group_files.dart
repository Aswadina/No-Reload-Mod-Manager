// "UI groups" — the file side.
//
// A UI group is a normal group folder with a `uigroup` marker file. Each mod in
// it is rewritten as if it were alone in its own two-state group `group_K`
// (slot 0 = off, slot 1 = on), so several mods can be on at once with no reload.
// K is a free number in 1..500, kept in the mod folder as `uikey`. The on/off
// state NRMM last sent is kept in `uistate`.
//
// No Flutter/UI code here so it can be unit tested on its own.

import 'dart:io';

import 'package:path/path.dart' as p;

const String _groupMarker = 'uigroup';
const String _keyFile = 'uikey';
const String _stateFile = 'uistate';
const int _maxKey = 500;

Future<bool> isUiGroupFolder(String groupPath) =>
    File(p.join(groupPath, _groupMarker)).exists();

Future<void> setUiGroupFolder(String groupPath, bool on) async {
  final marker = File(p.join(groupPath, _groupMarker));
  if (on) {
    await marker.writeAsString('1');
  } else if (await marker.exists()) {
    await marker.delete();
  }
}

Future<int?> readUiKey(String modPath) async {
  try {
    final k = int.tryParse(
      (await File(p.join(modPath, _keyFile)).readAsString()).trim(),
    );
    return k != null && k >= 1 && k <= _maxKey ? k : null;
  } catch (_) {
    return null;
  }
}

Future<void> writeUiKey(String modPath, int k) =>
    File(p.join(modPath, _keyFile)).writeAsString('$k');

Future<bool> readUiOn(String modPath) async {
  try {
    return (await File(p.join(modPath, _stateFile)).readAsString()).trim() ==
        '1';
  } catch (_) {
    return false;
  }
}

Future<void> writeUiOn(String modPath, bool on) =>
    File(p.join(modPath, _stateFile)).writeAsString(on ? '1' : '0');

/// Gives every mod in [uiModPaths] its own number in 1..500 that is not a real
/// group ([usedRealGroupIndexes]) and not used by another UI mod. A mod keeps
/// its stored number when that is still valid and unique. Mods that cannot get
/// a number (pool empty) are left out of the result.
Future<Map<String, int>> allocateUiKeys(
  List<String> uiModPaths,
  Set<int> usedRealGroupIndexes,
) async {
  final result = <String, int>{};
  final taken = {...usedRealGroupIndexes};

  // First pass: keep valid unique keys, so existing mods never move.
  final needKey = <String>[];
  for (final path in uiModPaths) {
    final k = await readUiKey(path);
    if (k != null && !taken.contains(k)) {
      taken.add(k);
      result[path] = k;
    } else {
      needKey.add(path);
    }
  }

  var next = 1;
  for (final path in needKey) {
    while (next <= _maxKey && taken.contains(next)) {
      next++;
    }
    if (next > _maxKey) break;
    taken.add(next);
    result[path] = next;
    await writeUiKey(path, next);
  }
  return result;
}

/// Fills the group ini template (assets/template_txt/template_group.txt).
String renderUiGroupIni(String template, int k) =>
    template.replaceAll('{x}', '$k').replaceAll('{group_x}', 'group_$k');
