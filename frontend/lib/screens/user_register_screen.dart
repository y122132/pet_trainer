import 'package:flutter/material.dart';
import '../config/design_system.dart';
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
            content: Text("회원가입 성공! 로그인해주세요.", style: AppTextStyles.button),
            backgroundColor: AppColors.primaryBrown,
            shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(20),
        ),
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
        content: Text(msg, style: AppTextStyles.button),
        backgroundColor: Colors.redAccent,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.primaryBrown),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: ThemedBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "새로운 트레이너 등록",
                  style: AppTextStyles.title.copyWith(
                    color: AppColors.primaryBrown,
                    shadows: AppDecorations.cardShadow,
                  ),
                ),
                const SizedBox(height: 60),
                _buildTextField(
                    controller: _userController,
                    hintText: '아이디',
                    icon: Icons.person_outline),
                const SizedBox(height: 24),
                _buildTextField(
                    controller: _nickController,
                    hintText: '닉네임',
                    icon: Icons.face_retouching_natural),
                const SizedBox(height: 24),
                _buildTextField(
                    controller: _passController,
                    hintText: '비밀번호',
                    icon: Icons.lock_outline,
                    obscureText: true),
                const SizedBox(height: 60),
                _buildSubmitButton(),
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

  Widget _buildSubmitButton() {
    return _isLoading
        ? const CircularProgressIndicator(color: AppColors.primaryBrown)
        : Container(
            decoration: BoxDecoration(
              boxShadow: AppDecorations.cardShadow,
              borderRadius: AppDecorations.cardRadius,
            ),
            child: ElevatedButton(
              onPressed: _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBrown,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
                elevation: 0,
              ),
              child: Text("가입하기", style: AppTextStyles.button.copyWith(fontSize: 22)),
            ),
          );
  }
}