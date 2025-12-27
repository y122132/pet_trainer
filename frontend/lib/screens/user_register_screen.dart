import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _nickController = TextEditingController();
  
  bool _isLoading = false;
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _nickController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty || _nickController.text.isEmpty) {
      _showError("모든 필드를 입력해주세요.");
      return;
    }

    setState(() => _isLoading = true);

    // AuthService를 이용한 회원가입 요청
    final result = await _authService.register(
      _userController.text, 
      _passController.text, 
      _nickController.text
    );

    if (!mounted) return;

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("회원가입 성공! 로그인해주세요.")),
      );
      Navigator.pop(context); 
    } else {
      _showError(result['message'] ?? "가입 실패");
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PetTrainer 회원가입")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            TextField(
              controller: _userController, 
              decoration: const InputDecoration(
                labelText: "아이디 (Username)",
                border: OutlineInputBorder(),
              )
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _nickController, 
              decoration: const InputDecoration(
                labelText: "닉네임 (Nickname)",
                border: OutlineInputBorder(),
              )
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
            const SizedBox(height: 30),
            _isLoading 
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  onPressed: _register, 
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                  child: const Text("가입하기", style: TextStyle(fontSize: 18)),
                ),
          ],
        ),
      ),
    );
  }
}