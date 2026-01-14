import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../config/theme.dart';
import '../config/design_system.dart';
import 'camera_screen.dart';

class ModeSelectPage extends StatelessWidget {
  const ModeSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. [Background] Studio Atmosphere
          // 1. [Background] Exact Friend Page Style
          Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              image: DecorationImage(
                image: AssetImage('assets/images/login_bg.png'),
                fit: BoxFit.cover,
                opacity: 0.3,
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2. [Header]
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textMain),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                           backgroundColor: Colors.white.withOpacity(0.5),
                           padding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text("오늘은 무엇을\n해볼까요?", style: GoogleFonts.jua(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textMain, height: 1.2)),
                      const SizedBox(height: 8),
                      Text("반려동물과 함께할 활동을 선택해주세요.", style: GoogleFonts.jua(fontSize: 16, color: AppColors.textSub)),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // 3. [Activity Cards]
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    children: [
                      _buildActivityCard(
                        context,
                        title: "놀이 훈련",
                        subtitle: "반려동물과 신나게 뛰어놀아요!",
                        icon: FontAwesomeIcons.baseball,
                        color: AppColors.secondary,
                        mode: "playing",
                        delay: 0,
                      ),
                      const SizedBox(height: 20),
                      _buildActivityCard(
                        context,
                        title: "교감 하기",
                        subtitle: "따뜻한 눈빛으로 마음을 나눠요.",
                        icon: FontAwesomeIcons.solidHeart,
                        color: Colors.pinkAccent,
                        mode: "interaction",
                        delay: 100,
                      ),
                      const SizedBox(height: 20),
                      _buildActivityCard(
                        context,
                        title: "식사 예절",
                        subtitle: "맛있는 간식을 챙겨줄 시간!",
                        icon: FontAwesomeIcons.bone,
                        color: AppColors.primary,
                        mode: "feeding",
                        delay: 200,
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(BuildContext context, {
    required String title, required String subtitle, required IconData icon, required Color color, required String mode, required int delay
  }) {
    // Simple entry animation simulation could be added here, 
    // but simplified to static glass card for now.
    return GestureDetector(
      onTap: () => _showDifficultyDialog(context, mode),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            // Left Accent Bar
            Container(
              width: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  bottomLeft: Radius.circular(24),
                ),
              ),
            ),
            
            // Icon Area
            Container(
              width: 80,
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: FaIcon(icon, color: color, size: 28),
              ),
            ),
            
            // Text Area
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.jua(fontSize: 20, color: AppColors.textMain, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: GoogleFonts.jua(fontSize: 13, color: AppColors.textSub)),
                ],
              ),
            ),
            
            // Arrow
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textSub.withOpacity(0.5), size: 18),
            )
          ],
        ),
      ),
    );
  }

  void _showDifficultyDialog(BuildContext parentContext, String mode) {
    showDialog(
      context: parentContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text("난이도 선택", textAlign: TextAlign.center, style: GoogleFonts.jua(fontWeight: FontWeight.bold, color: AppColors.textMain)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDifficultyButton(dialogContext, parentContext, "쉬움 (Easy)", AppColors.success, mode, "easy"),
              const SizedBox(height: 12),
              _buildDifficultyButton(dialogContext, parentContext, "어려움 (Hard)", AppColors.danger, mode, "hard"),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDifficultyButton(BuildContext dialogContext, BuildContext parentContext, String label, Color color, String mode, String difficulty) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        onPressed: () {
          Navigator.pop(dialogContext);
          _navigateToCamera(parentContext, mode, difficulty);
        },
        child: Text(label, style: GoogleFonts.jua(fontSize: 16)),
      ),
    );
  }

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