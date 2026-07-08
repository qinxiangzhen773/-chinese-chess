import 'package:flutter/material.dart';
import 'package:chinese_chess/game/chess_game.dart';
import 'package:chinese_chess/ui/chess_board.dart';

void main() {
  runApp(const ChineseChessApp());
}

class ChineseChessApp extends StatelessWidget {
  const ChineseChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '中国象棋',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.brown,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ChessHomePage(),
    );
  }
}

class ChessHomePage extends StatefulWidget {
  const ChessHomePage({super.key});

  @override
  State<ChessHomePage> createState() => _ChessHomePageState();
}

class _ChessHomePageState extends State<ChessHomePage> {
  late ChessGame _game;
  int? _selectedPiece;
  List<int> _legalMoves = [];
  bool _isAIThinking = false;
  final List<String> _displayMoveHistory = [];
  String _nnueStatus = '正在初始化 AI...';

  @override
  void initState() {
    super.initState();
    _game = ChessGame();
    _game.onNNUEStatus = (msg) {
      if (mounted) setState(() => _nnueStatus = msg);
    };
  }

  @override
  void dispose() {
    _game.dispose();
    super.dispose();
  }

  void _onPieceTapped(int index) {
    if (_isAIThinking) return;
    if (_game.gameStatus != GameStatus.ongoing) return;

    final piece = _game.getPieceAt(index);

    if (_selectedPiece == null) {
      // 选择棋子
      if (piece != null) {
        final isRedPiece = piece > 0;
        if (_game.currentTurn == 1 && isRedPiece) {
          setState(() {
            _selectedPiece = index;
            _legalMoves = _game.getLegalMoves(index);
          });
        }
      }
    } else {
      // 已选中棋子，尝试走棋
      if (_selectedPiece == index) {
        // 取消选中
        setState(() {
          _selectedPiece = null;
          _legalMoves = [];
        });
      } else if (_legalMoves.contains(index)) {
        // 走到合法位置
        final success = _game.move(_selectedPiece!, index);
        if (success) {
          setState(() {
            _selectedPiece = null;
            _legalMoves = [];
            _isAIThinking = true;
            _updateDisplayHistory();
          });
          _aiMove();
        }
      } else if (piece != null) {
        // 点击了另一个己方棋子，切换选中
        final isRedPiece = piece > 0;
        if (_game.currentTurn == 1 && isRedPiece) {
          setState(() {
            _selectedPiece = index;
            _legalMoves = _game.getLegalMoves(index);
          });
        }
      }
    }
  }

  Future<void> _aiMove() async {
    // 检查游戏是否已结束
    if (_game.gameStatus != GameStatus.ongoing) {
      setState(() {
        _isAIThinking = false;
      });
      _showGameResult();
      return;
    }

    await Future.delayed(const Duration(milliseconds: 400));

    final move = await _game.getAIMove();
    if (move.isNotEmpty && _game.gameStatus == GameStatus.ongoing) {
      setState(() {
        _game.applyAIMove(move);
        _isAIThinking = false;
        _updateDisplayHistory();
      });

      // 检查AI走后游戏是否结束
      if (_game.gameStatus != GameStatus.ongoing) {
        _showGameResult();
      }

      // 检查是否将军
      if (_game.isInCheck()) {
        _showCheckDialog();
      }
    } else {
      setState(() {
        _isAIThinking = false;
      });
      if (_game.gameStatus != GameStatus.ongoing) {
        _showGameResult();
      }
    }
  }

  void _updateDisplayHistory() {
    _displayMoveHistory.clear();
    for (int i = 0; i < _game.moveHistory.length; i++) {
      final turnLabel = i.isEven ? '红' : '黑';
      _displayMoveHistory.add('$turnLabel: ${_game.moveHistory[i]}');
    }
  }

  void _undo() {
    if (_isAIThinking) return;
    if (_game.undo()) {
      setState(() {
        _selectedPiece = null;
        _legalMoves = [];
        _updateDisplayHistory();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法悔棋')),
      );
    }
  }

  void _resetGame() {
    if (_isAIThinking) return;
    setState(() {
      _game.reset();
      _selectedPiece = null;
      _legalMoves = [];
      _isAIThinking = false;
      _displayMoveHistory.clear();
    });
  }

  void _showGameResult() {
    String message;
    switch (_game.gameStatus) {
      case GameStatus.redWins:
        message = '红方胜利！恭喜你赢了！';
        break;
      case GameStatus.blackWins:
        message = '黑方胜利！AI 获胜！';
        break;
      case GameStatus.draw:
        message = '和棋！';
        break;
      default:
        return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('游戏结束'),
        content: Text(message, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _resetGame();
            },
            child: const Text('再来一局'),
          ),
        ],
      ),
    );
  }

  void _showCheckDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('将军！', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        duration: Duration(seconds: 1),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showDifficultyDialog() {
    if (_isAIThinking) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('难度设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDifficultyOption(ctx, '入门', 1),
            _buildDifficultyOption(ctx, '初级', 3),
            _buildDifficultyOption(ctx, '中级', 5),
            _buildDifficultyOption(ctx, '高级', 8),
            _buildDifficultyOption(ctx, '大师', 12),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyOption(BuildContext ctx, String label, int depth) {
    final isSelected = _game.aiDepth == depth;
    return ListTile(
      title: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () {
        setState(() {
          _game.aiDepth = depth;
        });
        Navigator.of(ctx).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _game.getGameStatusText();
    final isCheck = _game.isInCheck() && _game.gameStatus == GameStatus.ongoing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('中国象棋'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '难度设置',
            onPressed: _showDifficultyDialog,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '棋谱',
            onPressed: _showMoveHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 游戏状态栏
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: isCheck ? Colors.red.shade100 : Colors.brown.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isAIThinking)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (_isAIThinking) const SizedBox(width: 8),
                  Text(
                    _isAIThinking ? 'AI 思考中...' : statusText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isCheck ? Colors.red : Colors.brown.shade800,
                    ),
                  ),
                ],
              ),
            ),

            // 棋盘
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ChessBoard(
                  board: _game.board,
                  selectedPiece: _selectedPiece,
                  legalMoves: _legalMoves,
                  lastMoveUci: _game.lastMoveUci,
                  onPieceTapped: _onPieceTapped,
                ),
              ),
            ),

            // NNUE 状态指示器
            if (!_game.nnueLoaded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                color: Colors.orange.shade50,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _nnueStatus,
                        style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // 操作按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _resetGame,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新开始'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _game.canUndo() && !_isAIThinking ? _undo : null,
                    icon: const Icon(Icons.undo),
                    label: const Text('悔棋'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoveHistory() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('棋谱', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            if (_displayMoveHistory.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('暂无走棋记录', style: TextStyle(color: Colors.grey))),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: (_displayMoveHistory.length / 2).ceil(),
                  itemBuilder: (context, index) {
                    final redIdx = index * 2;
                    final blackIdx = redIdx + 1;
                    final redMove = redIdx < _displayMoveHistory.length
                        ? _displayMoveHistory[redIdx]
                        : '';
                    final blackMove = blackIdx < _displayMoveHistory.length
                        ? _displayMoveHistory[blackIdx]
                        : '';
                    return ListTile(
                      dense: true,
                      leading: Text('${index + 1}.', style: const TextStyle(fontWeight: FontWeight.bold)),
                      title: Row(
                        children: [
                          Expanded(child: Text(redMove, style: const TextStyle(color: Colors.red))),
                          Expanded(child: Text(blackMove, style: const TextStyle(color: Colors.black))),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
