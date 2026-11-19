// GameBanana tab — the browse screen. Look and sizes follow NRMM's own mod
// cards (see mods_tab.dart). Logic lives in gb_api / gb_source / gb_install.
//
// Layout, top to bottom: search + sort, "Find mods for" (your groups),
// categories, the card grid, then the page bar.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_details_dialog.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_helpers.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_prefs.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_services.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_source.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_widgets.dart';
import 'package:no_reload_mod_manager/main.dart';
import 'package:no_reload_mod_manager/utils/constant_var.dart';
import 'package:no_reload_mod_manager/utils/mod_manager.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';
import 'package:no_reload_mod_manager/utils/ui_dialogues.dart';

export 'package:no_reload_mod_manager/custom/gb/gb_services.dart'
    show gbTabIndex;

class TabGameBanana extends ConsumerStatefulWidget {
  const TabGameBanana({super.key});

  @override
  ConsumerState<TabGameBanana> createState() => _TabGameBananaState();
}

class _TabGameBananaState extends ConsumerState<TabGameBanana> {
  final _search = TextEditingController();
  final _jump = TextEditingController();
  final _scroll = ScrollController();

  bool _started = false; // nothing is fetched until the tab is first opened
  bool _loading = false;
  String? _error;
  List<GbMod> _mods = [];
  int _page = 1;
  int _totalCount = 0;
  int _totalPages = 0;
  GbSort _sort = GbSort.newest;
  int? _categoryId;
  String _query = '';
  int _token = 0; // ignores answers that arrive after a newer request
  TargetGame? _loadedGame;
  List<GbCategory> _categories = [];
  Map<int, InstalledGbMod> _installed = {};

  // Pages already fetched this session, so going back costs no request.
  final Map<String, GbPage> _cache = {};

