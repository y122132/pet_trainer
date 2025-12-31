import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  // --- 색상 상수 (LoginPage와 동일) ---
  static const Color kBgColor = Color(0xFFFFF9E6);
  static const Color kBrown = Color(0xFF4E342E);
  static const Color kLightBrown = Color(0xFF8D6E63);
  static const Color kDarkBrown = Color(0xFF5D4037);

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _nickController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_userController.text.isEmpty ||
        _passController.text.isEmpty ||
        _nickController.text.isEmpty) {
      _showError("모든 필드를 입력해주세요.");
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.register(
      _userController.text,
      _passController.text,
      _nickController.text,
    );

    if (!mounted) return;

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("회원가입 성공! 로그인해주세요.", style: GoogleFonts.jua()),
            backgroundColor: kDarkBrown),
      );
      Navigator.pop(context);
    } else {
      _showError(result['message'] ?? "가입 실패");
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.jua()),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: kBgColor,
          image: DecorationImage(
            image: AssetImage('assets/images/login_bg.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black26, BlendMode.darken),
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/독고 표지 이름.png',
                  width: MediaQuery.of(context).size.width * 0.6,
                ),
                const SizedBox(height: 10),
                Text(
                  "새로운 트레이너 등록",
                  style: GoogleFonts.jua(
                    fontSize: 28,
                    color: Colors.white,
                    shadows: [
                      const Shadow(
                          blurRadius: 4.0, color: kBrown, offset: Offset(2.0, 2.0)),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                _buildTextField(
                    controller: _userController,
                    hintText: '아이디',
                    icon: Icons.person_outline),
                const SizedBox(height: 15),
                _buildTextField(
                    controller: _nickController,
                    hintText: '닉네임',
                    icon: Icons.face_retouching_natural),
                const SizedBox(height: 15),
                _buildTextField(
                    controller: _passController,
                    hintText: '비밀번호',
                    icon: Icons.lock_outline,
                    obscureText: true),
                const SizedBox(height: 30),
                _buildSubmitButton(),
                _buildBackButton(),
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

  Widget _buildSubmitButton() {
    return _isLoading
        ? const CircularProgressIndicator(color: Colors.white)
        : ElevatedButton(
            onPressed: _register,
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
              "가입하기",
              style: GoogleFonts.jua(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          );
  }

  Widget _buildBackButton() {
    return TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(
        "로그인 화면으로 돌아가기",
        style: GoogleFonts.jua(
          color: kBgColor,
          shadows: [const Shadow(blurRadius: 2.0, color: kDarkBrown)],
        ),
      ),
    );
  }
}