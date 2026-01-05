import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pet_trainer_frontend/screens/user_list_screen.dart'; // For friend selection
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart';
import 'package:provider/provider.dart';
import 'package:pet_trainer_frontend/screens/battle_page.dart';
import 'package:pet_trainer_frontend/providers/battle_provider.dart';

class BattleLobbyScreen extends StatefulWidget {
  const BattleLobbyScreen({super.key});

  @override
  State<BattleLobbyScreen> createState() => _BattleLobbyScreenState();
}

class _BattleLobbyScreenState extends State<BattleLobbyScreen>
    with SingleTickerProviderStateMixin {
  bool _isSearching = false;
  WebSocketChannel? _matchSocket;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final AuthService _authService = AuthService();

  // --- 색상 및 테마 상수 ---
  static const Color creamBackground = Color(0xFFFFF9E6);
  static const Color darkBrown = Color(0xFF5D4037);

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _pulseAnimation =
        Tween<double>(begin: 1.0, end: 1.1).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _matchSocket?.sink.close();
    _pulseController.dispose();
    super.dispose();
  }

  // --- 기존 로직 (변경 없음) ---
  void _startRandomMatch() async {
    setState(() => _isSearching = true);

    final idStr = await _authService.getUserId();
    int? userId = (idStr != null) ? int.tryParse(idStr) : null;

    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("로그인 정보 오류")));
      }
      setState(() => _isSearching = false);
      return;
    }

    final socketUrl = AppConfig.matchMakingSocketUrl(userId);
    debugPrint("Connecting to Matchmaker: $socketUrl");

    try {
      _matchSocket = WebSocketChannel.connect(Uri.parse(socketUrl));

      _matchSocket!.stream.listen((data) {
        debugPrint("Matchmaker Msg: $data");
        try {
          final decoded = jsonDecode(data);
          if (decoded['type'] == 'MATCH_FOUND') {
            _onMatchFound(decoded['room_id']);
          }
        } catch (e) {
          debugPrint("Error parsing match data: $e");
        }
      }, onError: (e) {
        debugPrint("Match Socket Error: $e");
        _cancelMatch();
      }, onDone: () {
        // Connection closed
      });
    } catch (e) {
      debugPrint("Connection failed: $e");
      _cancelMatch();
    }
  }

  void _cancelMatch() {
    _matchSocket?.sink.add("CANCEL");
    _matchSocket?.sink.close();
    _matchSocket = null;
    if (mounted) setState(() => _isSearching = false);
  }

  void _onMatchFound(String roomId) {
    if (!mounted) return;
    setState(() => _isSearching = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider(
          create: (_) => BattleProvider()..setRoomId(roomId),
          child: const BattleView(),
        ),
      ),
    );
  }

  void _onInviteFriend() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              const UserListScreen(initialTab: 0, isInviteMode: true)),
    );
  }

  // --- UI 빌더 ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBackground,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/login_bg.png'),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                opacity: 0.2,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child:
                  _isSearching ? _buildSearchingUI() : _buildSelectionUI(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionUI() {
    return Column(
      children: [
        const SizedBox(height: 40),
        _buildHeader(),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModeCard(
                title: "랜덤 매칭",
                subtitle: "전 세계의 친구들과 대결해보세요!",
                icon: Icons.public,
                onTap: _startRandomMatch,
              ),
              const SizedBox(height: 24),
              _buildModeCard(
                title: "친구 대전",
                subtitle: "친구와 함께 즐겨요!",
                icon: Icons.person,
                onTap: _onInviteFriend,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Text(
          "BATTLE ARENA",
          style: GoogleFonts.jua(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: darkBrown,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 60,
          height: 4,
          decoration: BoxDecoration(
            color: darkBrown,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _buildModeCard(
      {required String title,
      required String subtitle,
      required IconData icon,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30.0),
          border: Border.all(color: darkBrown, width: 2.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28.0),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Row(
              children: [
                Icon(icon, size: 40, color: darkBrown),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.jua(
                          color: darkBrown,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: GoogleFonts.jua(
                          color: darkBrown.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: darkBrown, size: 20)
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // 기존 검색 UI는 테마 일관성을 위해 약간만 수정
  Widget _buildSearchingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: darkBrown.withOpacity(0.5), width: 6),
                boxShadow: [
                  BoxShadow(
                      color: darkBrown.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5)
                ]),
            child: const Center(
                child: Icon(Icons.search_rounded, size: 80, color: darkBrown)),
          ),
        ),
        const SizedBox(height: 40),
        Text("상대를 찾는 중...",
            style: GoogleFonts.jua(
                color: darkBrown,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text("잠시만 기다려주세요",
            style: GoogleFonts.jua(color: Colors.grey[700], fontSize: 16)),
        const SizedBox(height: 40),
        SizedBox(
          width: 140,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                  side: const BorderSide(color: Colors.redAccent, width: 1.5)),
            ),
            onPressed: _cancelMatch,
            child: Text("취소",
                style: GoogleFonts.jua(
                    fontWeight: FontWeight.bold, fontSize: 18)),
          ),
        )
      ],
    );
  }
}
