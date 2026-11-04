import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_reload_mod_manager/custom/ui_group_files.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nrmm_ui_group_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<String> mod(String name, {String? uikey}) async {
    final dir = Directory(p.join(tmp.path, name));
    await dir.create(recursive: true);
    if (uikey != null) {
      await File(p.join(dir.path, 'uikey')).writeAsString(uikey);
    }
    return dir.path;
  }

  test('uikey ignores garbage', () async {
    expect(await readUiKey(await mod('a', uikey: 'abc')), isNull);
    expect(await readUiKey(await mod('b', uikey: '0')), isNull);
    expect(await readUiKey(await mod('c', uikey: '501')), isNull);
    expect(await readUiKey(await mod('d', uikey: '7')), 7);
    expect(await readUiKey(await mod('e')), isNull);
  });

  test('uistate defaults to off and round trips', () async {
    final m = await mod('a');
    expect(await readUiOn(m), false);
    await writeUiOn(m, true);
    expect(await readUiOn(m), true);
    await writeUiOn(m, false);
    expect(await readUiOn(m), false);
    await File(p.join(m, 'uistate')).writeAsString('junk');
    expect(await readUiOn(m), false);
  });

  test('ui group marker round trips', () async {
    final g = await mod('group_1');
    expect(await isUiGroupFolder(g), false);
    await setUiGroupFolder(g, true);
    expect(await isUiGroupFolder(g), true);
    await setUiGroupFolder(g, false);
    expect(await isUiGroupFolder(g), false);
  });

  test('allocate keeps valid unique keys', () async {
    final a = await mod('a', uikey: '10');
    final b = await mod('b', uikey: '20');
    final keys = await allocateUiKeys([a, b], {1});
    expect(keys[a], 10);
    expect(keys[b], 20);
  });

  test('allocate reassigns duplicate key', () async {
    final a = await mod('a', uikey: '10');
    final b = await mod('b', uikey: '10');
    final keys = await allocateUiKeys([a, b], {});
    expect(keys[a], 10);
    expect(keys[b], isNot(10));
    expect(await readUiKey(b), keys[b]);
  });

  test('allocate skips real group numbers', () async {
    final a = await mod('a');
    final b = await mod('b', uikey: '2');
    final keys = await allocateUiKeys([a, b], {1, 2, 3});
    expect(keys[a], 4);
    expect(keys[b], 5);
  });

  test('allocate stops when pool is empty', () async {
    final paths = [for (var i = 0; i < 501; i++) await mod('m$i')];
    final keys = await allocateUiKeys(paths, {});
    expect(keys.length, 500);
    expect(keys.values.toSet().length, 500);
    expect(keys.containsKey(paths.last), false);
  });

  test('renderUiGroupIni fills both placeholders', () {
    final template = File('assets/template_txt/template_group.txt')
        .readAsStringSync();
    final out = renderUiGroupIni(template, 7);
    expect(out, contains(r'namespace = modmanageragl\group_7'));
    expect(out, contains(r'global $group_id = 7'));
    expect(out, isNot(contains('{x}')));
  });
}
