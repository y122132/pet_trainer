import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../api_config.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/battle_service.dart';
import '../providers/chat_provider.dart';
import '../providers/battle_provider.dart';
import '../widgets/cute_avatar.dart';
import 'battle_page.dart';

class FriendPlayScreen extends StatefulWidget {
  const FriendPlayScreen({super.key});

  @override
  State<FriendPlayScreen> createState() => _FriendPlayScreenState();
}

class _FriendPlayScreenState extends State<FriendPlayScreen> {
  List<dynamic> _friends = []; // 친구 목록 데이터를 담을 리스트
  bool _isLoading = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadFriends(); // 화면 시작 시 친구 목록 로드
  }

  Future<void> _loadFriends() async {
    setState(() => _isLoading = true);
    final auth = AuthService();
    _token = await auth.getToken();
    
    if (_token != null) {
      try {
        final response = await http.get(
          Uri.parse('${AppConfig.baseUrl}/auth/friends'),
          headers: {"Authorization": "Bearer $_token"},
        );
        if (response.statusCode == 200) {
          setState(() {
            _friends = jsonDecode(utf8.decode(response.bodyBytes));
          });
        }
      } catch (e) {
        debugPrint("친구 목록 로드 실패: $e");
      }
    }
    setState(() => _isLoading = false);
  }
  // --- 초대 버튼 클릭 시 처리 함수 ---
  void _handleInvite(dynamic friend) async {
    final battleService = BattleService();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${friend['nickname']}님에게 도전장을 보냅니다!"))
    );

    // 서버에 초대 API 호출하여 방 ID(roomId)를 받아옴 (비동기 대기)
    final roomId = await battleService.sendInvite(friend['id']);
    
    if (roomId != null && mounted) {
      debugPrint("방 생성 성공! ID: $roomId. 이동을 시작합니다.");
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context){
            return ChangeNotifierProvider(
              create: (_) => BattleProvider()..setRoomId(roomId),
              child: const BattlePage(),
            );
          }
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("함께 놀 친구 선택", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.softCharcoal)),
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppColors.softCharcoal),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _friends.isEmpty 
          ? const Center(child: Text("대전 가능한 친구가 없어요."))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _friends.length,
              itemBuilder: (context, index) {
                final friend = _friends[index];
                return _buildFriendInviteCard(friend);
              },
            ),
    );
  }

  Widget _buildFriendInviteCard(dynamic friend) {
    // 온라인 상태 확인 로직 (ChatProvider 활용)
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        bool isOnline = chat.onlineStatus[friend['id']] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isOnline ? Colors.white : Colors.grey[50],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isOnline ? AppColors.primaryMint.withOpacity(0.3) : Colors.transparent),
            boxShadow: [
              if (isOnline) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            children: [
              CuteAvatar(petType: friend['pet_type'] ?? 'dog', size: 50),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(friend['nickname'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(isOnline ? "지금 접속 중" : "오프라인", 
                      style: TextStyle(color: isOnline ? Colors.green : Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: isOnline ? () => _handleInvite(friend) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryPink,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text("도전장"),
              ),
            ],
          ),
        );
      },
    );
  }
}