import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_install.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_source.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late String group;
  late String temp;
  late String backup;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nrmm_gb_install_');
    group = p.join(tmp.path, '_MANAGED_', 'group_1');
    temp = p.join(tmp.path, 'temp');
    backup = p.join(tmp.path, 'backup');
    await Directory(group).create(recursive: true);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  final bytes = utf8.encode('pretend archive');
  final goodMd5 = md5.convert(bytes).toString();

  GbFile file({String? md5Sum, int id = 11, int date = 5000}) => GbFile(
    id: id,
    fileName: 'My Mod v2.zip',
    size: bytes.length,
    dateAdded: date,
    downloadUrl: 'https://gamebanana.com/dl/$id',
    md5: md5Sum ?? goodMd5,
    isClean: true,
    description: '',
  );

  GbModDetails details(GbFile f, {String name = 'My: Mod?'}) => GbModDetails(
    mod: GbMod(
      id: 99,
      name: name,
      profileUrl: '',
      version: '',
      authorName: 'a',
      likeCount: 0,
      thumbUrl: null,
      dateAdded: null,
      dateUpdated: 4000,
    ),
    files: [f],
    images: const [],
    descriptionHtml: '',
    isBlocked: false,
  );

  http.Client client({int status = 200}) =>
      MockClient((r) async => http.Response.bytes(bytes, status));

  /// Fake unpacker: writes the given relative files into the output folder.
  GbExtract fakeExtract(Map<String, String> files, {bool ok = true}) =>
      (archive, outDir) async {
        expect(File(archive).existsSync(), true);
        await Directory(outDir).create(recursive: true);
        for (final e in files.entries) {
          final f = File(p.join(outDir, e.key));
          await f.parent.create(recursive: true);
          await f.writeAsString(e.value);
        }
        return ok;
      };

  Future<String> install(
    Map<String, String> files, {
    GbFile? f,
    bool ok = true,
    String name = 'My: Mod?',
  }) {
    final theFile = f ?? file();
    return installFile(
      client: client(),
      details: details(theFile, name: name),
      file: theFile,
      groupPath: group,
      tempRoot: temp,
      extract: fakeExtract(files, ok: ok),
    );
  }

  test('single wrapper folder becomes the mod folder', () async {
    final path = await install({'CoolMod/main.ini': 'x', 'CoolMod/a.dds': 'y'});
    expect(p.basename(path), 'CoolMod');
    expect(File(p.join(path, 'main.ini')).existsSync(), true);
    expect(File(p.join(path, 'gbsource.json')).existsSync(), true);
    final src = await readGbSource(path);
    expect(src!.modId, 99);
    expect(src.fileId, 11);
    expect(src.fileDate, 5000);
    expect(src.modDateUpdated, 4000);
  });

  test('loose files go into a folder named after the mod, made safe', () async {
    final path = await install({'main.ini': 'x', 'a.dds': 'y'});
    expect(p.basename(path), 'My Mod'); // ':' and '?' removed
    expect(File(p.join(path, 'main.ini')).existsSync(), true);
  });

  test('several folders are kept together in one mod folder', () async {
    final path = await install({'A/a.ini': 'x', 'B/b.ini': 'y'});
    expect(p.basename(path), 'My Mod');
    expect(File(p.join(path, 'A', 'a.ini')).existsSync(), true);
    expect(File(p.join(path, 'B', 'b.ini')).existsSync(), true);
  });

  test('never overwrites an existing mod folder', () async {
    await Directory(p.join(group, 'CoolMod')).create();
    await File(p.join(group, 'CoolMod', 'old.ini')).writeAsString('old');
    final path = await install({'CoolMod/new.ini': 'x'});
    expect(p.basename(path), 'CoolMod_1');
    expect(File(p.join(group, 'CoolMod', 'old.ini')).existsSync(), true);
  });

  test('md5 mismatch installs nothing and cleans temp', () async {
    await expectLater(
      install({'CoolMod/main.ini': 'x'}, f: file(md5Sum: 'deadbeef')),
      throwsA(isA<GbException>()),
    );
    expect(Directory(group).listSync(), isEmpty);
    expect(Directory(temp).existsSync() ? Directory(temp).listSync() : [], isEmpty);
  });

  test('failed unpack installs nothing', () async {
    await expectLater(
      install({'CoolMod/main.ini': 'x'}, ok: false),
      throwsA(isA<GbException>()),
    );
    expect(Directory(group).listSync(), isEmpty);
  });

  test('http error installs nothing', () async {
    final f = file();
    await expectLater(
      installFile(
        client: client(status: 404),
        details: details(f),
        file: f,
        groupPath: group,
        tempRoot: temp,
        extract: fakeExtract({'a.ini': 'x'}),
      ),
      throwsA(isA<GbException>()),
    );
    expect(Directory(group).listSync(), isEmpty);
  });

  Future<String> makeOld() async {
    final old = p.join(group, 'CoolMod');
    await Directory(old).create();
    await File(p.join(old, 'old.ini')).writeAsString('old');
    await File(p.join(old, 'icon.png')).writeAsString('my icon');
    await writeGbSource(
      old,
      const GbSource(
        modId: 99,
        fileId: 1,
        fileDate: 1,
        modDateUpdated: 1,
        downloadedAt: 'x',
      ),
    );
    return old;
  }

  test('update swaps the folder, keeps the old one in backup, carries icon', () async {
    final old = await makeOld();
    final f = file(id: 12, date: 6000);
    final path = await updateMod(
      client: client(),
      details: details(f),
      file: f,
      existingModPath: old,
      backupRoot: backup,
      tempRoot: temp,
      extract: fakeExtract({'CoolMod/new.ini': 'new'}),
      carryOverFiles: const ['icon.png'],
    );

    expect(p.equals(path, old), true); // same name, same place
    expect(File(p.join(old, 'new.ini')).existsSync(), true);
    expect(File(p.join(old, 'old.ini')).existsSync(), false);
    expect(File(p.join(old, 'icon.png')).readAsStringSync(), 'my icon');
    expect((await readGbSource(old))!.fileId, 12);
    final kept = Directory(backup).listSync().single.path;
    expect(File(p.join(kept, 'old.ini')).existsSync(), true);
  });

  test('failed update leaves the old folder untouched', () async {
    final old = await makeOld();
    final f = file(md5Sum: 'deadbeef', id: 12, date: 6000);
    await expectLater(
      updateMod(
        client: client(),
        details: details(f),
        file: f,
        existingModPath: old,
        backupRoot: backup,
        tempRoot: temp,
        extract: fakeExtract({'CoolMod/new.ini': 'new'}),
      ),
      throwsA(isA<GbException>()),
    );
    expect(File(p.join(old, 'old.ini')).existsSync(), true);
    expect((await readGbSource(old))!.fileId, 1);
    expect(Directory(backup).existsSync() ? Directory(backup).listSync() : [], isEmpty);
  });
}
