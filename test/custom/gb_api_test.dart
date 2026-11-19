import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';

String _fixture(String name) => File('test/fixtures/gb/$name').readAsStringSync();

GbApi _apiReturning(String body, {int status = 200, List<Uri>? seen}) =>
    GbApi(
      MockClient((request) async {
        seen?.add(request.url);
        return http.Response(body, status);
      }),
    );

void main() {
  test('browse parses a real page', () async {
    final page = await _apiReturning(_fixture('browse.json')).browse(
      gameId: 8552,
      page: 1,
      sort: GbSort.newest,
    );

    expect(page.totalCount, 13254);
    expect(page.mods.length, 2);
    final first = page.mods.first;
    expect(first.id, 736306);
    expect(first.name, 'Travelerless 7.2');
    expect(first.authorName, 'Hoonah');
    expect(first.likeCount, 10);
    expect(
      first.thumbUrl,
      'https://images.gamebanana.com/img/ss/mods/530-90_6aeb61e72723d.jpg',
    );
    expect(first.dateUpdated, isNull); // missing in the real data; must not crash
  });

  test('browse tolerates a record with no images and no version', () async {
    const body =
        '{"_aMetadata":{"_nRecordCount":1,"_nPerpage":15},"_aRecords":[{"_idRow":5,"_sName":"Bare"}]}';
    final page = await _apiReturning(body).browse(
      gameId: 1,
      page: 1,
      sort: GbSort.newest,
    );
    expect(page.mods.single.name, 'Bare');
    expect(page.mods.single.thumbUrl, isNull);
    expect(page.mods.single.version, '');
  });

  test('details parses files, checksum and flags', () async {
    final d = await _apiReturning(_fixture('profile.json')).details(736306);

    expect(d.mod.id, 736306);
    expect(d.mod.authorName, 'Hoonah');
    expect(d.files.length, 3);
    final f = d.files.first;
    expect(f.id, 1876598);
    expect(f.fileName, 'travelerless_standard.zip');
    expect(f.size, 3360758);
    expect(f.downloadUrl, 'https://gamebanana.com/dl/1876598');
    expect(f.md5, '36be8876daae24b4e6b1cecc146942e9');
    expect(f.isClean, true);
    expect(d.isBlocked, false);
    expect(d.images, isNotEmpty);
    expect(d.descriptionHtml, contains('like or agree'));
  });

  test('browse builds the exact url', () async {
    final seen = <Uri>[];
    await _apiReturning(_fixture('browse.json'), seen: seen).browse(
      gameId: 8552,
      page: 3,
      sort: GbSort.mostLiked,
    );
    final u = seen.single;
    expect(u.path, '/apiv11/Mod/Index');
    expect(u.queryParameters['_nPage'], '3');
    expect(u.queryParameters['_nPerpage'], '20');
    expect(u.queryParameters['_aFilters[Generic_Game]'], '8552');
    expect(u.queryParameters['_sSort'], 'Generic_MostLiked');
  });

  test('search builds the exact url', () async {
    final seen = <Uri>[];
    await _apiReturning(_fixture('browse.json'), seen: seen).search(
      gameId: 8552,
      query: 'hu tao',
      page: 1,
    );
    final u = seen.single;
    expect(u.path, '/apiv11/Util/Search/Results');
    expect(u.queryParameters['_sSearchString'], 'hu tao');
    expect(u.queryParameters['_idGameRow'], '8552');
    expect(u.queryParameters['_sModelName'], 'Mod');
  });

  test('errors become GbException', () async {
    for (final status in [400, 429, 500]) {
      expect(
        () => _apiReturning('{}', status: status).browse(
          gameId: 1,
          page: 1,
          sort: GbSort.newest,
        ),
        throwsA(
          isA<GbException>().having((e) => e.statusCode, 'status', status),
        ),
      );
    }
  });

  test('garbage json becomes GbException', () async {
    expect(
      () => _apiReturning('<html>oops</html>').browse(
        gameId: 1,
        page: 1,
        sort: GbSort.newest,
      ),
      throwsA(isA<GbException>()),
    );
  });

  test('browse record carries category, sub-category, views and tags', () async {
    final page = await _apiReturning(_fixture('browse.json')).browse(
      gameId: 8552,
      page: 1,
      sort: GbSort.newest,
    );
    expect(page.mods[0].categoryName, 'UI');
    expect(page.mods[0].subCategoryName, '');
    expect(page.mods[1].categoryName, 'Skins');
    expect(page.mods[1].subCategoryName, 'Mavuika');
    expect(page.mods[1].viewCount, 756);
    expect(page.mods[1].tags, contains('Character: Mavuika'));
  });

  test('browse with a category adds the category filter', () async {
    final seen = <Uri>[];
    await _apiReturning(_fixture('browse.json'), seen: seen).browse(
      gameId: 8552,
      page: 1,
      sort: GbSort.newest,
      categoryId: 22474,
    );
    expect(seen.single.queryParameters['_aFilters[Generic_Category]'], '22474');
  });

  test('categories parse the real list', () async {
    final seen = <Uri>[];
    final cats = await _apiReturning(_fixture('categories.json'), seen: seen)
        .categories(8552);
    expect(seen.single.path, '/apiv11/Mod/Categories');
    expect(seen.single.queryParameters['_idGameRow'], '8552');
    expect(cats.length, 7);
    final skins = cats.firstWhere((c) => c.name == 'Skins');
    expect(skins.id, 17510);
    expect(skins.itemCount, 12644);
  });

  test('page math', () {
    GbPage page(int total) => GbPage(mods: const [], totalCount: total, page: 1);
    expect(page(0).totalPages, 0);
    expect(page(1).totalPages, 1);
    expect(page(20).totalPages, 1);
    expect(page(21).totalPages, 2);
    expect(page(13254).totalPages, 663);
  });

  test('details carry credits, license, requirements, counts and category', () async {
    final d = await _apiReturning(_fixture('profile.json')).details(736306);
    expect(d.categoryName, 'UI');
    expect(
      d.fullImages.first,
      'https://images.gamebanana.com/img/ss/mods/6aeb61e72723d.jpg',
    );
    expect(d.images.first, contains('530-90_6aeb61e72723d.jpg'));
    expect(d.downloadCount, 14);
    expect(d.viewCount, 150);
    expect(d.likeCount, 10);
    expect(d.credits.single.name, 'Key Authors');
    expect(d.credits.single.people.single, 'Hoonah (artist)');
    expect(d.license['yes'], contains('Download and install this Mod'));
    expect(d.license['ask'], isNotEmpty);
    expect(d.tags, isEmpty);
    expect(d.requirements, isEmpty);
  });

  test('requirements and object tags parse', () async {
    const body =
        '{"_idRow":1,"_sName":"x","_aFiles":[],"_aRequirements":[["3dmigoto GIMI","https://example.com/gimi"]],"_aTags":[{"_sValue":"Theme: Winter"},"Plain"]}';
    final d = await _apiReturning(body).details(1);
    expect(d.requirements.single.name, '3dmigoto GIMI');
    expect(d.requirements.single.url, 'https://example.com/gimi');
    expect(d.tags, ['Theme: Winter', 'Plain']);
  });
}
