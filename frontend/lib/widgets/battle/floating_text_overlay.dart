import 'package:flutter/material.dart';
import 'package:pet_trainer_frontend/config/theme.dart';

class FloatingTextOverlay extends StatelessWidget {
  final List<FloatingTextItem> items;
  final int myId;

  const FloatingTextOverlay({super.key, required this.items, required this.myId});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: items.map((item) {
        // Coordinate Logic (Approximate for Me vs Opponent)
        bool isMe = (item.targetId == myId);

        return Positioned(
          top: isMe ? null : 150,
          bottom: isMe ? 450 : null,
          left: isMe ? 80 : null,
          right: isMe ? null : 80,
          child: _buildFloatingTextWidget(item),
        );
      }).toList(),
    );
  }

  Widget _buildFloatingTextWidget(FloatingTextItem item) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      builder: (context, double val, child) {
        // Fade out at end, move up
        double opacity = (val > 0.7) ? (1 - (val - 0.7) / 0.3) : 1.0;
        double offset = val * 60; // Move up 60 pixels

        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -offset),
            child: Text(
              item.text,
              style: TextStyle(
                  fontSize: item.isCrit ? 40 : (item.isHeal ? 28 : 36), // Slightly bigger
                  fontWeight: FontWeight.w900,
                  color: item.isHeal
                      ? AppColors.success
                      : (item.text == "MISS" ? Colors.grey : (item.isCrit ? Colors.amber : const Color(0xFFFF7043))), // Orange-Red for Damage
                  shadows: [
                    // Outline
                    Shadow(blurRadius: 2, color: item.isHeal ? Colors.green[900]! : (item.text == "MISS" ? Colors.black45 : Colors.brown), offset: const Offset(1, 1)),
                    // Glow
                    Shadow(blurRadius: 8, color: item.isHeal ? AppColors.success.withOpacity(0.5) : (item.isCrit ? Colors.amber.withOpacity(0.5) : Colors.redAccent.withOpacity(0.3)), offset: const Offset(0, 0))
                  ]),
            ),
          ),
        );
      },
    );
  }
}

class FloatingTextItem {
  final int id;
  final String text;
  final bool isCrit;
  final bool isHeal;
  final int targetId;

  FloatingTextItem({
    required this.id,
    required this.text,
    required this.isCrit,
    required this.targetId,
    this.isHeal = false,
  });
}
