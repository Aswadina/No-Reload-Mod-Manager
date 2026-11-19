// Renders the real GameBanana tab with recorded GameBanana data, at the smallest
// window NRMM allows and at larger ones. Any layout overflow or exception
// fails the test. Pictures cannot load in tests, so their error icon shows.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:flutter/services.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_image_viewer.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_services.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_tab.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_widgets.dart';
import 'package:no_reload_mod_manager/data/mod_data.dart';
import 'package:no_reload_mod_manager/utils/constant_var.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

String _fixture(String name) =>
    File('test/fixtures/gb/$name').readAsStringSync();

ModGroupData _group(String name, int index, String root) => ModGroupData(
  groupPath: p.join(root, 'group_$index'),
  iconPath: null,
  groupName: name,
  favoriteDateTime: null,
  modsInGroup: [
    ModData(
      modPath: 'None',
      iconPath: null,
      modName: 'None',
      realIndex: 0,
      isOldAutoFixed: false,
      isSyntaxErrorRemoved: false,
      isUnoptimized: false,
      isNamespaced: false,
      isDisabled: false,
      favoriteDateTime: null,
    ),
  ],
  realIndex: index,
  previousSelectedModOnGroup: 0,
);

/// Pumps frames while letting real file and timer work finish
/// (pumpAndSettle alone runs on a fake clock that never lets real I/O complete).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory tmp;
  late List<Uri> requests;

  setUp(() async {
    gbUsePoppins = false;
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('nrmm_gb_widget_');
    requests = [];
    gbApi = GbApi(
      MockClient((request) async {
        requests.add(request.url);
        final path = request.url.path;
        if (path.endsWith('/Mod/Categories')) {
          return http.Response(_fixture('categories.json'), 200);
        }
        if (path.endsWith('/ProfilePage')) {
          return http.Response(_fixture('profile.json'), 200);
        }
        return http.Response(_fixture('browse.json'), 200);
      }),
    );
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> pumpTab(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          targetGameProvider.overrideWith((ref) => TargetGame.Genshin_Impact),
          validModsPath.overrideWith((ref) => tmp.path),
          tabIndexProvider.overrideWith((ref) => gbTabIndex),
          modGroupDataProvider.overrideWith(
            (ref) => [
              _group('Raiden Shogun', 1, tmp.path),
              _group('Mavuika - Nord Express', 2, tmp.path),
              _group('group_3', 3, tmp.path), // unnamed: must not become a chip
            ],
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(body: TabGameBanana()),
        ),
      ),
    );
    await settle(tester);
  }

  for (final size in const [
    Size(750, 412), // smallest window NRMM allows
    Size(1000, 700),
    Size(1500, 900),
  ]) {
    testWidgets(
      'browse screen and dialogs at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await pumpTab(tester, size);
        expect(tester.takeException(), isNull);

        // The grid and the one filter row are there.
        expect(find.text('Travelerless 7.2'), findsOneWidget);
        expect(find.text('Mavuika - Nord Express'), findsOneWidget);
        expect(find.textContaining('Category:'), findsOneWidget);
        expect(find.textContaining('Find mods for'), findsOneWidget);
        expect(find.textContaining('Sort:'), findsOneWidget);
        expect(
          find.textContaining('page 1 of'),
          size.width > 800 ? findsOneWidget : findsNothing,
        );

        // "Find mods for" lists the user's groups, trimmed, without unnamed ones.
        await tester.tap(find.textContaining('Find mods for'));
        await settle(tester);
        expect(find.text('Raiden Shogun'), findsOneWidget);
        expect(find.text('Mavuika'), findsOneWidget);
        expect(find.text('group_3'), findsNothing);
        await tester.tapAt(const Offset(4, 4)); // close the menu
        await settle(tester);

        // It asked for the first page only, nothing more.
        final browseCalls =
            requests.where((u) => u.path.endsWith('/Mod/Index')).toList();
        expect(browseCalls.length, 1);
        expect(browseCalls.single.queryParameters['_nPage'], '1');

        // Open a mod: the large details dialog.
        await tester.ensureVisible(find.text('Travelerless 7.2'));
        await settle(tester);
        await tester.tap(find.text('Travelerless 7.2'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('About'), findsOneWidget);
        expect(find.textContaining('Files'), findsWidgets);
        expect(find.text('Credits & license'), findsOneWidget);
        expect(find.text('Download'), findsOneWidget);
        expect(find.text('Put it in'), findsOneWidget);

        // Each tab renders (a short window shows them by scrolling, so only check tall ones).
        if (size.height >= 600) {
          await tester.tap(find.textContaining('Files ('));
          await settle(tester);
          expect(find.text('travelerless_standard.zip'), findsOneWidget);
          await tester.tap(find.text('Credits & license'));
          await settle(tester);
          expect(find.text('Key Authors'), findsOneWidget);
          expect(find.text('Hoonah (artist)'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        // The group picker opens from the "Put it in" row.
        await tester.tap(find.text('Put it in'));
        await settle(tester);
        expect(find.text('Put it in…'), findsOneWidget);
        expect(find.text('New group…'), findsOneWidget);
        expect(find.text('All groups'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // The new-group form appears.
        await tester.tap(find.text('New group…'));
        await settle(tester);
        expect(find.text('Name of the new group'), findsOneWidget);
        expect(find.text('UI group (several on)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('searching and picking a category use the right requests', (
    tester,
  ) async {
    await pumpTab(tester, const Size(1000, 700));
    requests.clear();

    // Category menu: lists the categories with counts, and filters by the one picked.
    await tester.tap(find.textContaining('Category:'));
    await settle(tester);
    expect(find.text('All categories'), findsOneWidget);
    expect(find.textContaining('12,644'), findsOneWidget);
    await tester.tap(find.textContaining('12,644'));
    await settle(tester);
    final browse = requests.where((u) => u.path.endsWith('/Mod/Index')).single;
    expect(browse.queryParameters['_aFilters[Generic_Category]'], '17510');
    expect(find.textContaining('Category: Skins'), findsOneWidget);

    // A group in "Find mods for" searches by the trimmed character name.
    requests.clear();
    await tester.tap(find.textContaining('Find mods for'));
    await settle(tester);
    await tester.tap(find.text('Mavuika'));
    await settle(tester);
    final search =
        requests.where((u) => u.path.endsWith('/Util/Search/Results')).single;
    expect(search.queryParameters['_sSearchString'], 'Mavuika');
    expect(search.queryParameters['_nPage'], '1');
    expect(find.textContaining('For: Mavuika'), findsOneWidget);
    // Searching leaves the category.
    expect(find.textContaining('Category: All'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failing server shows a message with Try again', (
    tester,
  ) async {
    gbApi = GbApi(MockClient((r) async => http.Response('{}', 500)));
    await pumpTab(tester, const Size(1000, 700));
    expect(find.textContaining('having problems'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page buttons load the page asked for', (tester) async {
    await pumpTab(tester, const Size(1200, 700));
    requests.clear();
    await tester.tap(find.text('3').first);
    await settle(tester);
    final call = requests.where((u) => u.path.endsWith('/Mod/Index')).single;
    expect(call.queryParameters['_nPage'], '3');
    expect(find.textContaining('page 3 of'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full-screen viewer moves with arrow keys and closes with Esc', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    unawaited(
      showGbImageViewer(ctx, const [
        'http://x/1.jpg',
        'http://x/2.jpg',
        'http://x/3.jpg',
      ], 0),
    );
    await settle(tester);
    expect(find.textContaining('1 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(find.textContaining('2 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);
    expect(find.textContaining('1 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.textContaining('/ 3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Keep the body parse honest: the fixture is valid JSON.
  test('fixtures are valid JSON', () {
    for (final n in ['browse.json', 'profile.json', 'categories.json']) {
      expect(() => jsonDecode(_fixture(n)), returnsNormally);
    }
  });
}
