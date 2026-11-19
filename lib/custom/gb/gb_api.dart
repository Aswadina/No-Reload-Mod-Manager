// GameBanana tab — the API layer. All knowledge of GameBanana's JSON lives in
// this file, so if they change it, this is the only file to fix.
//
// Be gentle with their server: small pages, one request at a time (the UI
// awaits each call), no polling, and on 429/5xx we give up and say so.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const int gbPerPage = 20;

enum GbSort {
  newest('Generic_Newest', 'Newest'),
  mostLiked('Generic_MostLiked', 'Most liked'),
  mostDownloaded('Generic_MostDownloaded', 'Most downloaded'),
  recentlyUpdated('Generic_LatestUpdated', 'Recently updated');

  final String apiValue;
  final String label;
  const GbSort(this.apiValue, this.label);
}

class GbException implements Exception {
  final String message;
  final int? statusCode;
  GbException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class GbMod {
  final int id;
  final String name;
  final String profileUrl;
  final String version;
  final String authorName;
  final int likeCount;
  final String? thumbUrl;
  final int? dateAdded;
  final int? dateUpdated;
  final String categoryName;
  final String subCategoryName;
  final int viewCount;
  final List<String> tags;

  const GbMod({
    required this.id,
    required this.name,
    required this.profileUrl,
    required this.version,
    required this.authorName,
    required this.likeCount,
    required this.thumbUrl,
    required this.dateAdded,
    required this.dateUpdated,
    this.categoryName = '',
    this.subCategoryName = '',
    this.viewCount = 0,
    this.tags = const [],
  });

  factory GbMod.fromJson(Map<String, dynamic> j) {
    final images = _imageUrls(j['_aPreviewMedia']);
    return GbMod(
      id: _int(j['_idRow']) ?? 0,
      name: _str(j['_sName']),
      profileUrl: _str(j['_sProfileUrl']),
      version: _str(j['_sVersion']),
      authorName: _str((j['_aSubmitter'] as Map?)?['_sName']),
      likeCount: _int(j['_nLikeCount']) ?? 0,
      thumbUrl: images.isEmpty ? null : images.first,
      dateAdded: _int(j['_tsDateAdded']),
      dateUpdated: _int(j['_tsDateUpdated']),
      // Browse records name the category in _aRootCategory; a mod page in _aCategory.
      categoryName: _str(
        ((j['_aRootCategory'] ?? j['_aCategory']) as Map?)?['_sName'],
      ),
      subCategoryName: _str((j['_aSubCategory'] as Map?)?['_sName']),
      viewCount: _int(j['_nViewCount']) ?? 0,
      tags: _tags(j['_aTags']),
    );
  }
}

class GbCategory {
  final int id;
  final String name;
  final int itemCount;
  const GbCategory({
    required this.id,
    required this.name,
    required this.itemCount,
  });
}

class GbCreditGroup {
  final String name;
  final List<String> people;
  const GbCreditGroup({required this.name, required this.people});
}

class GbRequirement {
  final String name;
  final String url;
  const GbRequirement({required this.name, required this.url});
}

class GbPage {
  final List<GbMod> mods;
  final int totalCount;
  final int page;
  const GbPage({
    required this.mods,
    required this.totalCount,
    required this.page,
  });

  bool get hasMore => page * gbPerPage < totalCount;
  int get totalPages => (totalCount / gbPerPage).ceil();
}

class GbFile {
  final int id;
  final String fileName;
  final int size;
  final int dateAdded;
  final String downloadUrl;
  final String md5;
  final bool isClean;
  final String description;

  const GbFile({
    required this.id,
    required this.fileName,
    required this.size,
    required this.dateAdded,
    required this.downloadUrl,
    required this.md5,
    required this.isClean,
    required this.description,
  });

