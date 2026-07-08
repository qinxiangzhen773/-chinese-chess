import 'package:flutter/material.dart';

class ChessBoard extends StatelessWidget {
  final List<int?> board;
  final int? selectedPiece;
  final List<int> legalMoves;
  final String? lastMoveUci;
  final Function(int) onPieceTapped;

  const ChessBoard({
    super.key,
    required this.board,
    this.selectedPiece,
    this.legalMoves = const [],
    this.lastMoveUci,
    required this.onPieceTapped,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        // 棋盘是 9 列 x 10 行
        final cellSizeW = maxWidth / 9;
        final cellSizeH = maxHeight / 10;
        final cellSize = cellSizeW < cellSizeH ? cellSizeW : cellSizeH;
        final boardWidth = cellSize * 9;
        final boardHeight = cellSize * 10;

        return Center(
          child: Container(
            width: boardWidth,
            height: boardHeight,
            decoration: BoxDecoration(
              color: const Color(0xFFDEB887),
              border: Border.all(color: const Color(0xFF8B4513), width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              children: [
                _buildGrid(cellSize),
                _buildMoveHighlights(cellSize),
                _buildLastMoveHighlight(cellSize),
                _buildPieces(cellSize),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid(double cellSize) {
    return CustomPaint(
      painter: _ChessGridPainter(cellSize: cellSize),
    );
  }

  Widget _buildMoveHighlights(double cellSize) {
    final highlights = <Widget>[];
    for (final targetIndex in legalMoves) {
      final x = targetIndex % 9;
      final y = targetIndex ~/ 9;
      final isCapture = board[targetIndex] != null;

      highlights.add(
        Positioned(
          left: x * cellSize,
          top: y * cellSize,
          width: cellSize,
          height: cellSize,
          child: Center(
            child: isCapture
                ? Container(
                    width: cellSize * 0.85,
                    height: cellSize * 0.85,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red.withAlpha(180), width: 3),
                    ),
                  )
                : Container(
                    width: cellSize * 0.3,
                    height: cellSize * 0.3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green.withAlpha(120),
                    ),
                  ),
          ),
        ),
      );
    }
    return Stack(children: highlights);
  }

  Widget _buildLastMoveHighlight(double cellSize) {
    if (lastMoveUci == null || lastMoveUci!.length < 4) return const SizedBox.shrink();
    try {
      const files = 'abcdefghi';
      final fromFile = files.indexOf(lastMoveUci![0]);
      final fromRank = 10 - int.parse(lastMoveUci![1]);
      final toFile = files.indexOf(lastMoveUci![2]);
      final toRank = 10 - int.parse(lastMoveUci![3]);
      if (fromFile < 0 || toFile < 0) return const SizedBox.shrink();

      final fromX = fromFile;
      final fromY = fromRank;
      final toX = toFile;
      final toY = toRank;

      return Stack(
        children: [
          Positioned(
            left: fromX * cellSize,
            top: fromY * cellSize,
            width: cellSize,
            height: cellSize,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.yellow.withAlpha(80),
                ),
              ),
            ),
          ),
          Positioned(
            left: toX * cellSize,
            top: toY * cellSize,
            width: cellSize,
            height: cellSize,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.yellow.withAlpha(120),
                ),
              ),
            ),
          ),
        ],
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildPieces(double cellSize) {
    return Stack(
      children: board.asMap().entries.map((entry) {
        final index = entry.key;
        final piece = entry.value;
        if (piece == null) return const SizedBox.shrink();

        final x = index % 9;
        final y = index ~/ 9;
        final isSelected = selectedPiece == index;

        return Positioned(
          left: x * cellSize + cellSize * 0.1,
          top: y * cellSize + cellSize * 0.1,
          width: cellSize * 0.8,
          height: cellSize * 0.8,
          child: GestureDetector(
            onTap: () => onPieceTapped(index),
            child: _PieceWidget(
              piece: piece,
              isSelected: isSelected,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChessGridPainter extends CustomPainter {
  final double cellSize;

  _ChessGridPainter({required this.cellSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5D4037)
      ..strokeWidth = 1;

    // 垂直线（共 9 条）
    for (int i = 0; i <= 8; i++) {
      // 第一条和最后一条画通栏
      if (i == 0 || i == 8) {
        canvas.drawLine(
          Offset(i * cellSize, 0),
          Offset(i * cellSize, 9 * cellSize),
          paint,
        );
      } else {
        // 中间线在楚河汉界处断开
        canvas.drawLine(
          Offset(i * cellSize, 0),
          Offset(i * cellSize, 4 * cellSize),
          paint,
        );
        canvas.drawLine(
          Offset(i * cellSize, 5 * cellSize),
          Offset(i * cellSize, 9 * cellSize),
          paint,
        );
      }
    }

    // 水平线（共 10 条）
    for (int i = 0; i <= 9; i++) {
      canvas.drawLine(
        Offset(0, i * cellSize),
        Offset(8 * cellSize, i * cellSize),
        paint,
      );
    }

    _drawPalaces(canvas, paint);
    _drawRiver(canvas, paint);
    _drawCrossMarks(canvas, paint);
  }

  void _drawPalaces(Canvas canvas, Paint paint) {
    paint.strokeWidth = 1.5;

    // 上方九宫（黑方）
    canvas.drawLine(
      Offset(3 * cellSize, 0 * cellSize),
      Offset(5 * cellSize, 2 * cellSize),
      paint,
    );
    canvas.drawLine(
      Offset(5 * cellSize, 0 * cellSize),
      Offset(3 * cellSize, 2 * cellSize),
      paint,
    );

    // 下方九宫（红方）
    canvas.drawLine(
      Offset(3 * cellSize, 7 * cellSize),
      Offset(5 * cellSize, 9 * cellSize),
      paint,
    );
    canvas.drawLine(
      Offset(5 * cellSize, 7 * cellSize),
      Offset(3 * cellSize, 9 * cellSize),
      paint,
    );

    paint.strokeWidth = 1;
  }

  void _drawRiver(Canvas canvas, Paint paint) {
    // 楚河汉界标签
    final textStyle = TextStyle(
      color: const Color(0xFF5D4037),
      fontSize: cellSize * 0.35,
      fontWeight: FontWeight.bold,
    );

    final chuSpan = TextSpan(text: '楚  河', style: textStyle);
    final hanSpan = TextSpan(text: '汉  界', style: textStyle);

    final chuPainter = TextPainter(
      text: chuSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    chuPainter.paint(
      canvas,
      Offset(1.5 * cellSize, 4.35 * cellSize),
    );

    final hanPainter = TextPainter(
      text: hanSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    hanPainter.paint(
      canvas,
      Offset(5.2 * cellSize, 4.35 * cellSize),
    );
  }

  void _drawCrossMarks(Canvas canvas, Paint paint) {
    // 炮和兵/卒的站位标记
    const crossPositions = [
      // 黑方阵地
      (1, 2), (7, 2),  // 炮位
      (0, 3), (2, 3), (4, 3), (6, 3), (8, 3),  // 兵位
      // 红方阵地
      (1, 7), (7, 7),  // 炮位
      (0, 6), (2, 6), (4, 6), (6, 6), (8, 6),  // 兵位
    ];

    final smallSize = cellSize * 0.08;
    final gap = cellSize * 0.12;

    for (final (col, row) in crossPositions) {
      final cx = col * cellSize + cellSize / 2;
      final cy = row * cellSize + cellSize / 2;

      // 四个角落的小标记
      if (col > 0) {
        _drawCornerMark(canvas, paint, cx - gap, cy - gap, smallSize, false);
        _drawCornerMark(canvas, paint, cx - gap, cy + gap, smallSize, true);
      }
      if (col < 8) {
        _drawCornerMark(canvas, paint, cx + gap, cy - gap, smallSize, false);
        _drawCornerMark(canvas, paint, cx + gap, cy + gap, smallSize, true);
      }
    }
  }

  void _drawCornerMark(Canvas canvas, Paint paint, double x, double y, double size, bool flipY) {
    final path = Path();
    if (flipY) {
      path.moveTo(x, y - size);
      path.lineTo(x, y);
      path.lineTo(x + size, y);
    } else {
      path.moveTo(x, y + size);
      path.lineTo(x, y);
      path.lineTo(x + size, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChessGridPainter oldDelegate) {
    return oldDelegate.cellSize != cellSize;
  }
}

class _PieceWidget extends StatelessWidget {
  final int piece;
  final bool isSelected;

  const _PieceWidget({
    required this.piece,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isRed = piece > 0;
    final bgColor = isRed ? const Color(0xFFFFF8E7) : const Color(0xFF2C2C2C);
    final textColor = isRed ? const Color(0xFFCC0000) : Colors.white;
    final borderColor = isSelected
        ? const Color(0xFF2196F3)
        : const Color(0xFF8D6E63);
    final pieceName = _getPieceName(piece.abs());

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor,
          width: isSelected ? 3 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected ? Colors.blue.withAlpha(100) : Colors.black.withAlpha(50),
            blurRadius: isSelected ? 6 : 2,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          pieceName,
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _getPieceName(int type) {
    switch (type) {
      case 1: return '帅';
      case 2: return '仕';
      case 3: return '相';
      case 4: return '車';
      case 5: return '馬';
      case 6: return '炮';
      case 7: return '兵';
      default: return '';
    }
  }
}
