import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class StatDistributionDialog extends StatefulWidget {
  final int availablePoints; // 분배 가능한 총 포인트
  final Map<String, int> currentStats; // 현재 스탯 정보
  final Function(Map<String, int> allocated, int remaining) onConfirm; // 확인 콜백
  final VoidCallback onSkip; // 건너뛰기 콜백
  final String title;
  final String confirmLabel;
  final String skipLabel;

  const StatDistributionDialog({
    super.key,
    required this.availablePoints,
    required this.currentStats,
    required this.onConfirm,
    required this.onSkip,
    this.title = "스탯 분배",
    this.confirmLabel = "확인",
    this.skipLabel = "나중에 하기",
  });

  @override
  State<StatDistributionDialog> createState() => _StatDistributionDialogState();
}

class _StatDistributionDialogState extends State<StatDistributionDialog> {
  late int remainingPoints;
  late Map<String, int> allocated;

  @override
  void initState() {
    super.initState();
    remainingPoints = widget.availablePoints;
    
    // 할당된 스탯 초기화
    allocated = {
      "strength": 0,
      "intelligence": 0,
      "stamina": 0,
      "happiness": 0,
      "health": 0, // health 추가
    };
  }

  // 포인트 할당
  void _allocate(String stat) {
    if (remainingPoints > 0) {
      setState(() {
        allocated[stat] = (allocated[stat] ?? 0) + 1;
        remainingPoints--;
      });
    }
  }

  // 할당 취소 (길게 누르기)
  void _deallocate(String stat) {
    if ((allocated[stat] ?? 0) > 0) {
       setState(() {
        allocated[stat] = allocated[stat]! - 1;
        remainingPoints++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
       child: Container(
         padding: const EdgeInsets.all(20),
         constraints: const BoxConstraints(maxHeight: 650),
         decoration: BoxDecoration(
           borderRadius: BorderRadius.circular(20),
           color: Colors.white,
         ),
         child: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo)),
             const SizedBox(height: 10),
             Text("보너스 포인트: $remainingPoints", 
               style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
             const SizedBox(height: 5),
             const Text("차트 옆 + 버튼을 눌러 스탯을 올리세요!", style: TextStyle(fontSize: 12, color: Colors.grey)),
             const SizedBox(height: 20),
             
             // 레이더 차트 영역
             Expanded(
               child: Stack(
                 children: [
                   // 차트
                   Positioned.fill(
                     child: Padding(
                       padding: const EdgeInsets.all(30.0), // 버튼 공간 확보
                       child: _buildRadarChart(),
                     ),
                   ),
                   // 제어 버튼들 (Overlay)
                   Align(
                     alignment: Alignment.topCenter,
                     child: _buildStatCtrl("근력", "strength", Colors.redAccent),
                   ),
                   Align(
                     alignment: Alignment.centerRight,
                     child: _buildStatCtrl("지능", "intelligence", Colors.blueAccent),
                   ),
                   Align(
                     alignment: Alignment.bottomCenter,
                     child: _buildStatCtrl("행복", "happiness", Colors.pinkAccent),
                   ),
                   Align(
                     alignment: Alignment.centerLeft,
                     child: _buildStatCtrl("체력", "stamina", Colors.green),
                   ),
                 ],
               ),
             ),
             
             const SizedBox(height: 20),
             
             // 하단 버튼 (건너뛰기 / 확인)
             Row(
               children: [
                 Expanded(
                   child: TextButton(
                     onPressed: widget.onSkip,
                     child: Text(widget.skipLabel, style: const TextStyle(color: Colors.grey)),
                   ),
                 ),
                 Expanded(
                   child: ElevatedButton(
                     style: ElevatedButton.styleFrom(
                       backgroundColor: remainingPoints == 0 ? Colors.indigo : Colors.grey.shade400,
                       padding: const EdgeInsets.symmetric(vertical: 15),
                     ),
                     // 포인트를 다 써야만 확인 가능 (기획에 따라 변경 가능)
                     onPressed: remainingPoints == 0 ? () => widget.onConfirm(allocated, remainingPoints) : null,
                     child: Text(widget.confirmLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                   ),
                 ),
               ],
             ),
           ],
         ),
       ),
    );
  }
  
  // 스탯 증가 버튼 위젯
  Widget _buildStatCtrl(String label, String key, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
        InkWell(
           onTap: remainingPoints > 0 ? () => _allocate(key) : null,
           onLongPress: () => _deallocate(key), // 길게 눌러 취소 기능
           child: Container(
             margin: const EdgeInsets.only(top: 2),
             decoration: BoxDecoration(
               color: remainingPoints > 0 ? color : Colors.grey[300], 
               shape: BoxShape.circle
             ),
             width: 32, height: 32,
             child: const Icon(Icons.add, size: 20, color: Colors.white),
           ),
        ),
        Text("+${allocated[key] ?? 0}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
  
  // 레이더 차트 (현재 스탯 + 할당량 시각화)
  Widget _buildRadarChart() {
    // 0이 되지 않도록 기본값 처리
    final data = [
      (widget.currentStats["strength"]! + (allocated["strength"] ?? 0)).toDouble(),
      (widget.currentStats["intelligence"]! + (allocated["intelligence"] ?? 0)).toDouble(),
      (widget.currentStats["happiness"]! + (allocated["happiness"] ?? 0)).toDouble(),
      (widget.currentStats["stamina"]! + (allocated["stamina"] ?? 0)).toDouble(),
    ];
    
    return RadarChart(
      RadarChartData(
        radarTouchData: RadarTouchData(enabled: false),
        dataSets: [
          RadarDataSet(
            fillColor: Colors.indigo.withOpacity(0.2),
            borderColor: Colors.indigo,
            entryRadius: 2,
            dataEntries: data.map((v) => RadarEntry(value: v)).toList(),
            borderWidth: 2,
          ),
        ],
        radarBackgroundColor: Colors.transparent,
        borderData: FlBorderData(show: false),
        radarBorderData: const BorderSide(color: Colors.transparent),
        titlePositionPercentageOffset: 0.1,
        titleTextStyle: const TextStyle(color: Colors.transparent), 
        tickCount: 1,
        ticksTextStyle: const TextStyle(color: Colors.transparent),
        gridBorderData: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
    );
  }
}
