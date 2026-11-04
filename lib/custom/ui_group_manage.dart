// "UI groups" — hooks used by Update Mod Data (see ui_group_files.dart).

import 'dart:io';

import 'package:no_reload_mod_manager/custom/ui_group_files.dart';
import 'package:no_reload_mod_manager/data/mod_data.dart';
import 'package:path/path.dart' as p;

bool _isManageable(ModData mod) =>
    mod.realIndex != 0 &&
    !p.basename(mod.modPath).toLowerCase().startsWith('disabled');

/// modPath -> its own group number, for the mods of every UI group.
/// Called once before the groups are processed in parallel, so two groups
/// never pick the same number.
Future<Map<String, int>> prepareUiKeys(
  Map<(String, int), List<ModData>> groupAndModsPair,
) async {
  final realIndexes = {for (final key in groupAndModsPair.keys) key.$2};
  final uiModPaths = <String>[];
  for (final entry in groupAndModsPair.entries) {
    if (!await isUiGroupFolder(entry.key.$1)) continue;
    uiModPaths.addAll(entry.value.where(_isManageable).map((m) => m.modPath));
  }
  return allocateUiKeys(uiModPaths, realIndexes);
}

/// Update Mod Data for one UI group: every mod gets its own `group_K.ini`
/// and is rewritten as slot 1 of group K.
Future<void> manageUiGroup({
  required String groupPath,
  required List<ModData> mods,
  required Map<String, int> keys,
  required Future<void> Function(String modPath, int k) manageMod,
  required String template,
  required void Function(String message) logError,
}) async {
  for (final mod in mods.where(_isManageable)) {
    final k = keys[mod.modPath];
    if (k == null) {
      logError('No free group number for ${p.basename(mod.modPath)}');
      continue;
    }
    await File(
      p.join(groupPath, 'group_$k.ini'),
    ).writeAsString(renderUiGroupIni(template, k));
    await manageMod(mod.modPath, k);
  }
}
