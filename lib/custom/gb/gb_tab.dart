// GameBanana tab — the screen. Look and sizes follow NRMM's own mod cards and
// dialogs (see mods_tab.dart). Logic lives in gb_api / gb_source / gb_install.

import 'dart:async';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_install.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_source.dart';
import 'package:no_reload_mod_manager/main.dart';
import 'package:no_reload_mod_manager/utils/archive_manager.dart';
import 'package:no_reload_mod_manager/utils/constant_var.dart';
import 'package:no_reload_mod_manager/utils/get_cloud_data.dart';
import 'package:no_reload_mod_manager/utils/mod_manager.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Index of this tab in the tab bar (after Keybinds, Mods, Settings).
const int gbTabIndex = 3;

/// GameBanana's id for each game NRMM supports (checked against their API).
const Map<TargetGame, int> gbGameIds = {
  TargetGame.Genshin_Impact: 8552,
  TargetGame.Honkai_Star_Rail: 18366,
  TargetGame.Zenless_Zone_Zero: 19567,
  TargetGame.Wuthering_Waves: 20357,
  TargetGame.Arknights_Endfield: 21842,
};

const _line = Color.fromARGB(127, 255, 255, 255);
const _dialogColor = Color(0xFF2B2930);

// Files NRMM keeps in a mod folder for the user (custom name, favorite, icon).
final List<String> _carryOver = [
  'modname',
  'fav',
  ...ConstantVar.modIconFilenames,
];

final _api = GbApi(httpClient.client);

Future<bool> _sevenZipExtract(String archive, String outDir) async =>
    (await SevenZip.instance.extract(archive, outputDir: outDir)).success;

String _managedPath(String modsPath) =>
    p.join(modsPath, ConstantVar.managedFolderName);

class TabGameBanana extends ConsumerStatefulWidget {
  const TabGameBanana({super.key});

  @override
  ConsumerState<TabGameBanana> createState() => _TabGameBananaState();
}

