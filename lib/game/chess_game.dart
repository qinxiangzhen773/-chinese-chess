import 'dart:ffi';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// 游戏状态枚举
enum GameStatus { ongoing, redWins, blackWins, draw }

class ChessGame {
  // ── FFI 函数指针 ──
  late final DynamicLibrary _engine;
  late final void Function() _initEngine;
  late final void Function() _newGame;
  late final Pointer<Utf8> Function() _getBoard;
  late final void Function(Pointer<Utf8>) _makeMove;
  late final Pointer<Utf8> Function(int) _getBestMove;
  late final void Function() _freeMemory;
  late final int Function() _undoMove;
  late final int Function(Pointer<Utf8>) _isMoveLegal;
  late final int Function() _getGameStatus;
  late final int Function() _isInCheck;
  late final void Function(Pointer<Utf8>) _loadNnue;
  late final Pointer<Utf8> Function() _getLastMove;
  late final int Function() _getMoveHistoryCount;

  // ── 游戏状态 ──
  List<int?> board = List<int?>.filled(90, null);
  int currentTurn = 1; // 1=红方(人类), 2=黑方(AI)
  int moveCount = 0;
  GameStatus gameStatus = GameStatus.ongoing;
  int aiDepth = 5;
  List<String> moveHistory = [];
  String? lastMoveUci;
  bool nnueLoaded = false;

  // ── NNUE 加载状态回调 ──
  void Function(String)? onNNUEStatus;

  // ── 开局库（走法序列追踪模式） ──
  List<List<String>> _openingSequences = [];
  bool _openingBookLoaded = false;
  int _activeOpeningIndex = -1;  // 当前跟随的开局序列索引，-1 表示未激活
  int _activeOpeningStep = 0;    // 当前在此序列中的步数

  ChessGame() {
    _loadEngine();
    _initEngine();
    _loadOpeningBook();
    _loadNNUE();
    reset();
  }

  // ═══════════════════════════════════════════════
  // 引擎加载
  // ═══════════════════════════════════════════════

  void _loadEngine() {
    String libPath;
    if (Platform.isAndroid) {
      libPath = 'libfishengine.so';
    } else if (Platform.isLinux) {
      libPath = './libfishengine.so';
    } else {
      throw UnsupportedError('当前仅支持 Android 和 Linux 平台');
    }
    _engine = DynamicLibrary.open(libPath);

    _initEngine = _engine
        .lookup<NativeFunction<Void Function()>>('init_engine')
        .asFunction();
    _newGame = _engine
        .lookup<NativeFunction<Void Function()>>('new_game')
        .asFunction();
    _getBoard = _engine
        .lookup<NativeFunction<Pointer<Utf8> Function()>>('get_board')
        .asFunction();
    _makeMove = _engine
        .lookup<NativeFunction<Void Function(Pointer<Utf8>)>>('make_move')
        .asFunction();
    _getBestMove = _engine
        .lookup<NativeFunction<Pointer<Utf8> Function(Int32)>>('get_best_move')
        .asFunction();
    _freeMemory = _engine
        .lookup<NativeFunction<Void Function()>>('free_memory')
        .asFunction();
    _undoMove = _engine
        .lookup<NativeFunction<Int32 Function()>>('undo_move')
        .asFunction();
    _isMoveLegal = _engine
        .lookup<NativeFunction<Int32 Function(Pointer<Utf8>)>>('is_move_legal')
        .asFunction();
    _getGameStatus = _engine
        .lookup<NativeFunction<Int32 Function()>>('get_game_status')
        .asFunction();
    _isInCheck = _engine
        .lookup<NativeFunction<Int32 Function()>>('is_in_check')
        .asFunction();
    _loadNnue = _engine
        .lookup<NativeFunction<Void Function(Pointer<Utf8>)>>('load_nnue')
        .asFunction();
    _getLastMove = _engine
        .lookup<NativeFunction<Pointer<Utf8> Function()>>('get_last_move')
        .asFunction();
    _getMoveHistoryCount = _engine
        .lookup<NativeFunction<Int32 Function()>>('get_move_history_count')
        .asFunction();
  }

  // ═══════════════════════════════════════════════
  // NNUE 网络加载 — 多级回退策略
  // ═══════════════════════════════════════════════

