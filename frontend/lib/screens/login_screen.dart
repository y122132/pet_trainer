import 'package:flutter/material.dart';
import '../config/design_system.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import 'user_register_screen.dart';
import 'menu_page.dart';
import 'simple_char_create_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final AuthService _authService = AuthService();

  void _handleLogin() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "아이디와 비밀번호를 입력해주세요.",
            style: AppTextStyles.button,
          ),
          backgroundColor: AppColors.primaryBrown,
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
        ),
      );
      return;
    }

    final UserModel? user = await _authService.login(
      _userController.text,
      _passController.text,
    );

    if (user != null) {
      if (!mounted) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "로그인 실패! 아이디와 비밀번호를 확인하세요.",
            style: AppTextStyles.button,
          ),
          backgroundColor: Colors.redAccent,
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
        ),
      );
    }
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ThemedBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/독고 표지 이름.png',
                  width: MediaQuery.of(context).size.width * 0.7,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(height: 30),
                Text(
                  "반갑습니다!",
                  style: AppTextStyles.title.copyWith(
                    color: AppColors.primaryBrown,
                    shadows: AppDecorations.cardShadow,
                  ),
                ),
                const SizedBox(height: 60),
                _buildTextField(
                  controller: _userController,
                  hintText: '아이디',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 24),
                _buildTextField(
                  controller: _passController,
                  hintText: '비밀번호',
                  icon: Icons.lock_outline,
                  obscureText: true,
                ),
                const SizedBox(height: 60),
                _buildLoginButton(),
                const SizedBox(height: 24),
                _buildRegisterButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: AppDecorations.cardShadow,
        borderRadius: AppDecorations.cardRadius,
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: AppTextStyles.base,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTextStyles.body,
          prefixIcon: Icon(icon, color: AppColors.secondaryBrown),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 22, horizontal: 25),
          border: OutlineInputBorder(
            borderRadius: AppDecorations.cardRadius,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppDecorations.cardRadius,
            borderSide: const BorderSide(color: AppColors.primaryBrown, width: 2.5),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: AppDecorations.cardShadow,
        borderRadius: AppDecorations.cardRadius,
      ),
      child: ElevatedButton(
        onPressed: _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBrown,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
          elevation: 0,
        ),
        child: Text("로그인", style: AppTextStyles.button.copyWith(fontSize: 22)),
      ),
    );
  }

  Widget _buildRegisterButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "계정이 없으신가요?",
          style: AppTextStyles.body.copyWith(color: AppColors.secondaryBrown),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RegisterScreen()),
            );
          },
          child: Text(
            "회원가입",
            style: AppTextStyles.base.copyWith(
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}