class _TabGameBananaState extends ConsumerState<TabGameBanana> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  bool _started = false; // nothing is fetched until the tab is first opened
  bool _loading = false;
  String? _error;
  List<GbMod> _mods = [];
  int _page = 0;
  bool _hasMore = false;
  GbSort _sort = GbSort.newest;
  String _query = '';
  int _token = 0; // ignores answers that arrive after a newer request
  Map<int, InstalledGbMod> _installed = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _load(reset: false);
      }
    });
    ref.listenManual(targetGameProvider, (prev, next) {
      if (_started) _load(reset: true);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int? get _gameId => gbGameIds[ref.read(targetGameProvider)];

  Future<void> _refreshInstalled() async {
    final modsPath = ref.read(validModsPath);
    if (modsPath == null) return;
    final found = await scanInstalled(_managedPath(modsPath));
    if (mounted) setState(() => _installed = found);
  }

  Future<void> _load({required bool reset}) async {
    final gameId = _gameId;
    if (gameId == null) {
      setState(() {
        _mods = [];
        _error = null;
      });
      return;
    }
    if (_loading && !reset) return;
    if (!reset && !_hasMore) return;

    final token = ++_token;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _mods = [];
        _hasMore = false;
      }
    });
    try {
      final result =
          _query.isEmpty
              ? await _api.browse(gameId: gameId, page: page, sort: _sort)
              : await _api.search(gameId: gameId, query: _query, page: page);
      if (!mounted || token != _token) return;
      setState(() {
        _mods = reset ? result.mods : [..._mods, ...result.mods];
        _page = page;
        _hasMore = result.hasMore && result.mods.isNotEmpty;
        _loading = false;
      });
    } on GbException catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = 'Something went wrong while talking to GameBanana.';
        _loading = false;
      });
    }
  }

  void _firstOpen() {
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshInstalled());
      unawaited(_load(reset: true));
    });
  }

  Future<void> _openDetails(GbMod mod) async {
    final modsPath = ref.read(validModsPath);
    if (modsPath == null) return;
    ref.read(alertDialogShownProvider.notifier).state = true;
    await showDialog(
      barrierDismissible: false,
      context: context,
      builder:
          (_) => _GbDetailsDialog(
            mod: mod,
            installed: _installed[mod.id],
            modsPath: modsPath,
          ),
    );
    ref.read(alertDialogShownProvider.notifier).state = false;
    if (mounted) unawaited(_refreshInstalled());
  }

  @override
  Widget build(BuildContext context) {
    final sss = ref.watch(zoomScaleProvider);
    final game = ref.watch(targetGameProvider);
    final active = ref.watch(tabIndexProvider) == gbTabIndex;
    if (active && !_started) _firstOpen();

    return Padding(
      padding: EdgeInsets.only(
        top: 85 * sss,
        bottom: 15 * sss,
        left: 45 * sss,
        right: 45 * sss,
      ),
      child: Column(
        children: [
          _buildTopBar(sss, game),
          SizedBox(height: 14 * sss),
          Expanded(child: _buildBody(sss, game)),
        ],
      ),
    );
  }

  Widget _buildTopBar(double sss, TargetGame game) {
    final accent = getAccentColor(ref);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38 * sss,
            padding: EdgeInsets.symmetric(horizontal: 16 * sss),
            decoration: BoxDecoration(
              border: Border.all(color: _line, width: 3 * sss),
              borderRadius: BorderRadius.circular(999),
            ),
            child: TextField(
              controller: _search,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12 * sss,
              ),
              cursorColor: accent,
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10 * sss),
                hintText:
                    gbGameIds.containsKey(game)
                        ? 'Search ${game.name.replaceAll('_', ' ')} mods…'
                        : 'Pick a game in Settings first',
                hintStyle: GoogleFonts.poppins(
                  color: Colors.white54,
                  fontSize: 12 * sss,
                ),
              ),
              onSubmitted: (text) {
                _query = text.trim();
                _load(reset: true);
              },
            ),
          ),
        ),
        SizedBox(width: 10 * sss),
        for (final sort in GbSort.values)
          Padding(
            padding: EdgeInsets.only(left: 6 * sss),
            child: _Chip(
              label: sort.label,
              selected: _query.isEmpty && sort == _sort,
              onTap: () {
                _search.clear();
                _query = '';
                _sort = sort;
                _load(reset: true);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildBody(double sss, TargetGame game) {
    if (!gbGameIds.containsKey(game)) {
      return _Message(
        'Choose a game first. GameBanana mods are shown for the game NRMM is set to.',
      );
    }
    if (ref.watch(validModsPath) == null) {
      return _Message(
        'The Mods folder is not ready yet. Set it up in Settings, then come back.',
      );
    }
    if (_mods.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) {
        return _Message(_error!, retry: () => _load(reset: true));
      }
      if (_started) return _Message('No mods found.');
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: GridView.builder(
              controller: _scroll,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 156.816 * sss + 8 * sss,
                mainAxisExtent: 217.8 * sss + 56 * sss,
                crossAxisSpacing: 8 * sss,
                mainAxisSpacing: 12 * sss,
              ),
              itemCount: _mods.length,
              itemBuilder: (context, i) {
                final mod = _mods[i];
                final installed = _installed[mod.id];
                return _GbCard(
                  mod: mod,
                  badge:
                      installed == null
                          ? null
                          : hasUpdateForCard(installed, mod)
                          ? _Badge.update
                          : _Badge.installed,
                  onTap: () => _openDetails(mod),
                );
              },
            ),
          ),
        ),
        if (_loading)
          Padding(
            padding: EdgeInsets.only(top: 6 * sss),
            child: SizedBox(
              height: 16 * sss,
              width: 16 * sss,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(top: 6 * sss),
            child: Text(
              _error!,
              style: GoogleFonts.poppins(color: Colors.red, fontSize: 12 * sss),
            ),
          ),
      ],
    );
  }
}

class _Chip extends ConsumerWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sss = ref.watch(zoomScaleProvider);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30 * sss,
          padding: EdgeInsets.symmetric(horizontal: 12 * sss),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? getAccentColor(ref) : _line,
              width: 3 * sss,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 11 * sss,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends ConsumerWidget {
  final String text;
  final VoidCallback? retry;
  const _Message(this.text, {this.retry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sss = ref.watch(zoomScaleProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13 * sss),
          ),
          if (retry != null)
            Padding(
              padding: EdgeInsets.only(top: 10 * sss),
              child: _Chip(label: 'Try again', selected: true, onTap: retry!),
            ),
        ],
      ),
    );
  }
}

enum _Badge { installed, update }

class _GbCard extends ConsumerStatefulWidget {
  final GbMod mod;
  final _Badge? badge;
  final VoidCallback onTap;
  const _GbCard({required this.mod, required this.badge, required this.onTap});

  @override
  ConsumerState<_GbCard> createState() => _GbCardState();
}

