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
///   • SKIP   — defers the prompt for [EnvFacade.notifyCooldownSeconds]
///     and continues to the portal.
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

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(artwork, fit: BoxFit.cover),
              if (portrait)
                Positioned(
                  left: size.width * 0.08,
                  right: size.width * 0.08,
                  bottom: size.height * 0.06,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AcceptChip(onTap: () => _handleAccept(context)),
                      const SizedBox(height: 14),
                      _SkipLink(onTap: () => _handleSkip(context)),
                    ],
                  ),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: size.height * 0.05,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: size.width * 0.34,
                        child: _AcceptChip(
                          compact: true,
                          onTap: () => _handleAccept(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _SkipLink(
                        compact: true,
                        onTap: () => _handleSkip(context),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AcceptChip extends StatefulWidget {
  const _AcceptChip({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  State<_AcceptChip> createState() => _AcceptChipState();
}

class _AcceptChipState extends State<_AcceptChip> {
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
              'ACCEPT',
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

class _SkipLink extends StatefulWidget {
  const _SkipLink({required this.onTap, this.compact = false});
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_SkipLink> createState() => _SkipLinkState();
}

class _SkipLinkState extends State<_SkipLink> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedOpacity(
        opacity: _pressed ? 0.5 : 0.9,
        duration: const Duration(milliseconds: 80),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.compact ? 4 : 8),
          child: Text(
            'SKIP',
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.compact ? 16 : 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 3.0,
              shadows: const [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
