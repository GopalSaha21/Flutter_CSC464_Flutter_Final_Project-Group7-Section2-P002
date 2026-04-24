import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase Initialize করুন
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyAXXXXXXXXXXXXXXXXXXXXXX', // আপনার API Key দিন
      appId: '1:123456789:android:abc123def456', // আপনার App ID দিন
      messagingSenderId: '123456789', // আপনার Sender ID দিন
      projectId: 'your-project-id', // আপনার Project ID দিন
    ),
  );
  
  runApp(const TicTacToeApp());
}

class TicTacToeApp extends StatelessWidget {
  const TicTacToeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameProvider()),
        Provider(create: (_) => FirestoreService()),
      ],
      child: MaterialApp(
        title: 'টিক ট্যাক টো',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.blue,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            titleTextStyle: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

// ============================================================
// Firebase Service
// ============================================================
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String collectionName = 'matches';

  // ম্যাচ সেভ করা
  Future<void> saveMatch(MatchModel match) async {
    try {
      await _firestore.collection(collectionName).add({
        'playerX': match.playerX,
        'playerO': match.playerO,
        'winner': match.winner,
        'board': match.board,
        'createdAt': FieldValue.serverTimestamp(),
        'result': match.result,
      });
      print('✅ ম্যাচ সেভ হয়েছে Firebase এ!');
    } catch (e) {
      print('❌ Firebase এ সেভ করতে সমস্যা: $e');
      rethrow;
    }
  }

  // সব ম্যাচ পাওয়া (রিয়েল-টাইম)
  Stream<List<MatchModel>> getAllMatches() {
    return _firestore
        .collection(collectionName)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return MatchModel.fromFirestore(doc);
      }).toList();
    });
  }

  // সীমিত সংখ্যক ম্যাচ পাওয়া
  Stream<List<MatchModel>> getRecentMatches({int limit = 20}) {
    return _firestore
        .collection(collectionName)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return MatchModel.fromFirestore(doc);
      }).toList();
    });
  }

  // সব ম্যাচ ডিলিট করা
  Future<void> deleteAllMatches() async {
    try {
      final matches = await _firestore.collection(collectionName).get();
      final batch = _firestore.batch();
      
      for (var doc in matches.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('✅ সব ম্যাচ ডিলিট হয়েছে!');
    } catch (e) {
      print('❌ ডিলিট করতে সমস্যা: $e');
      rethrow;
    }
  }

  // গ্লোবাল স্ট্যাটিস্টিক্স
  Future<Map<String, int>> getGlobalStats() async {
    final matches = await _firestore.collection(collectionName).get();
    
    int xWins = 0;
    int oWins = 0;
    int draws = 0;
    
    for (var doc in matches.docs) {
      final winner = doc['winner'] as String;
      if (winner == 'X') xWins++;
      else if (winner == 'O') oWins++;
      else if (winner == 'Tie') draws++;
    }
    
    return {
      'xWins': xWins,
      'oWins': oWins,
      'draws': draws,
    };
  }
}

// ============================================================
// Data Models
// ============================================================
class MatchModel {
  final String? id;
  final String playerX;
  final String playerO;
  final String winner; // 'X', 'O', বা 'Tie'
  final List<String> board;
  final DateTime createdAt;
  final String result;

  MatchModel({
    this.id,
    required this.playerX,
    required this.playerO,
    required this.winner,
    required this.board,
    required this.createdAt,
    required this.result,
  });

