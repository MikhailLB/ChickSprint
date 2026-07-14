import 'dart:math';

enum CellKind { safe, coin, fire }

enum PlatformStyle { grass, stone, crate }

class LevelCell {
  LevelCell({
    required this.kind,
    required this.platform,
  });

  final CellKind kind;
  final PlatformStyle platform;
  bool collectedCoin = false;
}

class Level {
  Level({
    required this.number,
    required this.rows,
    required this.cols,
    required this.grid,
    required this.startRow,
    required this.startCol,
    required this.endRow,
    required this.endCol,
    required this.memorizeSeconds,
    required this.totalCoins,
  });

  final int number;
  final int rows;
  final int cols;
  final List<List<LevelCell>> grid;
  final int startRow;
  final int startCol;
  final int endRow;
  final int endCol;
  final int memorizeSeconds;
  final int totalCoins;
}

/// Procedurally generates a level with a guaranteed safe path from the top
/// row (start) to the bottom row (end). Cells off the safe path may be coins,
/// fire, or plain safe tiles. Path cells never contain fire.
class LevelGenerator {
  LevelGenerator({int? seed}) : _random = Random(seed);

  final Random _random;

  Level generate(int levelNumber) {
    // Difficulty scaling.
    final int cols = 3 + min<int>(levelNumber ~/ 4, 2); // 3..5
    final int rows = 4 + min<int>(levelNumber ~/ 3, 4); // 4..8
    final int memorize = max<int>(2, 5 - (levelNumber ~/ 3));
    final double fireRatio = min<double>(0.35, 0.12 + levelNumber * 0.02);
    const double coinRatio = 0.22;

    final startCol = _random.nextInt(cols);
    final endCol = _random.nextInt(cols);

    // Generate a safe path using a simple down-and-drift random walk.
    final pathCells = <Point<int>>{};
    int currentCol = startCol;
    for (int r = 0; r < rows; r++) {
      pathCells.add(Point(currentCol, r));
      if (r == rows - 1) break;
      // Move towards endCol with some randomness.
      final choices = <int>[];
      if (currentCol > 0) choices.add(currentCol - 1);
      choices.add(currentCol);
      if (currentCol < cols - 1) choices.add(currentCol + 1);

      // Bias towards endCol as we approach the bottom.
      final biasStrength = (r / rows);
      choices.sort((a, b) {
        final da = (a - endCol).abs();
        final db = (b - endCol).abs();
        final diff = da - db;
        // Add noise to prevent perfectly deterministic path.
        return diff + (_random.nextDouble() < biasStrength ? 0 : _random.nextInt(3) - 1);
      });
      currentCol = choices.first;
    }
    // Ensure end column is included on the last row.
    pathCells.removeWhere((p) => p.y == rows - 1);
    pathCells.add(Point(endCol, rows - 1));

    // Fill grid.
    int coinsPlaced = 0;
    final grid = List.generate(rows, (r) {
      return List.generate(cols, (c) {
        final onPath = pathCells.contains(Point(c, r));
        CellKind kind;
        if (onPath) {
          // Path cells are safe, but may host a coin (rare).
          if (_random.nextDouble() < 0.25) {
            kind = CellKind.coin;
            coinsPlaced++;
          } else {
            kind = CellKind.safe;
          }
        } else {
          final roll = _random.nextDouble();
          if (roll < fireRatio) {
            kind = CellKind.fire;
          } else if (roll < fireRatio + coinRatio) {
            kind = CellKind.coin;
            coinsPlaced++;
          } else {
            kind = CellKind.safe;
          }
        }

        final platformChoice = _random.nextDouble();
        final platform = platformChoice < 0.72
            ? PlatformStyle.grass
            : (platformChoice < 0.88
                ? PlatformStyle.stone
                : PlatformStyle.crate);

        return LevelCell(kind: kind, platform: platform);
      });
    });

    // Ensure start cell is safe (no fire, no coin), end cell may be nest-like.
    grid[0][startCol] = LevelCell(
      kind: CellKind.safe,
      platform: PlatformStyle.grass,
    );
    grid[rows - 1][endCol] = LevelCell(
      kind: CellKind.safe,
      platform: PlatformStyle.grass,
    );

    return Level(
      number: levelNumber,
      rows: rows,
      cols: cols,
      grid: grid,
      startRow: 0,
      startCol: startCol,
      endRow: rows - 1,
      endCol: endCol,
      memorizeSeconds: memorize,
      totalCoins: coinsPlaced,
    );
  }
}
