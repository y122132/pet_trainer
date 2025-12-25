import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

// --- 스탯 색상 매퍼 ---
class StatColorMapper {
  static Color getColor(String key) {
    switch (key.toUpperCase()) {
      case 'STR':
      case 'STRENGTH':
      case '근력':
        return Colors.redAccent;
      case 'INT':
      case 'INTELLIGENCE':
      case '지능':
        return Colors.blueAccent;
      case 'DEX':
      case 'AGILITY':
      case '민첩':
        return Colors.greenAccent;
      case 'DEF':
      case 'DEFENSE':
      case '방어':
        return Colors.grey;
      case 'LUK':
      case 'LUCK':
      case '운':
        return Colors.amber;
      case 'HAP':
      case 'HAPPINESS':
      case '행복':
        return Colors.pinkAccent;
      default:
        return Colors.indigoAccent;
    }
  }
}

// --- 공용 레이더 차트 위젯 ---
class StatRadarChart extends StatelessWidget {
  final Map<String, int> stats;
  final double maxValue;
  final bool showLabels;

  const StatRadarChart({
    super.key,
    required this.stats,
    this.maxValue = 100.0,
    this.showLabels = true,
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

    return RadarChart(
      RadarChartData(
        radarTouchData: RadarTouchData(enabled: false),
        dataSets: [
          RadarDataSet(
            fillColor: Colors.indigo.withOpacity(0.2),
            borderColor: Colors.indigo,
            entryRadius: 2,
            dataEntries: entries,
            borderWidth: 2,
          ),
        ],
        radarBackgroundColor: Colors.transparent,
        borderData: FlBorderData(show: false),
        radarBorderData: const BorderSide(color: Colors.transparent),
        titlePositionPercentageOffset: 0.1,
        titleTextStyle: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
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
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    Color color = StatColorMapper.getColor(label);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (value / maxValue).clamp(0.0, 1.0),
                backgroundColor: Colors.grey.shade100,
                color: color,
                minHeight: height,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text("$value", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
        ],
      ),
    );
  }
}
