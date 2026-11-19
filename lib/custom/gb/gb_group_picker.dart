// GameBanana tab — choosing which group a downloaded mod goes into.
//
// Shows a suggested group first (with the reason), then recent ones, then all
// groups, with a search box and a "New group" form that asks for a name and a
// type (character group or UI group).

import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_api.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_helpers.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_prefs.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_widgets.dart';
import 'package:no_reload_mod_manager/custom/ui_group_files.dart';
import 'package:no_reload_mod_manager/data/mod_data.dart';
import 'package:no_reload_mod_manager/main.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';

class GbTarget {
  final String? groupPath;
  final String? newName;
  final bool newIsUi;
  const GbTarget.existing(String path)
    : groupPath = path,
      newName = null,
      newIsUi = false;
  const GbTarget.create(String name, {required bool isUi})
    : groupPath = null,
      newName = name,
      newIsUi = isUi;

  bool get isNew => groupPath == null;
}

class GbPickerData {
  final List<GbGroupCandidate> groups;
  final List<GbSuggestion> suggestions;
  final List<String> recents; // group paths that still exist
  final GbTarget defaultTarget;
  final String defaultReason;
  final String suggestedNewName;
  const GbPickerData({
    required this.groups,
    required this.suggestions,
    required this.recents,
    required this.defaultTarget,
    required this.defaultReason,
    required this.suggestedNewName,
  });
}

/// Name to prefill when the user makes a new group for this mod.
String defaultNewGroupName(GbMod mod, String categoryName) {
  if (categoryName.toLowerCase() == 'ui') return 'UI';
  if (mod.subCategoryName.isNotEmpty) return mod.subCategoryName;
  return searchTermForGroup(mod.name);
}

Future<GbPickerData> loadGbPickerData(
  WidgetRef ref, {
  required GbModDetails details,
  required GbMod mod,
  required String game,
}) async {
  final groups = ref.read(modGroupDataProvider);
  final candidates = [
    for (final g in groups)
      GbGroupCandidate(
        path: g.groupPath,
        name: g.groupName,
        isUi: await isUiGroupFolder(g.groupPath),
      ),
  ];
  final category =
      mod.categoryName.isNotEmpty ? mod.categoryName : details.categoryName;
  final suggestions = suggestGroups(
    modName: mod.name,
    categoryName: category,
    tags: [
      ...mod.tags,
      ...details.tags,
      // For a skin, GameBanana's mod-page category is the character.
      if (details.categoryName.isNotEmpty && details.categoryName != category)
        details.categoryName,
      if (mod.subCategoryName.isNotEmpty) mod.subCategoryName,
    ],
    groups: candidates,
  );
  final known = {for (final c in candidates) c.path};
  final recents = [
    for (final path in await GbPrefs.recentGroups(game))
      if (known.contains(path)) path,
  ];
  final last = await GbPrefs.lastGroupFor(game, category);
  final newName = defaultNewGroupName(mod, category);

  GbTarget target;
  String reason;
  if (suggestions.isNotEmpty) {
    target = GbTarget.existing(suggestions.first.group.path);
    reason = suggestions.first.reason;
  } else if (last != null && known.contains(last)) {
    target = GbTarget.existing(last);
    reason =
        'Last group you used for ${category.isEmpty ? 'this kind of mod' : category}';
  } else {
    final index = ref.read(currentGroupIndexProvider);
    if (candidates.isNotEmpty) {
      final c = candidates[index.clamp(0, candidates.length - 1)];
      target = GbTarget.existing(c.path);
      reason = 'The group you are looking at in Mods';
    } else {
      target = GbTarget.create(newName, isUi: category.toLowerCase() == 'ui');
      reason = 'You have no groups yet, so a new one will be made';
    }
  }
  return GbPickerData(
    groups: candidates,
    suggestions: suggestions,
    recents: recents,
    defaultTarget: target,
    defaultReason: reason,
    suggestedNewName: newName,
  );
}

Future<GbTarget?> showGbGroupPicker(
  BuildContext context, {
  required GbPickerData data,
  required String? selectedPath,
}) {
  return showDialog<GbTarget>(
    barrierDismissible: false,
    context: context,
    builder: (_) => _GroupPicker(data: data, selectedPath: selectedPath),
  );
}

class _GroupPicker extends ConsumerStatefulWidget {
  final GbPickerData data;
  final String? selectedPath;
  const _GroupPicker({required this.data, required this.selectedPath});

  @override
  ConsumerState<_GroupPicker> createState() => _GroupPickerState();
}

class _GroupPickerState extends ConsumerState<_GroupPicker> {
  final _search = TextEditingController();
  late final _name = TextEditingController(text: widget.data.suggestedNewName);
  bool _creating = false;
  bool _newIsUi = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  void _pick(String path) => Navigator.of(context).pop(GbTarget.existing(path));

