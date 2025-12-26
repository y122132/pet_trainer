import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'chat_screen.dart';

class UserListScreen extends StatefulWidget {
  final int myId;
  const UserListScreen({super.key, required this.myId});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  List users = [];

  Future<void> _fetchUsers() async {
    final response = await http.get(Uri.parse('http://localhost:8000/api/v1/auth/users'));
    if (response.statusCode == 200) {
      setState(() => users = jsonDecode(response.body));
    }
  }

  @override
  void initState() { super.initState(); _fetchUsers(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("대화 상대 선택")),
      body: ListView.builder(
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          if (user['id'] == widget.myId) return const SizedBox(); // 나 제외
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(user['nickname']), // 닉네임 표시
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (context) => ChatScreen(
                myId: widget.myId,
                toUserId: user['id'],
                toUsername: user['nickname'],
              ),
            )),
          );
        },
      ),
    );
  }
}