class _GbCardState extends ConsumerState<_GbCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sss = ref.watch(zoomScaleProvider);
    final mod = widget.mod;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          children: [
            Container(
              height: 217.8 * sss,
              width: 156.816 * sss,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _hover ? Colors.white : _line,
                  width: 3 * sss,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
                borderRadius: BorderRadius.circular(17 * sss),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14 * sss),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    mod.thumbUrl == null
                        ? Icon(
                          Icons.image_outlined,
                          size: 40 * sss,
                          color: _line,
                        )
                        : Image.network(
                          mod.thumbUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 400,
                          errorBuilder:
                              (_, _, _) => Icon(
                                Icons.image_outlined,
                                size: 40 * sss,
                                color: _line,
                              ),
                        ),
                    if (widget.badge != null)
                      Positioned(
                        left: 6 * sss,
                        bottom: 6 * sss,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * sss,
                            vertical: 2 * sss,
                          ),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(180, 0, 0, 0),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.badge == _Badge.update
                                ? 'Update'
                                : 'Installed',
                            style: GoogleFonts.poppins(
                              fontSize: 10 * sss,
                              fontWeight: FontWeight.w600,
                              color:
                                  widget.badge == _Badge.update
                                      ? Colors.orangeAccent
                                      : Colors.lightGreenAccent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 4 * sss),
            Text(
              mod.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 11 * sss,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${mod.authorName}  ♥ ${mod.likeCount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: Colors.white60,
                fontSize: 10 * sss,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GbDetailsDialog extends ConsumerStatefulWidget {
  final GbMod mod;
  final InstalledGbMod? installed;
  final String modsPath;
  const _GbDetailsDialog({
    required this.mod,
    required this.installed,
    required this.modsPath,
  });

  @override
  ConsumerState<_GbDetailsDialog> createState() => _GbDetailsDialogState();
}

class _GbDetailsDialogState extends ConsumerState<_GbDetailsDialog> {
  GbModDetails? _details;
  String? _loadError;
  GbFile? _file;
  String _target = ''; // a group path, or _newGroup
  static const _newGroup = '::new::';
  int _image = 0;
  bool _busy = false;
  String _status = '';
  bool _done = false;
  String? _failed;

  @override
  void initState() {
    super.initState();
    final groups = ref.read(modGroupDataProvider);
    final current = ref.read(currentGroupIndexProvider);
    if (groups.isNotEmpty) {
      _target = groups[current.clamp(0, groups.length - 1)].groupPath;
    } else {
      _target = _newGroup;
    }
    _api
        .details(widget.mod.id)
        .then((d) {
          if (!mounted) return;
          setState(() {
            _details = d;
            _file = d.newestFile;
          });
        })
        .catchError((Object e) {
          if (mounted) {
            setState(() => _loadError = e is GbException ? e.message : '$e');
          }
        });
  }

  bool get _isUpdate =>
      widget.installed != null &&
      _details != null &&
      hasUpdateExact(widget.installed!.source, _details!);

  String? get _blockReason {
    final d = _details;
    final f = _file;
    if (d == null) return null;
    if (d.isBlocked) return 'This mod is withheld or removed on GameBanana.';
    if (f == null) return 'This mod has no files to download.';
    if (!f.isClean) {
      return 'GameBanana\'s virus scan did not mark this file clean.';
    }
    return null;
  }

  Future<void> _run() async {
    final details = _details!;
    final file = _file!;
    setState(() {
      _busy = true;
      _failed = null;
      _status = 'Starting…';
    });
    try {
      final temp = p.join((await getTemporaryDirectory()).path, 'nrmm_gb');
      void say(String s) {
        if (mounted) setState(() => _status = s);
      }

      if (_isUpdate) {
        await updateMod(
          client: httpClient.client,
          details: details,
          file: file,
          existingModPath: widget.installed!.modPath,
          backupRoot: p.join(p.dirname(widget.modsPath), 'NRMM_GB_Backups'),
          tempRoot: temp,
          extract: _sevenZipExtract,
          carryOverFiles: _carryOver,
          onStatus: say,
        );
      } else {
        var groupPath = _target;
        if (groupPath == _newGroup) {
          final index = await addGroup(ref, _managedPath(widget.modsPath));
          groupPath = ref.read(modGroupDataProvider)[(index ?? 1) - 1].groupPath;
        }
        await installFile(
          client: httpClient.client,
          details: details,
          file: file,
          groupPath: groupPath,
          tempRoot: temp,
          extract: _sevenZipExtract,
          onStatus: say,
        );
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _done = true;
        });
      }
    } on GbException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = 'Something went wrong: $e';
        });
      }
    }
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final sss = ref.watch(zoomScaleProvider);
    final accent = getAccentColor(ref);
    final d = _details;

    TextStyle t(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        GoogleFonts.poppins(
          fontSize: size * sss,
          fontWeight: w,
          color: c ?? Colors.white,
        );

    Widget body;
    if (_loadError != null) {
      body = Text(_loadError!, style: t(12, c: Colors.red));
    } else if (d == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 230 * sss, child: _pictures(d, sss)),
          SizedBox(width: 20 * sss),
          Expanded(child: _infoColumn(d, sss, accent, t)),
        ],
      );
    }

    return Stack(
      children: [
        MoveWindow(),
        AlertDialog(
          backgroundColor: _dialogColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(widget.mod.name, style: t(16, w: FontWeight.w600)),
          content: SizedBox(
            width: 680 * sss,
            height: 340 * sss,
            child: body,
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : _close,
              child: Text(_done ? 'Close' : 'Cancel', style: t(13, c: accent)),
            ),
            if (!_done && d != null)
              TextButton(
                onPressed:
                    _busy || _blockReason != null || _file == null ? null : _run,
                child: Text(
                  _isUpdate ? 'Update' : 'Download',
                  style: t(13, w: FontWeight.w600, c: accent),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _pictures(GbModDetails d, double sss) {
    if (d.images.isEmpty) {
      return Container(
        height: 300 * sss,
        decoration: BoxDecoration(
          border: Border.all(color: _line, width: 3 * sss),
          borderRadius: BorderRadius.circular(17 * sss),
        ),
        child: Icon(Icons.image_outlined, size: 40 * sss, color: _line),
      );
    }
    return Column(
      children: [
        Container(
          height: 250 * sss,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: _line, width: 3 * sss),
            borderRadius: BorderRadius.circular(17 * sss),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14 * sss),
            child: Image.network(
              d.images[_image.clamp(0, d.images.length - 1)],
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        SizedBox(height: 6 * sss),
        SizedBox(
          height: 40 * sss,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < d.images.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _image = i),
                  child: Container(
                    width: 50 * sss,
                    margin: EdgeInsets.only(right: 6 * sss),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: i == _image ? getAccentColor(ref) : _line,
                        width: 2 * sss,
                      ),
                      borderRadius: BorderRadius.circular(8 * sss),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6 * sss),
                      child: Image.network(
                        d.images[i],
                        fit: BoxFit.cover,
                        cacheWidth: 120,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoColumn(
    GbModDetails d,
    double sss,
    Color accent,
    TextStyle Function(double, {FontWeight w, Color? c}) t,
  ) {
    final groups = ref.watch(modGroupDataProvider);
    final installed = widget.installed;
    final reason = _blockReason;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'by ${d.mod.authorName}  ·  ♥ ${widget.mod.likeCount}',
            style: t(11, c: Colors.white60),
          ),
          SizedBox(height: 10 * sss),
          Text(_plainText(d.descriptionHtml), maxLines: 7, overflow: TextOverflow.ellipsis, style: t(11)),
          SizedBox(height: 12 * sss),
          Text('Files', style: t(11, c: Colors.white60)),
          for (final f in d.files)
            InkWell(
              onTap: _busy || _done ? null : () => setState(() => _file = f),
              child: Row(
                children: [
                  Icon(
                    f.id == _file?.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16 * sss,
                    color: f.id == _file?.id ? accent : Colors.white54,
                  ),
                  SizedBox(width: 6 * sss),
                  Expanded(
                    child: Text(
                      f.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: t(11),
                    ),
                  ),
                  Text(_size(f.size), style: t(10, c: Colors.white60)),
                ],
              ),
            ),
          SizedBox(height: 12 * sss),
          if (installed != null)
            Text(
              _isUpdate
                  ? 'You have an older version. Update replaces it and keeps a backup.'
                  : 'You already have the latest version.',
              style: t(11, c: _isUpdate ? Colors.orangeAccent : Colors.lightGreenAccent),
            )
          else ...[
            Text('Put it in', style: t(11, c: Colors.white60)),
            DropdownButton<String>(
              isExpanded: true,
              dropdownColor: _dialogColor,
              value: groups.any((g) => g.groupPath == _target) || _target == _newGroup
                  ? _target
                  : _newGroup,
              onChanged: _busy || _done ? null : (v) => setState(() => _target = v!),
              items: [
                for (final g in groups)
                  DropdownMenuItem(
                    value: g.groupPath,
                    child: Text(g.groupName, style: t(12)),
                  ),
                DropdownMenuItem(value: _newGroup, child: Text('New group', style: t(12))),
              ],
            ),
          ],
          if (reason != null) Text(reason, style: t(11, c: Colors.red)),
          if (_busy) Text(_status, style: t(11, c: accent)),
          if (_failed != null) Text(_failed!, style: t(11, c: Colors.red)),
          if (_done)
            Text(
              'Done. Run Update Mod Data so NRMM can set the mod up.',
              style: t(11, w: FontWeight.w600, c: Colors.lightGreenAccent),
            ),
        ],
      ),
    );
  }
}

String _size(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// GameBanana descriptions are HTML. This keeps the words and drops the tags.
String _plainText(String html) {
  return html
      .replaceAll(RegExp(r'<br\s*/?>|</p>|</li>|</h\d>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
