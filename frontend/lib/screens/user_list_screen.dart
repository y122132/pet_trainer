// frontend/lib/screens/user_list_screen.dart
import 'dart:convert';
import 'battle_page.dart';
import 'chat_screen.dart';
import '../api_config.dart';
import '../config/theme.dart';
import '../widgets/cute_avatar.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../services/battle_service.dart';
import '../providers/chat_provider.dart';
import '../providers/battle_provider.dart';

class UserListScreen extends StatefulWidget {
  final int initialTab;
  final bool isInviteMode;
  
  const UserListScreen({
    super.key, 
    this.initialTab = 0,
    this.isInviteMode = false,
  });

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  List<dynamic> _friends = [];
  List<dynamic> _searchResults = [];
  List<dynamic> _pendingRequests = [];
  
  bool _isLoading = false;
  int? _myId;
  String? _token;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _loadMyInfo();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMyInfo() async {
    final auth = AuthService();
    final token = await auth.getToken();
    final idStr = await auth.getUserId();

    if (token != null && idStr != null) {
      setState(() {
        _token = token;
        _myId = int.parse(idStr);
      });
      _fetchFriends();
      _fetchPendingRequests();
    }
  }

  Future<void> _fetchFriends() async {
    if (_token == null) return;
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/auth/friends'),
        headers: {"Authorization": "Bearer $_token"},
      );
      if (response.statusCode == 200) {
        setState(() {
          _friends = jsonDecode(utf8.decode(response.bodyBytes));
        });
        if (mounted) {
           Provider.of<ChatProvider>(context, listen: false).setInitialUnreadCounts(_friends);
        }
      }
    } catch (e) {
      debugPrint("Error fetching friends: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("친구 목록 로드 실패: $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchPendingRequests() async {
     if (_token == null) return;
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/auth/friends/pending'),
        headers: {"Authorization": "Bearer $_token"},
      );
      if (response.statusCode == 200) {
        setState(() {
          _pendingRequests = jsonDecode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      print("Error fetching pending requests: $e");
    }
  }
  
  Future<void> _searchUsers(String query) async {
    if (_token == null || query.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/auth/users?query=$query'),
        headers: {"Authorization": "Bearer $_token"},
      );
      if (response.statusCode == 200) {
        final List<dynamic> allUsers = jsonDecode(utf8.decode(response.bodyBytes));
        // Filter out myself
        setState(() {
          _searchResults = allUsers.where((u) => u['id'] != _myId).toList();
        });
      }
    } catch (e) {
      print("Error searching users: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendFriendRequest(int friendId) async {
    if (_token == null) return;
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/auth/friends/request/$friendId'),
        headers: {"Authorization": "Bearer $_token"},
      );
      
      final msg = response.statusCode == 200 
          ? "친구 요청을 보냈습니다." 
          : "요청 실패: ${utf8.decode(response.bodyBytes)}";
          
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      print("Error sending request: $e");
    }
  }

  Future<void> _acceptFriendRequest(int friendId) async {
    if (_token == null) return;
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/auth/friends/accept/$friendId'),
        headers: {"Authorization": "Bearer $_token"},
      );
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("친구 요청을 수락했습니다.")));
        _fetchPendingRequests(); // Refresh lists
        _fetchFriends();
      }
    } catch (e) {
      print("Error accepting request: $e");
    }
  }

  // --- ACTIONS ---

  void _onChallengeFriend(int friendId, String nickname) async {
    // 1. Send Invite via API
    // 2. Get Room ID
    // 3. Go to Battle Page (Waiting)
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.isInviteMode ? "친구랑 놀기" : "친구 목록"),
        // backgroundColor: Transparent by theme
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.secondaryPink,
          labelColor: AppColors.softCharcoal,
          unselectedLabelColor: Colors.grey,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
             Tab(text: "내 친구"),
             Tab(text: "친구 찾기"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsTab(),
          _buildSearchTab(),
        ],
      ),
    );
  }

  Widget _buildFriendsTab() {
    return Column(
      children: [
        // Pending Requests
        if (_pendingRequests.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accentYellow.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mail_outline, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text("새로운 친구 요청 (${_pendingRequests.length})", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ],
                ),
                const SizedBox(height: 8),
                ..._pendingRequests.map((user) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      CuteAvatar(petType: "dog", size: 40), // Placeholder type since we might not have it
                      const SizedBox(width: 12),
                      Expanded(child: Text(user['nickname'] ?? user['username'], style: const TextStyle(fontWeight: FontWeight.bold))),
                      TextButton(
                        onPressed: () => _acceptFriendRequest(user['id']),
                        style: TextButton.styleFrom(backgroundColor: AppColors.primaryMint, foregroundColor: AppColors.softCharcoal),
                        child: const Text("수락"),
                      )
                    ],
                  ),
                )).toList()
              ],
            ),
          ),
        ],
        // Friend List
        Expanded(
          child: _friends.isEmpty 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                     const Icon(Icons.pets, size: 60, color: AppColors.neutral),
                     const SizedBox(height: 16),
                     const Text("아직 친구가 없어요!\n'친구 찾기' 탭에서 새로운 친구를 만나보세요.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  ],
                )
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _friends.length,
                itemBuilder: (context, i) {
                  final user = _friends[i];
                  return _buildFriendCard(user);
                },
              ),
        ),
      ],
    );
  }

  Widget _buildFriendCard(dynamic user) {
    final int userId = user['id'];

    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        bool isOnline = chatProvider.onlineStatus[userId] ?? false;
        int unreadCount = chatProvider.unreadCounts[userId] ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryMint.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              // 1. 아바타와 상태 표시 점 (Stack 사용)
              Stack(
                children: [
                  CuteAvatar(petType: user['pet_type'] ?? 'dog', size: 55),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.grey, // 온라인: 초록, 오프라인: 회색
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2), // 경계선 추가
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              
              // 2. 유저 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user['nickname'] ?? user['username'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold, 
                              fontSize: 16,
                              overflow: TextOverflow.ellipsis,
                            ),
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 상태 텍스트 표시
                        Text(
                          isOnline ? "접속 중" : "오프라인",
                          style: TextStyle(
                            fontSize: 11,
                            color: isOnline ? Colors.green : Colors.grey,
                          ),
                        ),
                        const Spacer(),
                                                
                        Consumer<ChatProvider>(
                          builder: (context, chat, _) {
                            int count = chat.unreadCounts[user['id']] ?? 0;
                            if (count == 0) return const SizedBox.shrink();
                            
                            return Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.3), 
                                    blurRadius: 4,
                                    offset: const Offset(0, 2)
                                  )
                                ],
                              ),
                              child: Text(
                                count > 99 ? "99+" : "$count",
                                style: const TextStyle(
                                  color: Colors.white, 
                                  fontSize: 10, 
                                  fontWeight: FontWeight.w900
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.neutral.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "Lv.${user['level'] ?? 1} ${user['pet_type'] ?? 'Pet'}",
                        style: const TextStyle(fontSize: 12, color: AppColors.softCharcoal),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. 액션 버튼 (인바이트 모드 여부에 따라)
              if (widget.isInviteMode)
                _buildActionButton(
                  label: "같이 놀자!",
                  icon: Icons.gamepad,
                  // 오프라인이면 버튼 색상을 회색으로 변경
                  color: isOnline ? AppColors.secondaryPink : Colors.grey,
                  onTap: isOnline 
                    ? () => _handleChallenge(user) 
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("현재 오프라인인 친구에게는 요청을 보낼 수 없습니다."))
                        );
                      },
                )
              else
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primaryMint),
                  onPressed: () => _goToChat(user),
                ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildActionButton({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))]
        ),
        child: Row(
           children: [
             Icon(icon, color: Colors.white, size: 16),
             const SizedBox(width: 4),
             Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
           ],
        ),
      ),
    );
  }

  void _goToChat(dynamic user) {
     Navigator.push(
       context,
       MaterialPageRoute(
         builder: (context) => ChatScreen(
           myId: _myId!,
           toUserId: user['id'],
           toUsername: user['nickname'] ?? user['username'],
         ),
       ),
     );
  }

  void _handleChallenge(dynamic user) async {
     // [Implementation]
     if (user['id'] == null) return;
     
     final battleService = BattleService();
     
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
       content: Text("${user['nickname']}님에게 도전장을 보내는 중..."),
       duration: const Duration(seconds: 1),
     ));
     
     final roomId = await battleService.sendInvite(user['id']);
     
     if (roomId != null && mounted) {
       // Navigate to Battle Page (Waiting Mode)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChangeNotifierProvider(
              create: (_) => BattleProvider()..setRoomId(roomId), 
              child: const BattleView(),
            ),
          ),
        );
     } else {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("초대 실패")));
     }
  }

  Widget _buildSearchTab() {
     // ... (unchanged)
     return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "유저 닉네임 검색...",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () { _searchController.clear(); },
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
            ),
            onSubmitted: _searchUsers,
          ),
        ),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _searchResults.isEmpty 
               ? const Center(child: Text("검색 결과가 없습니다."))
               : ListView.builder(
                   itemCount: _searchResults.length,
                   itemBuilder: (context, i) {
                     final user = _searchResults[i];
                     bool isFriend = _friends.any((f) => f['id'] == user['id']);
                     
                     return ListTile(
                       leading: CircleAvatar(backgroundColor: Colors.grey[200], child: const Icon(Icons.person)),
                       title: Text(user['nickname'] ?? user['username']),
                       subtitle: Text("@${user['username']}"),
                       trailing: isFriend 
                         ? const Text("이미 친구", style: TextStyle(color: Colors.green))
                         : IconButton(
                             icon: const Icon(Icons.person_add, color: AppColors.navy),
                             onPressed: () => _sendFriendRequest(user['id']),
                           ),
                     );
                   },
                 ),
        ),
      ],
    );
  }
}