  factory MatchModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MatchModel(
      id: doc.id,
      playerX: data['playerX'] ?? 'Player X',
      playerO: data['playerO'] ?? 'Player O',
      winner: data['winner'] ?? 'Tie',
      board: List<String>.from(data['board'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      result: data['result'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'playerX': playerX,
      'playerO': playerO,
      'winner': winner,
      'board': board,
      'createdAt': FieldValue.serverTimestamp(),
      'result': result,
    };
  }
}

class MatchResult {
  final String playerX;
  final String playerO;
  final String result;
  final DateTime timestamp;

  MatchResult({
    required this.playerX,
    required this.playerO,
    required this.result,
    required this.timestamp,
  });
}

// ============================================================
// Game Provider (State Management)
// ============================================================
class GameProvider extends ChangeNotifier {
  List<String> _board = List.filled(9, '');
  String _currentPlayer = 'X';
  bool _gameActive = true;

  String _playerXName = 'প্লেয়ার X';
  String _playerOName = 'প্লেয়ার O';

  int _xWins = 0;
  int _oWins = 0;
  int _draws = 0;

  List<MatchResult> _history = [];
  bool _isSaving = false;

  List<String> get board => _board;
  String get currentPlayer => _currentPlayer;
  bool get gameActive => _gameActive;
  String get playerXName => _playerXName;
  String get playerOName => _playerOName;
  int get xWins => _xWins;
  int get oWins => _oWins;
  int get draws => _draws;
  List<MatchResult> get history => _history;
  bool get isSaving => _isSaving;

  static const List<List<int>> winPatterns = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ];

  String? checkWinner() {
    for (var pattern in winPatterns) {
      if (pattern.every((i) => _board[i] == 'X')) return 'X';
      if (pattern.every((i) => _board[i] == 'O')) return 'O';
    }
    return null;
  }

  bool isDraw() {
    return _board.every((cell) => cell.isNotEmpty) && checkWinner() == null;
  }

  void makeMove(int index) {
    if (!_gameActive || _board[index].isNotEmpty || _isSaving) return;

    _board[index] = _currentPlayer;
    notifyListeners();

    final winner = checkWinner();
    if (winner != null) {
      _gameActive = false;
      String resultText;
      if (winner == 'X') {
        _xWins++;
        resultText = '$_playerXName জিতেছে!';
      } else {
        _oWins++;
        resultText = '$_playerOName জিতেছে!';
      }
      _saveMatchResult(resultText, winner);
      notifyListeners();
      return;
    }

    if (isDraw()) {
      _gameActive = false;
      _draws++;
      _saveMatchResult('ড্র', 'Tie');
      notifyListeners();
      return;
    }

    _currentPlayer = (_currentPlayer == 'X') ? 'O' : 'X';
    notifyListeners();
  }

  Future<void> _saveMatchResult(String resultText, String winner) async {
    // লোকালি সেভ করুন
    final match = MatchResult(
      playerX: _playerXName,
      playerO: _playerOName,
      result: resultText,
      timestamp: DateTime.now(),
    );
    _history.insert(0, match);
    if (_history.length > 20) _history.removeLast();

    // Firebase এ সেভ করার চেষ্টা করুন
    try {
      final firestoreService = FirestoreService();
      final firestoreMatch = MatchModel(
        playerX: _playerXName,
        playerO: _playerOName,
        winner: winner,
        board: List.from(_board),
        createdAt: DateTime.now(),
        result: resultText,
      );
      
      _isSaving = true;
      notifyListeners();
      
      await firestoreService.saveMatch(firestoreMatch);
    } catch (e) {
      print('Firebase এ সেভ করতে সমস্যা: $e');
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void resetBoard() {
    _board = List.filled(9, '');
    _gameActive = true;
    _currentPlayer = 'X';
    notifyListeners();
  }

  void switchStartingPlayer() {
    _currentPlayer = (_currentPlayer == 'X') ? 'O' : 'X';
    resetBoard();
  }

  void updatePlayerNames({required String xName, required String oName}) {
    _playerXName = xName.trim().isEmpty ? 'প্লেয়ার X' : xName.trim();
    _playerOName = oName.trim().isEmpty ? 'প্লেয়ার O' : oName.trim();
    notifyListeners();
  }

  void resetScoresAndHistory() {
    _xWins = 0;
    _oWins = 0;
    _draws = 0;
    _history.clear();
    resetBoard();
    notifyListeners();
  }

  void showWinnerDialog(BuildContext context) {
    if (!_gameActive && !_isSaving) {
      String winnerMessage = '';
      final winner = checkWinner();
      if (winner == 'X') {
        winnerMessage = '$_playerXName জিতেছে! 🎉';
      } else if (winner == 'O') {
        winnerMessage = '$_playerOName জিতেছে! 🎉';
      } else if (isDraw()) {
        winnerMessage = 'খেলাটি ড্র! 🤝';
      }
      if (winnerMessage.isNotEmpty) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(winnerMessage),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  resetBoard();
                },
                child: const Text('আবার খেলুন'),
              ),
            ],
          ),
        );
      }
    }
  }
}

