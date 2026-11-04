// "UI groups" — the app side: toggling, highlight and the right-click item.
// See ui_group_files.dart for how a UI group works on disk.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:no_reload_mod_manager/custom/only_equipped_files.dart';
import 'package:no_reload_mod_manager/custom/ui_group_files.dart';
import 'package:no_reload_mod_manager/data/mod_data.dart';
import 'package:no_reload_mod_manager/utils/custom_menu_item.dart';
import 'package:no_reload_mod_manager/utils/keypress_simulator_manager.dart';
import 'package:no_reload_mod_manager/utils/managedfolder_watcher.dart';
import 'package:no_reload_mod_manager/utils/mod_manager.dart';

final uiGroupProvider = FutureProvider.family<bool, String>(
  (ref, groupPath) => isUiGroupFolder(groupPath),
);

/// Folder paths of the mods currently switched on in a UI group.
final uiOnModsProvider = FutureProvider.family<Set<String>, String>((
  ref,
  groupPath,
) async {
  final on = <String>{};
  for (final mod in await getModsOnGroup(groupPath, false)) {
    if (mod.realIndex != 0 && await readUiOn(mod.modPath)) on.add(mod.modPath);
  }
  return on;
});

bool isUiGroup(WidgetRef ref, String groupPath) =>
    ref.read(uiGroupProvider(groupPath)).valueOrNull ?? false;

/// For a UI group: the view indexes that should look switched on.
/// For a normal group: null (the caller keeps its usual single selection).
/// Call from build() so the tab rebuilds when a mod is toggled.
/// The "None" card (index 0) counts as selected when every mod is off.
Set<int>? uiShownIndexes(WidgetRef ref, ModGroupData group) {
  if (!(ref.watch(uiGroupProvider(group.groupPath)).valueOrNull ?? false)) {
    return null;
  }
  final on = ref.watch(uiOnModsProvider(group.groupPath)).valueOrNull ?? {};
  return {
    if (on.isEmpty) 0,
    for (var i = 1; i < group.modsInGroup.length; i++)
      if (on.contains(group.modsInGroup[i].modPath)) i,
  };
}

/// Click on a mod card of a UI group. Card 0 ("None") switches everything off.
Future<void> toggleUiMod(
  WidgetRef ref,
  ModGroupData group,
  int viewIndex,
) async {
  final groupPath = group.groupPath;
  final on = ref.read(uiOnModsProvider(groupPath)).valueOrNull ?? <String>{};
  final invalidate = ref.invalidate;

  // Our small state files should not trigger the folder watcher's UI refresh.
  final watchedPath = DynamicDirectoryWatcher.watcher?.path;
  DynamicDirectoryWatcher.stop();
  try {
    if (viewIndex == 0) {
      for (final modPath in on) {
        await _setMod(modPath, false);
      }
    } else {
      final modPath = group.modsInGroup[viewIndex].modPath;
      await _setMod(modPath, !on.contains(modPath));
    }
  } finally {
    if (watchedPath != null) DynamicDirectoryWatcher.watch(watchedPath);
  }
  invalidate(uiOnModsProvider(groupPath));
}

Future<void> _setMod(String modPath, bool on) async {
  final k = await readUiKey(modPath);
  if (k == null) return; // Update Mod Data has not numbered this mod yet.
  await writeUiOn(modPath, on);
  await simulateKeySelectMod(k, on ? 1 : 0);
}

/// Checkable item for a group's right-click menu.
CustomMenuItem uiGroupMenu(WidgetRef ref, String groupPath, double scale) {
  final current = isUiGroup(ref, groupPath);
  return CustomMenuItem(
    scale: scale,
    label: 'UI group (several mods on)',
    leftIcon: current ? Icons.check_box : Icons.check_box_outline_blank,
    onSelected: () async {
      final invalidate = ref.invalidate;
      await setUiGroupFolder(groupPath, !current);
      // A UI group must load every mod; "only equipped" would hide the others.
      await writeGroupLoadMode(
        groupPath,
        current ? GroupLoadMode.inherit : GroupLoadMode.loadAll,
      );
      invalidate(uiGroupProvider(groupPath));
    },
  );
}
