import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_reload_mod_manager/custom/drop_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  List<String> parse(String raw) => parseDropPaths([File(raw)]);

  test('backslash before n or r in a Windows path is not a line break', () {
    expect(parse(r'C:\Users\me\Downloads\nahida_mod.zip'),
        [p.normalize(r'C:\Users\me\Downloads\nahida_mod.zip')]);
    expect(parse(r'C:\Users\me\Downloads\raiden\new_mod'),
        [p.normalize(r'C:\Users\me\Downloads\raiden\new_mod')]);
  });

  test('literal \\n between two paths still splits them', () {
    expect(parse(r'C:\a\one.zip\nD:\b\two.zip'),
        [p.normalize(r'C:\a\one.zip'), p.normalize(r'D:\b\two.zip')]);
  });

  test('real newlines still split', () {
    expect(parse('C:\\a\\one.zip\r\nC:\\a\\two.zip'),
        [p.normalize(r'C:\a\one.zip'), p.normalize(r'C:\a\two.zip')]);
  });
}
