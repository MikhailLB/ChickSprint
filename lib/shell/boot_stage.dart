import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/net_sensor.dart';
import '../core/push_hub.dart';
import '../core/tracker_hub.dart';
import '../core/vault.dart';
import '../core/gateway_api.dart';
import '../state/gateway_reply.dart';
import '../state/route_mode.dart';
import 'portal_view.dart' deferred as portal;
import 'notify_prompt.dart';
import 'offline_stage.dart';
import '../screens/menu_screen.dart';

/// BootStage — the first screen users see.
///
/// Responsibilities:
///  1. Play the two-orientation loading art (portrait / landscape).
///  2. Fill a left→right progress bar; only complete 100 % on the
///     final tick before we actually navigate.
///  3. Run the gray/white router. On first launch:
///       fresh → race attribution → POST /config.php → portal | arena
///       portal (returning) → attempt fresh URL, fall back to saved
///       arena (returning) → straight to the native game
///  4. Bail to [OfflineStage] if we lose the network.
class BootStage extends StatefulWidget {
  const BootStage({
    super.key,
    required this.vault,
    required this.netSensor,
    required this.trackerHub,
    required this.gatewayApi,
    required this.pushHub,
  });

  final Vault vault;
  final NetSensor netSensor;
  final TrackerHub trackerHub;
  final GatewayApi gatewayApi;
  final PushHub pushHub;

  @override
  State<BootStage> createState() => _BootStageState();
}

