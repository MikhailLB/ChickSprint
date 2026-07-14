import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/level.dart';

enum _Phase { memorize, play, reveal, success, failure }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  final _generator = LevelGenerator();

  late Level _level;
  late _Phase _phase;

  int _levelNumber = 1;
  int _score = 0;
  int _coins = 0;
  int _bestScore = 0;
  int _streak = 0;
  int _bestStreak = 0;

  int _memorizeRemaining = 0;
  Timer? _memorizeTimer;

  // Player state.
  int _chickRow = 0;
  int _chickCol = 0;
  final List<Point<int>> _visited = [];

  bool _moving = false;

  @override
  void initState() {
    super.initState();
    _loadStats().then((_) => _startLevel());
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bestScore = prefs.getInt('best_score') ?? 0;
      _bestStreak = prefs.getInt('best_streak') ?? 0;
      _coins = prefs.getInt('total_coins') ?? 0;
    });
  }

  Future<void> _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('best_score', _bestScore);
    await prefs.setInt('best_streak', _bestStreak);
    await prefs.setInt('total_coins', _coins);
  }

  void _startLevel() {
    _level = _generator.generate(_levelNumber);
    _chickRow = _level.startRow;
    _chickCol = _level.startCol;
    _visited
      ..clear()
      ..add(Point(_chickCol, _chickRow));
    _phase = _Phase.memorize;
    _memorizeRemaining = _level.memorizeSeconds;
    setState(() {});
    _memorizeTimer?.cancel();
    _memorizeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _memorizeRemaining--;
      });
      if (_memorizeRemaining <= 0) {
        t.cancel();
        setState(() => _phase = _Phase.play);
      }
    });
  }

  bool _isAdjacent(int r, int c) {
    final dr = (r - _chickRow).abs();
    final dc = (c - _chickCol).abs();
    return (dr == 1 && dc == 0) || (dr == 0 && dc == 1);
  }

  Future<void> _onTapCell(int r, int c) async {
    if (_phase != _Phase.play || _moving) return;
    if (!_isAdjacent(r, c)) return;

    _moving = true;
    HapticFeedback.selectionClick();

    setState(() {
      _chickRow = r;
      _chickCol = c;
      _visited.add(Point(c, r));
    });

    await Future<void>.delayed(const Duration(milliseconds: 220));

    final cell = _level.grid[r][c];
    if (cell.kind == CellKind.fire) {
      HapticFeedback.heavyImpact();
      _endLevel(success: false);
      _moving = false;
      return;
    }

    if (cell.kind == CellKind.coin && !cell.collectedCoin) {
      setState(() {
        cell.collectedCoin = true;
        _coins++;
        _score += 15;
      });
    }

    if (r == _level.endRow && c == _level.endCol) {
      _endLevel(success: true);
    }
    _moving = false;
  }

  void _endLevel({required bool success}) {
    if (success) {
      final pathBonus = max(0, 200 - _visited.length * 5);
      setState(() {
        _score += 100 + pathBonus;
        _streak++;
        _bestStreak = max(_bestStreak, _streak);
        _bestScore = max(_bestScore, _score);
        _phase = _Phase.success;
      });
    } else {
      setState(() {
        _streak = 0;
        _phase = _Phase.reveal;
      });
    }
    _saveStats();
  }

  void _nextLevel() {
    setState(() {
      _levelNumber++;
    });
    _startLevel();
  }

  void _retryLevel() {
    _startLevel();
  }

  @override
  void dispose() {
    _memorizeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/bg1_asset.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              const SizedBox(height: 6),
              _buildStatusStrip(),
              const SizedBox(height: 8),
              Expanded(child: _buildBoard()),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _RoundIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          _StatChip(
            icon: Icons.emoji_events_rounded,
            iconColor: const Color(0xFFFFB300),
            label: 'BEST',
            value: '$_bestScore',
          ),
          const SizedBox(width: 8),
          _StatChip(
            icon: Icons.stars_rounded,
            iconColor: const Color(0xFFFF6F00),
            label: 'SCORE',
            value: '$_score',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStrip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _StatChip(
            icon: Icons.grid_view_rounded,
            iconColor: const Color(0xFF43A047),
            label: 'LEVEL',
            value: '$_levelNumber',
          ),
          const SizedBox(width: 8),
          _CoinChip(coins: _coins),
          const Spacer(),
          _StatChip(
            icon: Icons.local_fire_department_rounded,
            iconColor: const Color(0xFFE53935),
            label: 'STREAK',
            value: '$_streak / $_bestStreak',
          ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight;
          final cellSize = min(
            maxW / _level.cols,
            maxH / _level.rows,
          );
          final boardW = cellSize * _level.cols;
          final boardH = cellSize * _level.rows;

          final showAll = _phase == _Phase.memorize ||
              _phase == _Phase.reveal ||
              _phase == _Phase.success;

          return Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: boardW + 24,
                  height: boardH + 24,
                  decoration: BoxDecoration(
                    color: Colors.brown.shade900.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.brown.shade200.withValues(alpha: 0.6),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: boardW,
                  height: boardH,
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _level.cols,
                    ),
                    itemCount: _level.rows * _level.cols,
                    itemBuilder: (context, index) {
                      final r = index ~/ _level.cols;
                      final c = index % _level.cols;
                      return _buildCell(r, c, cellSize, showAll);
                    },
                  ),
                ),
                if (_phase == _Phase.memorize)
                  Positioned(
                    top: 0,
                    child: _MemorizeBadge(seconds: _memorizeRemaining),
                  ),
                if (_phase == _Phase.success ||
                    _phase == _Phase.reveal)
                  Positioned.fill(
                    child: _EndOverlay(
                      success: _phase == _Phase.success,
                      onNext: _nextLevel,
                      onRetry: _retryLevel,
                      score: _score,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCell(int r, int c, double size, bool showAll) {
    final cell = _level.grid[r][c];
    final isChick = _chickRow == r && _chickCol == c;
    final isStart = r == _level.startRow && c == _level.startCol;
    final isEnd = r == _level.endRow && c == _level.endCol;
    final visited = _visited.contains(Point(c, r));

    final platformAsset = _platformAsset(cell.platform);

    return GestureDetector(
      onTap: () => _onTapCell(r, c),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Platform base.
            Positioned.fill(
              child: Image.asset(
                platformAsset,
                fit: BoxFit.fill,
              ),
            ),
            if (visited && !isChick)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            // Nest / end marker
            if (isEnd)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(size * 0.10),
                  child: Image.asset(
                    'assets/straw_nest_strict_asset.webp',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            // Content (coin / fire) — hidden while playing unless revealed.
            if (showAll)
              _buildCellContent(cell, size)
            else if (cell.kind == CellKind.coin && cell.collectedCoin)
              const SizedBox.shrink()
            else
              const SizedBox.shrink(),
            // Egg on start cell.
            if (isStart && !isChick)
              Padding(
                padding: EdgeInsets.all(size * 0.18),
                child: Image.asset(
                  'assets/egg_asset.webp',
                  fit: BoxFit.contain,
                ),
              ),
            if (isChick)
              _AnimatedChick(size: size * 0.72),
            // Highlight adjacent tappable cells during play.
            if (_phase == _Phase.play && !isChick && _isAdjacent(r, c))
              IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCellContent(LevelCell cell, double size) {
    switch (cell.kind) {
      case CellKind.coin:
        if (cell.collectedCoin) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.all(size * 0.18),
          child: Image.asset(
            'assets/coin_asset.webp',
            fit: BoxFit.contain,
          ),
        );
      case CellKind.fire:
        return Padding(
          padding: EdgeInsets.all(size * 0.14),
          child: Image.asset(
            'assets/fire_asset.webp',
            fit: BoxFit.contain,
          ),
        );
      case CellKind.safe:
        return const SizedBox.shrink();
    }
  }

  String _platformAsset(PlatformStyle p) {
    switch (p) {
      case PlatformStyle.grass:
        return 'assets/dree_platform_asset.webp';
      case PlatformStyle.stone:
        return 'assets/stone_platform_asset.webp';
      case PlatformStyle.crate:
        return 'assets/small_wooden_crate_asset.webp';
    }
  }

  Widget _buildBottomBar() {
    String hint;
    switch (_phase) {
      case _Phase.memorize:
        hint = 'Memorize the safe path!';
        break;
      case _Phase.play:
        hint = 'Tap an adjacent tile to move';
        break;
      case _Phase.reveal:
        hint = 'You stepped on fire!';
        break;
      case _Phase.success:
        hint = 'Level complete!';
        break;
      case _Phase.failure:
        hint = 'Try again';
        break;
    }
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          if (_phase == _Phase.play)
            TextButton.icon(
              onPressed: _startLevel,
              icon: const Icon(
                Icons.refresh_rounded,
                color: Colors.white,
              ),
              label: const Text(
                'RESET',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoinChip extends StatelessWidget {
  const _CoinChip({required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/coin_asset.webp',
            width: 22,
            height: 22,
          ),
          const SizedBox(width: 6),
          Text(
            '$coins',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white54, width: 1.5),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _MemorizeBadge extends StatelessWidget {
  const _MemorizeBadge({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              'MEMORIZE  $seconds',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedChick extends StatefulWidget {
  const _AnimatedChick({required this.size});
  final double size;

  @override
  State<_AnimatedChick> createState() => _AnimatedChickState();
}

class _AnimatedChickState extends State<_AnimatedChick>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, -4 * t),
          child: Transform.scale(
            scale: 1.0 + 0.04 * t,
            child: Image.asset(
              'assets/chicken_asset.webp',
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
            ),
          ),
        );
      },
    );
  }
}

class _EndOverlay extends StatelessWidget {
  const _EndOverlay({
    required this.success,
    required this.onNext,
    required this.onRetry,
    required this.score,
  });

  final bool success;
  final int score;
  final VoidCallback onNext;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: success ? const Color(0xFFFFF8E1) : const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: success ? const Color(0xFFFFC107) : const Color(0xFFE53935),
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              success
                  ? Icons.emoji_events_rounded
                  : Icons.local_fire_department_rounded,
              color: success
                  ? const Color(0xFFFFB300)
                  : const Color(0xFFE53935),
              size: 56,
            ),
            const SizedBox(height: 8),
            Text(
              success ? 'LEVEL COMPLETE!' : 'GAME OVER',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: success
                    ? const Color(0xFF3E2723)
                    : const Color(0xFFB71C1C),
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              success
                  ? 'Score: $score'
                  : 'The chick stepped on fire!',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3E2723),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: success ? onNext : onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      success ? const Color(0xFF43A047) : const Color(0xFFFFC107),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.white, width: 2),
                  ),
                  elevation: 4,
                ),
                child: Text(
                  success ? 'NEXT LEVEL' : 'TRY AGAIN',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
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