// ============================================================
// Splash Screen
// ============================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GameHomeScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.cyanAccent, Colors.pinkAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyanAccent.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          "✕ ●",
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      "টিক ট্যাক টো",
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 60),
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// Game Home Screen
// ============================================================
class GameHomeScreen extends StatefulWidget {
  const GameHomeScreen({super.key});

  @override
  State<GameHomeScreen> createState() => _GameHomeScreenState();
}

class _GameHomeScreenState extends State<GameHomeScreen> {
  int _selectedNavIndex = 0;

  void _showEditNamesDialog(GameProvider provider) {
    final xController = TextEditingController(text: provider.playerXName);
    final oController = TextEditingController(text: provider.playerOName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('প্লেয়ারের নাম পরিবর্তন করুন'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: xController,
              decoration: const InputDecoration(
                labelText: 'প্লেয়ার X এর নাম',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: oController,
              decoration: const InputDecoration(
                labelText: 'প্লেয়ার O এর নাম',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বাতিল'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.updatePlayerNames(
                xName: xController.text,
                oName: oController.text,
              );
              Navigator.pop(context);
            },
            child: const Text('সেভ করুন'),
          ),
        ],
      ),
    );
  }

  void _showStatsDialog(GameProvider provider) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2535),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.insights, color: Colors.cyanAccent),
                  SizedBox(width: 10),
                  Text(
                    'পরিসংখ্যান',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _StatRow(
                label: '✕ ${provider.playerXName}',
                value: provider.xWins,
                color: Colors.cyanAccent,
              ),
              _StatRow(
                label: '● ${provider.playerOName}',
                value: provider.oWins,
                color: Colors.pinkAccent,
              ),
              _StatRow(
                label: 'ড্র',
                value: provider.draws,
                color: Colors.white70,
              ),
              if (provider.history.isNotEmpty) ...[
                const Divider(height: 32, color: Colors.white24),
                const Text(
                  'সর্বশেষ ম্যাচ',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 8),
                ...provider.history.take(5).map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        entry.result,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )),
              ],
              const SizedBox(height: 20),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    provider.resetScoresAndHistory();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.refresh, color: Colors.redAccent),
                  label: const Text(
                    'সব রিসেট করুন',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GameProvider>(context);

    if (!provider.gameActive && provider.history.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.showWinnerDialog(context);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('টিক ট্যাক টো'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'নাম পরিবর্তন',
            onPressed: () => _showEditNamesDialog(provider),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'ম্যাচ ইতিহাস',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ScoreTile(
                  name: provider.playerXName,
                  symbol: '✕',
                  wins: provider.xWins,
                  color: Colors.cyanAccent,
                ),
                Container(width: 1, height: 40, color: Colors.white24),
                _ScoreTile(
                  name: provider.playerOName,
                  symbol: '●',
                  wins: provider.oWins,
                  color: Colors.pinkAccent,
                ),
                Container(width: 1, height: 40, color: Colors.white24),
                _ScoreTile(
                  name: 'ড্র',
                  symbol: '⚖️',
                  wins: provider.draws,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: provider.currentPlayer == 'X'
                    ? Colors.cyanAccent.withOpacity(0.5)
                    : Colors.pinkAccent.withOpacity(0.5),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider.currentPlayer == 'X' ? '✕' : '●',
                  style: TextStyle(
                    fontSize: 28,
                    color: provider.currentPlayer == 'X'
                        ? Colors.cyanAccent
                        : Colors.pinkAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  provider.gameActive
                      ? '${provider.currentPlayer == 'X' ? provider.playerXName : provider.playerOName} এর পালা'
                      : 'খেলা শেষ',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (provider.isSaving)
            const LinearProgressIndicator(),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 32,
                  maxHeight: MediaQuery.of(context).size.width - 32,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 9,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemBuilder: (_, i) => GameCell(index: i),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _buildModernBottomNav(provider),
        ],
      ),
    );
  }

  Widget _buildModernBottomNav(GameProvider provider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2538), Color(0xFF111B28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.grid_3x3,
            label: 'বোর্ড',
            index: 0,
            selectedIndex: _selectedNavIndex,
            onTap: () => setState(() => _selectedNavIndex = 0),
          ),
          _NavItem(
            icon: Icons.refresh,
            label: 'রিসেট',
            index: 1,
            selectedIndex: _selectedNavIndex,
            onTap: () {
              setState(() => _selectedNavIndex = 1);
              provider.resetBoard();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('গেম রিসেট হয়েছে'),
                  duration: Duration(milliseconds: 800),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: Colors.cyanAccent,
                  shape: StadiumBorder(),
                ),
              );
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) setState(() => _selectedNavIndex = 0);
              });
            },
          ),
          _NavItem(
            icon: Icons.bar_chart,
            label: 'পরিসংখ্যান',
            index: 2,
            selectedIndex: _selectedNavIndex,
            onTap: () {
              setState(() => _selectedNavIndex = 2);
              _showStatsDialog(provider);
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) setState(() => _selectedNavIndex = 0);
              });
            },
          ),
        ],
      ),
    );
  }
}

