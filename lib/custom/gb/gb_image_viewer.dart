// GameBanana tab — full-screen picture viewer.
// Arrow keys or the side buttons change picture, the mouse wheel zooms,
// dragging pans, Esc or the X closes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:no_reload_mod_manager/custom/gb/gb_widgets.dart';

Future<void> showGbImageViewer(
  BuildContext context,
  List<String> urls,
  int start,
) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Close',
    barrierColor: const Color.fromARGB(235, 0, 0, 0),
    pageBuilder: (_, _, _) => _Viewer(urls: urls, start: start),
  );
}

class _Viewer extends StatefulWidget {
  final List<String> urls;
  final int start;
  const _Viewer({required this.urls, required this.start});

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late int _index = widget.start.clamp(0, widget.urls.length - 1);

  void _move(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.urls.length) return;
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.urls.length > 1;
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _move(-1);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _move(1);
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              key: ValueKey(_index), // a new picture starts unzoomed
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: Image.network(
                  widget.urls[_index],
                  fit: BoxFit.contain,
                  loadingBuilder:
                      (context, child, progress) =>
                          progress == null
                              ? child
                              : const Center(
                                child: CircularProgressIndicator(),
                              ),
                  errorBuilder:
                      (_, _, _) => const Icon(
                        Icons.image_not_supported_outlined,
                        color: gbLine,
                        size: 48,
                      ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: _RoundButton(
                icon: Icons.close,
                tooltip: 'Close (Esc)',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            if (many && _index > 0)
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _RoundButton(
                    icon: Icons.chevron_left,
                    tooltip: 'Previous (←)',
                    onTap: () => _move(-1),
                  ),
                ),
              ),
            if (many && _index < widget.urls.length - 1)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _RoundButton(
                    icon: Icons.chevron_right,
                    tooltip: 'Next (→)',
                    onTap: () => _move(1),
                  ),
                ),
              ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(160, 0, 0, 0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.urls.length}   ·   scroll to zoom, drag to move',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color.fromARGB(150, 0, 0, 0),
              shape: BoxShape.circle,
              border: Border.all(color: gbLine, width: 2),
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
