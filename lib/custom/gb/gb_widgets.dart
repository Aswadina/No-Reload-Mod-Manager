// GameBanana tab — small shared widgets in NRMM's own look
// (3px translucent-white borders, pill shapes, Poppins, accent color).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_html.dart';
import 'package:no_reload_mod_manager/main.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';
import 'package:url_launcher/url_launcher.dart';

const gbLine = Color.fromARGB(127, 255, 255, 255);
const gbDialogColor = Color(0xFF2B2930);

Future<void> gbOpenUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url));
  } catch (_) {}
}

/// Tests switch this off, because google_fonts cannot load fonts there.
bool gbUsePoppins = true;

TextStyle gbText(
  double sss,
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
}) =>
    gbUsePoppins
        ? GoogleFonts.poppins(
          fontSize: size * sss,
          fontWeight: weight,
          color: color,
        )
        : TextStyle(fontSize: size * sss, fontWeight: weight, color: color);

/// A pill like the tab bar's. Highlights with the accent color when selected.
class GbPill extends ConsumerStatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool compact;
  const GbPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.compact = false,
  });

  @override
  ConsumerState<GbPill> createState() => _GbPillState();
}

class _GbPillState extends ConsumerState<GbPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sss = ref.watch(zoomScaleProvider);
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            height: (widget.compact ? 26 : 30) * sss,
            padding: EdgeInsets.symmetric(horizontal: 12 * sss),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color:
                    widget.selected
                        ? getAccentColor(ref)
                        : (_hover && enabled ? Colors.white : gbLine),
                width: 3 * sss,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 14 * sss, color: Colors.white),
                  SizedBox(width: 4 * sss),
                ],
                Text(
                  widget.label,
                  style: gbText(sss, 11, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bigger action button. [primary] fills it with the accent color.
class GbButton extends ConsumerWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;
  const GbButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sss = ref.watch(zoomScaleProvider);
    final accent = getAccentColor(ref);
    final enabled = onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            height: 36 * sss,
            padding: EdgeInsets.symmetric(
              horizontal: (label.isEmpty ? 11 : 18) * sss,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary ? accent : Colors.transparent,
              border: Border.all(
                color: primary ? accent : gbLine,
                width: 3 * sss,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null)
                  Icon(icon, size: 16 * sss, color: Colors.white),
                if (icon != null && label.isNotEmpty) SizedBox(width: 6 * sss),
                if (label.isNotEmpty)
                  Text(label, style: gbText(sss, 12, weight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GbMessage extends ConsumerWidget {
  final String text;
  final VoidCallback? retry;
  const GbMessage(this.text, {super.key, this.retry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sss = ref.watch(zoomScaleProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center, style: gbText(sss, 13)),
          if (retry != null)
            Padding(
              padding: EdgeInsets.only(top: 10 * sss),
              child: GbPill(label: 'Try again', selected: true, onTap: retry),
            ),
        ],
      ),
    );
  }
}

/// Grey placeholder shaped like a mod card, shown while a page loads.
class GbSkeletonCard extends ConsumerWidget {
  const GbSkeletonCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sss = ref.watch(zoomScaleProvider);
    Widget bar(double w, double h) => Container(
      width: w * sss,
      height: h * sss,
      decoration: BoxDecoration(
        color: const Color.fromARGB(30, 255, 255, 255),
        borderRadius: BorderRadius.circular(6 * sss),
      ),
    );
    return Column(
      children: [
        Container(
          height: 217.8 * sss,
          width: 156.816 * sss,
          decoration: BoxDecoration(
            color: const Color.fromARGB(18, 255, 255, 255),
            border: Border.all(
              color: const Color.fromARGB(50, 255, 255, 255),
              width: 3 * sss,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
            borderRadius: BorderRadius.circular(17 * sss),
          ),
        ),
        SizedBox(height: 8 * sss),
        bar(120, 10),
        SizedBox(height: 6 * sss),
        bar(80, 8),
      ],
    );
  }
}

/// Network picture that fades in and shows an icon if it cannot load.
class GbNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  const GbNetworkImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      frameBuilder:
          (context, child, frame, sync) =>
              sync
                  ? child
                  : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: child,
                  ),
      errorBuilder:
          (_, _, _) => const Center(
            child: Icon(Icons.image_not_supported_outlined, color: gbLine),
          ),
    );
  }
}

/// Renders the blocks from [parseGbHtml]: bold, italic, bullets, and links
/// that open in the browser.
class GbRichText extends ConsumerStatefulWidget {
  final List<GbBlock> blocks;
  const GbRichText(this.blocks, {super.key});

  @override
  ConsumerState<GbRichText> createState() => _GbRichTextState();
}

class _GbRichTextState extends ConsumerState<GbRichText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sss = ref.watch(zoomScaleProvider);
    final accent = getAccentColor(ref);
    _disposeRecognizers();

    TextSpan span(GbSpan s) {
      TapGestureRecognizer? tap;
      if (s.link != null) {
        tap = TapGestureRecognizer()..onTap = () => gbOpenUrl(s.link!);
        _recognizers.add(tap);
      }
      return TextSpan(
        text: s.text,
        recognizer: tap,
        style: gbText(
          sss,
          12,
          weight: s.bold ? FontWeight.w600 : FontWeight.w400,
          color: s.link != null ? accent : Colors.white,
        ).copyWith(
          fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
          decoration: s.link != null ? TextDecoration.underline : null,
          decorationColor: accent,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in widget.blocks)
          Padding(
            padding: EdgeInsets.only(bottom: 7 * sss),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (block.bullet)
                  SizedBox(
                    width: 16 * sss,
                    child: Text('•', style: gbText(sss, 12)),
                  ),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [for (final s in block.spans) span(s)]),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
