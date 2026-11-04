import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_reload_mod_manager/custom/ui_group_import_files.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nrmm_ui_import_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<String> dir(String relative, {String? file}) async {
    final d = Directory(p.join(tmp.path, relative));
    await d.create(recursive: true);
    if (file != null) await File(p.join(d.path, file)).writeAsString('x');
    return d.path;
  }

  test('listLooseModFolders skips managed, disabled and loose files', () async {
    await dir('_MANAGED_');
    await dir('DISABLEDOld');
    await dir('disabled_two');
    await dir('Ui 10');
    await dir('Ui 2');
    await File(p.join(tmp.path, 'notes.txt')).writeAsString('x');

    final names = (await listLooseModFolders(
      tmp.path,
      '_MANAGED_',
    )).map(p.basename).toList();

    expect(names, ['Ui 2', 'Ui 10']);
  });

  test('importModFolders moves folders with their contents', () async {
    final a = await dir('Loose/A', file: 'a.ini');
    final group = await dir('_MANAGED_/group_1');

    final moved = await importModFolders([a], group);

    expect(moved, 1);
    expect(File(p.join(group, 'A', 'a.ini')).existsSync(), true);
    expect(Directory(a).existsSync(), false);
  });

  test('importModFolders never overwrites', () async {
    final a = await dir('Loose/A', file: 'new.ini');
    final group = await dir('_MANAGED_/group_1');
    await dir('_MANAGED_/group_1/A', file: 'old.ini');

    final moved = await importModFolders([a], group);

    expect(moved, 1);
    expect(File(p.join(group, 'A', 'old.ini')).existsSync(), true);
    expect(File(p.join(group, 'A_1', 'new.ini')).existsSync(), true);
  });
}
