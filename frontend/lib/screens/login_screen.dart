import 'package:flutter/material.dart';
import 'package:pet_trainer_frontend/screens/menu_page.dart';
// import 'package:pet_trainer_frontend/widgets/common/custom_text_field.dart'; // File missing
// import 'package:pet_trainer_frontend/logic/login_logic.dart'; // File missing
import 'package:pet_trainer_frontend/screens/user_register_screen.dart'; 
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/config/design_system.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart';
import 'package:pet_trainer_frontend/models/user_model.dart';
import 'package:google_fonts/google_fonts.dart'; // Added
import 'creation_name_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final AuthService _authService = AuthService();
  
  late AnimationController _logoController;
  late Animation<double> _logoScaleAnimation;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _logoScaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );
  }

  void _handleLogin() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "아이디와 비밀번호를 입력해주세요.",
            style: GoogleFonts.jua(color: Colors.white, fontSize: 16),
          ),
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          MaterialPageRoute(builder: (context) => const CreationNameScreen()),
        );
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "로그인에 실패했습니다. 아이디/비밀번호를 다시 확인하시거나 서버 연결 상태를 점검해주세요.",
            style: GoogleFonts.jua(color: Colors.white, fontSize: 14),
          ),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
        ),
      );
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
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
                ScaleTransition(
                  scale: _logoScaleAnimation,
                  child: Image.asset(
                    'assets/images/독고 표지 이름.png',
                    width: MediaQuery.of(context).size.width * 0.7,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  "반갑습니다!",
                  style: GoogleFonts.jua(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMain,
                    shadows: [
                      Shadow(
                        color: AppColors.primary.withOpacity(0.1),
                        offset: const Offset(2, 2),
                        blurRadius: 4,
                      )
                    ]
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
        color: Colors.white,
        boxShadow: AppDecorations.softShadow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: GoogleFonts.jua(color: AppColors.textMain, fontSize: 16),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.jua(color: AppColors.textSub),
          prefixIcon: Icon(icon, color: AppColors.textMain),
          filled: true,
          fillColor: Colors.transparent, // Container has color
          contentPadding: const EdgeInsets.symmetric(vertical: 22, horizontal: 25),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: AppColors.primary, width: 2.0),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: AppDecorations.floatShadow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: ElevatedButton(
        onPressed: _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
        ),
        child: Text("로그인", style: GoogleFonts.jua(fontSize: 22, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildRegisterButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "계정이 없으신가요?",
          style: GoogleFonts.jua(color: AppColors.textSub, fontSize: 14),
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
            style: GoogleFonts.jua(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}