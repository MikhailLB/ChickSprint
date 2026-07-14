import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_screen.dart';
import 'web_page_screen.dart';

const _privacyUrl = 'https://chicksprint.com/privacy-policy.html';
const _supportUrl = 'https://chicksprint.com/support.html';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  int _bestScore = 0;
  int _totalCoins = 0;
  int _bestStreak = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bestScore = prefs.getInt('best_score') ?? 0;
      _totalCoins = prefs.getInt('total_coins') ?? 0;
      _bestStreak = prefs.getInt('best_streak') ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/bg2_asset.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildLogo(),
              const SizedBox(height: 12),
              _buildStatsPanel(),
              const Spacer(),
              _buildMenuButtons(context),
              const SizedBox(height: 12),
              _buildFooterLinks(context),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Image.asset(
        'assets/Game_Name.webp',
        fit: BoxFit.contain,
        height: 190,
      ),
    );
  }

  Widget _buildStatsPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatBlock(
              label: 'BEST SCORE',
              value: '$_bestScore',
              icon: Icons.emoji_events_rounded,
              iconColor: Color(0xFFFFC107),
            ),
          ),
          _divider(),
          Expanded(
            child: _StatBlock(
              label: 'COINS',
              value: '$_totalCoins',
              iconAsset: 'assets/coin_asset.webp',
            ),
          ),
          _divider(),
          Expanded(
            child: _StatBlock(
              label: 'STREAK',
              value: '$_bestStreak',
              icon: Icons.local_fire_department_rounded,
              iconColor: Color(0xFFFF7043),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        color: Colors.white.withValues(alpha: 0.25),
        margin: const EdgeInsets.symmetric(horizontal: 6),
      );

  Widget _buildMenuButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          _MenuButton(
            label: 'PLAY',
            icon: Icons.play_arrow_rounded,
            primary: true,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GameScreen()),
              );
              _loadStats();
            },
          ),
          const SizedBox(height: 12),
          _MenuButton(
            label: 'HOW TO PLAY',
            icon: Icons.help_outline_rounded,
            onPressed: () => _showHowToPlay(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLinks(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Expanded(
            child: _FooterButton(
              label: 'Privacy Policy',
              icon: Icons.privacy_tip_outlined,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WebPageScreen(
                      title: 'Privacy Policy',
                      url: _privacyUrl,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FooterButton(
              label: 'Support',
              icon: Icons.support_agent_rounded,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WebPageScreen(
                      title: 'Support',
                      url: _supportUrl,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showHowToPlay(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        backgroundColor: const Color(0xFFFFF8E1),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.lightbulb_rounded,
                    color: Color(0xFFFFB300),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'HOW TO PLAY',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF3E2723),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '1. Memorize the coins, safe tiles and fire.\n'
                '2. When the board hides, tap adjacent tiles to move the chick.\n'
                '3. Collect coins on the way and reach the nest at the bottom.\n'
                '4. Avoid fire — one step ends the level!',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3E2723),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: const Color(0xFF3E2723),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'GOT IT!',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.iconAsset,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconAsset != null)
          Image.asset(iconAsset!, width: 26, height: 26)
        else
          Icon(icon, color: iconColor ?? Colors.white, size: 26),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? const Color(0xFFFFC107) : Colors.white;
    final fg = const Color(0xFF3E2723);
    return SizedBox(
      width: double.infinity,
      height: primary ? 64 : 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: primary ? 30 : 24, color: fg),
        label: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: primary ? 22 : 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(
              color: primary ? Colors.white : const Color(0xFFFFC107),
              width: 3,
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.45),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}
