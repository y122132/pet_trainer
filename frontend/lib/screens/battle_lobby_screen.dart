import 'dart:convert';
import 'friend_play_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pet_trainer_frontend/screens/battle_page.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart';
import 'package:pet_trainer_frontend/screens/user_list_screen.dart'; // For friend selection
import 'package:pet_trainer_frontend/providers/battle_provider.dart';

class BattleLobbyScreen extends StatefulWidget {
  const BattleLobbyScreen({super.key});

  @override
  State<BattleLobbyScreen> createState() => _BattleLobbyScreenState();
}

class _BattleLobbyScreenState extends State<BattleLobbyScreen> with SingleTickerProviderStateMixin {
  bool _isSearching = false;
  WebSocketChannel? _matchSocket;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _matchSocket?.sink.close();
    _pulseController.dispose();
    super.dispose();
  }

  void _startRandomMatch() async {
    setState(() => _isSearching = true);
    
    final idStr = await _authService.getUserId();
    int? userId = (idStr != null) ? int.tryParse(idStr) : null;
    
    if (userId == null) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("로그인 정보 오류")));
       setState(() => _isSearching = false);
       return;
    }

    // Connect to Matchmaking Socket
    final socketUrl = AppConfig.matchMakingSocketUrl(userId);
    print("Connecting to Matchmaker: $socketUrl");
    
    try {
      _matchSocket = WebSocketChannel.connect(Uri.parse(socketUrl));
      
      _matchSocket!.stream.listen((data) {
        print("Matchmaker Msg: $data");
        try {
          final decoded = jsonDecode(data);
          if (decoded['type'] == 'MATCH_FOUND') {
             _onMatchFound(decoded['room_id']);
          }
        } catch (e) {
          print("Error parsing match data: $e");
        }
      }, onError: (e) {
         print("Match Socket Error: $e");
         _cancelMatch();
      }, onDone: () { 
         // Connection closed
      });
      
    } catch (e) {
      print("Connection failed: $e");
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
      MaterialPageRoute(builder: (context) => const FriendPlayScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("BATTLE ARENA", style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.softCharcoal, letterSpacing: 1.0)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.softCharcoal),
      ),
      body: Container(
         decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF0F5), Color(0xFFE0F7FA)] // Lavender blush to Cyan mist
            )
         ),
         child: Center(
           child: _isSearching ? _buildSearchingUI() : _buildSelectionUI(),
         ),
      ),
    );
  }

  Widget _buildSearchingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 160, height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: AppColors.secondaryPink.withOpacity(0.5), width: 6),
              boxShadow: [BoxShadow(color: AppColors.secondaryPink.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)]
            ),
            child: const Center(child: Icon(Icons.search_rounded, size: 80, color: AppColors.secondaryPink)),
          ),
        ),
        const SizedBox(height: 40),
        const Text("상대를 찾는 중...", style: TextStyle(color: AppColors.softCharcoal, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        const Text("잠시만 기다려주세요", style: TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 40),
        SizedBox(
          width: 140,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: const BorderSide(color: AppColors.danger, width: 1.5)),  
            ),
            onPressed: _cancelMatch,
            child: const Text("취소", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        )
      ],
    );
  }

  Widget _buildSelectionUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildModeCard(
          title: "랜덤 매칭", 
          subtitle: "전 세계의 친구들과 대결해보세요!",
          icon: Icons.public,
          color: AppColors.primaryMint, // Paste Mint
          onTap: _startRandomMatch
        ),
        const SizedBox(height: 24),
        _buildModeCard(
          title: "친구 대전", 
          subtitle: "친구와 함께 즐겨요!",
          icon: Icons.emoji_people_rounded,
          color: AppColors.secondaryPink, // Pastel Pink
          onTap: _onInviteFriend
        ),
      ],
    );
  }

  Widget _buildModeCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))]
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: AppColors.softCharcoal, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 18)
          ],
        ),
      ),
    );
  }
}
