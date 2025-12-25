import 'package:flutter/material.dart';

class BattleLogWidget extends StatelessWidget {
  final List<String> logs;

  const BattleLogWidget({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    // Show only last 3 logs for compactness
    final displayLogs = logs.take(3).toList(); // Newest first (index 0)

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.transparent], // Fade out older messages (at bottom since we map reversed?)
          // Wait, if it's new-on-top, we want bottom fade.
          stops: [0.3, 1.0], 
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        children: displayLogs.map((log) => _buildLogItem(log, displayLogs.indexOf(log))).toList(),
      ),
    );
  }

  Widget _buildLogItem(String log, int index) {
    // Highlight important events
    bool isDamage = log.contains("damage") || log.contains("피해");
    bool isEffect = log.contains("Status") || log.contains("상태");
    bool isCrit = log.contains("CRITICAL") || log.contains("크리티컬");

    Color textColor = Colors.white;
    if (isCrit) textColor = Colors.yellowAccent;
    else if (isDamage) textColor = Colors.redAccent;
    else if (isEffect) textColor = Colors.greenAccent;

    // First item is most opaque
    double opacity = (index == 0) ? 1.0 : (index == 1 ? 0.6 : 0.3);

    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          log,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: index == 0 ? 14 : 12,
            fontWeight: index == 0 ? FontWeight.bold : FontWeight.normal,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))]
          ),
        ),
      ),
    );
  }
}
