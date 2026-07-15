import 'package:flutter/material.dart';

/// OfflineStage — shown when we cannot reach the network. The full
/// artwork lives in the static asset (portrait + landscape variants);
/// we overlay a "Reconnect" pill near the bottom edge.
///
/// The retry action is deliberately expressed as a [WidgetBuilder]
/// (a fresh page factory) rather than a bare callback. Using a
/// callback that captured the previous page's `BuildContext` caused
/// the reconnect tap to freeze: the source page had already been
/// disposed by `pushReplacement`, so `Navigator.of(<stale context>)`
/// referred to a defunct element and did nothing.
class OfflineStage extends StatefulWidget {
  const OfflineStage({super.key, required this.retryScreenBuilder});

  final WidgetBuilder retryScreenBuilder;

  @override
  State<OfflineStage> createState() => _OfflineStageState();
}

class _OfflineStageState extends State<OfflineStage> {
  bool _busy = false;

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Brief pause so the busy state is visible even on instant retries.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.retryScreenBuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, box) {
          final portrait = box.maxHeight >= box.maxWidth;
          final artwork = portrait
              ? 'assets/Vertical_Nowifi_Screen.webp'
              : 'assets/Horizontal_Nowifi_Screen.webp';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(artwork, fit: BoxFit.cover),
              // Sit the Reconnect chip flush with the artwork — no
              // SafeArea here; the invisible system-bar inset was
              // pushing the button visibly higher than where the
              // background art wants it.
              Positioned(
                left: 0,
                right: 0,
                bottom: portrait ? 42 : 22,
                child: Center(
                  child: _ReconnectChip(
                    busy: _busy,
                    onTap: _handleTap,
                    portrait: portrait,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReconnectChip extends StatefulWidget {
  const _ReconnectChip({
    required this.busy,
    required this.onTap,
    required this.portrait,
  });
  final bool busy;
  final VoidCallback onTap;
  final bool portrait;

  @override
  State<_ReconnectChip> createState() => _ReconnectChipState();
}

class _ReconnectChipState extends State<_ReconnectChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final width = widget.portrait ? 240.0 : 220.0;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: width,
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFB71C1C), Color(0xFF7B0F0F)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFE0B2), width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: const Color(0xFFFFAB40).withValues(alpha: 0.25),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFFFFE0B2),
                  ),
                )
              : const Text(
                  'RECONNECT',
                  style: TextStyle(
                    color: Color(0xFFFFF3E0),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.4,
                  ),
                ),
        ),
      ),
    );
  }
}
