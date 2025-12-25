import 'package:flutter/material.dart';

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
                  fontFamily: 'Roboto', // Or any bold font
                  fontSize: item.isCrit ? 36 : (item.isHeal ? 28 : 32),
                  fontWeight: FontWeight.w900,
                  color: item.isHeal
                      ? Colors.greenAccent
                      : (item.isCrit ? Colors.amber : Colors.white),
                  shadows: [
                    const Shadow(blurRadius: 2, color: Colors.black, offset: Offset(2, 2)),
                    Shadow(
                        blurRadius: 10,
                        color: item.isCrit
                            ? Colors.orange
                            : (item.isHeal ? Colors.green : Colors.red),
                        offset: const Offset(0, 0))
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
