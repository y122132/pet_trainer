import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pet_trainer_frontend/config/design_system.dart'; 
import 'package:pet_trainer_frontend/config/theme.dart';

// --- 스탯 색상 매퍼 ---
class StatColorMapper {
  static Color getColor(String key) {
    switch (key.toUpperCase()) {
      case 'STR': case 'STRENGTH': case '근력': return AppColors.statRed;
      case 'INT': case 'INTELLIGENCE': case '지능': return AppColors.statBlue;
      case 'DEX': case 'AGILITY': case '민첩': return AppColors.statYellow;
      case 'DEF': case 'DEFENSE': case '방어': return AppColors.statGrey;
      case 'LUK': case 'LUCK': case '운': return AppColors.statGreen;
      default: return AppColors.textSub;
    }
  }

  static String getEmoji(String key) {
     switch (key.toUpperCase()) {
      case 'STR': case '근력': return "💪";
      case 'INT': case '지능': return "🧠";
      case 'DEX': case '민첩': return "⚡";
      case 'DEF': case '방어': return "🛡️";
      case 'LUK': case '운': return "🍀";
      case 'LV': case 'LEVEL': return "⭐";
      default: return "✨";
    }
  }
}

// --- 3D Floating Stat Bubble (HUD Style) ---
class StatBubble extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  const StatBubble({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? AppColors.secondary;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.stroke, width: 2.5),
        boxShadow: const [
           BoxShadow(color: AppColors.stroke, offset: Offset(0, 3), blurRadius: 0)
        ]
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
             Icon(icon, size: 20, color: AppColors.textMain),
             const SizedBox(width: 8),
          ],
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: bgColor, fontSize: 16)),
        ],
      ),
    );
  }
}

// --- Choco Circular Gauge (Thick Donut) ---
class ChocoStatGauge extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final Color? color;

  const ChocoStatGauge({
    super.key,
    required this.label,
    required this.value,
    this.maxValue = 100,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progress = value / maxValue;
    final gaugeColor = color ?? StatColorMapper.getColor(label);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
         SizedBox(
           width: 60, 
           height: 60,
           child: Stack(
             alignment: Alignment.center,
             children: [
               // Track
               CircularProgressIndicator(
                 value: 1.0,
                 strokeWidth: 8,
                 color: AppColors.stroke.withOpacity(0.1),
               ),
               // Progress
               CircularProgressIndicator(
                 value: progress,
                 strokeWidth: 8,
                 color: gaugeColor,
                 strokeCap: StrokeCap.round,
               ),
               // Emoji Center
               Text(StatColorMapper.getEmoji(label), style: const TextStyle(fontSize: 22)),
             ],
           ),
         ),
         const SizedBox(height: 6),
         Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
         Text("$value", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      ],
    );
  }
}

// --- 공용 레이더 차트 위젯 (Maintained with Choco Style) ---
class StatRadarChart extends StatelessWidget {
  final Map<String, int> stats;
  final double maxValue;
  final bool showLabels;
  final TextStyle? labelStyle;
  final List<Color>? graphColors;

  const StatRadarChart({
    super.key,
    required this.stats,
    this.maxValue = 100.0,
    this.showLabels = true,
    this.labelStyle,
    this.graphColors,
  });

  @override
  Widget build(BuildContext context) {
    final keys = ['strength', 'intelligence', 'luck', 'defense', 'agility'];
    final labels = ['STR', 'INT', 'LUK', 'DEF', 'DEX'];
    
    List<RadarEntry> entries = keys.map((k) {
      final val = stats[k] ?? stats[k.toUpperCase()] ?? 0;
      return RadarEntry(value: val.toDouble());
    }).toList();

    final fillColor = AppColors.primary.withOpacity(0.2);
    final borderColor = AppColors.stroke;

    return RadarChart(
      RadarChartData(
        radarTouchData: RadarTouchData(enabled: false),
        dataSets: [
          RadarDataSet(
            fillColor: fillColor,
            borderColor: borderColor,
            entryRadius: 4, // Chunky dots
            dataEntries: entries,
            borderWidth: 3, // Chunky lines
          ),
        ],
        radarBackgroundColor: Colors.transparent,
        borderData: FlBorderData(show: false),
        radarBorderData: const BorderSide(color: Colors.transparent),
        titlePositionPercentageOffset: 0.15,
        titleTextStyle: labelStyle ?? AppTextStyles.subBody.copyWith(fontWeight: FontWeight.bold),
        getTitle: (index, angle) {
            if (!showLabels) return const RadarChartTitle(text: "");
            if (index < labels.length) {
               return RadarChartTitle(text: labels[index]);
            }
            return const RadarChartTitle(text: "");
        },
        tickCount: 1,
        ticksTextStyle: const TextStyle(color: Colors.transparent),
        gridBorderData: BorderSide(color: AppColors.stroke.withOpacity(0.1), width: 2),
      ),
    );
  }
}

// Deprecated: StatProgressBar (Kept as empty or stub if needed for compilation, 
// OR replaced by ChocoGauge. If old screens use it, we map it to ChocoGauge Row)
class StatProgressBar extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final double height;

  const StatProgressBar({
    super.key,
    required this.label,
    required this.value,
    this.maxValue = 100,
    this.height = 14, 
  });

  @override
  Widget build(BuildContext context) {
     // Fallback to minimal text row for now to avoid breaking battle screen layout heavily
     Color color = StatColorMapper.getColor(label);
     return Padding(
       padding: const EdgeInsets.symmetric(vertical: 4),
       child: Row(
         children: [
           Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
           const SizedBox(width: 8),
           Expanded(
             child: ClipRRect(
               borderRadius: BorderRadius.circular(4),
               child: LinearProgressIndicator(
                 value: value / maxValue,
                 color: color,
                 backgroundColor: AppColors.stroke.withOpacity(0.1),
                 minHeight: 8,
               ),
             ),
           )
         ],
       ),
     );
  }
}
