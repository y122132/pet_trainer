import 'package:flutter/material.dart';

class BattleCharacterWidget extends StatelessWidget {
  final String name;
  final int hp;
  final int maxHp;
  final String petType;
  final bool isMe;
  final double damageOpacity;
  final bool isThinking;
  final String? customImagePath;
  final List<String> statuses;
  final Animation<double> idleAnimation;

  const BattleCharacterWidget({
    super.key,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.petType,
    required this.isMe,
    this.damageOpacity = 0.0,
    this.isThinking = false,
    this.customImagePath,
    this.statuses = const [],
    required this.idleAnimation,
  });

  @override
  Widget build(BuildContext context) {
    // 3D-ish Stand with Shadow
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Floating HP Bar + Name
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Column(
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              if (isThinking)
                const Text("Thinking...", style: TextStyle(color: Colors.yellowAccent, fontSize: 10)),
              const SizedBox(height: 4),
              _buildHpBar(hp, maxHp),
              const SizedBox(height: 2),
              Text("$hp / $maxHp", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              if (statuses.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: statuses.map((s) => Container(
                    margin: const EdgeInsets.only(right: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(4)),
                    child: Text(s, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                  )).toList(),
                )
              ]
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Character + Shadow
        Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Shadow
            Transform.translate(
              offset: const Offset(0, 5),
              child: Container(
                width: 80, height: 20,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(100), // Ellipse shadow
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
              ),
            ),
            // Image
            ScaleTransition(
              scale: idleAnimation,
              alignment: Alignment.bottomCenter,
              child: _buildCharImage(petType, damageOpacity, 160, customPath: customImagePath),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildCharImage(String petType, double opacity, double size, {String? customPath}) {
    String imagePath = customPath ?? _getAssetPath(petType);
    return Stack(
      children: [
        Image.asset(imagePath, height: size, fit: BoxFit.contain),
        AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 100),
          child: Image.asset(imagePath, height: size, color: Colors.red, colorBlendMode: BlendMode.srcATop),
        )
      ],
    );
  }

  Widget _buildHpBar(int current, int max) {
    double pct = (max == 0) ? 0 : (current / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 80,
      height: 6,
      child: Stack(
        children: [
          Container(decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(3))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            width: 80 * pct,
            decoration: BoxDecoration(
              color: _getHpColor(pct),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  Color _getHpColor(double pct) {
    if (pct > 0.5) {
      return Color.lerp(Colors.yellow, Colors.green, (pct - 0.5) * 2)!;
    } else {
      return Color.lerp(Colors.red, Colors.yellow, pct * 2)!;
    }
  }

  String _getAssetPath(String petType) {
    switch (petType.toLowerCase()) {
      case 'dog':
        return "assets/images/characters/멜빵옷.png"; // Dog -> Overalls
      case 'cat':
        return "assets/images/characters/공주옷.png"; // Cat -> Princess
      case 'banana':
        return "assets/images/characters/바나나옷.png"; // Banana -> Banana
      case 'ninja':
        return "assets/images/characters/닌자옷.png"; // Ninja -> Ninja
      default:
        return "assets/images/characters/닌자옷.png"; // Default -> Ninja
    }
  }
}
