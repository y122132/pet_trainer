import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'chat_screen.dart';
import '../services/auth_service.dart'; // [New]
import '../api_config.dart'; // [New]
import '../config/theme.dart'; // [New] style
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key}); // myId 파라미터 제거 (내부 조회)

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final _storage = const FlutterSecureStorage();
  List users = [];
  int? myId;
  String? myNickname;
  bool _isLoading = true;

  @override
  void initState() { 
    super.initState(); 
    _init(); 
  }

  Future<void> _init() async {
     try {
       // 1. 내 정보 가져오기
       final idStr = await _storage.read(key: 'user_id');
       // 닉네임은 저장하지 않았으므로 생략하거나 필요하면 저장 로직 추가 필요. 
       // 우선 ID만 확인.
       if (idStr != null) myId = int.parse(idStr);

       // 2. 유저 목록 가져오기
       await _fetchUsers();
     } catch (e) {
       print("Init Error: $e");
     } finally {
       if (mounted) setState(() => _isLoading = false);
     }
  }

  Future<void> _fetchUsers() async {
    // AppConfig.baseUrl 사용 (주의: /users 엔드포인트는 v1/auth/users에 위치)
    // 현재 v1/auth.py에 추가했으므로 경로는 /v1/auth/users 가 됨.
    final url = Uri.parse("${AppConfig.baseUrl}/auth/users"); 
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        // 한글 깨짐 방지
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() => users = data);
      } else {
        print("Fetch users failed: ${response.statusCode}");
      }
    } catch (e) {
      print("Fetch users error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("친구 선택", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.navy,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final userId = user['id'];
              final userNick = user['nickname'] ?? 'Unknown';
              
              if (userId == myId) return const SizedBox(); // 나 제외
              
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.cyberYellow.withOpacity(0.2),
                    child: const Icon(Icons.person, color: AppColors.navy),
                  ),
                  title: Text(userNick, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  trailing: const Icon(Icons.chat_bubble_outline, color: AppColors.navy),
                  onTap: () {
                    if (myId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("내 정보를 불러올 수 없습니다.")));
                      return;
                    }
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        myId: myId!,
                        toUserId: userId,
                        toUsername: userNick,
                      ),
                    ));
                  },
                ),
              );
            },
          ),
    );
  }
}