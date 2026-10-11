// "Load only equipped mod" — the app side: settings, menus and switching.
//
// When a group is in "only equipped" mode, every mod except the equipped one
// has its inis hidden (see only_equipped_files.dart). Picking another mod
// swaps which mod is hidden and presses F10 so 3DMigoto reloads. That makes
// switching a bit slower, but loading (startup and F10) much faster because
// the game only reads one mod per group.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:no_reload_mod_manager/custom/only_equipped_files.dart';
import 'package:no_reload_mod_manager/data/mod_data.dart';
import 'package:no_reload_mod_manager/main.dart';
import 'package:no_reload_mod_manager/utils/constant_var.dart';
import 'package:no_reload_mod_manager/utils/custom_menu_item.dart';
import 'package:no_reload_mod_manager/utils/keypress_simulator_manager.dart';
import 'package:no_reload_mod_manager/utils/managedfolder_watcher.dart';
import 'package:no_reload_mod_manager/utils/mod_manager.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

export 'package:no_reload_mod_manager/custom/only_equipped_files.dart'
    show unhideModInis;

/// After F10 we send the slot keypress once more, in case the reload did not
/// keep the slot we set just before it. Sending the same slot twice is harmless.
const Duration _reselectDelay = Duration(milliseconds: 1500);

// ---------- Global setting (one per game) ----------

String _prefKey(TargetGame game) => 'nrmmOnlyEquipped_${game.name}';

Future<bool> getOnlyEquippedGlobal(TargetGame game) async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_prefKey(game)) ??
        false;
  } catch (_) {
    return false;
  }
}

final onlyEquippedGlobalProvider = FutureProvider.family<bool, TargetGame>(
  (ref, game) => getOnlyEquippedGlobal(game),
);

final groupLoadModeProvider = FutureProvider.family<GroupLoadMode, String>(
  (ref, groupPath) => readGroupLoadMode(groupPath),
);

// ---------- Helpers ----------

// One rename-and-reload job at a time, so quick clicks can't interleave.
Future<void> _queue = Future.value();
Future<T> _serial<T>(Future<T> Function() job) {
  final result = _queue.then((_) => job());
  _queue = result.then((_) {}, onError: (_) {});
  return result;
}

// Our renames should not trigger the folder watcher's UI refresh.
Future<T> _withWatcherPaused<T>(Future<T> Function() job) async {
  final watchedPath = DynamicDirectoryWatcher.watcher?.path;
  DynamicDirectoryWatcher.stop();
  try {
    return await job();
  } finally {
    if (watchedPath != null) DynamicDirectoryWatcher.watch(watchedPath);
  }
}

/// The equipped mod's folder name ('' for None). Uses the name we recorded on
/// the last pick; falls back to the app's own selected index.
Future<String> _resolveEquippedFolder(String groupPath) async {
  final recorded = await readEquippedMod(groupPath);
  if (recorded != null &&
      (recorded.isEmpty ||
          await Directory(p.join(groupPath, recorded)).exists())) {
    return recorded;
  }
  final mods = await getModsOnGroup(groupPath, false);
  final index = await getSelectedModInGroup(groupPath, mods.length);
  return index == 0 ? '' : p.basename(mods[index].modPath);
}

Future<int> _applyGroup(String groupPath, {required bool globalOn}) async {
  final mode = await readGroupLoadMode(groupPath);
  final onlyEquipped = isOnlyEquipped(mode, globalOn: globalOn);
  return applyGroupVisibility(
    groupPath,
    onlyEquipped: onlyEquipped,
    equippedFolder: onlyEquipped ? await _resolveEquippedFolder(groupPath) : '',
  );
}

/// Hides/un-hides inis in every group to match its load mode.
/// Called at the end of "Update Mod Data". Returns how many files changed.
Future<int> applyLoadModesToAllGroups(
  String managedPath,
  TargetGame game,
) async {
  final globalOn = await getOnlyEquippedGlobal(game);
  int renamed = 0;
  for (final (groupPath, _) in await getGroupFolders(managedPath)) {
    renamed += await _applyGroup(groupPath, globalOn: globalOn);
  }
  return renamed;
}

// ---------- Switching ----------

final Map<String, int> _pickCount = {};

/// Replaces a plain [simulateKeySelectMod] call when the user picks a mod.
/// In "only equipped" groups it also swaps the hidden inis and presses F10.
Future<void> selectModWithLoadMode(
  TargetGame game,
  ModGroupData group,
  int viewIndex,
) async {
  final mod = group.modsInGroup[viewIndex];
  await simulateKeySelectMod(group.realIndex, mod.realIndex);

  final groupPath = group.groupPath;
  final folder = viewIndex == 0 ? '' : p.basename(mod.modPath);
  final pick = (_pickCount[groupPath] ?? 0) + 1;
  _pickCount[groupPath] = pick;
  bool isLatestPick() => _pickCount[groupPath] == pick;

  await _serial(() async {
    // A newer pick in this group is queued and will do the work.
    if (!isLatestPick()) return;

    final renamed = await _withWatcherPaused(() async {
      await writeEquippedMod(groupPath, folder);
      final mode = await readGroupLoadMode(groupPath);
      final globalOn = await getOnlyEquippedGlobal(game);
      if (!isOnlyEquipped(mode, globalOn: globalOn)) return 0;
      return applyGroupVisibility(
        groupPath,
        onlyEquipped: true,
        equippedFolder: folder,
      );
    });
    if (renamed == 0) return;

    await simulateKeyF10();
    await Future.delayed(_reselectDelay);
    if (isLatestPick()) {
      await simulateKeySelectMod(group.realIndex, mod.realIndex);
    }
  });
}