  Future<void> _loadNNUE() async {
    _notifyNNUE('正在初始化 AI 引擎...');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final nnuePath = p.join(dir.path, 'pikafish.nnue');
      final file = File(nnuePath);

      // 策略 1：已经下载过，直接加载
      if (await file.exists()) {
        _loadNnue(nnuePath.toNativeUtf8());
        nnueLoaded = true;
        _notifyNNUE('NNUE 神经网络已就绪，棋力全开');
        return;
      }

      // 策略 2：从 APK 内置资产复制（开发者预先打包）
      final fromAsset = await _tryLoadFromAsset(dir);
      if (fromAsset) {
        _loadNnue(nnuePath.toNativeUtf8());
        nnueLoaded = true;
        _notifyNNUE('NNUE 神经网络已就绪（内置）');
        return;
      }

      // 策略 3：从网络下载
      _notifyNNUE('正在下载 AI 神经网络权重（约 20MB）...');
      final downloaded = await _downloadNNUE(file);
      if (downloaded) {
        _loadNnue(nnuePath.toNativeUtf8());
        nnueLoaded = true;
        _notifyNNUE('NNUE 神经网络下载完成，棋力全开');
        return;
      }

      // 策略 4：全部失败，降级运行
      _notifyNNUE('AI 将以传统模式运行（棋力较弱），建议联网后重启');

    } catch (e) {
      _notifyNNUE('AI 加载异常，以传统模式运行');
      print('NNUE 加载异常: $e');
    }
  }

  /// 尝试从 APK 内置资源复制 NNUE 文件
  Future<bool> _tryLoadFromAsset(Directory targetDir) async {
    try {
      final data = await rootBundle.load('assets/nnue/pikafish.nnue');
      final nnuePath = p.join(targetDir.path, 'pikafish.nnue');
      await File(nnuePath).writeAsBytes(data.buffer.asUint8List());
      _notifyNNUE('正在加载内置神经网络...');
      return true;
    } catch (_) {
      // 资源不存在（正常情况，开发者可能未打包）
      return false;
    }
  }

  /// 从网络下载 NNUE 权重文件，多源尝试
  Future<bool> _downloadNNUE(File targetFile) async {
    // 下载源列表（按优先级排列）
    final urls = <String>[
      // GitHub Releases 官方发布页（最新版）
      'https://github.com/official-pikafish/Networks/releases/latest/download/pikafish.nnue',
      // 带 tag 的直链（master-net 是正确的 release tag）
      'https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue',
      // jsDelivr CDN 镜像
      'https://cdn.jsdelivr.net/gh/official-pikafish/Networks@master-net/pikafish.nnue',
      // 备用：下载 zip 包里的文件（GitHub 有时以 zip 分发）
      'https://github.com/official-pikafish/Networks/releases/latest/download/pikafish.zip',
    ];

    for (int i = 0; i < urls.length; i++) {
      try {
        _notifyNNUE('尝试下载源 ${i + 1}/${urls.length}...');
        final response = await http.get(Uri.parse(urls[i])).timeout(
          const Duration(seconds: 60),
        );

        if (response.statusCode == 200) {
          var bodyBytes = response.bodyBytes;

          // 检测是否下载的是 zip 包（PK 头）
          if (bodyBytes.length > 4 &&
              bodyBytes[0] == 0x50 && bodyBytes[1] == 0x4B) {
            _notifyNNUE('检测到 ZIP 格式，正在解压...');
            final nnueData = _extractNnueFromZip(bodyBytes);
            if (nnueData != null) {
              bodyBytes = nnueData;
            } else {
              continue; // zip 中没有 nnue 文件，尝试下一个源
            }
          }

          // 验证是否是有效的 NNUE 文件（至少大于 100KB）
          if (bodyBytes.length > 100000) {
            await targetFile.writeAsBytes(bodyBytes);
            _notifyNNUE('NNUE 下载成功 (${(bodyBytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
            return true;
          }
        }
      } catch (e) {
        print('下载失败 (源 ${i + 1}): $e');
      }
    }

    _notifyNNUE('所有下载源均失败，请检查网络连接');
    return false;
  }

  /// 从 zip 字节中提取 pikafish.nnue 文件
  Uint8List? _extractNnueFromZip(Uint8List zipData) {
    // 简单地从 zip 流中搜索 pikafish.nnue 文件名并提取
    // ZIP 格式：Local File Header 签名 0x504B0304
    try {
      for (int offset = 0; offset < zipData.length - 30; offset++) {
        if (zipData[offset] == 0x50 && zipData[offset + 1] == 0x4B &&
            zipData[offset + 2] == 0x03 && zipData[offset + 3] == 0x04) {
          final fileNameLen = zipData[offset + 26] | (zipData[offset + 27] << 8);
          final extraLen = zipData[offset + 28] | (zipData[offset + 29] << 8);
          final compSize = zipData[offset + 18] | (zipData[offset + 19] << 8) |
              (zipData[offset + 20] << 16) | (zipData[offset + 21] << 24);

          final nameStart = offset + 30;
          if (nameStart + fileNameLen > zipData.length) break;

          final name = String.fromCharCodes(
            zipData.sublist(nameStart, nameStart + fileNameLen));
          if (name.endsWith('.nnue')) {
            final dataStart = nameStart + fileNameLen + extraLen;
            final dataEnd = dataStart + compSize;
            if (dataEnd <= zipData.length) {
              return Uint8List.fromList(
                zipData.sublist(dataStart, dataEnd));
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  void _notifyNNUE(String msg) {
    print('NNUE: $msg');
    onNNUEStatus?.call(msg);
  }

  // ═══════════════════════════════════════════════
  // 开局库 — 走法序列追踪模式（彻底修复 FEN 匹配缺陷）
  // ═══════════════════════════════════════════════

  Future<void> _loadOpeningBook() async {
    try {
      final content = await rootBundle.loadString('assets/openings.txt');
      _parseOpeningBook(content);
      _openingBookLoaded = true;
      print('开局库加载成功，共 ${_openingSequences.length} 条走法序列');
    } catch (e) {
      print('开局库加载失败: $e');
      _openingBookLoaded = false;
    }
  }

  void _parseOpeningBook(String content) {
    _openingSequences.clear();
    for (final line in content.split('\n')) {
      if (line.startsWith('[') || line.startsWith('#') || line.trim().isEmpty) continue;
      final parts = line.trim().split(' ');
      if (parts.length < 3) continue;
      // 格式: FEN 步数 move1 move2 ...
      // parts[0] = FEN, parts[1] = 步数, parts[2..] = UCI 走法序列
      final moves = parts.sublist(2).toList();
      if (moves.isNotEmpty) {
        _openingSequences.add(moves);
      }
    }
  }

  /// 为新游戏选择一条开局路线（在 reset 时调用）
  void _selectNewOpening() {
    _activeOpeningIndex = -1;
    _activeOpeningStep = 0;
    if (!_openingBookLoaded || _openingSequences.isEmpty) return;

    // 收集所有从初始局面开始、红方先走的开局序列
    // （开局库中所有序列的第一步都是红方走法，AI 是黑方）
    // 随机选择一条
    final rng = Random();
    _activeOpeningIndex = rng.nextInt(_openingSequences.length);
    _activeOpeningStep = 0;

    final seq = _openingSequences[_activeOpeningIndex];
    print('开局库选中序列 (${seq.length} 步): ${seq.join(' ')}');
  }

  /// 检查黑方(AI)的下一步是否命中开局库
  /// 返回 null 表示开局库未命中，需要引擎自行搜索
  String? _lookupOpeningBook() {
    if (!_openingBookLoaded ||
        _activeOpeningIndex < 0 ||
        _activeOpeningIndex >= _openingSequences.length) {
      return null;
    }

    final seq = _openingSequences[_activeOpeningIndex];
    // 开局序列的第 0 步是红方走法（人类先走）
    // 第 1 步是黑方走法（AI 第 1 步回应）
    // 第 2 步是红方走法（人类第 2 步）
    // 第 3 步是黑方走法（AI 第 2 步回应）
    // ...
    // 所以 AI 走第 _activeOpeningStep 步（从 1 开始计数，步数是奇数）

    // AI 只走奇数索引：1, 3, 5, 7...
    final aiStep = _activeOpeningStep + 1;  // AI 要走的步在序列中的索引
    if (aiStep < seq.length && aiStep % 2 == 1) {
      // 验证：红方刚走了一步，检查它是否匹配
      if (_activeOpeningStep < seq.length && moveHistory.isNotEmpty) {
        final humanExpected = seq[_activeOpeningStep];
        final humanActual = moveHistory.last;
        if (humanExpected != humanActual) {
          // 人类没按开局库走 → 退出开局库模式
          print('人类走法 $humanActual 不匹配开局库预期 $humanExpected，退出开局库');
          _activeOpeningIndex = -1;
          return null;
        }
      }

      print('开局库命中 (步 $aiStep/${seq.length}): ${seq[aiStep]}');
      _activeOpeningStep = aiStep + 1;  // 跳过 AI 这一步，指向下一个红方应走位置
      return seq[aiStep];
    }

    // 序列结束或不是 AI 步
    _activeOpeningIndex = -1;
    return null;
  }

  // ═══════════════════════════════════════════════
  // 游戏控制
  // ═══════════════════════════════════════════════

  void reset() {
    _newGame();
    currentTurn = 1;
    moveCount = 0;
    moveHistory.clear();
    lastMoveUci = null;
    gameStatus = GameStatus.ongoing;
    _selectNewOpening();
    _updateBoard();
  }

  void _updateBoard() {
    final boardStr = _getBoard().toDartString();
    _parseBoard(boardStr);
    _checkGameStatus();
  }

  void _checkGameStatus() {
    final status = _getGameStatus();
    switch (status) {
      case 1:
        gameStatus = GameStatus.redWins;
        break;
      case 2:
        gameStatus = GameStatus.blackWins;
        break;
      case 3:
        gameStatus = GameStatus.draw;
        break;
      default:
        gameStatus = GameStatus.ongoing;
    }
  }

  void _parseBoard(String boardStr) {
    board.fillRange(0, 90, null);
    if (!boardStr.contains('/')) return;
    int y = 0, x = 0;
    for (final c in boardStr.split(' ')[0]) {
      if (c == '/') {
        y++;
        x = 0;
      } else if (c >= '1' && c <= '9') {
        x += int.parse(c);
      } else {
        final piece = _parsePiece(c);
        if (piece != null) board[y * 9 + x] = piece;
        x++;
      }
    }
  }

  int? _parsePiece(String c) {
    switch (c) {
      case 'K': return 1;   // 帅
      case 'A': return 2;   // 仕
      case 'B': return 3;   // 相
      case 'R': return 4;   // 车
      case 'N': return 5;   // 马
      case 'C': return 6;   // 炮
      case 'P': return 7;   // 兵
      case 'k': return -1;
      case 'a': return -2;
      case 'b': return -3;
      case 'r': return -4;
      case 'n': return -5;
      case 'c': return -6;
      case 'p': return -7;
      default:  return null;
    }
  }

  // ═══════════════════════════════════════════════
  // 走法校验（Dart 层实现中国象棋规则）
  // ═══════════════════════════════════════════════

  int? getPieceAt(int index) => board[index];

  /// 检查某个走法是否符合基本规则（Dart 层）
  bool isValidMoveByRules(int from, int to) {
    final piece = board[from];
    if (piece == null) return false;

    // 不能吃己方棋子
    final targetPiece = board[to];
    if (targetPiece != null) {
      if ((piece > 0 && targetPiece > 0) || (piece < 0 && targetPiece < 0)) {
        return false;
      }
    }

    final fromX = from % 9;
    final fromY = from ~/ 9;
    final toX = to % 9;
    final toY = to ~/ 9;
    final dx = toX - fromX;
    final dy = toY - fromY;
    final absDx = dx.abs();
    final absDy = dy.abs();
    final isRed = piece > 0;
    final pieceType = piece.abs();

    switch (pieceType) {
      case 1: return _isValidKingMove(fromX, fromY, toX, toY, isRed, absDx, absDy);
      case 2: return _isValidAdvisorMove(fromX, fromY, toX, toY, isRed, absDx, absDy);
      case 3: return _isValidElephantMove(fromX, fromY, toX, toY, isRed, absDx, absDy, dx, dy);
      case 4: return _isValidRookMove(fromX, fromY, toX, toY, dx, dy);
      case 5: return _isValidKnightMove(fromX, fromY, toX, toY, absDx, absDy, dx, dy);
      case 6: return _isValidCannonMove(fromX, fromY, toX, toY, dx, dy);
      case 7: return _isValidPawnMove(fromX, fromY, toX, toY, isRed, dx, dy);
      default: return false;
    }
  }

  bool _inPalace(int x, int y, bool isRed) {
    if (isRed) {
      return x >= 3 && x <= 5 && y >= 7 && y <= 9;
    } else {
      return x >= 3 && x <= 5 && y >= 0 && y <= 2;
    }
  }

  bool _crossedRiver(int y, bool isRed) {
    return isRed ? y <= 4 : y >= 5;
  }

  bool _isValidKingMove(int fx, int fy, int tx, int ty, bool isRed, int adx, int ady) {
    if (adx + ady != 1) return false;
    if (!_inPalace(tx, ty, isRed)) return false;
    return !_kingsAreFacing(tx, ty);
  }

  bool _kingsAreFacing(int kingX, int kingY) {
    final isRedKing = board[kingY * 9 + kingX]! > 0;
    int opponentKing = -1;
    for (int i = 0; i < 90; i++) {
      final p = board[i];
      if (p != null) {
        if ((isRedKing && p == -1) || (!isRedKing && p == 1)) {
          opponentKing = i;
          break;
        }
      }
    }
    if (opponentKing == -1) return false;
    final opX = opponentKing % 9;
    final opY = opponentKing ~/ 9;
    if (kingX != opX) return false;
    final minY = kingY < opY ? kingY : opY;
    final maxY = kingY > opY ? kingY : opY;
    for (int y = minY + 1; y < maxY; y++) {
      if (board[y * 9 + kingX] != null) return false;
    }
    return true;
  }

  bool _isValidAdvisorMove(int fx, int fy, int tx, int ty, bool isRed, int adx, int ady) {
    if (adx != 1 || ady != 1) return false;
    return _inPalace(tx, ty, isRed);
  }

  bool _isValidElephantMove(int fx, int fy, int tx, int ty, bool isRed, int adx, int ady, int dx, int dy) {
    if (adx != 2 || ady != 2) return false;
    if (_crossedRiver(ty, isRed)) return false;
    final eyeX = fx + dx ~/ 2;
    final eyeY = fy + dy ~/ 2;
    return board[eyeY * 9 + eyeX] == null;
  }

  bool _isValidRookMove(int fx, int fy, int tx, int ty, int dx, int dy) {
    if (dx != 0 && dy != 0) return false;
    return _isPathClear(fx, fy, tx, ty);
  }

  bool _isValidKnightMove(int fx, int fy, int tx, int ty, int adx, int ady, int dx, int dy) {
    if (!((adx == 2 && ady == 1) || (adx == 1 && ady == 2))) return false;
    int legX = fx;
    int legY = fy;
    if (adx == 2) {
      legX = fx + dx ~/ 2;
    } else {
      legY = fy + dy ~/ 2;
    }
    return board[legY * 9 + legX] == null;
  }

  bool _isValidCannonMove(int fx, int fy, int tx, int ty, int dx, int dy) {
    if (dx != 0 && dy != 0) return false;
    final targetPiece = board[ty * 9 + tx];
    final piecesBetween = _countPiecesBetween(fx, fy, tx, ty);
    if (targetPiece == null) {
      return piecesBetween == 0;
    } else {
      return piecesBetween == 1;
    }
  }

  bool _isValidPawnMove(int fx, int fy, int tx, int ty, bool isRed, int dx, int dy) {
    final forward = isRed ? -1 : 1;
    if (_crossedRiver(fy, isRed)) {
      if (dy.abs() + dx.abs() != 1) return false;
      if (dy == forward && dx == 0) return true;
      if (dy == 0 && dx.abs() == 1) return true;
      return false;
    } else {
      return dx == 0 && dy == forward;
    }
  }

  bool _isPathClear(int fx, int fy, int tx, int ty) {
    if (fx == tx) {
      final step = fy < ty ? 1 : -1;
      for (int y = fy + step; y != ty; y += step) {
        if (board[y * 9 + fx] != null) return false;
      }
    } else if (fy == ty) {
      final step = fx < tx ? 1 : -1;
      for (int x = fx + step; x != tx; x += step) {
        if (board[fy * 9 + x] != null) return false;
      }
    }
    return true;
  }

  int _countPiecesBetween(int fx, int fy, int tx, int ty) {
    int count = 0;
    if (fx == tx) {
      final step = fy < ty ? 1 : -1;
      for (int y = fy + step; y != ty; y += step) {
        if (board[y * 9 + fx] != null) count++;
      }
    } else if (fy == ty) {
      final step = fx < tx ? 1 : -1;
      for (int x = fx + step; x != tx; x += step) {
        if (board[fy * 9 + x] != null) count++;
      }
    }
    return count;
  }

  String _coordToUci(int fromX, int fromY, int toX, int toY) {
    const files = 'abcdefghi';
    return '${files[fromX]}${10 - fromY}${files[toX]}${10 - toY}';
  }

  /// 获取某个棋子的所有合法走法目标位置（用于 UI 高亮）
  List<int> getLegalMoves(int fromIndex) {
    final moves = <int>[];
    final piece = board[fromIndex];
    if (piece == null) return moves;

    final isRed = piece > 0;
    if ((currentTurn == 1 && !isRed) || (currentTurn == 2 && isRed)) {
      return moves;
    }

    for (int to = 0; to < 90; to++) {
      if (isValidMoveByRules(fromIndex, to)) {
        final fromX = fromIndex % 9;
        final fromY = fromIndex ~/ 9;
        final toX = to % 9;
        final toY = to ~/ 9;
        final uci = _coordToUci(fromX, fromY, toX, toY);
        if (_isMoveLegal(uci.toNativeUtf8()) == 1) {
          moves.add(to);
        }
      }
    }
    return moves;
  }

  /// 执行走子，返回是否成功
  bool move(int from, int to) {
    if (gameStatus != GameStatus.ongoing) return false;
    final piece = board[from];
    if (piece == null) return false;

    final isRedPiece = piece > 0;
    if ((currentTurn == 1 && !isRedPiece) || (currentTurn == 2 && isRedPiece)) {
      return false;
    }

    if (!isValidMoveByRules(from, to)) return false;

    final fromX = from % 9;
    final fromY = from ~/ 9;
    final toX = to % 9;
    final toY = to ~/ 9;
    final uci = _coordToUci(fromX, fromY, toX, toY);

    if (_isMoveLegal(uci.toNativeUtf8()) != 1) return false;

    _makeMove(uci.toNativeUtf8());
    moveHistory.add(uci);
    lastMoveUci = uci;
    moveCount++;
    _updateBoard();
    currentTurn = 2; // 轮到黑方(AI)
    return true;
  }

  void applyAIMove(String move) {
    _makeMove(move.toNativeUtf8());
    moveHistory.add(move);
    lastMoveUci = move;
    moveCount++;
    _updateBoard();
    currentTurn = 1; // 轮到红方(人类)
  }

  // ═══════════════════════════════════════════════
  // AI 走棋 — 开局库优先，引擎搜索回退
  // ═══════════════════════════════════════════════

  Future<String> getAIMove() async {
    if (currentTurn != 2 || gameStatus != GameStatus.ongoing) return '';

    // 先查开局库（序列追踪模式）
    final bookMove = _lookupOpeningBook();
    if (bookMove != null) {
      return bookMove;
    }

    // 使用引擎搜索
    return await Future<String>.microtask(() {
      final move = _getBestMove(aiDepth).toDartString();
      return move;
    });
  }

  // ═══════════════════════════════════════════════
  // 悔棋 — 同时重置开局库状态
  // ═══════════════════════════════════════════════

  bool canUndo() {
    return moveHistory.length >= 2 && gameStatus == GameStatus.ongoing;
  }

  bool undo() {
    if (!canUndo()) return false;

    if (_undoMove() == 1) {
      // 移除最后两步（人类一步 + AI 一步）
      if (moveHistory.length >= 2) {
        moveHistory.removeLast();
        moveHistory.removeLast();
      }
      moveCount = moveHistory.length;
      currentTurn = 1;
      lastMoveUci = moveHistory.isNotEmpty ? moveHistory.last : null;

      // 悔棋后退出开局库（无法简单恢复开局序列状态）
      _activeOpeningIndex = -1;
      _activeOpeningStep = 0;

      _updateBoard();
      return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════
  // 将军/状态检测
  // ═══════════════════════════════════════════════

  bool isInCheck() {
    return _isInCheck() == 1;
  }

  String getGameStatusText() {
    switch (gameStatus) {
      case GameStatus.ongoing:
        if (isInCheck()) {
          return currentTurn == 1 ? '将军！红方走棋' : '将军！黑方走棋';
        }
        return currentTurn == 1 ? '红方走棋' : '黑方走棋';
      case GameStatus.redWins:
        return '红方胜利！';
      case GameStatus.blackWins:
        return '黑方胜利！';
      case GameStatus.draw:
        return '和棋！';
    }
  }

  // ═══════════════════════════════════════════════
  // 清理
  // ═══════════════════════════════════════════════

  void dispose() {
    _freeMemory();
  }
}
