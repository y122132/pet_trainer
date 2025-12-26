import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'user_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 1. 변수 선언 (이 부분이 클래스 바로 안에 있어야 합니다)
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final AuthService _authService = AuthService();

  // 2. 로그인 로직 함수
  void _handleLogin() async {
    final result = await _authService.login(
      _userController.text,
      _passController.text,
    );

    if (result != null) {
      if (!mounted) return;
      // 로그인 성공 시 유저 목록 화면으로 이동
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => UserListScreen(myId: result['user_id']),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("로그인 실패! 아이디와 비밀번호를 확인하세요.")),
      );
    }
  }

  // 3. UI 빌드 메서드 (반드시 @override가 필요하고 클래스 내부에 있어야 함)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pet Trainer 로그인")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "반갑습니다!",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _userController,
              decoration: const InputDecoration(
                labelText: "아이디 (Username)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passController,
              decoration: const InputDecoration(
                labelText: "비밀번호 (Password)",
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: _handleLogin,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text("로그인"),
            ),
            const SizedBox(height: 15),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                );
              },
              child: const Text("계정이 없으신가요? 회원가입 하러가기"),
            ),
          ],
        ),
      ),
    );
  }
}