  @override
  Widget build(BuildContext context) {
    final sss = ref.watch(zoomScaleProvider);
    final groups = {
      for (final g in ref.watch(modGroupDataProvider)) g.groupPath: g,
    };
    final query = _search.text.trim().toLowerCase();
    final searching = query.isNotEmpty;

    bool matches(GbGroupCandidate c) =>
        !searching || c.name.toLowerCase().contains(query);

    final suggestedPaths = {
      for (final s in widget.data.suggestions) s.group.path,
    };
    final recentPaths = [
      for (final p in widget.data.recents)
        if (!suggestedPaths.contains(p)) p,
    ];
    final byPath = {for (final c in widget.data.groups) c.path: c};

    Widget section(String label) => Padding(
      padding: EdgeInsets.only(top: 10 * sss, bottom: 4 * sss),
      child: Text(label, style: gbText(sss, 11, color: Colors.white60)),
    );

    Widget row(GbGroupCandidate c, {String? reason}) => _GroupRow(
      candidate: c,
      group: groups[c.path],
      subtitle: reason,
      selected: c.path == widget.selectedPath,
      onTap: () => _pick(c.path),
    );

    return Stack(
      children: [
        MoveWindow(),
        Dialog(
          backgroundColor: gbDialogColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            width: 460 * sss,
            height: 540 * sss,
            child: Padding(
              padding: EdgeInsets.all(18 * sss),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Put it in…',
                    style: gbText(sss, 16, weight: FontWeight.w600),
                  ),
                  SizedBox(height: 10 * sss),
                  Container(
                    height: 36 * sss,
                    padding: EdgeInsets.symmetric(horizontal: 14 * sss),
                    decoration: BoxDecoration(
                      border: Border.all(color: gbLine, width: 3 * sss),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      style: gbText(sss, 12),
                      cursorColor: getAccentColor(ref),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 9 * sss),
                        hintText: 'Search your groups…',
                        hintStyle: gbText(sss, 12, color: Colors.white54),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        if (!searching &&
                            widget.data.suggestions.isNotEmpty) ...[
                          section('Suggested'),
                          for (final s in widget.data.suggestions)
                            row(s.group, reason: s.reason),
                        ],
                        if (!searching && recentPaths.isNotEmpty) ...[
                          section('Recent'),
                          for (final p in recentPaths)
                            if (byPath[p] != null) row(byPath[p]!),
                        ],
                        section(searching ? 'Matching groups' : 'All groups'),
                        if (!searching) _newGroupRow(sss),
                        for (final c in widget.data.groups)
                          if (matches(c)) row(c),
                        if (searching && !widget.data.groups.any(matches))
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 12 * sss),
                            child: Text(
                              'No group matches "${_search.text.trim()}".',
                              style: gbText(sss, 12, color: Colors.white60),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8 * sss),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GbButton(
                        label: 'Cancel',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _newGroupRow(double sss) {
    final accent = getAccentColor(ref);
    if (!_creating) {
      return InkWell(
        onTap: () => setState(() => _creating = true),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8 * sss),
          child: Row(
            children: [
              Container(
                width: 38 * sss,
                height: 38 * sss,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 3 * sss),
                ),
                child: Icon(Icons.add, size: 18 * sss, color: accent),
              ),
              SizedBox(width: 10 * sss),
              Text(
                'New group…',
                style: gbText(sss, 12, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      margin: EdgeInsets.symmetric(vertical: 6 * sss),
      padding: EdgeInsets.all(12 * sss),
      decoration: BoxDecoration(
        border: Border.all(color: accent, width: 3 * sss),
        borderRadius: BorderRadius.circular(17 * sss),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Name of the new group',
            style: gbText(sss, 11, color: Colors.white60),
          ),
          SizedBox(height: 4 * sss),
          Container(
            height: 34 * sss,
            padding: EdgeInsets.symmetric(horizontal: 12 * sss),
            decoration: BoxDecoration(
              border: Border.all(color: gbLine, width: 2 * sss),
              borderRadius: BorderRadius.circular(999),
            ),
            child: TextField(
              controller: _name,
              style: gbText(sss, 12),
              cursorColor: accent,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8 * sss),
              ),
            ),
          ),
          SizedBox(height: 8 * sss),
          Wrap(
            spacing: 6 * sss,
            runSpacing: 6 * sss,
            children: [
              GbPill(
                label: 'Character group',
                selected: !_newIsUi,
                onTap: () => setState(() => _newIsUi = false),
              ),
              GbPill(
                label: 'UI group (several on)',
                selected: _newIsUi,
                onTap: () => setState(() => _newIsUi = true),
              ),
            ],
          ),
          SizedBox(height: 10 * sss),
          Align(
            alignment: Alignment.centerRight,
            child: GbButton(
              label: 'Create',
              primary: true,
              onTap:
                  _name.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(
                        context,
                      ).pop(GbTarget.create(_name.text.trim(), isUi: _newIsUi)),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends ConsumerWidget {
  final GbGroupCandidate candidate;
  final ModGroupData? group;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _GroupRow({
    required this.candidate,
    required this.group,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sss = ref.watch(zoomScaleProvider);
    final accent = getAccentColor(ref);
    final modCount =
        group == null ? 0 : group!.modsInGroup.length - 1; // minus "None"
    final iconPath = group?.iconPath;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12 * sss),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6 * sss),
        child: Row(
          children: [
            Container(
              width: 38 * sss,
              height: 38 * sss,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accent : gbLine,
                  width: 3 * sss,
                ),
              ),
              child: ClipOval(
                child:
                    iconPath == null
                        ? Icon(
                          Icons.folder_outlined,
                          size: 18 * sss,
                          color: gbLine,
                        )
                        : Image.file(
                          File(iconPath),
                          fit: BoxFit.cover,
                          cacheWidth: 100,
                          errorBuilder:
                              (_, _, _) => Icon(
                                Icons.folder_outlined,
                                size: 18 * sss,
                                color: gbLine,
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
                    candidate.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: gbText(sss, 12, weight: FontWeight.w500),
                  ),
                  Text(
                    subtitle ??
                        '$modCount mod${modCount == 1 ? '' : 's'}${candidate.isUi ? '  ·  UI group' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: gbText(
                      sss,
                      10,
                      color: subtitle != null ? accent : Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check, size: 16 * sss, color: accent),
          ],
        ),
      ),
    );
  }
}
