import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_source.dart';
import 'package:path/path.dart' as p;

GbMod _mod({int id = 1, int? updated}) => GbMod(
  id: id,
  name: 'n',
  profileUrl: '',
  version: '',
  authorName: '',
  likeCount: 0,
  thumbUrl: null,
  dateAdded: null,
  dateUpdated: updated,
);

GbFile _file(int id, int date) => GbFile(
  id: id,
  fileName: 'f.zip',
  size: 1,
  dateAdded: date,
  downloadUrl: '',
  md5: '',
  isClean: true,
  description: '',
);

GbModDetails _details(List<GbFile> files) => GbModDetails(
  mod: _mod(),
  files: files,
  images: const [],
  descriptionHtml: '',
  isBlocked: false,
);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nrmm_gb_source_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<String> dir(String relative) async {
    final d = Directory(p.join(tmp.path, relative));
    await d.create(recursive: true);
    return d.path;
  }

  const source = GbSource(
    modId: 42,
    fileId: 100,
    fileDate: 1000,
    modDateUpdated: 2000,
    downloadedAt: '2026-11-04T10:00:00.000',
  );

  test('source round trips through the mod folder', () async {
    final m = await dir('group_1/ModA');
    await writeGbSource(m, source);
    final back = await readGbSource(m);
    expect(back!.modId, 42);
    expect(back.fileId, 100);
    expect(back.fileDate, 1000);
    expect(back.modDateUpdated, 2000);
  });

  test('garbage source file reads as null', () async {
    final m = await dir('group_1/ModA');
    await File(p.join(m, 'gbsource.json')).writeAsString('not json');
    expect(await readGbSource(m), isNull);
    await File(p.join(m, 'gbsource.json')).writeAsString('{"modId":"x"}');
    expect(await readGbSource(m), isNull);
  });

  test('scanInstalled finds sourced mods one group deep and ignores others', () async {
    final a = await dir('group_1/ModA');
    await dir('group_1/Plain');
    await dir('group_2/ModB');
    await writeGbSource(a, source);
    await writeGbSource(
      p.join(tmp.path, 'group_2', 'ModB'),
      const GbSource(
        modId: 7,
        fileId: 1,
        fileDate: 1,
        modDateUpdated: null,
        downloadedAt: 'x',
      ),
    );

    final found = await scanInstalled(tmp.path);

    expect(found.keys.toSet(), {42, 7});
    expect(found[42]!.modPath, a);
    expect(found[7]!.source.modDateUpdated, isNull);
  });

  test('card update badge needs a newer updated date', () {
    final inst = InstalledGbMod(modPath: 'x', source: source);
    expect(hasUpdateForCard(inst, _mod(updated: 2500)), true);
    expect(hasUpdateForCard(inst, _mod(updated: 2000)), false);
    expect(hasUpdateForCard(inst, _mod(updated: null)), false);
  });

  test('exact update compares the newest file, not the version text', () {
    expect(hasUpdateExact(source, _details([_file(101, 3000), _file(100, 1000)])), true);
    expect(hasUpdateExact(source, _details([_file(100, 1000)])), false);
    // Same date or older file with a different id is not an update.
    expect(hasUpdateExact(source, _details([_file(99, 900)])), false);
    expect(hasUpdateExact(source, _details([])), false);
  });
}
