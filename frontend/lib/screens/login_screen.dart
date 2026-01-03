import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import 'user_register_screen.dart';
import 'menu_page.dart';
import 'creation_name_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final AuthService _authService = AuthService();

  // --- 색상 상수 ---
  static const Color kBgColor = Color(0xFFFFF9E6);
  static const Color kBrown = Color(0xFF4E342E);
  static const Color kLightBrown = Color(0xFF8D6E63);
  static const Color kDarkBrown = Color(0xFF5D4037);

  void _handleLogin() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "아이디와 비밀번호를 입력해주세요.",
            style: GoogleFonts.jua(),
          ),
          backgroundColor: kDarkBrown,
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
          MaterialPageRoute(builder: (context) => const CreationNameScreen()),
        );
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "로그인 실패! 아이디와 비밀번호를 확인하세요.",
            style: GoogleFonts.jua(),
          ),
          backgroundColor: Colors.redAccent,
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
      body: Container(
        // 1. 배경 설정
        decoration: const BoxDecoration(
          color: kBgColor, // 이미지 없을 경우 대체 색상
          image: DecorationImage(
            image: AssetImage('assets/images/login_bg.png'),
            fit: BoxFit.cover,
            // 이미지가 어두울 경우를 대비한 투명도
            colorFilter: ColorFilter.mode(Colors.black26, BlendMode.darken)
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 로고 (기존 에셋 활용)
                Image.asset(
                  'assets/images/독고 표지 이름.png',
                  width: MediaQuery.of(context).size.width * 0.7,
                ),
                const SizedBox(height: 20),
                Text(
                  "반갑습니다!",
                  style: GoogleFonts.jua(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                     shadows: [
                      const Shadow(
                        blurRadius: 4.0,
                        color: kBrown,
                        offset: Offset(2.0, 2.0),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                // 아이디 입력창
                _buildTextField(
                  controller: _userController,
                  hintText: '아이디',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 15),
                // 비밀번호 입력창
                _buildTextField(
                  controller: _passController,
                  hintText: '비밀번호',
                  icon: Icons.lock_outline,
                  obscureText: true,
                ),
                const SizedBox(height: 40),
                // 로그인 버튼
                _buildLoginButton(),
                const SizedBox(height: 20),
                _buildRegisterButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 3. 입력창 위젯
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: GoogleFonts.jua(color: kBrown),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.jua(color: kLightBrown),
        prefixIcon: Icon(icon, color: kLightBrown),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 25),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: kLightBrown, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: kLightBrown, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: kDarkBrown, width: 2.5),
        ),
      ),
    );
  }

  // 4. 로그인 버튼 위젯
  Widget _buildLoginButton() {
    return ElevatedButton(
      onPressed: _handleLogin,
      style: ElevatedButton.styleFrom(
        backgroundColor: kDarkBrown,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        elevation: 5,
      ),
      child: Text(
        "로그인",
        style: GoogleFonts.jua(fontSize: 22, fontWeight: FontWeight.bold),
      ),
    );
  }

  // 회원가입 버튼 위젯
  Widget _buildRegisterButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("계정이 없으신가요?", style: GoogleFonts.jua(color: Colors.white, shadows: [const Shadow(blurRadius: 2.0, color: kBrown,)])),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RegisterScreen()),
            );
          },
          child: Text(
            "회원가입",
            style: GoogleFonts.jua(
              fontWeight: FontWeight.bold,
              color: kBgColor,
              shadows: [const Shadow(blurRadius: 2.0, color: kDarkBrown,)]
            ),
          ),
        ),
      ],
    );
  }
}