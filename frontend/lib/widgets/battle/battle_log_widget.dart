import 'package:flutter/material.dart';
import 'package:pet_trainer_frontend/config/theme.dart';

class BattleLogWidget extends StatelessWidget {
  final List<String> logs;

  const BattleLogWidget({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    // Show only last 2 logs for extreme compactness to avoid overlap
    final displayLogs = logs.take(2).toList(); 

    return ListView(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: displayLogs.map((log) => _buildLogItem(log, displayLogs.indexOf(log))).toList(),
    );
  }

  Widget _buildLogItem(String log, int index) {
    // ... (rest of the logic) ...
    Color textColor = AppColors.softCharcoal;
    // ... (color logic) ...

    double opacity = (index == 0) ? 1.0 : 0.6;

    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1), // Minimal vertical spacing
        child: Container(
           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), // Thinner box
           decoration: BoxDecoration(
             color: Colors.white.withOpacity(0.3), // More subtle background
             borderRadius: BorderRadius.circular(8),
           ),
           child: Text(
            log,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: index == 0 ? 13 : 11, // Smaller fonts
              fontWeight: index == 0 ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