  @override
  void initState() {
    super.initState();
    // "Update Mod Data" resets the game to none and back; only react to a real change.
    ref.listenManual(targetGameProvider, (prev, next) {
      if (!_started || next == TargetGame.none || next == _loadedGame) return;
      unawaited(_startForGame());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _jump.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int? get _gameId => gbGameIds[ref.read(targetGameProvider)];
  String get _gameKey => ref.read(targetGameProvider).name;

  Future<void> _refreshInstalled() async {
    final modsPath = ref.read(validModsPath);
    if (modsPath == null) return;
    final found = await scanInstalled(gbManagedPath(modsPath));
    if (mounted) setState(() => _installed = found);
  }

  /// First open, or the game changed: restore the remembered view and load.
  Future<void> _startForGame() async {
    final game = ref.read(targetGameProvider);
    final gameId = gbGameIds[game];
    _loadedGame = game;
    _cache.clear();
    _query = '';
    _search.clear();
    _mods = [];
    _error = null;
    if (gameId == null) {
      setState(() {});
      return;
    }
    final (sort, category) = await GbPrefs.loadBrowse(game.name);
    if (!mounted) return;
    setState(() {
      _sort = sort;
      _categoryId = category;
      _categories = [];
    });
    unawaited(_refreshInstalled());
    unawaited(_loadCategories(gameId));
    await _go(1);
  }

  Future<void> _loadCategories(int gameId) async {
    try {
      final cats = await gbApi.categories(gameId);
      if (mounted && _gameId == gameId) setState(() => _categories = cats);
    } catch (_) {
      // The chips are a bonus; browsing still works without them.
    }
  }

  String _key(int gameId, int page) =>
      '$gameId|${_sort.name}|${_categoryId ?? ''}|$_query|$page';

  Future<void> _go(int page) async {
    final gameId = _gameId;
    if (gameId == null) return;
    final key = _key(gameId, page);
    final token = ++_token;

    void show(GbPage result) {
      _mods = result.mods;
      _page = page;
      _totalCount = result.totalCount;
      _totalPages = result.totalPages;
      _loading = false;
      _error = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }

    final cached = _cache[key];
    if (cached != null) {
      setState(() => show(cached));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _mods = [];
    });
    try {
      final result =
          _query.isEmpty
              ? await gbApi.browse(
                gameId: gameId,
                page: page,
                sort: _sort,
                categoryId: _categoryId,
              )
              : await gbApi.search(gameId: gameId, query: _query, page: page);
      if (!mounted || token != _token) return;
      _cache[key] = result;
      setState(() => show(result));
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

  void _runSearch(String text) {
    _query = text.trim();
    if (_query.isNotEmpty) _categoryId = null; // a search covers every category
    unawaited(GbPrefs.saveBrowse(_gameKey, _sort, _categoryId));
    unawaited(_go(1));
  }

  void _pickCategory(int? id) {
    _categoryId = id;
    _query = '';
    _search.clear();
    unawaited(GbPrefs.saveBrowse(_gameKey, _sort, _categoryId));
    unawaited(_go(1));
  }

  void _pickSort(GbSort sort) {
    _sort = sort;
    _query = ''; // search results have no sort order, so leave the search
    _search.clear();
    unawaited(GbPrefs.saveBrowse(_gameKey, _sort, _categoryId));
    unawaited(_go(1));
  }

  Future<void> _openDetails(GbMod mod) async {
    final modsPath = ref.read(validModsPath);
    if (modsPath == null) return;
    ref.read(alertDialogShownProvider.notifier).state = true;
    final changed = await showDialog<bool>(
      barrierDismissible: false,
      context: context,
      builder:
          (_) => GbDetailsDialog(
            mod: mod,
            installed: _installed[mod.id],
            modsPath: modsPath,
            game: _gameKey,
          ),
    );
    ref.read(alertDialogShownProvider.notifier).state = false;
    if (!mounted) return;
    unawaited(_refreshInstalled());
    if (changed == true) await _setUp(modsPath);
  }

  /// Runs the same "Update Mod Data" step the app offers, so a new mod works at once.
  Future<void> _setUp(String modsPath) async {
    ref.read(alertDialogShownProvider.notifier).state = true;
    await showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) => UpdateModDialog(modsPath: modsPath),
    );
    ref.read(alertDialogShownProvider.notifier).state = false;
    if (!mounted) return;
    triggerRefresh(ref);
    unawaited(_refreshInstalled());
  }

  @override
  Widget build(BuildContext context) {
    final sss = ref.watch(zoomScaleProvider);
    final game = ref.watch(targetGameProvider);
    final active = ref.watch(tabIndexProvider) == gbTabIndex;
    if (active && !_started && game != TargetGame.none) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startForGame());
      });
    }

    return Padding(
      padding: EdgeInsets.only(
        top: 85 * sss,
        bottom: 12 * sss,
        left: 45 * sss,
        right: 45 * sss,
      ),
      child: Column(
        children: [
          _topBar(sss, game),
          SizedBox(height: 8 * sss),
          _groupChips(sss),
          _categoryChips(sss),
          SizedBox(height: 8 * sss),
          Expanded(child: _body(sss, game)),
          if (_totalPages > 0) ...[
            SizedBox(height: 8 * sss),
            _pager(sss),
          ],
        ],
      ),
    );
  }

  // ---------- rows above the grid ----------

  Widget _topBar(double sss, TargetGame game) {
    final accent = getAccentColor(ref);
    final hasGame = gbGameIds.containsKey(game);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38 * sss,
            padding: EdgeInsets.symmetric(horizontal: 16 * sss),
            decoration: BoxDecoration(
              border: Border.all(color: gbLine, width: 3 * sss),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    enabled: hasGame,
                    style: gbText(sss, 12),
                    cursorColor: accent,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10 * sss),
                      hintText:
                          hasGame
                              ? 'Search ${game.name.replaceAll('_', ' ')} mods…'
                              : 'Pick a game in Settings first',
                      hintStyle: gbText(sss, 12, color: Colors.white54),
                    ),
                    onSubmitted: _runSearch,
                  ),
                ),
                if (_search.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _search.clear();
                      if (_query.isNotEmpty) _runSearch('');
                      setState(() {});
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(Icons.close, size: 16 * sss, color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(width: 10 * sss),
        PopupMenuButton<GbSort>(
          tooltip: 'Sort',
          color: gbDialogColor,
          onSelected: _pickSort,
          itemBuilder:
              (_) => [
                for (final s in GbSort.values)
                  PopupMenuItem(
                    value: s,
                    child: Text(
                      s.label,
                      style: gbText(
                        sss,
                        12,
                        weight: s == _sort && _query.isEmpty ? FontWeight.w700 : FontWeight.w400,
                        color: s == _sort && _query.isEmpty ? accent : Colors.white,
                      ),
                    ),
                  ),
              ],
          child: IgnorePointer(
            child: GbPill(
              label: 'Sort: ${_query.isEmpty ? _sort.label : 'Relevance'}  ▾',
              icon: Icons.sort,
            ),
          ),
        ),
      ],
    );
  }

  /// One chip per group the user already has: a quick way to find a character.
  Widget _groupChips(double sss) {
    final terms = <String>[];
    for (final g in ref.watch(modGroupDataProvider)) {
      final term = searchTermForGroup(g.groupName);
      if (term.isEmpty || RegExp(r'^group_\d+$').hasMatch(term)) continue;
      if (!terms.any((t) => t.toLowerCase() == term.toLowerCase())) terms.add(term);
    }
    if (terms.isEmpty) return const SizedBox.shrink();
    return _chipRow(
      sss,
      'Find mods for',
      [
        for (final t in terms)
          GbPill(
            label: t,
            selected: _query.toLowerCase() == t.toLowerCase(),
            onTap: () {
              _search.text = t;
              _runSearch(t);
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _categoryChips(double sss) {
    if (_categories.isEmpty) return const SizedBox.shrink();
    return _chipRow(
      sss,
      'Category',
      [
        GbPill(
          label: 'All',
          selected: _query.isEmpty && _categoryId == null,
          onTap: () => _pickCategory(null),
        ),
        for (final c in _categories)
          GbPill(
            label: '${c.name}  ${formatCount(c.itemCount)}',
            selected: _query.isEmpty && _categoryId == c.id,
            onTap: () => _pickCategory(c.id),
          ),
      ],
    );
  }

  Widget _chipRow(double sss, String label, List<Widget> chips) {
    return Padding(
      padding: EdgeInsets.only(top: 6 * sss),
      child: Row(
        children: [
          SizedBox(
            width: 92 * sss,
            child: Text(label, style: gbText(sss, 11, color: Colors.white60)),
          ),
          Expanded(
            child: SizedBox(
              height: 32 * sss,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: chips.length,
                  separatorBuilder: (_, _) => SizedBox(width: 6 * sss),
                  itemBuilder: (_, i) => Center(child: chips[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- grid ----------

  SliverGridDelegateWithMaxCrossAxisExtent _gridDelegate(double sss) =>
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 156.816 * sss + 8 * sss,
        mainAxisExtent: 217.8 * sss + 74 * sss,
        crossAxisSpacing: 8 * sss,
        mainAxisSpacing: 10 * sss,
      );

  Widget _body(double sss, TargetGame game) {
    if (!gbGameIds.containsKey(game)) {
      return const GbMessage(
        'Choose a game first. GameBanana mods are shown for the game NRMM is set to.',
      );
    }
    if (ref.watch(validModsPath) == null) {
      return const GbMessage(
        'The Mods folder is not ready yet. Set it up in Settings, then come back.',
      );
    }
    if (_error != null) {
      return GbMessage(_error!, retry: () => _go(_page));
    }
    if (_loading || (_mods.isEmpty && !_started)) {
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: _gridDelegate(sss),
        itemCount: 10,
        itemBuilder: (_, _) => const GbSkeletonCard(),
      );
    }
    if (_mods.isEmpty) return const GbMessage('No mods found.');
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: GridView.builder(
        controller: _scroll,
        gridDelegate: _gridDelegate(sss),
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
    );
  }

  // ---------- page bar ----------

  Widget _pager(double sss) {
    Widget nav(String label, int? target) => GbPill(
      label: label,
      compact: true,
      onTap: target == null || _loading ? null : () => _go(target),
    );

    final atFirst = _page <= 1;
    final atLast = _page >= _totalPages;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_withCommas(_totalCount)} mods  ·  page $_page of ${_withCommas(_totalPages)}',
            style: gbText(sss, 11, color: Colors.white60),
          ),
        ),
        nav('«', atFirst ? null : 1),
        SizedBox(width: 4 * sss),
        nav('‹', atFirst ? null : _page - 1),
        SizedBox(width: 4 * sss),
        for (final n in pageWindow(_page, _totalPages)) ...[
          if (n == null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4 * sss),
              child: Text('…', style: gbText(sss, 12, color: Colors.white60)),
            )
          else
            GbPill(
              label: '$n',
              compact: true,
              selected: n == _page,
              onTap: n == _page || _loading ? null : () => _go(n),
            ),
          SizedBox(width: 4 * sss),
        ],
        nav('›', atLast ? null : _page + 1),
        SizedBox(width: 4 * sss),
        nav('»', atLast ? null : _totalPages),
        SizedBox(width: 10 * sss),
        Container(
          width: 74 * sss,
          height: 26 * sss,
          padding: EdgeInsets.symmetric(horizontal: 10 * sss),
          decoration: BoxDecoration(
            border: Border.all(color: gbLine, width: 3 * sss),
            borderRadius: BorderRadius.circular(999),
          ),
          child: TextField(
            controller: _jump,
            style: gbText(sss, 11),
            cursorColor: getAccentColor(ref),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(vertical: 5 * sss),
              hintText: 'Go to…',
              hintStyle: gbText(sss, 11, color: Colors.white54),
            ),
            onSubmitted: (text) {
              final n = int.tryParse(text.trim());
              if (n != null) unawaited(_go(n.clamp(1, _totalPages)));
              _jump.clear();
            },
          ),
        ),
      ],
    );
  }
}

String _withCommas(int n) => n.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

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
    final kind =
        mod.subCategoryName.isNotEmpty ? mod.subCategoryName : mod.categoryName;
    final age = ageLabel(mod.dateAdded);
    final line1 = [if (kind.isNotEmpty) kind, if (age.isNotEmpty) age].join('  ·  ');

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
                  color: _hover ? Colors.white : gbLine,
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
                        ? Icon(Icons.image_outlined, size: 40 * sss, color: gbLine)
                        : GbNetworkImage(mod.thumbUrl!, cacheWidth: 400),
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
                            widget.badge == _Badge.update ? 'Update' : 'Installed',
                            style: gbText(
                              sss,
                              10,
                              weight: FontWeight.w600,
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
              style: gbText(sss, 11, weight: FontWeight.w500),
            ),
            if (line1.isNotEmpty)
              Text(
                line1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: gbText(sss, 10, color: Colors.white60),
              ),
            Text(
              '${mod.authorName}  ♥ ${formatCount(mod.likeCount)}  ·  ${formatCount(mod.viewCount)} views',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: gbText(sss, 10, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
