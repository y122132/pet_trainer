import 'dart:convert';
import 'friend_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/config/design_system.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pet_trainer_frontend/screens/battle_page.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart';
import 'package:pet_trainer_frontend/screens/user_list_screen.dart'; 
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

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _pulseAnimation =
        Tween<double>(begin: 0.95, end: 1.05).animate(CurvedAnimation(
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

  // --- Logic Methods (Preserved) ---
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
      _matchSocket?.sink.close();
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
    
    _matchSocket?.sink.close();
    _matchSocket = null;

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

  void _startAIBattle() async {
    setState(() => _isSearching = true);
    
    final idStr = await _authService.getUserId();
    int? userId = (idStr != null) ? int.tryParse(idStr) : null;
    
    if (userId == null) {
       setState(() => _isSearching = false);
       return;
    }

    final socketUrl = AppConfig.matchMakingSocketUrl(userId);
    try { 
      _matchSocket?.sink.close();
      _matchSocket = WebSocketChannel.connect(Uri.parse(socketUrl));
      
      _matchSocket!.stream.listen((data) {
        final decoded = jsonDecode(data);
        if (decoded['type'] == 'MATCH_FOUND') {
           _onMatchFound(decoded['room_id']);
        } else if (decoded['type'] == 'ERROR') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(decoded['message'])));
          _cancelMatch();
        }
      });
      
      _matchSocket!.sink.add("AI_BATTLE");
      
    } catch (e) {
      _cancelMatch();
    }
  }

  void _onInviteFriend() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FriendPlayScreen()),
    );
  }

  // --- UI Builder ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. [Background] Studio Gradient
          // 1. [Background] Exact Friend Page Style
          Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              image: DecorationImage(
                image: AssetImage('assets/images/login_bg.png'),
                fit: BoxFit.cover,
                opacity: 0.3,
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: _isSearching ? _buildSearchingUI() : _buildSelectionUI(),
            ),
          ),

          // Back Button
          if (!_isSearching)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 20,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textMain),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                   backgroundColor: Colors.white.withValues(alpha: 0.5),
                   padding: const EdgeInsets.all(12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionUI() {
    return Column(
      children: [
        const SizedBox(height: 60),
        
        // Header
        ScaleTransition(
          scale: _pulseAnimation,
          child: Column(
            children: [
               const FaIcon(FontAwesomeIcons.flagCheckered, color: AppColors.primary, size: 40),
               const SizedBox(height: 10),
               Text(
                "READY TO BATTLE?",
                style: GoogleFonts.jua(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMain,
                ),
              ),
              Text(
                "친구들과 실력을 겨뤄보세요!",
                style: GoogleFonts.jua(
                  fontSize: 14,
                  color: AppColors.textSub,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ListView(
              children: [
                _buildTypeCard(
                  title: "랜덤 매칭",
                  subtitle: "새로운 친구 만나기",
                  icon: FontAwesomeIcons.earthAmericas,
                  color: AppColors.primary,
                  onTap: _startRandomMatch,
                ),
                const SizedBox(height: 20),
                _buildTypeCard(
                  title: "친구 대전",
                  subtitle: "베스트 프렌드와 한판!",
                  icon: FontAwesomeIcons.userGroup,
                  color: AppColors.accent,
                  onTap: _onInviteFriend,
                ),
                const SizedBox(height: 20),
                _buildTypeCard(
                  title: "AI 연습",
                  subtitle: "로봇과 훈련하기",
                  icon: FontAwesomeIcons.robot,
                  color: AppColors.textSub,
                  onTap: _startAIBattle,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 100,
              decoration: BoxDecoration(
                 color: color.withValues(alpha: 0.1),
                 borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), bottomLeft: Radius.circular(22)),
              ),
              child: Center(
                child: FaIcon(icon, color: color, size: 36),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.title.copyWith(fontSize: 20)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppTextStyles.body.copyWith(fontSize: 12, color: AppColors.textSub)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: const FaIcon(FontAwesomeIcons.circlePlay, color: AppColors.textSub, size: 20),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Pulsing Paw Ripple
        Stack(
          alignment: Alignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondary.withValues(alpha: 0.1),
                ),
              ),
            ),
             Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondary.withValues(alpha: 0.2),
                ),
              ),
             Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: AppDecorations.softShadow,
                ),
                child: Center(child: FaIcon(FontAwesomeIcons.paw, color: AppColors.primary, size: 40)),
              ),
          ],
        ),
        
        const SizedBox(height: 40),
        
        Text("친구를 찾는 중...", style: AppTextStyles.title.copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text("잠시만 기다려주세요", style: AppTextStyles.body),
        
        const SizedBox(height: 60),
        
        SizedBox(
          width: 160,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.danger,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: _cancelMatch,
            child: Text("그만하기", style: GoogleFonts.jua(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        )
      ],
    );
  }
}
