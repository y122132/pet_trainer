import 'package:flutter/material.dart';

class CuteAvatar extends StatelessWidget {
  final String petType;
  final double size;
  final bool isSelected;
  final VoidCallback? onTap;

  const CuteAvatar({
    super.key, 
    required this.petType, 
    this.size = 60, 
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor = _getBgColor(petType);
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(
             color: isSelected ? Colors.white : Colors.transparent,
             width: isSelected ? 4 : 0, 
          ),
          boxShadow: [
             if (isSelected) 
               BoxShadow(color: bgColor.withOpacity(0.6), blurRadius: 10, spreadRadius: 2)
             else
               BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
          ]
        ),
        child: Center(
          // For MVP, using Icons. Real app should use Image.asset
          child: _getIcon(petType),
        ),
      ),
    );
  }

  Color _getBgColor(String type) {
    switch (type.toLowerCase()) {
      case 'fire': return const Color(0xFFFFAEBC);
      case 'water': return const Color(0xFFB4F8C8);
      case 'grass': return const Color(0xFFA0E7E5);
      case 'dog': return const Color(0xFFFBE7C6);
      case 'cat': return const Color(0xFFD4C1EC);
      case 'bird': return const Color(0xFFFFCCB6);
      case 'robot': return const Color(0xFFE2F0CB);
      default: return const Color(0xFFFDFD96);
    }
  }

  Widget _getIcon(String type) {
    String t = type.toLowerCase();
    String iconPath = "assets/images/characters/dog_idle.png"; // fallback
    
    // Simple Mapping for now, assuming assets exist or using flutter_launcher_icons
    // If not, use Text Emoji as fallback for maximum cuteness
    String emoji = "🐶";
    if (t.contains("cat")) emoji = "🐱";
    else if (t.contains("bird")) emoji = "🐦";
    else if (t.contains("bear")) emoji = "🐻"; 
    else if (t.contains("robot")) emoji = "🤖";
    else if (t.contains("fire")) emoji = "🔥";
    else if (t.contains("water")) emoji = "💧";
    
    return Text(emoji, style: TextStyle(fontSize: size * 0.5));
  }
}
