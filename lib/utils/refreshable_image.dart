import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:no_reload_mod_manager/data/mod_data.dart';
import 'package:no_reload_mod_manager/utils/constant_var.dart';
import 'package:path/path.dart' as p;

class RefreshableLocalImage extends ConsumerStatefulWidget {
  final Image? imageWidget;
  final Widget errorWidget;

  const RefreshableLocalImage({
    required this.imageWidget,
    required this.errorWidget,
    super.key,
  });

  @override
  ConsumerState<RefreshableLocalImage> createState() =>
      _RefreshableLocalImageState();
}

class _RefreshableLocalImageState extends ConsumerState<RefreshableLocalImage> {
  @override
  Widget build(BuildContext context) {
    if (widget.imageWidget != null) {
      return widget.imageWidget!;
    } else {
      return widget.errorWidget;
    }
  }
}

class ImageRefreshListener {
  static void refreshImages(List<ModGroupData> modGroupDatas) {
    for (final groupData in modGroupDatas) {
      if (groupData.groupIcon != null) {
        groupData.groupIcon!.image.evict();
      }
      // Also evict the file paths directly just in case (raw and resized versions)
      for (final name in ConstantVar.modIconFilenames) {
        final path = p.join(groupData.groupDir.path, name);
        FileImage(File(path)).evict();
        ResizeImage(FileImage(File(path)), width: 156 * 2).evict();
      }

      for (var modData in groupData.modsInGroup) {
        if (modData.modIcon != null) {
          modData.modIcon!.image.evict();
        }
        for (final name in ConstantVar.modIconFilenames) {
          final path = p.join(modData.modDir.path, name);
          FileImage(File(path)).evict();
          ResizeImage(FileImage(File(path)), width: 156 * 2).evict();
        }
      }
    }
  }
}
