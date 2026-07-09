#include <string>
#include <string_view>
#include <cstring>
#include <memory>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <vector>
#include <deque>

#include "engine.h"
#include "search.h"
#include "thread.h"
#include "ucioption.h"
#include "uci.h"
#include "movegen.h"

// === Forward declarations ===
extern "C" {
    const char* get_engine_version();
    void init_engine();
    void load_nnue(const char* nnue_path);
    void new_game();
    const char* get_board();
    void make_move(const char* move_str);
    int undo_move();
    int is_move_legal(const char* move_str);
    int get_game_status();
    int is_in_check();
    int get_move_history_count();
    const char* get_last_move();
    const char* get_best_move(int depth);
    void free_memory();
}

// === Internal state ===
static std::unique_ptr<Stockfish::Engine> g_engine;
static std::atomic<bool> g_searching{false};
static std::string g_bestmove;
static std::mutex g_mutex;
static std::condition_variable g_cv;

// Move history for undo support
static std::vector<std::string> g_fen_history;
static std::vector<std::string> g_move_history;

// === Implementations ===

extern "C" const char* get_engine_version() {
    static const char* version = "Pikafish 1.0.0";
    return version;
}

extern "C" void init_engine() {
    if (!g_engine) {
        g_engine = std::make_unique<Stockfish::Engine>();
        g_engine->set_tt_size(256);  // 256 MB transposition table for better mid/endgame
        g_engine->resize_threads();
        g_fen_history.clear();
        g_move_history.clear();
    }
}

extern "C" void load_nnue(const char* nnue_path) {
    if (g_engine && nnue_path) {
        g_engine->load_network(std::string(nnue_path));
    }
}

extern "C" void new_game() {
    if (g_engine) {
        g_engine->set_position(Stockfish::StartFEN, {});
    }
    g_fen_history.clear();
    g_move_history.clear();
}

extern "C" const char* get_board() {
    static char buffer[1024];
    if (g_engine) {
        std::string fen = g_engine->fen();
        strncpy(buffer, fen.c_str(), sizeof(buffer) - 1);
    } else {
        strcpy(buffer, Stockfish::StartFEN);
    }
    buffer[sizeof(buffer) - 1] = '\0';
    return buffer;
}

extern "C" void make_move(const char* move_str) {
    if (g_engine && move_str && strlen(move_str) >= 4) {
        // Save current state for undo
        g_fen_history.push_back(g_engine->fen());
        g_move_history.push_back(std::string(move_str));
        g_engine->set_position(g_engine->fen(), {std::string(move_str)});
    }
}

extern "C" int undo_move() {
    if (!g_engine || g_move_history.size() < 2) return 0;

    // Remove the last human+AI move pair
    g_move_history.pop_back();
    g_move_history.pop_back();

    // Rebuild position from scratch with remaining moves
    g_fen_history.clear();
    g_engine->set_position(Stockfish::StartFEN, {});

    // Save remaining moves and replay
    auto saved_moves = g_move_history;
    g_move_history.clear();

    for (const auto& move : saved_moves) {
        g_fen_history.push_back(g_engine->fen());
        g_move_history.push_back(move);
        g_engine->set_position(g_engine->fen(), {move});
    }

    return 1;
}

extern "C" int is_move_legal(const char* move_str) {
    if (!g_engine || !move_str || strlen(move_str) < 4) {
        return 0;
    }
    // Use UCIEngine::to_move and Position::legal to check
    Stockfish::StateListPtr tempStates(new std::deque<Stockfish::StateInfo>(1));
    Stockfish::Position tempPos;
    tempPos.set(g_engine->fen(), &tempStates->back());
    
    Stockfish::Move m = Stockfish::UCIEngine::to_move(tempPos, std::string(move_str));
    if (m == Stockfish::Move::none()) {
        return 0;
    }
    return tempPos.legal(m) ? 1 : 0;
}

extern "C" int get_game_status() {
    // Returns: 0 = ongoing, 1 = red wins (checkmate), 2 = black wins (checkmate), 3 = draw
    if (!g_engine) return 0;
    
    Stockfish::StateListPtr tempStates(new std::deque<Stockfish::StateInfo>(1));
    Stockfish::Position tempPos;
    tempPos.set(g_engine->fen(), &tempStates->back());
    
    // Check for rule-based draw/win (repetition, perpetual chase, etc.)
    Stockfish::Value result;
    if (tempPos.rule_judge(result)) {
        if (result > 0) return 1;  // Red wins
        if (result < 0) return 2;  // Black wins
        return 3;  // Draw
    }
    
    // Check if side to move has any legal moves using proper move generation
    Stockfish::MoveList<Stockfish::LEGAL> moveList(tempPos);
    
    if (moveList.size() == 0) {
        // No legal moves - check if in check (checkmate) or stalemate (draw)
        Stockfish::Color sideToMove = tempPos.side_to_move();
        Stockfish::Square kingSq = tempPos.king_square(sideToMove);
        bool inCheck = tempPos.checkers() && (tempPos.checkers() & kingSq);
        
        if (sideToMove == Stockfish::WHITE) {
            return inCheck ? 2 : 3;  // White has no moves: black wins or draw
        } else {
            return inCheck ? 1 : 3;  // Black has no moves: red wins or draw
        }
    }
    
    return 0;  // Game ongoing
}

extern "C" int is_in_check() {
    if (!g_engine) return 0;
    
    Stockfish::StateListPtr tempStates(new std::deque<Stockfish::StateInfo>(1));
    Stockfish::Position tempPos;
    tempPos.set(g_engine->fen(), &tempStates->back());
    
    Stockfish::Color sideToMove = tempPos.side_to_move();
    Stockfish::Square kingSq = tempPos.king_square(sideToMove);
    
    return (tempPos.checkers() && (tempPos.checkers() & kingSq)) ? 1 : 0;
}

extern "C" int get_move_history_count() {
    return (int)g_move_history.size();
}

extern "C" const char* get_last_move() {
    static char move[16];
    move[0] = '\0';
    if (!g_move_history.empty()) {
        strncpy(move, g_move_history.back().c_str(), sizeof(move) - 1);
        move[sizeof(move) - 1] = '\0';
    }
    return move;
}

static void on_bestmove_callback(std::string_view bestmove, std::string_view) {
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_bestmove = std::string(bestmove);
        g_searching = false;
    }
    g_cv.notify_one();
}

extern "C" const char* get_best_move(int depth) {
    static char move[16];
    move[0] = '\0';
    
    if (!g_engine || g_searching.load()) {
        return move;
    }
    
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_searching = true;
        g_bestmove.clear();
    }
    
    g_engine->set_on_bestmove([](std::string_view bestmove, std::string_view ponder) {
        on_bestmove_callback(bestmove, ponder);
    });
    
    Stockfish::Search::LimitsType limits;
    limits.depth = depth;
    
    g_engine->go(limits);
    
    {
        std::unique_lock<std::mutex> lock(g_mutex);
        g_cv.wait(lock, []{ return !g_searching.load(); });
    }
    
    if (!g_bestmove.empty()) {
        strncpy(move, g_bestmove.c_str(), sizeof(move) - 1);
        move[sizeof(move) - 1] = '\0';
    }
    
    return move;
}

extern "C" void free_memory() {
    g_engine.reset();
    g_searching = false;
    g_bestmove.clear();
    g_fen_history.clear();
    g_move_history.clear();
}
