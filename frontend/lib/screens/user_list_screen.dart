// frontend/lib/screens/user_list_screen.dart
import 'dart:convert';
import 'battle_page.dart';
import 'chat_screen.dart';
import '../api_config.dart';
import '../config/theme.dart';
import 'pet_universe_screen.dart';
import '../widgets/cute_avatar.dart';
import '../widgets/common/bone_widget.dart'; // Added
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../services/battle_service.dart';
import '../providers/chat_provider.dart';
import '../providers/battle_provider.dart';
import 'package:google_fonts/google_fonts.dart';

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

class _UserListScreenState extends State<UserListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  List<dynamic> _friends = [];
  List<dynamic> _searchResults = [];
  List<dynamic> _pendingRequests = [];
  
  bool _isLoading = false;
  int? _myId;
  String? _token;

  String _getTimeAgo(String? isoTimestamp) {
    if (isoTimestamp == null || isoTimestamp.isEmpty) return "접속 기록 없음";
    
    try {
      // 서버의 UTC 시간을 내 로컬 시간으로 변환
      String formattedTimestamp = isoTimestamp;
      if (!formattedTimestamp.endsWith('Z') && !formattedTimestamp.contains('+')) {
        formattedTimestamp += 'Z'; 
      }
      DateTime lastActive = DateTime.parse(isoTimestamp).toLocal();
      DateTime now = DateTime.now();
      Duration diff = now.difference(lastActive);

      if (diff.inMinutes < 1) return "방금 전";
      if (diff.inMinutes < 60) return "${diff.inMinutes}분 전";
      if (diff.inHours < 24) return "${diff.inHours}시간 전";
      if (diff.inDays < 7) return "${diff.inDays}일 전";
      
      // 일주일 이상 지나면 날짜 표시 (예: 1월 12일)
      return "${lastActive.month}월 ${lastActive.day}일";
    } catch (e) {
      debugPrint("Time Parsing Error: $e");
      return "기록 없음";
    }
  }

  // 색상 상수
  static const Color creamBackground = Color(0xFFFFF9E6);
  static const Color darkBrown = Color(0xFF5D4037);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
    _tabController.addListener(() {
      // Swipe support: Update UI whenever index changes
       if (!_tabController.indexIsChanging) {
         setState(() {}); 
       }
    });
    _loadMyInfo();
  }

  @override
  void dispose() {
    _tabController.removeListener(() {});
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

  // --- API Calls (기존 로직 유지) ---

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
      debugPrint("Error fetching pending requests: $e");
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
        final List<dynamic> allUsers =
            jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _searchResults = allUsers.where((u) => u['id'] != _myId).toList();
        });
      }
    } catch (e) {
      debugPrint("Error searching users: $e");
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

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      debugPrint("Error sending request: $e");
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
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("친구 요청을 수락했습니다.")));
        }
        _fetchPendingRequests();
        _fetchFriends();
      }
    } catch (e) {
      debugPrint("Error accepting request: $e");
    }
  }

  // 프로필 이미지를 생성
  Widget _buildProfileImage(dynamic user, double size) {
    final String? faceUrl = user['face_url'];
    
    final String fullImageUrl = (faceUrl != null && faceUrl.isNotEmpty)
        ? "${AppConfig.baseUrl.replaceFirst('/v1', '')}$faceUrl"
        : "";

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: darkBrown.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
        ],
      ),
      child: ClipOval(
        child: fullImageUrl.isNotEmpty
            ? Image.network(
                fullImageUrl,
                fit: BoxFit.cover,
                // 이미지 로드 실패 시 기본 아바타 표시
                errorBuilder: (context, error, stackTrace) => 
                    CuteAvatar(petType: user['pet_type'] ?? 'dog', size: size),
              )
            : CuteAvatar(petType: user['pet_type'] ?? 'dog', size: size),
      ),
    );
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
      backgroundColor: creamBackground,
      body: Stack(
        children: [
          // 1. 배경 패턴
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('assets/images/login_bg.png'),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                opacity: 0.3,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // 2. 상단 뼈다귀 타이틀
                _buildHeader(),
                // 3. 탭 메뉴
                _buildTabBar(),
                // 콘텐츠
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFriendsTab(),
                      _buildSearchTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 2. 상단 뼈다귀 타이틀 위젯
  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.only(top: 20, bottom: 10),
      child: BoneWidget(
        text: "친구 목록",
        fontSize: 28,
        paddingHorizontal: 50,
        paddingVertical: 15,
      ),
    );
  }

  // 3. 탭 메뉴 위젯
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Row(
        children: [
          Expanded(child: _buildTabItem(text: "내 친구", index: 0)),
          const SizedBox(width: 15),
          Expanded(child: _buildTabItem(text: "친구 찾기", index: 1)),
        ],
      ),
    );
  }

  Widget _buildTabItem({required String text, required int index}) {
    bool isActive = _tabController.index == index;
    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() {}); // 즉각적인 UI 반영
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? darkBrown : creamBackground,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: darkBrown, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: GoogleFonts.jua(
              fontSize: 18,
              color: isActive ? Colors.white : darkBrown,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendsTab() {
    bool hasFriends = _friends.isNotEmpty;
    bool hasRequests = _pendingRequests.isNotEmpty;

    if (!hasFriends && !hasRequests) {
      return Center(
          child: Text("아직 친구가 없어요!\n'친구 찾기' 탭에서 새로운 친구를 만나보세요.",
              textAlign: TextAlign.center,
              style: GoogleFonts.jua(fontSize: 16, color: Colors.grey[700])));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (hasRequests) _buildPendingRequests(),
        if (hasFriends)
          ..._friends.map((user) => _buildFriendCard(user)).toList(),
      ],
    );
  }

  Widget _buildPendingRequests() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0C7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8D5A3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "새로운 친구 요청 (${_pendingRequests.length})",
            style: GoogleFonts.jua(
                fontSize: 18,
                color: darkBrown,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ..._pendingRequests.map((user) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    _buildProfileImage(user, 40),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(user['nickname'] ?? user['username'],
                            style: const TextStyle(fontWeight: FontWeight.bold))),
                    TextButton(
                      onPressed: () => _acceptFriendRequest(user['id']),
                      style: TextButton.styleFrom(
                        backgroundColor: darkBrown,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text("수락"),
                    )
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // 4. 친구 목록 아이템 위젯
  Widget _buildFriendCard(dynamic user) {
    final int userId = user['id'];

    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        bool isOnline = chatProvider.onlineStatus[userId] ?? false;
        int unreadCount = chatProvider.unreadCounts[userId] ?? 0;

        return Container(
          height: 100,
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
                  _buildProfileImage(user, 55),
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
                            fontSize: 12,
                            color: isOnline ? Colors.green : Colors.grey,
                            fontWeight: isOnline ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (!isOnline) 
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              "(${_getTimeAgo(user['last_active_at'])})", 
                              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
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
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.home_filled, color: const Color(0xFF5D4037)),
                      onPressed: () => _goToPetUniverse(user),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.teal),
                      onPressed: () => _goToChat(user),
                    ),
                  ],
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

  void _goToPetUniverse(dynamic user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PetUniverseScreen(user: user),
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
     if (user['id'] == null) return;
     
     final battleService = BattleService();
     
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
       content: Text("${user['nickname']}님에게 도전장을 보내는 중..."),
       duration: const Duration(seconds: 1),
     ));
     
     final roomId = await battleService.sendInvite(user['id']);
     
     if (roomId != null && mounted) {
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: darkBrown),
            decoration: InputDecoration(
              hintText: "유저 닉네임 검색...",
              hintStyle: TextStyle(color: darkBrown.withOpacity(0.7)),
              prefixIcon: const Icon(Icons.search, color: darkBrown),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: darkBrown),
                onPressed: () => _searchController.clear(),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: const BorderSide(color: darkBrown, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: const BorderSide(color: darkBrown, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: const BorderSide(color: darkBrown, width: 3),
              ),
            ),
            onSubmitted: _searchUsers,
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: darkBrown))
              : _searchResults.isEmpty
                  ? Center(
                      child: Text("검색 결과가 없습니다.",
                          style: GoogleFonts.jua(
                              fontSize: 16, color: Colors.grey[700])))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, i) {
                        final user = _searchResults[i];
                        bool isFriend =
                            _friends.any((f) => f['id'] == user['id']);
                        return _buildSearchItem(user, isFriend);
                      },
                    ),
        ),
      ],
    );
  }
  
  Widget _buildSearchItem(dynamic user, bool isFriend) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: darkBrown.withOpacity(0.5))
      ),
      child: Row(
        children: [
          _buildProfileImage(user, 45),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['nickname'] ?? user['username'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("@${user['username']}", style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ),
          isFriend
              ? Text("친구", style: GoogleFonts.jua(color: Colors.green, fontSize: 16))
              : IconButton(
                  icon: const Icon(Icons.person_add, color: darkBrown),
                  onPressed: () => _sendFriendRequest(user['id']),
                ),
        ],
      ),
    );
  }

}