// GameBanana tab — the large mod details dialog.
//
// Left: a big picture gallery (click for the full-screen viewer).
// Right: facts, then tabs (About, Files, Credits and license), then the
// "Put it in" row and the buttons. Returns true when a mod was installed or
// updated, so the tab can set it up right away.

import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_group_picker.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_helpers.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_html.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_image_viewer.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_install.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_prefs.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_services.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_source.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_widgets.dart';
import 'package:no_reload_mod_manager/custom/ui_group.dart';
import 'package:no_reload_mod_manager/data/mod_data.dart';
import 'package:no_reload_mod_manager/main.dart';
import 'package:no_reload_mod_manager/utils/mod_manager.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class GbDetailsDialog extends ConsumerStatefulWidget {
  final GbMod mod;
  final InstalledGbMod? installed;
  final String modsPath;
  final String game;
  const GbDetailsDialog({
    super.key,
    required this.mod,
    required this.installed,
    required this.modsPath,
    required this.game,
  });

  @override
  ConsumerState<GbDetailsDialog> createState() => _GbDetailsDialogState();
}

enum _Tab { about, files, credits }

class _GbDetailsDialogState extends ConsumerState<GbDetailsDialog> {
  GbModDetails? _details;
  String? _loadError;
  GbPickerData? _picker;
  GbTarget? _target;
  String _targetReason = '';
  GbFile? _file;
  int _image = 0;
  _Tab _tab = _Tab.about;

