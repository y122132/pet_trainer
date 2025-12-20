import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'camera_screen.dart';

class ModeSelectPage extends StatelessWidget {
  const ModeSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('훈련장', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("훈련 모드를 선택하세요", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              
              // 모드 선택 버튼들
              _buildModeCard(
                context, 
                "🎾 놀이", 
                "반려동물과 공놀이를 즐기세요!", 
                Icons.sports_baseball, 
                Colors.indigo,
                "playing"
              ),
              const SizedBox(height: 20),
              _buildModeCard(
                context, 
                "🤝 교감", 
                "반려동물과 함께 사진을 찍으세요!", 
                Icons.favorite, 
                Colors.pinkAccent,
                "interaction"
              ),
              const SizedBox(height: 20),
              _buildModeCard(
                context, 
                "🥣 식사", 
                "맛있는 간식을 챙겨주세요!", 
                Icons.restaurant, 
                Colors.brown,
                "feeding"
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 카메라 화면으로 이동하는 로직
  void _navigateToCamera(BuildContext context, String mode, String difficulty) async {
      try {
        // 카메라 권한 및 사용 가능 여부 확인
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("사용 가능한 카메라가 없습니다.")));
            return;
        }
        // 카메라 화면으로 이동 (모드 및 난이도 전달)
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => CameraScreen(cameras: cameras, mode: mode, difficulty: difficulty)),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("카메라 오류: $e")));
      }
  }

  Widget _buildModeCard(BuildContext context, String title, String subtitle, IconData icon, Color color, String mode) {
    return GestureDetector(
      onTap: () => _showDifficultyDialog(context, mode),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Row(
          children: [
            Icon(icon, size: 50, color: Colors.white),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 5),
                  Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: Colors.white),
          ],
        ),
      ),
    );
  }

  // 난이도 선택 팝업 표시
  void _showDifficultyDialog(BuildContext parentContext, String mode) {
    showDialog(
      context: parentContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("난이도 선택", textAlign: TextAlign.center),
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

  Widget _buildDifficultyButton(BuildContext dialogContext, BuildContext parentContext, String label, Color color, String mode, String difficulty) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () {
          Navigator.pop(dialogContext); // 다이얼로그 닫기
          _navigateToCamera(parentContext, mode, difficulty); // 카메라 화면으로 이동
        },
        child: Text(
          label, 
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)
        ),
      ),
    );
  }
}
