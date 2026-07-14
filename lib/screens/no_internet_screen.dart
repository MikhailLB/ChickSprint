import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'menu_screen.dart';

class NoInternetScreen extends StatefulWidget {
  const NoInternetScreen({super.key});

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen> {
  bool _checking = false;

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    final results = await Connectivity().checkConnectivity();
    final hasConnection = results.any((r) => r != ConnectivityResult.none);
    if (!mounted) return;
    setState(() => _checking = false);
    if (hasConnection) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MenuScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isPortrait = constraints.maxHeight >= constraints.maxWidth;
          final asset = isPortrait
              ? 'assets/Vertical_Nowifi_Screen.webp'
              : 'assets/Horizontal_Nowifi_Screen.webp';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(asset, fit: BoxFit.cover),
              Positioned(
                left: 0,
                right: 0,
                bottom: isPortrait ? 40 : 24,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: _RetryButton(
                      loading: _checking,
                      onPressed: _retry,
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

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFC107),
          foregroundColor: const Color(0xFF3E2723),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
            side: const BorderSide(color: Colors.white, width: 3),
          ),
          elevation: 8,
        ),
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF3E2723),
                ),
              )
            : const Text(
                'TRY AGAIN',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
      ),
    );
  }
}