class _BootStageState extends State<BootStage>
    with TickerProviderStateMixin {
  late final AnimationController _barCtrl;
  Timer? _dotsTicker;
  int _dotFrame = 0;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    // Loading screen supports both orientations — locking to portrait
    // happens only after we route into the game (arena).
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _barCtrl = AnimationController(
      vsync: this,
      value: 0,
      duration: const Duration(milliseconds: 900),
    );

    _dotsTicker = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() => _dotFrame = (_dotFrame + 1) % 3);
    });

    _steerToDestination();
  }

  @override
  void dispose() {
    _dotsTicker?.cancel();
    _barCtrl.dispose();
    super.dispose();
  }

  Future<void> _pulseBarTo(double target, {int ms = 700}) async {
    if (!mounted) return;
    await _barCtrl.animateTo(
      target,
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _steerToDestination() async {
    widget.pushHub.onTokenRotate = _onTokenRotate;
    await widget.pushHub.boot();

    await _pulseBarTo(0.15);

    switch (widget.vault.currentMode()) {
      case RouteMode.fresh:
        await _runFirstLaunch();
        break;
      case RouteMode.portal:
        await _runReturningPortal();
        break;
      case RouteMode.arena:
        await _runReturningArena();
        break;
    }
  }

  // ─── First launch ──────────────────────────────────────────────
  Future<void> _runFirstLaunch() async {
    final online = await widget.netSensor.online();
    if (!online) {
      if (!mounted) return;
      _swapToOffline(fromFirstLaunch: true);
      return;
    }

    await _pulseBarTo(0.35);
    await widget.trackerHub.boot();

    // Phase 1 — race SDK attribution and UDL.
    await Future.wait([
      widget.trackerHub.awaitInstallData(),
      widget.trackerHub.awaitDeepLink(),
    ]);
    await _pulseBarTo(0.65);

    // Phase 2 — pitfalls §11 rescue.
    if (!widget.trackerHub.hasInstallData &&
        widget.trackerHub.deepLinkLooksPaid) {
      await Future.any([
        widget.trackerHub.rescueViaGcd(),
        widget.trackerHub.awaitInstallData(),
      ]);
    }
    await _pulseBarTo(0.85, ms: 550);

    final locale = Platform.localeName.replaceAll('-', '_');
    final payload = await widget.trackerHub.assemblePayload(
      locale: locale,
      pushToken: widget.pushHub.token,
    );
    final reply = await widget.gatewayApi.submit(payload);

    if (!mounted) return;
    if (reply.ok && reply.hasUrl) {
      await widget.vault.commitMode(RouteMode.portal);
      await _completeBarAndNavigate(() => _routeToPortal(reply.url!));
    } else {
      await widget.vault.commitMode(RouteMode.arena);
      await _completeBarAndNavigate(_routeToArena);
    }
  }

  // ─── Returning portal user ─────────────────────────────────────
  Future<void> _runReturningPortal() async {
    final online = await widget.netSensor.online();
    if (!online) {
      if (!mounted) return;
      await _completeBarAndNavigate(() => _swapToOffline(fromFirstLaunch: false));
      return;
    }

    final cold = await widget.vault.pluckColdTapUrl();
    if (cold != null) {
      final safe = sanitisePushUri(cold);
      if (safe != null) {
        if (!mounted) return;
        await _completeBarAndNavigate(() => _routeToPortal(safe.toString()));
        return;
      }
    }

    final savedPortalUrl = await widget.vault.readPortalUrl();

    await widget.trackerHub.boot();
    await Future.wait([
      widget.trackerHub.awaitInstallDataQuick(),
      widget.trackerHub.awaitDeepLink(),
    ]);
    await _pulseBarTo(0.7);

    final locale = Platform.localeName.replaceAll('-', '_');
    final payload = await widget.trackerHub.assemblePayload(
      locale: locale,
      pushToken: widget.pushHub.token,
    );
    final GatewayReply reply = await widget.gatewayApi.submit(payload);

    if (!mounted) return;
    if (reply.ok && reply.hasUrl) {
      await _completeBarAndNavigate(() => _routeToPortal(reply.url!));
    } else if (savedPortalUrl != null && savedPortalUrl.isNotEmpty) {
      await _completeBarAndNavigate(() => _routeToPortal(savedPortalUrl));
    } else {
      await _completeBarAndNavigate(
          () => _swapToOffline(fromFirstLaunch: false));
    }
  }

  // ─── Returning arena user ──────────────────────────────────────
  Future<void> _runReturningArena() async {
    await _pulseBarTo(0.5, ms: 500);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _completeBarAndNavigate(_routeToArena);
  }

  // ─── Navigation helpers ────────────────────────────────────────
  Future<void> _completeBarAndNavigate(FutureOr<void> Function() go) async {
    await _pulseBarTo(1.0, ms: 450);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    if (_left) return;
    _left = true;
    await go();
  }

  Future<void> _routeToPortal(String url) async {
    await portal.loadLibrary();
    if (!mounted) return;

    if (widget.vault.shouldShowNotifyPrompt()) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => NotifyPrompt(
          vault: widget.vault,
          pushHub: widget.pushHub,
          netSensor: widget.netSensor,
          contentUrl: url,
        ),
      ));
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => portal.PortalView(
          initialUrl: url,
          vault: widget.vault,
          pushHub: widget.pushHub,
          netSensor: widget.netSensor,
        ),
      ));
    }
  }

  Future<void> _routeToArena() async {
    // The white part is portrait-only.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MenuScreen()),
    );
  }

  void _swapToOffline({required bool fromFirstLaunch}) {
    if (_left) return;
    _left = true;
    // Snapshot services now — `widget.*` is safe to read at this point
    // even though the OfflineStage's retry builder will fire long after
    // this BootStage instance is disposed.
    final vault = widget.vault;
    final netSensor = widget.netSensor;
    final trackerHub = widget.trackerHub;
    final gatewayApi = widget.gatewayApi;
    final pushHub = widget.pushHub;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineStage(
          retryScreenBuilder: (_) => BootStage(
            vault: vault,
            netSensor: netSensor,
            trackerHub: trackerHub,
            gatewayApi: gatewayApi,
            pushHub: pushHub,
          ),
        ),
      ),
    );
  }

  void _onTokenRotate(String freshToken) async {
    // Re-POST the gateway with the rotated token so the backend knows
    // where to reach this user for push.
    try {
      final locale = Platform.localeName.replaceAll('-', '_');
      final payload = await widget.trackerHub.assemblePayload(
        locale: locale,
        pushToken: freshToken,
      );
      unawaited(widget.gatewayApi.submit(payload));
    } catch (_) {}
  }

  // ─── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0700),
      body: LayoutBuilder(
        builder: (context, box) {
          final portraitMode = box.maxHeight >= box.maxWidth;
          final backgroundAsset = portraitMode
              ? 'assets/Vertical_Loading_Screen.webp'
              : 'assets/Horizontal_Loading_Screen.webp';

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(backgroundAsset, fit: BoxFit.cover),
              // Vignette so the loader reads on top of the busy art.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x66000000),
                    ],
                    stops: [0.55, 1.0],
                  ),
                ),
              ),
              // SafeArea handles the landscape camera cutout — without
              // it the loader can end up under the punch-hole on
              // devices like Galaxy S24/S25.
              Positioned.fill(
                child: SafeArea(
                  minimum: EdgeInsets.only(bottom: portraitMode ? 64 : 26),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: portraitMode ? 40 : 90,
                        right: portraitMode ? 40 : 90,
                        bottom: portraitMode ? 64 : 26,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _loadingLabel(),
                          const SizedBox(height: 14),
                          _progressCapsule(),
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

  Widget _loadingLabel() {
    final dots = '.' * (_dotFrame + 1);
    return Text(
      'Loading$dots',
      style: TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _progressCapsule() {
    return AnimatedBuilder(
      animation: _barCtrl,
      builder: (context, _) {
        final value = _barCtrl.value.clamp(0.0, 1.0);
        return Container(
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value,
                heightFactor: 1,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFFF176),
                        Color(0xFFFFB300),
                        Color(0xFFFF6F00),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
