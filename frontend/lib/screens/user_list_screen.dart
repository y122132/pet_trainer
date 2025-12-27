import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'chat_screen.dart';
import '../services/auth_service.dart';
import '../api_config.dart';
import '../services/chat_service.dart'; // import if needed, or use http direct
import '../config/theme.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  List<dynamic> _friends = [];
  List<dynamic> _searchResults = []; // Users from search
  List<dynamic> _pendingRequests = []; // Requests I received
  
  bool _isLoading = false;
  int? _myId;
  String? _token;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    final idStr = await auth.getUserId(); // getUserId needs to be public in AuthService or use storage

    if (token != null && idStr != null) {
      setState(() {
        _token = token;
        _myId = int.parse(idStr);
      });
      _fetchFriends();
      _fetchPendingRequests();
    }
  }

  // --- API Calls ---

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
      print("Error fetching friends: $e");
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

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("FRIENDS", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.cyberYellow,
          labelColor: AppColors.cyberYellow,
          unselectedLabelColor: Colors.white70,
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
        // Pending Requests Section (if any)
        if (_pendingRequests.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.orangeAccent.withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text("받은 친구 요청 (${_pendingRequests.length})", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _pendingRequests.length,
            itemBuilder: (context, i) {
               final user = _pendingRequests[i];
               return ListTile(
                 leading: CircleAvatar(backgroundColor: Colors.grey[300], child: const Icon(Icons.person)),
                 title: Text(user['nickname'] ?? user['username']),
                 trailing: ElevatedButton(
                   onPressed: () => _acceptFriendRequest(user['id']),
                   child: const Text("수락"),
                   style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                 ),
               );
            },
          ),
          const Divider(),
        ],
        // Friends List
        Expanded(
          child: _friends.isEmpty 
            ? const Center(child: Text("친구가 없습니다. 친구를 찾아보세요!"))
            : ListView.separated(
                itemCount: _friends.length,
                separatorBuilder: (c, i) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final user = _friends[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.cyberYellow,
                      child: Text(user['nickname'][0].toUpperCase(), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(user['nickname'] ?? user['username'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Level 5 • Dog Trainer"), // Dummy data for UI
                    trailing: const Icon(Icons.chat_bubble_outline, color: AppColors.navy),
                    onTap: () {
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
                    },
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildSearchTab() {
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
                     // Check if already friend (simple UI check, better to have server flag)
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