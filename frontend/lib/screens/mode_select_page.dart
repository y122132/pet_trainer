import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'camera_screen.dart';

class ModeSelectPage extends StatelessWidget {
  const ModeSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E6), // 1. 배경색
      body: Stack(
        children: [
          // 1. 배경 패턴
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/login_bg.png'),
                fit: BoxFit.cover,
                opacity: 0.2,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 50.0),
                child: Column(
                  children: [
                    // 2. 상단 타이틀
                    Text(
                      "훈련 모드를 선택하세요",
                      style: GoogleFonts.jua(
                        fontSize: 26,
                        color: const Color(0xFF5D4037),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // 3. 훈련 모드 카드들
                    _buildModeCard(
                      context,
                      "놀이",
                      "반려동물과 신나게 놀아주세요!",
                      Icons.pets,
                      const Color(0xFF82B1FF),
                      "playing",
                    ),
                    const SizedBox(height: 20),
                    _buildModeCard(
                      context,
                      "교감",
                      "따뜻한 눈빛으로 마음을 나눠요.",
                      Icons.favorite_border,
                      const Color(0xFFFF8A80),
                      "interaction",
                    ),
                    const SizedBox(height: 20),
                    _buildModeCard(
                      context,
                      "식사",
                      "맛있는 간식을 챙겨줄 시간!",
                      Icons.restaurant_menu,
                      const Color(0xFF8D6E63),
                      "feeding",
                    ),
                    const SizedBox(height: 40), // 4. 하단 여백
                  ],
                ),
              ),
            ),
          ),
           // 커스텀 뒤로가기 버튼
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF5D4037)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 모드 선택 카드 위젯
  Widget _buildModeCard(BuildContext context, String title, String subtitle, IconData icon, Color color, String mode) {
    return GestureDetector(
      onTap: () => _showDifficultyDialog(context, mode), // 기능 유지
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        decoration: BoxDecoration(
          color: Colors.white, // 흰색 배경
          borderRadius: BorderRadius.circular(30.0), // 둥근 모서리
          border: Border.all(color: const Color(0xFF5D4037), width: 2.0), // 갈색 테두리
          boxShadow: [
            BoxShadow(
              color: Colors.brown.withOpacity(0.15),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // 왼쪽 아이콘
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 20),
            // 중앙 텍스트 (Expanded 적용으로 overflow 방지)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.jua(fontSize: 22, color: const Color(0xFF4E342E), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: GoogleFonts.jua(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF5D4037), size: 20),
          ],
        ),
      ),
    );
  }

  // 난이도 선택 팝업 (테마에 맞게 스타일 수정)
  void _showDifficultyDialog(BuildContext parentContext, String mode) {
    showDialog(
      context: parentContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFFFFF9E6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: const BorderSide(color: Color(0xFF5D4037), width: 2),
          ),
          title: Text("난이도 선택", textAlign: TextAlign.center, style: GoogleFonts.jua(color: const Color(0xFF4E342E), fontSize: 22)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDifficultyButton(dialogContext, parentContext, "Easy (쉬움)", Colors.green, mode, "easy"),
              const SizedBox(height: 10),
              _buildDifficultyButton(dialogContext, parentContext, "Hard (어려움)", Colors.redAccent, mode, "hard"),
            ],
          ),
        );
      },
    );
  }

  // 난이도 버튼 (테마에 맞게 스타일 수정)
  Widget _buildDifficultyButton(BuildContext dialogContext, BuildContext parentContext, String label, Color color, String mode, String difficulty) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 3,
        ),
        onPressed: () {
          Navigator.pop(dialogContext); // 다이얼로그 닫기
          _navigateToCamera(parentContext, mode, difficulty); // 카메라 화면으로 이동 (기능 유지)
        },
        child: Text(
          label,
          style: GoogleFonts.jua(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  // 카메라 화면으로 이동하는 로직 (수정하지 않음)
  void _navigateToCamera(BuildContext context, String mode, String difficulty) async {
    try {
      final cameras = await availableCameras();
      if (!context.mounted) return;
      if (cameras.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("사용 가능한 카메라가 없습니다.")));
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => CameraScreen(cameras: cameras, mode: mode, difficulty: difficulty)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("카메라 오류: $e")));
    }
  }
}