import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pet_trainer_frontend/config/theme.dart';
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
      MaterialPageRoute(builder: (context) => const UserListScreen(initialTab: 0, isInviteMode: true)), 
    );
    // ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("친구와 채팅방에서 '초대'를 보내보세요! (기능 준비중)")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("BATTLE ARENA", style: TextStyle(fontFamily: 'Orbitron', fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
         decoration: const BoxDecoration(
            image: DecorationImage(image: AssetImage('assets/images/cyber_city_bg.jpg'), fit: BoxFit.cover, opacity: 0.3)
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
            width: 150, height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.cyanAccent, width: 4),
              boxShadow: [BoxShadow(color: Colors.cyan.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)]
            ),
            child: const Center(child: Icon(Icons.radar, size: 80, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 30),
        const Text("SEARCHING...", style: TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        SizedBox(
          width: 120,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),  
            ),
            onPressed: _cancelMatch,
            child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold)),
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
          title: "RANDOM MATCH", 
          subtitle: "Find a worthy opponent worldwide",
          icon: Icons.public,
          color: Colors.cyan,
          onTap: _startRandomMatch
        ),
        const SizedBox(height: 30),
        _buildModeCard(
          title: "FRIEND DUEL", 
          subtitle: "Challenge your friends",
          icon: Icons.people_alt,
          color: Colors.purpleAccent,
          onTap: _onInviteFriend
        ),
      ],
    );
  }

  Widget _buildModeCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 15)]
        ),
        child: Row(
          children: [
            Icon(icon, size: 50, color: color),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16)
          ],
        ),
      ),
    );
  }
}
