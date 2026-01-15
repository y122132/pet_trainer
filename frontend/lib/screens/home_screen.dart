import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/config/design_system.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:camera/camera.dart';
import 'camera_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Data Loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CharProvider>(context, listen: false).fetchCharacter(1);
    });

    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent, // Handled by ThemedBackground
        body: SafeArea(
          child: Consumer<CharProvider>(
            builder: (context, provider, child) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  // Responsive Breakpoint
                  bool isWide = constraints.maxWidth > 600;

                  return Column(
                    children: [
                      // 1. Top Bar
                      _buildTopBar(context, provider),
                      
                      const SizedBox(height: 16),

                      // 2. Main Content
                      Expanded(
                        child: isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 4, child: _buildCharacterCard(provider)),
                                  const SizedBox(width: 16),
                                  Expanded(flex: 6, child: _buildStatsCard(context, provider)),
                                ],
                              )
                            : ListView(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                children: [
                                  // Character Area
                                  AspectRatio(
                                    aspectRatio: 1.0, 
                                    child: _buildCharacterCard(provider)
                                  ),
                                  const SizedBox(height: 16),
                                  // Stats Area
                                  SizedBox(
                                    height: 300, 
                                    child: _buildStatsCard(context, provider)
                                  ),
                                  const SizedBox(height: 80), // Space for bottom button
                                ],
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        floatingActionButton: _buildBottomButton(context),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, CharProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("안녕하세요,", style: AppTextStyles.subBody),
              Text(
                provider.character?.name ?? "트레이너님",
                style: AppTextStyles.title.copyWith(color: AppColors.primaryMint, fontSize: 28),
              ),
            ],
          ),
          // User Icon / Profile link could go here
          CircleAvatar(
             radius: 24,
             backgroundColor: AppColors.white,
             child: const Icon(Icons.person, color: AppColors.textMain),
          )
        ],
      ),
    );
  }

  Widget _buildCharacterCard(CharProvider provider) {
    final char = provider.character;
    // Handle Image URL
    String? imageUrl = char?.frontUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
        if (imageUrl.startsWith('/')) {
            // imageUrl = "${AppConfig.serverBaseUrl}$imageUrl"; // Need AppConfig import if used
            // Simplified for now, assuming relative path handling or logic is in provider/model
        } 
    }

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: imageUrl != null && imageUrl.isNotEmpty
              ? Image.network(imageUrl, fit: BoxFit.contain, errorBuilder: (_,__,___) => const Icon(Icons.pets, size: 80, color: AppColors.textSub))
              : Image.asset("assets/images/characters/닌자옷.png", fit: BoxFit.contain), // Default fallback
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              char != null ? "Lv. ${char.stat?.level ?? 1}" : "Loading...",
              style: AppTextStyles.title.copyWith(fontSize: 18),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context, CharProvider provider) {
    // This would typically contain the Radar Chart or List of Stats
    // Implementation simplified to focus on layout structure
    final stats = provider.character?.stat;
    
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text("스탯 분석", style: AppTextStyles.title.copyWith(fontSize: 20)),
           const SizedBox(height: 20),
           // Placeholder for Stats List or Chart
           if (stats != null) ...[
             _buildStatRow("근력 (Str)", stats.strength, AppColors.danger),
             _buildStatRow("지능 (Int)", stats.intelligence, AppColors.info),
             _buildStatRow("민첩 (Dex)", stats.agility, AppColors.success),
             _buildStatRow("방어 (Def)", stats.defense, AppColors.textSub),
             _buildStatRow("행운 (Luk)", stats.luck, AppColors.warning),
           ] else
             const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMain))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (value / 100).clamp(0.0, 1.0), // Assuming 100 max for vis
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 10,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text("$value", style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBottomButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton(
          onPressed: () async {
            try {
              final cameras = await availableCameras();
              if (!context.mounted) return;
              if (cameras.isEmpty) return;
              Navigator.push(context, MaterialPageRoute(builder: (c) => CameraScreen(cameras: cameras)));
            } catch (e) {
              print("Camera Error: $e");
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryMint,
            foregroundColor: AppColors.textMain,
            elevation: 8,
            shadowColor: AppColors.primaryMint.withOpacity(0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
               Icon(Icons.play_circle_fill, size: 28),
               SizedBox(width: 10),
               Text("오늘의 운동 시작하기", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
