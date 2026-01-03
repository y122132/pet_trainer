import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pet_trainer_frontend/screens/login_screen.dart';
import 'package:pet_trainer_frontend/screens/menu_page.dart';
import 'package:pet_trainer_frontend/screens/creation_name_screen.dart';
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
  
  // [Fix] 로딩 상태 추가 (터치 피드백용)
  bool _isLoading = false;

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
    if (_isLoading) return; // 중복 터치 방지
    
    setState(() => _isLoading = true); // 로딩 시작
    
    final authService = AuthService();
    
    // [보안] 토큰 유효성 및 캐릭터 존재 여부 확인 (네트워크 요청 등 시간 소요 가능)
    final bool isValid = await authService.validateToken();
    final String? charId = await authService.getCharacterId();

    if (!mounted) return;

    if (isValid) {
      if (charId != null) {
        // 1. 캐릭터 보유 -> 메인 로비
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MenuPage()),
        );
      } else {
        // 2. 캐릭터 미보유 -> 캐릭터 생성 (1단계)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CreationNameScreen()),
        );
      }
    } else {
      // 3. 비로그인/토큰 만료 -> 로그인 화면
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _navigateToNextScreen,
        behavior: HitTestBehavior.translucent, // [Fix] 투명 영역도 터치 인식
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: '뽀잉뽀잉' 움직이는 배경 이미지
            _buildAnimatedBackground(),

            // Layer 2: 로고와 텍스트
            _buildContent(),
            
            // Layer 3: 로딩 인디케이터 (터치 시 피드백)
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
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
