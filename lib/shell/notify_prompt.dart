import 'package:flutter/material.dart';

import '../core/net_sensor.dart';
import '../core/push_hub.dart';
import '../core/vault.dart';
import '../env/facade.dart';
import 'portal_view.dart' deferred as portal;

/// NotifyPrompt — one-shot promo for enabling push. Uses the static
/// portrait/landscape artwork bundled with the project so we don't
/// need a video decoder here (differs from sibling apps by design).
///
/// Buttons:
///   • ACCEPT — fires the system permission dialog. On denial the
///     OS-banned latch is set inside PushHub.requestPermission.
///   • SKIP   — same gradient chip as Accept, but defers the prompt
///     for [EnvFacade.notifyCooldownSeconds].
class NotifyPrompt extends StatelessWidget {
  const NotifyPrompt({
    super.key,
    required this.vault,
    required this.pushHub,
    required this.netSensor,
    required this.contentUrl,
  });

  final Vault vault;
  final PushHub pushHub;
  final NetSensor netSensor;
  final String contentUrl;

  Future<void> _handleAccept(BuildContext context) async {
    final granted = await pushHub.requestPermission();
    if (!granted) {
      final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          EnvFacade.notifyCooldownSeconds;
      await vault.deferNotifyPromptUntil(until);
    }
    if (!context.mounted) return;
    await _leaveToPortal(context);
  }

  Future<void> _handleSkip(BuildContext context) async {
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        EnvFacade.notifyCooldownSeconds;
    await vault.deferNotifyPromptUntil(until);
    if (!context.mounted) return;
    await _leaveToPortal(context);
  }

  Future<void> _leaveToPortal(BuildContext context) async {
    await portal.loadLibrary();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => portal.PortalView(
        initialUrl: contentUrl,
        vault: vault,
        pushHub: pushHub,
        netSensor: netSensor,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, box) {
          final portrait = box.maxHeight >= box.maxWidth;
          final artwork = portrait
              ? 'assets/Vertical_Notifications_Screen.webp'
              : 'assets/Horizontal_Notifications_Screen.webp';
          final size = MediaQuery.of(context).size;
          final accept = _GradientChip(
            label: 'ACCEPT',
            compact: !portrait,
            onTap: () => _handleAccept(context),
          );
          final skip = _GradientChip(
            label: 'SKIP',
            compact: !portrait,
            onTap: () => _handleSkip(context),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(artwork, fit: BoxFit.cover),
              // Anchor the buttons directly to the raw screen edges —
              // no SafeArea. The invisible system-bar inset was
              // shifting the button stack visibly upward.
              if (portrait)
                Positioned(
                  left: size.width * 0.08,
                  right: size.width * 0.08,
                  bottom: size.height * 0.06,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      accept,
                      const SizedBox(height: 12),
                      skip,
                    ],
                  ),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: size.height * 0.05,
                  child: Center(
                    // Nudge the button stack 8 px to the left so it
                    // lines up with the composition in
                    // assets/Horizontal_Notifications_Screen.webp
                    // (the artwork's speech bubble sits slightly
                    // left of the geometric centre).
                    child: Transform.translate(
                      offset: const Offset(-8, 0),
                      child: SizedBox(
                        width: size.width * 0.34,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            accept,
                            const SizedBox(height: 8),
                            skip,
                          ],
                        ),
                      ),
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

/// Shared button widget. Accept and Skip use the same fiery gradient
/// so the choice reads as symmetric — only the label differs.
class _GradientChip extends StatefulWidget {
  const _GradientChip({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_GradientChip> createState() => _GradientChipState();
}

class _GradientChipState extends State<_GradientChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final vPad = widget.compact ? 12.0 : 18.0;
    final fontSize = widget.compact ? 16.0 : 22.0;
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
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: vPad),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _pressed
                  ? const [Color(0xFFCC3B0F), Color(0xFF8F1A00)]
                  : const [Color(0xFFFF5722), Color(0xFFBF360C)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFE0B2), width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6D00).withValues(alpha: 0.55),
                blurRadius: 22,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: const Color(0xFFFFF8E1),
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
