import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/config/design_system.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/widgets/common/stat_widgets.dart';
import 'package:camera/camera.dart';
import 'camera_screen.dart';
import 'battle_lobby_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CharProvider>(context, listen: false).fetchCharacter(1);
    });

    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false, // Let the bottom sheet go to the edge
          child: Column(
            children: [
              // 1. TOP HUD (Floating Bubbles)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _buildTopHud(context),
              ),

              // 2. CENTER STAGE (Character on Rug)
              Expanded(
                child: Consumer<CharProvider>(
                   builder: (context, provider, _) {
                     return _buildCenterStage(provider.character?.frontUrl);
                   }
                ),
              ),

              // 3. BOTTOM CONTROLLER (Game Pad)
              _buildControlPanel(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHud(BuildContext context) {
    return Consumer<CharProvider>(
      builder: (context, provider, _) {
        final char = provider.character;
        final stats = char?.stat;
        
        return Column(
          children: [
             // Name Tag
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
               decoration: BoxDecoration(
                 color: AppColors.primary,
                 borderRadius: BorderRadius.circular(20),
                 border: Border.all(color: AppColors.stroke, width: 2.5),
               ),
               child: Text(
                 char?.name ?? "불러오는 중...",
                 style: AppTextStyles.title.copyWith(color: AppColors.white, fontSize: 18),
               ),
             ),
             const SizedBox(height: 10),
             // Stat Bubbles Wrap
             Wrap(
               alignment: WrapAlignment.center,
               children: [
                 StatBubble(label: "Lv", value: "${stats?.level ?? 1}", icon: Icons.star, color: AppColors.statYellow),
                 StatBubble(label: "HP", value: "100%", icon: Icons.favorite, color: AppColors.statRed),
                 StatBubble(label: "기분", value: "좋음", icon: Icons.mood, color: AppColors.statGreen),
               ],
             )
          ],
        );
      },
    );
  }

  Widget _buildCenterStage(String? imageUrl) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // The Rug (Background Decor)
        Positioned(
          bottom: 40,
          child: Container(
            width: 280,
            height: 80,
            decoration: BoxDecoration(
               color: AppColors.primary.withOpacity(0.1),
               borderRadius: BorderRadius.all(Radius.elliptical(280, 80)),
               border: Border.all(color: AppColors.stroke.withOpacity(0.1), width: 3),
            ),
          ),
        ),
        
        // Character Sprite
        // Add a gentle bounce animation later
        Padding(
          padding: const EdgeInsets.only(bottom: 50),
          child: imageUrl != null && imageUrl.isNotEmpty
             ? Image.network(imageUrl, height: 280, fit: BoxFit.contain)
             : Image.asset("assets/images/characters/닌자옷.png", height: 280, fit: BoxFit.contain),
        ),
      ],
    );
  }

  Widget _buildControlPanel(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 280, // Fixed height for the panel
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        border: Border(top: BorderSide(color: AppColors.stroke, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
      child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
            Text("COMMANDS", style: AppTextStyles.title.copyWith(fontSize: 20, color: AppColors.textSub)),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.4, // Wide buttons
                physics: const NeverScrollableScrollPhysics(),
                children: [
                   _buildCmdBtn(
                     context, 
                     icon: Icons.restaurant, 
                     label: "밥주기", 
                     color: AppColors.statRed,
                     onTap: () {}
                   ),
                   _buildCmdBtn(
                     context, 
                     icon: Icons.fitness_center, 
                     label: "훈련하기", 
                     color: AppColors.statBlue,
                     onTap: () async {
                        final cameras = await availableCameras();
                        if (context.mounted && cameras.isNotEmpty) {
                           Navigator.push(context, MaterialPageRoute(builder: (_) => CameraScreen(cameras: cameras)));
                        }
                     }
                   ),
                   _buildCmdBtn(
                     context, 
                     icon: Icons.sports_kabaddi, 
                     label: "대결하기", 
                     color: AppColors.statYellow,
                     onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BattleLobbyScreen()))
                   ),
                   _buildCmdBtn(
                     context, 
                     icon: Icons.bed, 
                     label: "잠자기", 
                     color: AppColors.statGreen,
                     onTap: () {}
                   )
                ],
              ),
            ),
         ],
      ),
    );
  }

  Widget _buildCmdBtn(BuildContext context, {
    required IconData icon, 
    required String label, 
    required Color color,
    required VoidCallback onTap}) {
      
    return ChocoButton(
      onPressed: onTap,
      color: color,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
           Icon(icon, size: 36, color: AppColors.textMain),
           const SizedBox(height: 4),
           Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textMain)),
        ],
      )
    );
  }
}