class GameCell extends StatelessWidget {
  final int index;
  const GameCell({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GameProvider>(context);
    final value = provider.board[index];
    final isX = value == 'X';
    final isO = value == 'O';

    return GestureDetector(
      onTap: () => provider.makeMove(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              value == 'X' ? '✕' : (value == 'O' ? '●' : ''),
              key: ValueKey(value),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: isX
                    ? Colors.cyanAccent
                    : isO
                        ? Colors.pinkAccent
                        : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  final String name;
  final String symbol;
  final int wins;
  final Color color;
  const _ScoreTile({
    required this.name,
    required this.symbol,
    required this.wins,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(symbol, style: TextStyle(color: color, fontSize: 24)),
        const SizedBox(height: 4),
        Text(
          name,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '$wins',
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int selectedIndex;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20 : 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Colors.cyanAccent, Colors.blueAccent],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(40),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.cyanAccent.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.black87 : Colors.white70,
              size: 22,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          Text(
            value.toString(),
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// History Screen with Firebase Integration
// ============================================================
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);
    final localProvider = Provider.of<GameProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ম্যাচ ইতিহাস'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync),
            tooltip: 'ক্লাউড সিঙ্ক',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Firebase এর সাথে সিঙ্ক হচ্ছে...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'ইতিহাস মুছুন',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('ইতিহাস মুছবেন?'),
                  content: const Text('সব ম্যাচ রেকর্ড ডিলিট হয়ে যাবে।'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('বাতিল'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await firestoreService.deleteAllMatches();
                        localProvider.resetScoresAndHistory();
                        if (context.mounted) Navigator.pop(context);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('সব ইতিহাস মুছে ফেলা হয়েছে'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'মুছুন',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<MatchModel>>(
        stream: firestoreService.getRecentMatches(limit: 50),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('এরর: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('আবার চেষ্টা করুন'),
                  ),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final matches = snapshot.data ?? [];

          if (matches.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.white54),
                  SizedBox(height: 16),
                  Text(
                    'কোনো ম্যাচ খেলা হয়নি\nখেলা শুরু করুন',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final match = matches[index];
              final formattedDate = DateFormat('dd MMM yyyy, hh:mm a')
                  .format(match.createdAt);
              
              Color resultColor;
              IconData resultIcon;
              if (match.winner == 'X') {
                resultColor = Colors.cyanAccent;
                resultIcon = Icons.emoji_events;
              } else if (match.winner == 'O') {
                resultColor = Colors.pinkAccent;
                resultIcon = Icons.emoji_events;
              } else {
                resultColor = Colors.white70;
                resultIcon = Icons.handshake;
              }
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ListTile(
                  leading: Icon(resultIcon, color: resultColor),
                  title: Text(
                    match.result,
                    style: TextStyle(
                      color: resultColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${match.playerX} ✕ vs ● ${match.playerO}\n$formattedDate',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: resultColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      match.winner == 'Tie' ? 'ড্র' : '${match.winner} জিতেছে',
                      style: TextStyle(
                        color: resultColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}