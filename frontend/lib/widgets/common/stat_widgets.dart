import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/design_system.dart'; // Import design system for colors

// --- 스탯 색상 매퍼 ---
class StatColorMapper {
  static Color getColor(String key) {
    switch (key.toUpperCase()) {
      case 'STR':
      case 'STRENGTH':
      case '근력':
        return AppColors.statStr;
      case 'INT':
      case 'INTELLIGENCE':
      case '지능':
        return AppColors.statInt;
      case 'DEX':
      case 'AGILITY':
      case '민첩':
        return AppColors.statDex;
      case 'DEF':
      case 'DEFENSE':
      case '방어':
        return AppColors.statDef;
      case 'LUK':
      case 'LUCK':
      case '운':
        return const Color(0xFFD7CCC8); // Use DEF color for LUK as per design
      case 'HAP':
      case 'HAPPINESS':
      case '행복':
        return AppColors.statDef;
      default:
        return AppColors.secondaryBrown;
    }
  }
}

// --- 공용 레이더 차트 위젯 ---
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
    // 5각형 스탯 순서 고정 (레이더 차트의 균형을 위해)
    // Strength(상) -> Intelligence(우) -> Luck(우하) -> Defense(좌하) -> Agility(좌)
    // 데이터가 맵으로 들어오면 이 순서대로 매핑
    final keys = ['strength', 'intelligence', 'luck', 'defense', 'agility'];
    final labels = ['STR', 'INT', 'LUK', 'DEF', 'DEX'];
    
    // 만약 stats 키가 한글이나 축약어라면 대응 필요하지만, 
    // 현재 프로젝트에서는 'strength', 'intelligence' 등 풀네임 key 사용 중.
    
    List<RadarEntry> entries = keys.map((k) {
      final val = stats[k] ?? stats[k.toUpperCase()] ?? 0;
      return RadarEntry(value: val.toDouble());
    }).toList();

    // Determine colors based on input or default
    final fillColor = (graphColors != null && graphColors!.isNotEmpty)
        ? graphColors![0]
        : AppColors.statInt.withOpacity(0.2);
    final borderColor = (graphColors != null && graphColors!.length > 1)
        ? graphColors![1]
        : AppColors.secondaryBrown;

    return RadarChart(
      RadarChartData(
        radarTouchData: RadarTouchData(enabled: false),
        dataSets: [
          RadarDataSet(
            fillColor: fillColor,
            borderColor: borderColor,
            entryRadius: 2,
            dataEntries: entries,
            borderWidth: 1.5, // Thinner line
          ),
        ],
        radarBackgroundColor: Colors.transparent,
        borderData: FlBorderData(show: false),
        radarBorderData: const BorderSide(color: Colors.transparent),
        titlePositionPercentageOffset: 0.2, // Adjust label position
        titleTextStyle: labelStyle ?? AppTextStyles.body.copyWith(fontSize: 14),
        getTitle: (index, angle) {
            if (!showLabels) return const RadarChartTitle(text: "");
            if (index < labels.length) {
               return RadarChartTitle(text: labels[index]);
            }
            return const RadarChartTitle(text: "");
        },
        tickCount: 1,
        ticksTextStyle: const TextStyle(color: Colors.transparent),
        gridBorderData: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
    );
  }
}

// --- 공용 스탯 바 위젯 ---
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
    this.height = 10, // Slightly thicker
  });

  @override
  Widget build(BuildContext context) {
    Color color = StatColorMapper.getColor(label);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 45,
            child: Text(label, style: AppTextStyles.base.copyWith(color: color, fontSize: 14)),
          ),
          Expanded(
            child: Container(
              height: height,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height),
                  color: Colors.black.withOpacity(0.05),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(height),
                child: LinearProgressIndicator(
                  value: (value / maxValue).clamp(0.0, 1.0),
                  backgroundColor: Colors.transparent,
                  color: color,
                  minHeight: height,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text("$value", style: AppTextStyles.base.copyWith(fontSize: 14, color: AppColors.secondaryBrown)),
        ],
      ),
    );
  }
}