  bool _busy = false;
  String _status = '';
  double? _progress;
  String? _failed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final d = await gbApi.details(widget.mod.id);
      final picker = await loadGbPickerData(
        ref,
        details: d,
        mod: widget.mod,
        game: widget.game,
      );
      if (!mounted) return;
      setState(() {
        _details = d;
        _file = d.newestFile;
        _picker = picker;
        _target = picker.defaultTarget;
        _targetReason = picker.defaultReason;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e is GbException ? e.message : '$e');
      }
    }
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

  /// The top-level category (Skins, UI, ...), as the browse list names it.
  String get _category =>
      widget.mod.categoryName.isNotEmpty
          ? widget.mod.categoryName
          : (_details?.categoryName ?? '');

  Future<void> _change() async {
    final picker = _picker;
    if (picker == null) return;
    final chosen = await showGbGroupPicker(
      context,
      data: picker,
      selectedPath: _target?.groupPath,
    );
    if (chosen != null && mounted) {
      setState(() {
        _target = chosen;
        _targetReason =
            chosen.isNew ? 'A new group will be made' : 'Your choice';
      });
    }
  }

  /// Makes the new group the user asked for and returns its folder path.
  Future<String> _createGroup(GbTarget target) async {
    final index = await addGroup(ref, gbManagedPath(widget.modsPath));
    final groups = ref.read(modGroupDataProvider);
    final path =
        groups[((index ?? 1) - 1).clamp(0, groups.length - 1)].groupPath;
    await setGroupNameOnDisk(path, target.newName!);
    ref.read(modGroupDataProvider.notifier).state = [
      for (final g in ref.read(modGroupDataProvider))
        g.groupPath == path
            ? ModGroupData(
              groupPath: g.groupPath,
              iconPath: g.iconPath,
              groupName: target.newName!,
              favoriteDateTime: g.favoriteDateTime,
              modsInGroup: g.modsInGroup,
              realIndex: g.realIndex,
              previousSelectedModOnGroup: g.previousSelectedModOnGroup,
            )
            : g,
    ];
    if (target.newIsUi) await setUiGroup(ref, path, true);
    return path;
  }

  Future<void> _run() async {
    final details = _details!;
    final file = _file!;
    setState(() {
      _busy = true;
      _failed = null;
      _progress = null;
      _status = 'Starting…';
    });
    void say(String s) {
      if (mounted) setState(() => _status = s);
    }

    void progress(int got, int total) {
      if (mounted && total > 0) {
        setState(() => _progress = (got / total).clamp(0.0, 1.0));
      }
    }

    try {
      final temp = p.join((await getTemporaryDirectory()).path, 'nrmm_gb');
      if (_isUpdate) {
        await updateMod(
          client: gbHttpClient,
          details: details,
          file: file,
          existingModPath: widget.installed!.modPath,
          backupRoot: p.join(p.dirname(widget.modsPath), 'NRMM_GB_Backups'),
          tempRoot: temp,
          extract: gbSevenZipExtract,
          carryOverFiles: gbCarryOverFiles,
          onStatus: say,
          onProgress: progress,
        );
      } else {
        final target = _target!;
        final groupPath =
            target.isNew ? await _createGroup(target) : target.groupPath!;
        await installFile(
          client: gbHttpClient,
          details: details,
          file: file,
          groupPath: groupPath,
          tempRoot: temp,
          extract: gbSevenZipExtract,
          onStatus: say,
          onProgress: progress,
        );
        await GbPrefs.rememberGroup(widget.game, _category, groupPath);
      }
      if (mounted) Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    final sss = ref.watch(zoomScaleProvider);
    final screen = MediaQuery.of(context).size;
    final width = (1040 * sss).clamp(300.0, screen.width - 40);
    final height = (660 * sss).clamp(300.0, screen.height - 60);

    return Stack(
      children: [
        MoveWindow(),
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (!_busy) Navigator.of(context).pop(false);
            },
          },
          child: Focus(
            autofocus: true,
            child: Dialog(
              backgroundColor: gbDialogColor,
              insetPadding: const EdgeInsets.all(20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: SizedBox(
                width: width,
                height: height,
                child: Padding(
                  padding: EdgeInsets.all(18 * sss),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: width < 860 * sss ? 8 : 11,
                        child: _gallery(sss),
                      ),
                      SizedBox(width: 18 * sss),
                      Expanded(
                        flex: width < 860 * sss ? 12 : 9,
                        child: _rightSide(sss),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- left: pictures ----------

  Widget _gallery(double sss) {
    final d = _details;
    final images =
        d?.images.isNotEmpty == true
            ? d!.images
            : [if (widget.mod.thumbUrl != null) widget.mod.thumbUrl!];
    final full = d?.fullImages.isNotEmpty == true ? d!.fullImages : images;
    final index = images.isEmpty ? 0 : _image.clamp(0, images.length - 1);
    final accent = getAccentColor(ref);

    Widget arrow(IconData icon, int delta, Alignment at) => Align(
      alignment: at,
      child: GestureDetector(
        onTap: () => setState(() => _image = index + delta),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            margin: EdgeInsets.all(8 * sss),
            width: 34 * sss,
            height: 34 * sss,
            decoration: const BoxDecoration(
              color: Color.fromARGB(150, 0, 0, 0),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );

    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: gbLine, width: 3 * sss),
              borderRadius: BorderRadius.circular(17 * sss),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14 * sss),
              child:
                  images.isEmpty
                      ? Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 40 * sss,
                          color: gbLine,
                        ),
                      )
                      : Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            onTap:
                                () => showGbImageViewer(context, full, index),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.zoomIn,
                              child: GbNetworkImage(
                                images[index],
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          if (index > 0)
                            arrow(Icons.chevron_left, -1, Alignment.centerLeft),
                          if (index < images.length - 1)
                            arrow(
                              Icons.chevron_right,
                              1,
                              Alignment.centerRight,
                            ),
                          Positioned(
                            right: 8 * sss,
                            bottom: 8 * sss,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10 * sss,
                                vertical: 4 * sss,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(170, 0, 0, 0),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.zoom_in,
                                    size: 14 * sss,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 4 * sss),
                                  Text(
                                    'Click to enlarge  ·  ${index + 1}/${images.length}',
                                    style: gbText(sss, 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        ),
        if (images.length > 1) ...[
          SizedBox(height: 8 * sss),
          SizedBox(
            height: 54 * sss,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => SizedBox(width: 6 * sss),
              itemBuilder:
                  (_, i) => GestureDetector(
                    onTap: () => setState(() => _image = i),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 84 * sss,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: i == index ? accent : gbLine,
                            width: 2.5 * sss,
                          ),
                          borderRadius: BorderRadius.circular(10 * sss),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7 * sss),
                          child: GbNetworkImage(images[i], cacheWidth: 200),
                        ),
                      ),
                    ),
                  ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------- right: facts, tabs, footer ----------

  Widget _rightSide(double sss) {
    final d = _details;
    final mod = widget.mod;
    final accent = getAccentColor(ref);
    final updated =
        d?.mod.dateUpdated ??
        mod.dateUpdated ??
        d?.mod.dateAdded ??
        mod.dateAdded;

    Widget stat(IconData icon, String text) => Padding(
      padding: EdgeInsets.only(right: 14 * sss),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14 * sss, color: Colors.white60),
          SizedBox(width: 4 * sss),
          Text(text, style: gbText(sss, 11, color: Colors.white70)),
        ],
      ),
    );

    final tags =
        (d?.tags.isNotEmpty == true ? d!.tags : mod.tags).take(8).toList();
    final categoryLine = [
      if (_category.isNotEmpty) _category,
      if (mod.subCategoryName.isNotEmpty) mod.subCategoryName,
    ].join('  ›  ');

    final headerAndTabs = <Widget>[
      Text(
        mod.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: gbText(sss, 17, weight: FontWeight.w600),
      ),
      SizedBox(height: 2 * sss),
      Text(
        'by ${d?.mod.authorName.isNotEmpty == true ? d!.mod.authorName : mod.authorName}'
        '${categoryLine.isEmpty ? '' : '   ·   $categoryLine'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: gbText(sss, 11, color: Colors.white60),
      ),
      SizedBox(height: 8 * sss),
      Wrap(
        runSpacing: 4 * sss,
        children: [
          if (d != null)
            stat(Icons.download_outlined, formatCount(d.downloadCount)),
          stat(
            Icons.favorite_border,
            formatCount(d?.likeCount ?? mod.likeCount),
          ),
          stat(
            Icons.visibility_outlined,
            formatCount(d?.viewCount ?? mod.viewCount),
          ),
          if (updated != null) stat(Icons.update, ageLabel(updated)),
        ],
      ),
      if (tags.isNotEmpty) ...[
        SizedBox(height: 6 * sss),
        Wrap(
          spacing: 5 * sss,
          runSpacing: 5 * sss,
          children: [
            for (final t in tags)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 8 * sss,
                  vertical: 2 * sss,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(30, 255, 255, 255),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(t, style: gbText(sss, 10, color: Colors.white70)),
              ),
          ],
        ),
      ],
      SizedBox(height: 10 * sss),
      Wrap(
        spacing: 6 * sss,
        runSpacing: 6 * sss,
        children: [
          GbPill(
            label: 'About',
            selected: _tab == _Tab.about,
            onTap: () => setState(() => _tab = _Tab.about),
          ),
          GbPill(
            label: 'Files${d == null ? '' : ' (${d.files.length})'}',
            selected: _tab == _Tab.files,
            onTap: () => setState(() => _tab = _Tab.files),
          ),
          GbPill(
            label: 'Credits & license',
            selected: _tab == _Tab.credits,
            onTap: () => setState(() => _tab = _Tab.credits),
          ),
        ],
      ),
      SizedBox(height: 8 * sss),
    ];

    Widget bodyBox() => Container(
      width: double.infinity,
      padding: EdgeInsets.all(10 * sss),
      decoration: BoxDecoration(
        color: const Color.fromARGB(18, 255, 255, 255),
        borderRadius: BorderRadius.circular(14 * sss),
      ),
      child: _tabBody(sss, accent),
    );

    return LayoutBuilder(
      builder: (context, c) {
        // In a short window the facts and text scroll while the footer stays put.
        final compact = c.maxHeight < 560 * sss;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...headerAndTabs,
                      SizedBox(height: 240 * sss, child: bodyBox()),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 8 * sss),
              _footer(sss, accent),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...headerAndTabs,
            Expanded(child: bodyBox()),
            SizedBox(height: 10 * sss),
            _footer(sss, accent),
          ],
        );
      },
    );
  }

  Widget _tabBody(double sss, Color accent) {
    final d = _details;
    if (_loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_loadError!, style: gbText(sss, 12, color: Colors.redAccent)),
          SizedBox(height: 8 * sss),
          GbPill(label: 'Try again', selected: true, onTap: _load),
        ],
      );
    }
    if (d == null) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_tab) {
      case _Tab.about:
        final blocks = parseGbHtml(d.descriptionHtml);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (d.requirements.isNotEmpty) ...[
                Text('Requires', style: gbText(sss, 11, color: Colors.white60)),
                SizedBox(height: 3 * sss),
                for (final r in d.requirements)
                  GestureDetector(
                    onTap: r.url.isEmpty ? null : () => gbOpenUrl(r.url),
                    child: MouseRegion(
                      cursor:
                          r.url.isEmpty
                              ? MouseCursor.defer
                              : SystemMouseCursors.click,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 2 * sss),
                        child: Text(
                          r.name,
                          style: gbText(
                            sss,
                            12,
                            color: r.url.isEmpty ? Colors.white : accent,
                          ).copyWith(
                            decoration:
                                r.url.isEmpty ? null : TextDecoration.underline,
                            decorationColor: accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                SizedBox(height: 10 * sss),
              ],
              if (blocks.isEmpty)
                Text(
                  'No description.',
                  style: gbText(sss, 12, color: Colors.white60),
                )
              else
                GbRichText(blocks),
            ],
          ),
        );
      case _Tab.files:
        if (d.files.isEmpty) {
          return Text(
            'No files.',
            style: gbText(sss, 12, color: Colors.white60),
          );
        }
        return ListView(
          children: [
            for (var i = 0; i < d.files.length; i++)
              _fileRow(sss, accent, d.files[i], i == 0),
          ],
        );
      case _Tab.credits:
        return SingleChildScrollView(child: _creditsBody(sss, d));
    }
  }

  Widget _fileRow(double sss, Color accent, GbFile f, bool newest) {
    final selected = f.id == _file?.id;
    final canPick = !_busy && widget.installed == null || _isUpdate && !_busy;
    return GestureDetector(
      onTap: canPick ? () => setState(() => _file = f) : null,
      child: MouseRegion(
        cursor: canPick ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          margin: EdgeInsets.only(bottom: 6 * sss),
          padding: EdgeInsets.all(8 * sss),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? accent : gbLine,
              width: 2.5 * sss,
            ),
            borderRadius: BorderRadius.circular(12 * sss),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      f.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: gbText(sss, 12, weight: FontWeight.w500),
                    ),
                  ),
                  if (newest)
                    Text(
                      'Newest',
                      style: gbText(
                        sss,
                        10,
                        weight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                ],
              ),
              Text(
                '${_size(f.size)}  ·  ${ageLabel(f.dateAdded)}',
                style: gbText(sss, 10, color: Colors.white60),
              ),
              if (f.description.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 2 * sss),
                  child: Text(
                    f.description,
                    style: gbText(sss, 11, color: Colors.white70),
                  ),
                ),
              if (!f.isClean)
                Padding(
                  padding: EdgeInsets.only(top: 2 * sss),
                  child: Text(
                    'Not marked clean by GameBanana\'s virus scan',
                    style: gbText(sss, 10, color: Colors.redAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _creditsBody(double sss, GbModDetails d) {
    Widget heading(String text) => Padding(
      padding: EdgeInsets.only(top: 6 * sss, bottom: 3 * sss),
      child: Text(text, style: gbText(sss, 11, color: Colors.white60)),
    );

    Widget licenseGroup(String key, String title, IconData icon, Color color) {
      final items = d.license[key] ?? const [];
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(title),
          for (final item in items)
            Padding(
              padding: EdgeInsets.only(bottom: 3 * sss),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 14 * sss, color: color),
                  SizedBox(width: 6 * sss),
                  Expanded(child: Text(item, style: gbText(sss, 11))),
                ],
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d.credits.isEmpty)
          Text(
            'No credits listed.',
            style: gbText(sss, 12, color: Colors.white60),
          ),
        for (final g in d.credits) ...[
          heading(g.name),
          for (final person in g.people) Text(person, style: gbText(sss, 12)),
        ],
        SizedBox(height: 10 * sss),
        Text('License', style: gbText(sss, 13, weight: FontWeight.w600)),
        licenseGroup(
          'yes',
          'You can',
          Icons.check_circle_outline,
          Colors.lightGreenAccent,
        ),
        licenseGroup(
          'ask',
          'Ask the author first',
          Icons.help_outline,
          Colors.orangeAccent,
        ),
        licenseGroup('no', 'Not allowed', Icons.block, Colors.redAccent),
        if (d.license.isEmpty)
          Text('Not specified.', style: gbText(sss, 12, color: Colors.white60)),
      ],
    );
  }

  Widget _footer(double sss, Color accent) {
    final reason = _blockReason;
    final installed = widget.installed;
    final canRun =
        !_busy &&
        reason == null &&
        _file != null &&
        _details != null &&
        (_isUpdate || (installed == null && _target != null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reason != null)
          Padding(
            padding: EdgeInsets.only(bottom: 6 * sss),
            child: Text(
              reason,
              style: gbText(sss, 11, color: Colors.redAccent),
            ),
          ),
        if (installed != null)
          Padding(
            padding: EdgeInsets.only(bottom: 8 * sss),
            child: Text(
              _details == null
                  ? 'Checking your installed copy…'
                  : _isUpdate
                  ? 'You have an older version. Update replaces it and keeps a backup.'
                  : 'You already have the latest version.',
              style: gbText(
                sss,
                11,
                color:
                    _isUpdate ? Colors.orangeAccent : Colors.lightGreenAccent,
              ),
            ),
          )
        else
          _targetRow(sss, accent),
        if (_busy) ...[
          SizedBox(height: 8 * sss),
          Text(_status, style: gbText(sss, 11, color: accent)),
          SizedBox(height: 4 * sss),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 5 * sss,
              color: accent,
              backgroundColor: const Color.fromARGB(40, 255, 255, 255),
            ),
          ),
        ],
        if (_failed != null)
          Padding(
            padding: EdgeInsets.only(top: 6 * sss),
            child: Text(
              _failed!,
              style: gbText(sss, 11, color: Colors.redAccent),
            ),
          ),
        SizedBox(height: 10 * sss),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8 * sss,
          runSpacing: 6 * sss,
          children: [
            Tooltip(
              message: 'Open on GameBanana',
              child: GbButton(
                label: '',
                icon: Icons.open_in_new,
                onTap: () => gbOpenUrl(widget.mod.profileUrl),
              ),
            ),
            GbButton(
              label: 'Close',
              onTap: _busy ? null : () => Navigator.of(context).pop(false),
            ),
            GbButton(
              label: _isUpdate ? 'Update' : 'Download',
              primary: true,
              icon: Icons.download,
              onTap: canRun ? _run : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _targetRow(double sss, Color accent) {
    final target = _target;
    final groups = ref.watch(modGroupDataProvider);
    ModGroupData? group;
    if (target?.groupPath != null) {
      for (final g in groups) {
        if (g.groupPath == target!.groupPath) group = g;
      }
    }
    final name =
        target == null
            ? 'Loading your groups…'
            : target.isNew
            ? 'New group "${target.newName}"${target.newIsUi ? ' (UI group)' : ''}'
            : (group?.groupName ?? 'Unknown group');
    final iconPath = group?.iconPath;

    return GestureDetector(
      onTap: _busy || _picker == null ? null : _change,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: EdgeInsets.all(8 * sss),
          decoration: BoxDecoration(
            border: Border.all(color: gbLine, width: 3 * sss),
            borderRadius: BorderRadius.circular(17 * sss),
          ),
          child: Row(
            children: [
              Container(
                width: 36 * sss,
                height: 36 * sss,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 3 * sss),
                ),
                child: ClipOval(
                  child:
                      target?.isNew == true || iconPath == null
                          ? Icon(
                            target?.isNew == true
                                ? Icons.add
                                : Icons.folder_outlined,
                            size: 16 * sss,
                            color: Colors.white70,
                          )
                          : Image.file(
                            File(iconPath),
                            fit: BoxFit.cover,
                            cacheWidth: 100,
                            errorBuilder:
                                (_, _, _) => Icon(
                                  Icons.folder_outlined,
                                  size: 16 * sss,
                                  color: Colors.white70,
                                ),
                          ),
                ),
              ),
              SizedBox(width: 10 * sss),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Put it in',
                      style: gbText(sss, 10, color: Colors.white60),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: gbText(sss, 12, weight: FontWeight.w600),
                    ),
                    if (_targetReason.isNotEmpty)
                      Text(
                        _targetReason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: gbText(sss, 10, color: accent),
                      ),
                  ],
                ),
              ),
              Icon(Icons.unfold_more, size: 18 * sss, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

String _size(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}
