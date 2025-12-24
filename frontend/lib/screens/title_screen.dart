import 'package:flutter/material.dart';
import 'menu_page.dart';

class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opacityAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _navigateToMenu() {
    // pushReplacement를 사용하여 뒤로가기 버튼으로 타이틀 화면으로 돌아오지 않도록 합니다.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MenuPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 화면 전체의 탭을 감지하기 위해 GestureDetector를 사용합니다.
      body: GestureDetector(
        onTap: _navigateToMenu,
        child: Container(
          // 터치 영역을 화면 전체로 확장하기 위해 color를 설정합니다.
          color: Colors.transparent,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                // 화면 상단에 표시될 게임 제목
                const Text(
                  'Dog Go',
                  style: TextStyle(
                    fontSize: 50,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(flex: 3),
                // 깜빡이는 효과를 위한 FadeTransition 위젯
                FadeTransition(
                  opacity: _opacityAnimation,
                  child: const Text(
                    '화면을 터치하세요',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.black54,
                    ),
                  ),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
