import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_reload_mod_manager/custom/ui_group_files.dart';
import 'package:no_reload_mod_manager/custom/ui_group_manage.dart';
import 'package:no_reload_mod_manager/data/mod_data.dart';
import 'package:path/path.dart' as p;

ModData _mod(String path, int i) => ModData(
  modPath: path,
  iconPath: null,
  modName: p.basename(path),
  realIndex: i,
  isOldAutoFixed: false,
  isSyntaxErrorRemoved: false,
  isUnoptimized: false,
  isNamespaced: false,
  isDisabled: false,
  favoriteDateTime: null,
);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nrmm_ui_manage_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<String> dir(String relative) async {
    final d = Directory(p.join(tmp.path, relative));
    await d.create(recursive: true);
    return d.path;
  }

  test('prepareUiKeys numbers only UI group mods, avoiding real groups', () async {
    final normal = await dir('group_1');
    final ui = await dir('group_2');
    await setUiGroupFolder(ui, true);
    final n1 = await dir('group_1/NormalMod');
    final a = await dir('group_2/A');
    final b = await dir('group_2/B');
    final off = await dir('group_2/DISABLEDC');

    final pairs = {
      (normal, 1): [_mod('None', 0), _mod(n1, 1)],
      (ui, 2): [_mod('None', 0), _mod(a, 1), _mod(b, 2), _mod(off, 3)],
    };
    final keys = await prepareUiKeys(pairs);

    expect(keys.keys.toSet(), {a, b});
    expect(keys.values.toSet().length, 2);
    for (final k in keys.values) {
      expect(k, inInclusiveRange(1, 500));
      expect({1, 2}.contains(k), false);
    }
  });

  test('manageUiGroup writes one group ini per mod and manages each', () async {
    final ui = await dir('group_2');
    final a = await dir('group_2/A');
    final b = await dir('group_2/B');
    final managed = <String, int>{};
    final errors = <String>[];

    await manageUiGroup(
      groupPath: ui,
      mods: [_mod('None', 0), _mod(a, 1), _mod(b, 2)],
      keys: {a: 7},
      manageMod: (path, k) async => managed[path] = k,
      template: 'namespace = modmanageragl\\{group_x}\n\$group_id = {x}',
      logError: errors.add,
    );

    expect(managed, {a: 7});
    expect(
      File(p.join(ui, 'group_7.ini')).readAsStringSync(),
      contains(r'modmanageragl\group_7'),
    );
    expect(errors.single, contains('B'));
  });
}
