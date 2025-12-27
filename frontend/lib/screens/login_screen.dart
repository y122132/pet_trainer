import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart'; // UserModel 인식을 위해 추가
import 'register_screen.dart';
import 'menu_page.dart'; // 로그인 성공 시 이동할 페이지
import 'simple_char_create_page.dart'; // [New] 캐릭터 생성 페이지

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 1. 컨트롤러 및 서비스 선언
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final AuthService _authService = AuthService();

  // 2. 로그인 로직 함수
  void _handleLogin() async {
    // 공백 체크 (기본적인 방어 코드)
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("아이디와 비밀번호를 입력해주세요.")),
      );
      return;
    }

    // AuthService.login은 이제 리팩토링되어 UserModel? 객체를 반환합니다.
    final UserModel? user = await _authService.login(
      _userController.text,
      _passController.text,
    );

    if (user != null) {
      if (!mounted) return;
      
      // 로그인 성공 시 정보 표시 (디버깅용)
      print("[AUTH] ${user.nickname}님 환영합니다. (ID: ${user.id}, Char: ${user.hasCharacter})");

      // [핵심] 캐릭터 존재 여부에 따라 분기
      if (user.hasCharacter) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MenuPage()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SimpleCharCreatePage()),
        );
      }
    } else {
      if (!mounted) return;
      // 로그인 실패 시 에러 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("로그인 실패! 아이디와 비밀번호를 확인하세요.")),
      );
    }
  }

  // 3. UI 빌드 메서드
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pet Trainer 로그인"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView( // 키보드 올라올 때 가려짐 방지
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 50),
              const Text(
                "반갑습니다!",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "반려동물 훈련을 시작하기 위해 로그인하세요.",
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: "아이디 (Username)",
                  hintText: "아이디를 입력하세요",
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passController,
                decoration: const InputDecoration(
                  labelText: "비밀번호 (Password)",
                  hintText: "비밀번호를 입력하세요",
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _handleLogin,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  "로그인",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("계정이 없으신가요?"),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegisterScreen()),
                      );
                    },
                    child: const Text(
                      "회원가입 하러가기",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // 컨트롤러 해제
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }
}