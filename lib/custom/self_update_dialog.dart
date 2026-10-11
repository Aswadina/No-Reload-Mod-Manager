import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:no_reload_mod_manager/main.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';

/// Personal build: shown instead of the upstream auto-updater. Updates are
/// installed by the daily "NRMM Self-Update" task (tools/self-update).
class SelfUpdateInfoDialog extends ConsumerWidget {
  const SelfUpdateInfoDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        MoveWindow(),
        AlertDialog(
          title: Text(
            'Updates'.tr(),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          content: Text(
            'This is a personal build. New releases are merged, built and '
            'installed automatically by the daily "NRMM Self-Update" task.\n\n'
            'Logs: %LOCALAPPDATA%\\NRMM-Builder\\logs',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(alertDialogShownProvider.notifier).state = false;
              },
              child: Text(
                'OK'.tr(),
                style: GoogleFonts.poppins(color: getAccentColor(ref)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