  factory GbFile.fromJson(Map<String, dynamic> j) => GbFile(
    id: _int(j['_idRow']) ?? 0,
    fileName: _str(j['_sFile']),
    size: _int(j['_nFilesize']) ?? 0,
    dateAdded: _int(j['_tsDateAdded']) ?? 0,
    downloadUrl: _str(j['_sDownloadUrl']),
    md5: _str(j['_sMd5Checksum']).toLowerCase(),
    // Only an explicit "clean" counts; anything else (unknown, infected) blocks.
    isClean: _str(j['_sAvResult']) == 'clean',
    description: _str(j['_sDescription']),
  );
}

class GbModDetails {
  final GbMod mod;
  final List<GbFile> files;
  final List<String> images;

  /// Same pictures at full size, for the big viewer.
  final List<String> fullImages;
  final String descriptionHtml;
  final bool isBlocked;
  final List<String> tags;
  final List<GbCreditGroup> credits;
  final List<GbRequirement> requirements;

  /// "yes" / "ask" / "no" -> what the author allows.
  final Map<String, List<String>> license;
  final int downloadCount;
  final int viewCount;
  final int likeCount;
  final String categoryName;

  const GbModDetails({
    required this.mod,
    required this.files,
    required this.images,
    required this.descriptionHtml,
    required this.isBlocked,
    this.fullImages = const [],
    this.tags = const [],
    this.credits = const [],
    this.requirements = const [],
    this.license = const {},
    this.downloadCount = 0,
    this.viewCount = 0,
    this.likeCount = 0,
    this.categoryName = '',
  });

  /// Newest file first, as GameBanana lists them.
  GbFile? get newestFile => files.isEmpty ? null : files.first;
}

class GbApi {
  final http.Client _client;
  GbApi(this._client);

  Future<GbPage> browse({
    required int gameId,
    required int page,
    required GbSort sort,
    int? categoryId,
  }) async {
    final json = await _get(
      Uri.https('gamebanana.com', '/apiv11/Mod/Index', {
        '_nPerpage': '$gbPerPage',
        '_nPage': '$page',
        '_aFilters[Generic_Game]': '$gameId',
        if (categoryId != null) '_aFilters[Generic_Category]': '$categoryId',
        '_sSort': sort.apiValue,
      }),
    );
    return _page(json, page);
  }

  /// The game's top-level mod categories (Skins, UI, ...), with counts.
  Future<List<GbCategory>> categories(int gameId) async {
    final json = await _getJson(
      Uri.https('gamebanana.com', '/apiv11/Mod/Categories', {
        '_idGameRow': '$gameId',
        '_sSort': 'a_to_z',
        '_bShowEmpty': 'false',
      }),
    );
    if (json is! List) {
      throw GbException('GameBanana sent something we could not read.');
    }
    return [
      for (final c in json)
        if (c is Map && _int(c['_idRow']) != null)
          GbCategory(
            id: _int(c['_idRow'])!,
            name: _str(c['_sName']),
            itemCount: _int(c['_nItemCount']) ?? 0,
          ),
    ];
  }

  Future<GbPage> search({
    required int gameId,
    required String query,
    required int page,
  }) async {
    final json = await _get(
      Uri.https('gamebanana.com', '/apiv11/Util/Search/Results', {
        '_sSearchString': query,
        '_idGameRow': '$gameId',
        '_sModelName': 'Mod',
        '_nPage': '$page',
        '_nPerpage': '$gbPerPage',
      }),
    );
    return _page(json, page);
  }

