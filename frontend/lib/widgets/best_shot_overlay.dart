import 'package:flutter/material.dart';
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/api_config.dart';

class BestShotOverlay extends StatelessWidget {
  final String imageUrl;
  final VoidCallback onClose;

  const BestShotOverlay({
    Key? key,
    required this.imageUrl,
    required this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String fullUrl = imageUrl;
    if (fullUrl.startsWith('/')) {
        fullUrl = "${AppConfig.serverBaseUrl}$fullUrl";
    }

    return Material(
      color: Colors.black87, // Dark dim background
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Content
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "📸 베스트 샷!",
                style: AppTextStyles.title.copyWith(color: AppColors.primaryMint, fontSize: 32),
              ),
              const SizedBox(height: 20),
              
              // Photo Frame
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.white.withOpacity(0.5), blurRadius: 20, spreadRadius: 2)
                  ]
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        fullUrl,
                        width: 300,
                        height: 300,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          width: 300, height: 300, 
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey))
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "미니홈피 다이어리에\n자동으로 기록되었습니다 📝",
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMain.copyWith(fontSize: 14, color: AppColors.textMain),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
          
          // 2. Close Button (Bottom)
          Positioned(
            bottom: 50,
            child: TextButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.check_circle, color: Colors.white, size: 30),
              label: const Text("확인", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            )
          ),
          
          // 3. Close Button (Top Right)
          Positioned(
            top: 40, right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: onClose,
            )
          )
        ],
      ),
    );
  }
}