// ---------- Changing the mode ----------

Future<void> setGroupLoadModeAndApply(
  WidgetRef ref,
  String groupPath,
  GroupLoadMode mode,
) async {
  final game = ref.read(targetGameProvider);
  final provider = groupLoadModeProvider(groupPath);
  final invalidate = ref.invalidate;

  await _serial(() async {
    final renamed = await _withWatcherPaused(() async {
      await writeGroupLoadMode(groupPath, mode);
      return _applyGroup(
        groupPath,
        globalOn: await getOnlyEquippedGlobal(game),
      );
    });
    if (renamed > 0) await simulateKeyF10();
  });

  try {
    invalidate(provider);
  } catch (_) {}
}

Future<void> setOnlyEquippedGlobalAndApply(
  WidgetRef ref,
  TargetGame game,
  bool on,
) async {
  final modsPath = ref.read(validModsPath);
  final provider = onlyEquippedGlobalProvider(game);
  final invalidate = ref.invalidate;

  await (await SharedPreferences.getInstance()).setBool(_prefKey(game), on);
  try {
    invalidate(provider);
  } catch (_) {}

  if (modsPath == null) return;
  final managedPath = p.join(modsPath, ConstantVar.managedFolderName);

  await _serial(() async {
    final renamed = await _withWatcherPaused(
      () => applyLoadModesToAllGroups(managedPath, game),
    );
    if (renamed > 0) await simulateKeyF10();
  });
}

// ---------- UI pieces ----------

/// "Mod loading" submenu for a group's right-click menu.
CustomMenuItem loadModeMenu(WidgetRef ref, String groupPath, double scale) {
  final game = ref.read(targetGameProvider);
  final globalOn =
      ref.read(onlyEquippedGlobalProvider(game)).valueOrNull ?? false;
  final current =
      ref.read(groupLoadModeProvider(groupPath)).valueOrNull ??
      GroupLoadMode.inherit;

  CustomMenuItem item(GroupLoadMode mode, String label) => CustomMenuItem(
    scale: scale,
    label: label,
    leftIcon:
        mode == current
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
    onSelected: () => setGroupLoadModeAndApply(ref, groupPath, mode),
  );

  return CustomMenuItem.submenu(
    label: 'Mod loading',
    scale: scale,
    items: [
      item(
        GroupLoadMode.inherit,
        'Default (${globalOn ? 'only equipped' : 'load all'})',
      ),
      item(GroupLoadMode.onlyEquipped, 'Only equipped mod'),
      item(GroupLoadMode.loadAll, 'Load all mods'),
    ],
  );
}

/// Small badge on a group icon when only its equipped mod is loaded.
/// Must be placed directly inside a Stack.
class OnlyEquippedBadge extends ConsumerWidget {
  final String groupPath;
  const OnlyEquippedBadge({super.key, required this.groupPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sss = ref.watch(zoomScaleProvider);
    final game = ref.watch(targetGameProvider);
    final globalOn =
        ref.watch(onlyEquippedGlobalProvider(game)).valueOrNull ?? false;
    final mode =
        ref.watch(groupLoadModeProvider(groupPath)).valueOrNull ??
        GroupLoadMode.inherit;

    return Positioned(
      right: 4 * sss,
      bottom: 4 * sss,
      child:
          isOnlyEquipped(mode, globalOn: globalOn)
              ? Tooltip(
                message: 'Only the equipped mod is loaded',
                child: Container(
                  padding: EdgeInsets.all(2 * sss),
                  decoration: const BoxDecoration(
                    color: Color.fromARGB(200, 0, 0, 0),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.looks_one_rounded,
                    size: 14 * sss,
                    color: getAccentColor(ref),
                  ),
                ),
              )
              : const SizedBox.shrink(),
    );
  }
}

/// Settings switch for the current game.
class OnlyEquippedSettingTile extends ConsumerWidget {
  const OnlyEquippedSettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sss = ref.watch(zoomScaleProvider);
    final game = ref.watch(targetGameProvider);
    final on = ref.watch(onlyEquippedGlobalProvider(game)).valueOrNull ?? false;

    return Row(
      children: [
        SizedBox(
          height: 25 * sss,
          width: 35 * sss,
          child: FittedBox(
            fit: BoxFit.fill,
            child: Switch(
              value: on,
              onChanged:
                  (value) => setOnlyEquippedGlobalAndApply(ref, game, value),
              activeColor: getAccentColor(ref),
              trackOutlineWidth: const WidgetStatePropertyAll(0),
              trackOutlineColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
            ),
          ),
        ),
        Container(width: 15 * sss),
        Expanded(
          child: Text(
            'Load only the equipped mod per group (faster loading; each '
            'switch reloads with F10). Groups can override this from their '
            'right-click menu.',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 12 * sss,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
