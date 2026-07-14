import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_screen.dart';
import 'no_internet_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _progressController;
  late final AnimationController _dotsController;
  Timer? _dotsTimer;
  int _dotsCount = 1;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _dotsTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted) return;
      setState(() {
        _dotsCount = (_dotsCount % 3) + 1;
      });
    });

    _startLoading();
  }

  Future<void> _startLoading() async {
    // Simulated warm-up progress with slight staggering so it feels alive.
    _progressController.animateTo(
      0.35,
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
    );

    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    _progressController.animateTo(
      0.72,
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOutCubic,
    );

    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;

    // Final fill – "полностью ТОЛЬКО в момент перед непосредственным запуском".
    _progressController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeInOut,
    );
    await Future<void>.delayed(const Duration(milliseconds: 620));
    if (!mounted) return;

    await _navigateNext();
  }

  Future<void> _navigateNext() async {
    if (_isNavigating) return;
    _isNavigating = true;

    // Check connectivity before entering menu.
    final results = await Connectivity().checkConnectivity();
    final hasConnection = results.any((r) => r != ConnectivityResult.none);

    if (!mounted) return;

    // Lock game orientation to portrait for the rest of the app.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) =>
            hasConnection ? const MenuScreen() : const NoInternetScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _dotsTimer?.cancel();
    _progressController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF6BAF3B),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isPortrait = constraints.maxHeight >= constraints.maxWidth;
          final backgroundAsset = isPortrait
              ? 'assets/Vertical_Loading_Screen.webp'
              : 'assets/Horizontal_Loading_Screen.webp';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(backgroundAsset, fit: BoxFit.cover),
              // Bottom gradient so text/progress reads well.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.35),
                      ],
                      stops: const [0.55, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: isPortrait ? 60 : 30,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isPortrait ? 36 : 80,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLoadingText(),
                        const SizedBox(height: 14),
                        _buildProgressBar(),
                      ],
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

  Widget _buildLoadingText() {
    final dots = '.' * _dotsCount;
    return Text(
      'Loading$dots',
      style: TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return AnimatedBuilder(
      animation: _progressController,
      builder: (context, _) {
        final value = _progressController.value.clamp(0.0, 1.0);
        return Container(
          height: 22,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFFFFEB3B),
                        Color(0xFFFFA726),
                        Color(0xFFFFD54F),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFFFFC107,
                        ).withValues(alpha: 0.7),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
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
