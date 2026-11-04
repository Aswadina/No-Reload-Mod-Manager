// "UI groups" — importing loose mods: the dialog and the right-click item.
// The file work is in ui_group_import_files.dart.

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:no_reload_mod_manager/custom/ui_group_import_files.dart';
import 'package:no_reload_mod_manager/main.dart';
import 'package:no_reload_mod_manager/utils/constant_var.dart';
import 'package:no_reload_mod_manager/utils/custom_menu_item.dart';
import 'package:no_reload_mod_manager/utils/managedfolder_watcher.dart';
import 'package:no_reload_mod_manager/utils/mod_manager.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';
import 'package:path/path.dart' as p;

CustomMenuItem importLooseModsMenu(
  BuildContext context,
  WidgetRef ref,
  String groupPath,
  double scale,
) {
  return CustomMenuItem(
    scale: scale,
    label: 'Import loose mods…',
    onSelected: () {
      if (!context.mounted) return;
      ref.read(alertDialogShownProvider.notifier).state = true;
      showDialog(
        barrierDismissible: false,
        context: context,
        builder: (_) => _ImportLooseModsDialog(groupPath: groupPath),
      );
    },
  );
}

class _ImportLooseModsDialog extends ConsumerStatefulWidget {
  final String groupPath;
  const _ImportLooseModsDialog({required this.groupPath});

  @override
  ConsumerState<_ImportLooseModsDialog> createState() =>
      _ImportLooseModsDialogState();
}

class _ImportLooseModsDialogState
    extends ConsumerState<_ImportLooseModsDialog> {
  List<String>? _folders;
  final Set<String> _picked = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final modsPath = ref.read(validModsPath);
    if (modsPath == null) {
      _folders = [];
    } else {
      listLooseModFolders(modsPath, ConstantVar.managedFolderName).then((
        list,
      ) {
        if (mounted) setState(() => _folders = list);
      });
    }
  }

  void _close() {
    Navigator.of(context).pop();
    ref.read(alertDialogShownProvider.notifier).state = false;
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    // Our moves should not trigger the folder watcher's UI refresh.
    final watchedPath = DynamicDirectoryWatcher.watcher?.path;
    DynamicDirectoryWatcher.stop();
    await importModFolders(_picked.toList(), widget.groupPath);
    if (watchedPath != null) DynamicDirectoryWatcher.watch(watchedPath);
    if (!mounted) return;
    triggerRefresh(ref);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final accent = getAccentColor(ref);
    final folders = _folders;
    return Stack(
      children: [
        MoveWindow(),
        AlertDialog(
          title: Text(
            'Import loose mods',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          content: SizedBox(
            width: 380,
            height: 320,
            child:
                folders == null
                    ? const Center(child: CircularProgressIndicator())
                    : folders.isEmpty
                    ? Text(
                      'No loose mod folders found in the Mods folder.',
                      style: GoogleFonts.poppins(color: Colors.white),
                    )
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tick the mods to move into this group. Then run '
                          'Update Mod Data.',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final folder in folders)
                                CheckboxListTile(
                                  dense: true,
                                  activeColor: accent,
                                  value: _picked.contains(folder),
                                  title: Text(
                                    p.basename(folder),
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                  onChanged:
                                      _busy
                                          ? null
                                          : (on) => setState(() {
                                            on == true
                                                ? _picked.add(folder)
                                                : _picked.remove(folder);
                                          }),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : _close,
              child: Text('Cancel', style: GoogleFonts.poppins(color: accent)),
            ),
            TextButton(
              onPressed: _busy || _picked.isEmpty ? null : _import,
              child: Text(
                'Import (${_picked.length})',
                style: GoogleFonts.poppins(color: accent),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