  Future<GbModDetails> details(int modId) async {
    final j = await _get(
      Uri.https('gamebanana.com', '/apiv11/Mod/$modId/ProfilePage'),
    );
    return GbModDetails(
      mod: GbMod.fromJson(j),
      files: [
        for (final f in (j['_aFiles'] as List? ?? []))
          if (f is Map<String, dynamic>) GbFile.fromJson(f),
      ],
      images: _imageUrls(j['_aPreviewMedia']),
      fullImages: _imageUrls(j['_aPreviewMedia'], full: true),
      descriptionHtml: _str(j['_sText']),
      isBlocked:
          j['_bIsWithheld'] == true ||
          j['_bIsTrashed'] == true ||
          j['_bIsPrivate'] == true,
      tags: _tags(j['_aTags']),
      credits: [
        for (final g in (j['_aCredits'] as List? ?? []))
          if (g is Map)
            GbCreditGroup(
              name: _str(g['_sGroupName']),
              people: [
                for (final a in (g['_aAuthors'] as List? ?? []))
                  if (a is Map && _str(a['_sName']).isNotEmpty)
                    _str(a['_sRole']).isEmpty
                        ? _str(a['_sName'])
                        : '${_str(a['_sName'])} (${_str(a['_sRole'])})',
              ],
            ),
      ],
      requirements: [
        for (final r in (j['_aRequirements'] as List? ?? []))
          if (r is List && r.isNotEmpty)
            GbRequirement(
              name: _str(r[0]),
              url: r.length > 1 ? _str(r[1]) : '',
            ),
      ],
      license: {
        if (j['_aLicenseChecklist'] is Map)
          for (final e in (j['_aLicenseChecklist'] as Map).entries)
            if (e.value is List)
              '${e.key}': [for (final x in e.value as List) if (x is String) x],
      },
      downloadCount: _int(j['_nDownloadCount']) ?? 0,
      viewCount: _int(j['_nViewCount']) ?? 0,
      likeCount: _int(j['_nLikeCount']) ?? 0,
      categoryName: _str((j['_aCategory'] as Map?)?['_sName']),
    );
  }

  GbPage _page(Map<String, dynamic> json, int page) {
    final meta = json['_aMetadata'];
    return GbPage(
      mods: [
        for (final r in (json['_aRecords'] as List? ?? []))
          if (r is Map<String, dynamic>) GbMod.fromJson(r),
      ],
      totalCount: meta is Map ? (_int(meta['_nRecordCount']) ?? 0) : 0,
      page: page,
    );
  }

  Future<Map<String, dynamic>> _get(Uri url) async {
    final decoded = await _getJson(url);
    if (decoded is Map<String, dynamic>) return decoded;
    throw GbException('GameBanana sent something we could not read.');
  }

  Future<Object?> _getJson(Uri url) async {
    final http.Response response;
    try {
      response = await _client
          .get(url, headers: {'User-Agent': 'NRMM-personal'})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw GbException('GameBanana took too long to answer.');
    } on SocketException {
      throw GbException('Could not reach GameBanana. Check your connection.');
    } on http.ClientException {
      throw GbException('Could not reach GameBanana. Check your connection.');
    }

    final code = response.statusCode;
    if (code == 429) {
      throw GbException(
        'GameBanana asked us to slow down. Try again in a minute.',
        statusCode: code,
      );
    }
    if (code >= 500) {
      throw GbException(
        'GameBanana is having problems right now (HTTP $code).',
        statusCode: code,
      );
    }
    if (code != 200) {
      throw GbException(
        'GameBanana did not accept the request (HTTP $code).',
        statusCode: code,
      );
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw GbException('GameBanana sent something we could not read.');
    }
  }
}

String _str(Object? v) => v is String ? v : '';

/// Tags come as plain strings or as {_sValue: ...} objects.
List<String> _tags(Object? v) => [
  if (v is List)
    for (final t in v)
      if (t is String && t.isNotEmpty)
        t
      else if (t is Map && _str(t['_sValue']).isNotEmpty)
        _str(t['_sValue']),
];

int? _int(Object? v) =>
    v is int ? v : (v is String ? int.tryParse(v) : (v is num ? v.toInt() : null));

/// Picture urls, medium size when GameBanana has one.
List<String> _imageUrls(Object? previewMedia, {bool full = false}) {
  final images = previewMedia is Map ? previewMedia['_aImages'] : null;
  if (images is! List) return [];
  final urls = <String>[];
  for (final img in images) {
    if (img is! Map) continue;
    final base = _str(img['_sBaseUrl']);
    final candidates =
        full
            ? [_str(img['_sFile']), _str(img['_sFile530']), _str(img['_sFile220'])]
            : [_str(img['_sFile530']), _str(img['_sFile220']), _str(img['_sFile'])];
    final file = candidates.firstWhere((f) => f.isNotEmpty, orElse: () => '');
    if (base.isNotEmpty && file.isNotEmpty) urls.add('$base/$file');
  }
  return urls;
}
