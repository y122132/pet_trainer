import 'package:flutter/material.dart';
import 'dart:ui'; // For ImageFilter

// --- NEW WIDGETS ---

class BattleAvatarWidget extends StatelessWidget {
  final String petType;
  final String? customImagePath;
  final double damageOpacity;
  final Animation<double> idleAnimation;
  final double size;

  const BattleAvatarWidget({
    super.key,
    required this.petType,
    required this.idleAnimation,
    this.customImagePath,
    this.damageOpacity = 0.0,
    this.size = 160,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // Shadow (Dynamic size based on char size)
        Transform.translate(
          offset: const Offset(0, 10),
          child: Container(
            width: size * 0.6, 
            height: size * 0.15,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.all(Radius.elliptical(size*0.6, size*0.15)),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 15)],
            ),
          ),
        ),
        // Image with Animation
        ScaleTransition(
          scale: idleAnimation,
          alignment: Alignment.bottomCenter,
          child: _buildCharImage(),
        ),
      ],
    );
  }

  Widget _buildCharImage() {
    String imagePath = customImagePath ?? _getAssetPath(petType);
    return Stack(
      children: [
        Image.asset(imagePath, height: size, fit: BoxFit.contain),
        AnimatedOpacity(
          opacity: damageOpacity,
          duration: const Duration(milliseconds: 100),
          child: Image.asset(imagePath, height: size, color: Colors.white, colorBlendMode: BlendMode.srcATop),
        )
      ],
    );
  }
  
  String _getAssetPath(String petType) {
    switch (petType.toLowerCase()) {
      case 'dog': return "assets/images/characters/멜빵옷.png";
      case 'cat': return "assets/images/characters/공주옷.png";
      case 'banana': return "assets/images/characters/바나나옷.png";
      case 'ninja': return "assets/images/characters/닌자옷.png";
      default: return "assets/images/characters/닌자옷.png"; 
    }
  }
}

class BattleHudWidget extends StatelessWidget {
  final String name;
  final int hp;
  final int maxHp;
  final bool isMe;
  final bool isThinking;
  final List<String> statuses;

  const BattleHudWidget({
    super.key,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.isMe, // Defines alignment
    this.isThinking = false,
    this.statuses = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Glassmorphism HUD
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(isMe ? 0 : 20),
        topRight: Radius.circular(isMe ? 20 : 0),
        bottomRight: Radius.circular(isMe ? 20 : 0),
        bottomLeft: Radius.circular(isMe ? 0 : 20),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.4),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: isMe 
                ? [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.05)]
                : [Colors.black.withOpacity(0.5), Colors.black.withOpacity(0.2)]
            )
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Name & Thinking
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  if (isThinking) ...[
                     const SizedBox(width: 8),
                     const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.yellowAccent)))
                  ]
                ],
              ),
              const SizedBox(height: 6),
              
              // HP Bar
              _buildHpBar(hp, maxHp),
              const SizedBox(height: 4),
              Text("$hp / $maxHp", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w500)),

              // Buffs
              if (statuses.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  alignment: isMe ? WrapAlignment.start : WrapAlignment.end,
                  children: statuses.map((s) => _buildStatusChip(s)).toList(),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getStatusColor(label).withOpacity(0.8),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white30, width: 0.5)
      ),
      child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
  
  Color _getStatusColor(String status) {
    if (status.contains('poison')) return Colors.purple;
    if (status.contains('burn')) return Colors.red;
    if (status.contains('paral')) return Colors.yellow[700]!;
    if (status.contains('sleep')) return Colors.grey;
    if (status.contains('reco')) return Colors.green; // Heal/Recover
    return Colors.blueGrey;
  }

  Widget _buildHpBar(int current, int max) {
    double pct = (max == 0) ? 0 : (current / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 140, // Wider bar
      height: 10,  // Thicker bar
      child: Stack(
        children: [
          // Background
          Container(decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(5))),
          // Fill
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            widthFactor: pct,
            child: Container(
               decoration: BoxDecoration(
                 gradient: LinearGradient(colors: [_getHpColor(pct).withOpacity(0.6), _getHpColor(pct)]),
                 borderRadius: BorderRadius.circular(5),
                 boxShadow: [BoxShadow(color: _getHpColor(pct).withOpacity(0.5), blurRadius: 6)]
               ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getHpColor(double pct) {
    if (pct > 0.5) return Colors.greenAccent;
    if (pct > 0.2) return Colors.amber;
    return Colors.redAccent;
  }
}


// --- COMPATAIBILITY WRAPPER (DEPRECATED) ---

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BattleHudWidget(name: name, hp: hp, maxHp: maxHp, isMe: isMe, isThinking: isThinking, statuses: statuses),
        const SizedBox(height: 10),
        BattleAvatarWidget(petType: petType, idleAnimation: idleAnimation, customImagePath: customImagePath, damageOpacity: damageOpacity),
      ],
    );
  }
}
