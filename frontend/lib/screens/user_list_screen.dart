import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'chat_screen.dart';
import '../services/auth_service.dart';
import '../api_config.dart';
import '../widgets/cute_avatar.dart';

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

  // 색상 상수
  static const Color creamBackground = Color(0xFFFFF9E6);
  static const Color darkBrown = Color(0xFF5D4037);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {}); // 탭 변경 시 UI 갱신
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
      debugPrint("Error fetching friends: $e");
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
    return Container(
      height: 100,
      margin: const EdgeInsets.only(top: 20, bottom: 10),
      decoration: BoxDecoration(
        color: darkBrown, // Solid dark brown background
        borderRadius: BorderRadius.circular(10), // Slightly rounded corners
      ),
      child: Center(
        child: Text(
          "친구 목록",
          style: GoogleFonts.jua(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white, // Text color changed to white for contrast
          ),
        ),
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
                    const CuteAvatar(petType: "dog", size: 40),
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
    return Container(
      height: 100, // 고정 높이
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: darkBrown.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 25.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CuteAvatar(petType: user['pet_type'] ?? 'dog', size: 50), // Fix: 크기 55->50
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['nickname'] ?? user['username'],
                    style: GoogleFonts.jua(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: darkBrown,
                    ),
                  ),
                  const SizedBox(height: 2), // Fix: 간격 4->2
                  Text(
                    "Lv.${user['level'] ?? 1} ${user['pet_type'] ?? 'Pet'}",
                    style: TextStyle(fontSize: 13, color: darkBrown.withOpacity(0.8)),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chat_bubble_rounded,
                  color: darkBrown, size: 30),
              onPressed: () => _goToChat(user),
            ),
          ],
        ),
      ),
    );
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
          const CuteAvatar(petType: "dog", size: 45),
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