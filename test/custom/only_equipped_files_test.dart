import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_reload_mod_manager/custom/only_equipped_files.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nrmm_only_equipped_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> touch(String relative) async {
    final f = File(p.join(tmp.path, relative));
    await f.parent.create(recursive: true);
    await f.writeAsString('x');
  }

  bool exists(String relative) => File(p.join(tmp.path, relative)).existsSync();

  group('hideModInis / unhideModInis', () {
    test('hides every active ini, recursively, and only ini files', () async {
      await touch('ModA/main.ini');
      await touch('ModA/sub/extra.INI');
      await touch('ModA/main.ini_managed_backup');
      await touch('ModA/tex.dds');

      final count = await hideModInis(p.join(tmp.path, 'ModA'));

      expect(count, 2);
      expect(exists('ModA/DISABLED_NRMM_main.ini'), isTrue);
      expect(exists('ModA/sub/DISABLED_NRMM_extra.INI'), isTrue);
      expect(exists('ModA/main.ini'), isFalse);
      expect(exists('ModA/main.ini_managed_backup'), isTrue);
      expect(exists('ModA/tex.dds'), isTrue);
    });

    test('leaves inis the author disabled, and disabled folders, alone',
        () async {
      await touch('ModA/DISABLED_variant.ini');
      await touch('ModA/disabledOther.ini');
      await touch('ModA/DISABLED_folder/inner.ini');
      await touch('ModA/desktop.ini');

      final count = await hideModInis(p.join(tmp.path, 'ModA'));

      expect(count, 0);
      expect(exists('ModA/DISABLED_variant.ini'), isTrue);
      expect(exists('ModA/disabledOther.ini'), isTrue);
      expect(exists('ModA/DISABLED_folder/inner.ini'), isTrue);
      expect(exists('ModA/desktop.ini'), isTrue);
    });

    test('unhide only restores our own prefix', () async {
      await touch('ModA/DISABLED_NRMM_main.ini');
      await touch('ModA/sub/DISABLED_NRMM_extra.ini');
      await touch('ModA/DISABLED_variant.ini');

      final count = await unhideModInis(p.join(tmp.path, 'ModA'));

      expect(count, 2);
      expect(exists('ModA/main.ini'), isTrue);
      expect(exists('ModA/sub/extra.ini'), isTrue);
      expect(exists('ModA/DISABLED_variant.ini'), isTrue);
    });

    test('hide then unhide is a round trip', () async {
      await touch('ModA/main.ini');
      await touch('ModA/DISABLED_variant.ini');

      await hideModInis(p.join(tmp.path, 'ModA'));
      await unhideModInis(p.join(tmp.path, 'ModA'));

      expect(exists('ModA/main.ini'), isTrue);
      expect(exists('ModA/DISABLED_variant.ini'), isTrue);
      expect(exists('ModA/DISABLED_NRMM_main.ini'), isFalse);
    });

    test('hiding twice does not double the prefix', () async {
      await touch('ModA/main.ini');
      await hideModInis(p.join(tmp.path, 'ModA'));
      final second = await hideModInis(p.join(tmp.path, 'ModA'));

      expect(second, 0);
      expect(exists('ModA/DISABLED_NRMM_main.ini'), isTrue);
    });

    test('unhide never overwrites an existing file', () async {
      await touch('ModA/main.ini');
      await touch('ModA/DISABLED_NRMM_main.ini');

      final count = await unhideModInis(p.join(tmp.path, 'ModA'));

      expect(count, 0);
      expect(exists('ModA/main.ini'), isTrue);
      expect(exists('ModA/DISABLED_NRMM_main.ini'), isTrue);
    });

    test('missing folder is a no-op', () async {
      expect(await hideModInis(p.join(tmp.path, 'nope')), 0);
      expect(await unhideModInis(p.join(tmp.path, 'nope')), 0);
    });
  });

  group('applyGroupVisibility', () {
    Future<void> makeGroup() async {
      await touch('group_1/ModA/a.ini');
      await touch('group_1/ModB/b.ini');
      await touch('group_1/DISABLEDModC/c.ini');
    }

    final group = () => p.join(tmp.path, 'group_1');

    test('only equipped: hides everything except the equipped mod', () async {
      await makeGroup();

      final changed = await applyGroupVisibility(
        group(),
        onlyEquipped: true,
        equippedFolder: 'ModB',
      );

      expect(changed, 1);
      expect(exists('group_1/ModA/DISABLED_NRMM_a.ini'), isTrue);
      expect(exists('group_1/ModB/b.ini'), isTrue);
      expect(exists('group_1/DISABLEDModC/c.ini'), isTrue);
    });

    test('switching equipped mod swaps which one is hidden', () async {
      await makeGroup();
      await applyGroupVisibility(group(),
          onlyEquipped: true, equippedFolder: 'ModB');

      final changed = await applyGroupVisibility(
        group(),
        onlyEquipped: true,
        equippedFolder: 'ModA',
      );

      expect(changed, 2);
      expect(exists('group_1/ModA/a.ini'), isTrue);
      expect(exists('group_1/ModB/DISABLED_NRMM_b.ini'), isTrue);
    });

    test('equipped "none" hides every mod', () async {
      await makeGroup();

      await applyGroupVisibility(group(), onlyEquipped: true, equippedFolder: '');

      expect(exists('group_1/ModA/DISABLED_NRMM_a.ini'), isTrue);
      expect(exists('group_1/ModB/DISABLED_NRMM_b.ini'), isTrue);
    });

    test('load all: un-hides everything', () async {
      await makeGroup();
      await applyGroupVisibility(group(), onlyEquipped: true, equippedFolder: '');

      final changed = await applyGroupVisibility(
        group(),
        onlyEquipped: false,
        equippedFolder: '',
      );

      expect(changed, 2);
      expect(exists('group_1/ModA/a.ini'), isTrue);
      expect(exists('group_1/ModB/b.ini'), isTrue);
    });

    test('no change means zero renames (so no F10 needed)', () async {
      await makeGroup();
      await applyGroupVisibility(group(),
          onlyEquipped: true, equippedFolder: 'ModA');

      final changed = await applyGroupVisibility(
        group(),
        onlyEquipped: true,
        equippedFolder: 'ModA',
      );

      expect(changed, 0);
    });
  });

  group('load mode and equipped files', () {
    test('missing loadmode file means inherit', () async {
      expect(await readGroupLoadMode(tmp.path), GroupLoadMode.inherit);
    });

    test('loadmode round trip', () async {
      for (final mode in GroupLoadMode.values) {
        await writeGroupLoadMode(tmp.path, mode);
        expect(await readGroupLoadMode(tmp.path), mode);
      }
    });

    test('inherit removes the file', () async {
      await writeGroupLoadMode(tmp.path, GroupLoadMode.onlyEquipped);
      await writeGroupLoadMode(tmp.path, GroupLoadMode.inherit);
      expect(File(p.join(tmp.path, 'loadmode')).existsSync(), isFalse);
    });

    test('garbage loadmode file means inherit', () async {
      await File(p.join(tmp.path, 'loadmode')).writeAsString('banana');
      expect(await readGroupLoadMode(tmp.path), GroupLoadMode.inherit);
    });

    test('equipped mod: missing is null, none is empty, name round trips',
        () async {
      expect(await readEquippedMod(tmp.path), isNull);
      await writeEquippedMod(tmp.path, '');
      expect(await readEquippedMod(tmp.path), '');
      await writeEquippedMod(tmp.path, 'Some Mod');
      expect(await readEquippedMod(tmp.path), 'Some Mod');
    });

    test('isOnlyEquipped resolves overrides against the global default', () {
      expect(isOnlyEquipped(GroupLoadMode.inherit, globalOn: true), isTrue);
      expect(isOnlyEquipped(GroupLoadMode.inherit, globalOn: false), isFalse);
      expect(isOnlyEquipped(GroupLoadMode.onlyEquipped, globalOn: false),
          isTrue);
      expect(isOnlyEquipped(GroupLoadMode.loadAll, globalOn: true), isFalse);
    });
  });
}
