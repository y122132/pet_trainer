import 'package:flutter/material.dart';

class BattleLogWidget extends StatelessWidget {
  final List<String> logs;

  const BattleLogWidget({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
          stops: [0.0, 0.1, 0.9, 1.0], // Fade top and bottom
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        reverse: true, // Bubbles stack up
        itemCount: logs.length,
        itemBuilder: (context, index) {
          return _buildLogBubble(logs[index]);
        },
      ),
    );
  }

  Widget _buildLogBubble(String log) {
    bool isDamage = log.contains("피해") || log.contains("damage");
    bool isCrit = log.contains("크리티컬") || log.contains("CRITICAL");

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCrit ? Colors.amber[800]!.withOpacity(0.9) : (isDamage ? Colors.redAccent.withOpacity(0.8) : Colors.black54),
        borderRadius: BorderRadius.circular(15),
        border: isCrit ? Border.all(color: Colors.yellowAccent, width: 2) : null,
        boxShadow: isCrit ? [const BoxShadow(color: Colors.amber, blurRadius: 10)] : null,
      ),
      child: Text(log,
          style: TextStyle(
              color: Colors.white,
              fontSize: isCrit ? 16 : 12,
              fontWeight: isCrit ? FontWeight.w900 : FontWeight.bold)),
    );
  }
}
