import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _userController = TextEditingController(); // 아이디
  final _passController = TextEditingController(); // 비밀번호
  final _nickController = TextEditingController(); // 닉네임 (추가됨)

  Future<void> _register() async {
    // 웹 환경이므로 localhost 사용
    final url = Uri.parse('http://localhost:8000/api/v1/auth/register');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": _userController.text,
          "password": _passController.text,
          "nickname": _nickController.text, // 닉네임 포함
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("회원가입 성공! 로그인해주세요.")),
        );
        Navigator.pop(context); // 가입 성공 후 로그인 화면으로 이동
      } else {
        final errorData = jsonDecode(response.body);
        _showError("가입 실패: ${errorData['detail']}");
      }
    } catch (e) {
      _showError("서버 연결 실패. 서버가 켜져 있는지 확인하세요.");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PetTrainer 회원가입")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _userController, 
              decoration: const InputDecoration(labelText: "아이디 (Username)")
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nickController, 
              decoration: const InputDecoration(labelText: "닉네임 (Nickname)")
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passController, 
              decoration: const InputDecoration(labelText: "비밀번호 (Password)"),
              obscureText: true,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _register, 
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: const Text("가입하기"),
            ),
          ],
        ),
      ),
    );
  }
}