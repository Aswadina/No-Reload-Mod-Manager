// GameBanana tab — the API layer. All knowledge of GameBanana's JSON lives in
// this file, so if they change it, this is the only file to fix.
//
// Be gentle with their server: small pages, one request at a time (the UI
// awaits each call), no polling, and on 429/5xx we give up and say so.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const int gbPerPage = 15;

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
    );
  }
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
  final String descriptionHtml;
  final bool isBlocked;

  const GbModDetails({
    required this.mod,
    required this.files,
    required this.images,
    required this.descriptionHtml,
    required this.isBlocked,
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
  }) async {
    final json = await _get(
      Uri.https('gamebanana.com', '/apiv11/Mod/Index', {
        '_nPerpage': '$gbPerPage',
        '_nPage': '$page',
        '_aFilters[Generic_Game]': '$gameId',
        '_sSort': sort.apiValue,
      }),
    );
    return _page(json, page);
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
      descriptionHtml: _str(j['_sText']),
      isBlocked:
          j['_bIsWithheld'] == true ||
          j['_bIsTrashed'] == true ||
          j['_bIsPrivate'] == true,
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
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw GbException('GameBanana sent something we could not read.');
  }
}

String _str(Object? v) => v is String ? v : '';

int? _int(Object? v) =>
    v is int ? v : (v is String ? int.tryParse(v) : (v is num ? v.toInt() : null));

/// Picture urls, medium size when GameBanana has one.
List<String> _imageUrls(Object? previewMedia) {
  final images = previewMedia is Map ? previewMedia['_aImages'] : null;
  if (images is! List) return [];
  final urls = <String>[];
  for (final img in images) {
    if (img is! Map) continue;
    final base = _str(img['_sBaseUrl']);
    final file = [
      _str(img['_sFile530']),
      _str(img['_sFile220']),
      _str(img['_sFile']),
    ].firstWhere((f) => f.isNotEmpty, orElse: () => '');
    if (base.isNotEmpty && file.isNotEmpty) urls.add('$base/$file');
  }
  return urls;
}
