// GameBanana tab — download, check, unpack and place (or swap) a mod.
//
// Nothing here touches the user's mods until the download is verified and
// unpacked. An update moves the old folder to a backup folder and never
// deletes it. The unpacker is passed in so tests do not need 7-Zip.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_source.dart';
import 'package:no_reload_mod_manager/custom/ui_group_import_files.dart';
import 'package:path/path.dart' as p;

typedef GbExtract = Future<bool> Function(String archivePath, String outDir);

/// Installs [file] as a new mod folder inside [groupPath]. Returns its path.
Future<String> installFile({
  required http.Client client,
  required GbModDetails details,
  required GbFile file,
  required String groupPath,
  required String tempRoot,
  required GbExtract extract,
  void Function(String status)? onStatus,
}) async {
  final workDir = await _newWorkDir(tempRoot, file.id);
  try {
    final staged = await _fetchAndStage(
      client: client,
      file: file,
      workDir: workDir,
      fallbackName: _safeName(details.mod.name),
      extract: extract,
      onStatus: onStatus,
    );
    onStatus?.call('Adding to your group…');
    final path = await moveFolderInto(staged, groupPath);
    await writeGbSource(path, _sourceFor(details, file));
    return path;
  } finally {
    await _cleanup(workDir);
  }
}

/// Replaces [existingModPath] with [file]. The new folder keeps the old name
/// and place. The old folder goes to [backupRoot]. If anything fails after the
/// old folder was moved, it is put back. Files named in [carryOverFiles]
/// (like the user's own icon) are copied from the old folder.
Future<String> updateMod({
  required http.Client client,
  required GbModDetails details,
  required GbFile file,
  required String existingModPath,
  required String backupRoot,
  required String tempRoot,
  required GbExtract extract,
  List<String> carryOverFiles = const [],
  void Function(String status)? onStatus,
}) async {
  final workDir = await _newWorkDir(tempRoot, file.id);
  try {
    final oldName = p.basename(existingModPath);
    final staged = await _fetchAndStage(
      client: client,
      file: file,
      workDir: workDir,
      fallbackName: oldName,
      forceName: oldName,
      extract: extract,
      onStatus: onStatus,
    );

    onStatus?.call('Swapping in the new version…');
    final groupPath = p.dirname(existingModPath);
    final backupPath = await moveFolderInto(existingModPath, backupRoot);
    try {
      final path = await moveFolderInto(staged, groupPath);
      for (final name in carryOverFiles) {
        final from = File(p.join(backupPath, name));
        final to = File(p.join(path, name));
        if (await from.exists() && !await to.exists()) await from.copy(to.path);
      }
      await writeGbSource(path, _sourceFor(details, file));
      return path;
    } catch (_) {
      // Put the old version back exactly where it was.
      await Directory(existingModPath).delete(recursive: true).catchError(
        (_) => Directory(existingModPath),
      );
      await Directory(backupPath).rename(existingModPath);
      rethrow;
    }
  } finally {
    await _cleanup(workDir);
  }
}

GbSource _sourceFor(GbModDetails details, GbFile file) => GbSource(
  modId: details.mod.id,
  fileId: file.id,
  fileDate: file.dateAdded,
  modDateUpdated: details.mod.dateUpdated ?? file.dateAdded,
  downloadedAt: DateTime.now().toIso8601String(),
);

Future<String> _newWorkDir(String tempRoot, int fileId) async {
  final dir = p.join(
    tempRoot,
    'gb_${fileId}_${DateTime.now().microsecondsSinceEpoch}',
  );
  await Directory(dir).create(recursive: true);
  return dir;
}

Future<void> _cleanup(String workDir) async {
  try {
    await Directory(workDir).delete(recursive: true);
  } catch (_) {}
}

/// Downloads, verifies and unpacks. Returns a staged folder whose name is the
/// name the mod should get. Throws [GbException] and leaves nothing behind
/// outside [workDir].
Future<String> _fetchAndStage({
  required http.Client client,
  required GbFile file,
  required String workDir,
  required String fallbackName,
  String? forceName,
  required GbExtract extract,
  void Function(String status)? onStatus,
}) async {
  final archive = p.join(workDir, _safeFileName(file.fileName));

  onStatus?.call('Downloading ${file.fileName}…');
  final response = await client
      .send(
        http.Request('GET', Uri.parse(file.downloadUrl))
          ..headers['User-Agent'] = 'NRMM-personal',
      )
      .timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    throw GbException(
      'The download failed (HTTP ${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }
  await response.stream.pipe(File(archive).openWrite());

  if (file.md5.isNotEmpty) {
    onStatus?.call('Checking the download…');
    final actual = (await md5.bind(File(archive).openRead()).first).toString();
    if (actual != file.md5.toLowerCase()) {
      throw GbException(
        'The download did not match GameBanana\'s checksum, so it was not installed.',
      );
    }
  }

  onStatus?.call('Unpacking…');
  final extracted = p.join(workDir, 'extracted');
  if (!await extract(archive, extracted)) {
    throw GbException('Could not unpack ${file.fileName}.');
  }
  final entries = await Directory(extracted).list().toList();
  if (entries.isEmpty) {
    throw GbException('The download had no files in it.');
  }

  // One wrapper folder with nothing beside it IS the mod. Otherwise the
  // whole archive is the mod.
  final bool wrapper = entries.length == 1 && entries.single is Directory;
  final name = forceName ?? (wrapper ? p.basename(entries.single.path) : fallbackName);
  final finalDir = Directory(p.join(workDir, 'final'));
  await finalDir.create();
  final target = p.join(finalDir.path, name);
  await Directory(wrapper ? entries.single.path : extracted).rename(target);
  return target;
}

String _safeName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '');
  final short = cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned;
  return short.isEmpty ? 'GameBanana mod' : short;
}

String _safeFileName(String name) {
  final base = p.basename(name.replaceAll('\\', '/'));
  final cleaned = base.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  return cleaned.isEmpty ? 'download.bin' : cleaned;
}
