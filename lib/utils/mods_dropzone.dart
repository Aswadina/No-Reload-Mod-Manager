import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:no_reload_mod_manager/main.dart';
import 'package:no_reload_mod_manager/utils/archive_manager.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';
import 'package:no_reload_mod_manager/utils/ui_dialogues.dart';
import 'package:path/path.dart' as p;

class ModsDropZone extends ConsumerStatefulWidget {
  final String? copyDestination;
  final TextSpan? additionalContent;
  final bool? checkForMaxMods;
  final int? currentModsCountInGroup;
  final bool acceptArchived;
  final String dialogTitleText;
  final void Function(List<Directory> validFolders, List<File>)
  onConfirmFunction;
  final bool forRestorer;
  const ModsDropZone({
    super.key,
    required this.dialogTitleText,
    required this.onConfirmFunction,
    this.acceptArchived = false,
    this.checkForMaxMods = false,
    this.currentModsCountInGroup,
    this.additionalContent,
    this.copyDestination,
    this.forRestorer = false,
  });

  @override
  ConsumerState<ModsDropZone> createState() => _ModsDropZoneState();
}

class _ModsDropZoneState extends ConsumerState<ModsDropZone> {
  bool _dragging = false;

  List<String> parseDropPaths(List<dynamic> files) {
    final Set<String> results = {};
    for (var f in files) {
      String rawPath = f.path;
      // Split by newlines in case paths got merged (happens on some platforms/bugs)
      // Also replace literal '\n' and '\r' strings with actual newlines to support Windows Chrome drops properly
      final lines = rawPath
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '\r')
          .split(RegExp(r'[\r\n]+'));
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        // Handle file:// URIs
        if (line.startsWith('file:')) {
          try {
            // Decode percent-encoded characters like %20 to space
            String decoded = Uri.decodeFull(line);
            // Strip "file:" and any following forward or backward slashes
            decoded = decoded.replaceFirst(RegExp(r'^file:[\/\\]+'), '');
            // On Windows, if the path starts with a slash, strip it if followed by a drive letter (e.g. /C:/ -> C:/)
            if (Platform.isWindows &&
                decoded.startsWith('/') &&
                decoded.length > 2 &&
                decoded[2] == ':') {
              decoded = decoded.substring(1);
            }
            results.add(p.normalize(decoded));
            continue;
          } catch (_) {
            // Fallback stripping if Uri parsing fails
            line = line.replaceFirst(RegExp(r'^file:[\/\\]+'), '');
          }
        }
        results.add(p.normalize(line));
      }
    }
    return results.toList();
  }

  bool isFolderAndExist(String path) {
    try {
      if (Directory(path).existsSync()) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  bool isFileAndExist(String path) {
    try {
      if (File(path).existsSync()) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  void showMaxMessage(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF2B2930),
        margin: EdgeInsets.only(left: 20, right: 20, bottom: 20),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        closeIconColor: getAccentColor(ref),
        showCloseIcon: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Text(
          text,
          style: GoogleFonts.poppins(
            color: Colors.yellow,
            fontSize: 13 * ref.read(zoomScaleProvider),
          ),
        ),
        dismissDirection: DismissDirection.down,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (details) {
        final List<String> parsedPaths = parseDropPaths(details.files);

        final List<Directory> droppedFolders = parsedPaths
            .where((path) => isFolderAndExist(path))
            .map((path) => Directory(path))
            .toList();

        List<File> droppedArchives = [];
        //modArchives is empty for restore function
        if (widget.acceptArchived) {
          droppedArchives = parsedPaths
              .where((path) => isFileAndExist(path) && SevenZip.isSupported(path))
              .map((path) => File(path))
              .toList();
        }

        if (widget.checkForMaxMods != null &&
            widget.currentModsCountInGroup != null) {
          if (widget.checkForMaxMods == true) {
            //Max actually 500, but 501, because index 0 is None mod
            if (widget.currentModsCountInGroup! +
                    droppedFolders.length +
                    droppedArchives.length >
                501) {
              showMaxMessage(
                'Max mod info'.tr(
                  args: [
                    (widget.currentModsCountInGroup! - 1).toString(),
                    (droppedFolders.length + droppedArchives.length).toString(),
                  ],
                ),
              );
              return;
            }
          }
        }

        if (droppedFolders.isNotEmpty || droppedArchives.isNotEmpty) {
          ref.read(alertDialogShownProvider.notifier).state = true;
          showDialog(
            barrierDismissible: false,
            context: context,
            builder:
                (context) => OnDropModFolderDialog(
                  droppedFolders: droppedFolders,
                  droppedArchives: droppedArchives,
                  copyDestination: widget.copyDestination,
                  dialogTitleText: widget.dialogTitleText,
                  onConfirmFunction: widget.onConfirmFunction,
                  additionalContent: widget.additionalContent,
                  forRestorer: widget.forRestorer,
                ),
          );
        }
      },
      onDragEntered: (details) {
        setState(() {
          _dragging = true;
        });
      },
      onDragExited: (details) {
        setState(() {
          _dragging = false;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color:
              _dragging ? getAccentColor(ref, alpha: 30) : Colors.transparent,
        ),
      ),
    );
  }
}
