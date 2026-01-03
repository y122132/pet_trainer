import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pet_trainer_frontend/screens/login_screen.dart';
import 'package:pet_trainer_frontend/screens/menu_page.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart';

class MainTitleScreen extends StatefulWidget {
  const MainTitleScreen({super.key});

  @override
  State<MainTitleScreen> createState() => _MainTitleScreenState();
}

class _MainTitleScreenState extends State<MainTitleScreen>
    with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _logoAnimationController;
  late Animation<double> _logoScaleAnimation;
  late AnimationController _textAnimationController;
  late Animation<double> _textOpacityAnimation;
  late AnimationController _backgroundAnimationController;
  late Animation<double> _backgroundScaleAnimation;

  final String _backgroundImagePath = 'assets/images/메인3.png';

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    // 1. 로고 애니메이션: 한 번만 통통 튀도록
    _logoAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _logoScaleAnimation = CurvedAnimation(
      parent: _logoAnimationController,
      curve: Curves.elasticOut,
    );
    _logoAnimationController.forward();

    // 2. 텍스트 애니메이션: 계속 깜빡이도록
    _textAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _textOpacityAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _textAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // 3. 배경 이미지 애니메이션: '뽀잉뽀잉' (Scaling) 효과로 변경
    _backgroundAnimationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    _backgroundScaleAnimation =
        Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _backgroundAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _logoAnimationController.dispose();
    _textAnimationController.dispose();
    _backgroundAnimationController.dispose();
    super.dispose();
  }

  void _navigateToNextScreen() async {
    final authService = AuthService();
    
    // [보안 업데이트] 단순 존재 여부만 체크하는 게 아니라, 서버에 유효성을 물어봅니다.
    // 네트워크 요청이 포함되므로 약간의 딜레이가 생길 수 있으나, 안전을 위해 필수적입니다.
    final bool isValid = await authService.validateToken();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            isValid ? const MenuPage() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _navigateToNextScreen,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: '뽀잉뽀잉' 움직이는 배경 이미지
            _buildAnimatedBackground(),

            // Layer 2: 로고와 텍스트
            _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return ScaleTransition(
      scale: _backgroundScaleAnimation,
      child: Image.asset(
        _backgroundImagePath,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 1),
        ScaleTransition(
          scale: _logoScaleAnimation,
          child: Image.asset(
            'assets/images/독고 표지 이름.png',
            width: MediaQuery.of(context).size.width * 0.8,
          ),
        ),
        const Spacer(flex: 3),
        FadeTransition(
          opacity: _textOpacityAnimation,
          child: const Text(
            "화면을 터치하면 시작",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  blurRadius: 10.0,
                  color: Colors.black,
                  offset: Offset(2.0, 2.0),
                ),
              ],
            ),
          ),
        ),
        const Spacer(flex: 1),
      ],
    );
  }
}
