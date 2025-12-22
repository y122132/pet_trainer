import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

// --- 스탯 분배 다이얼로그 (StatDistributionDialog) ---
// 훈련 보상이나 레벨업으로 얻은 보너스 포인트를 캐릭터의 능력치에 투자하는 팝업창입니다.
class StatDistributionDialog extends StatefulWidget {
  final int availablePoints; // 분배 가능한 총 포인트
  final Map<String, int> currentStats; // 현재 캐릭터의 스탯 정보
  final Function(Map<String, int> allocated, int remaining) onConfirm; // 확인 버튼 클릭 시 콜백
  final VoidCallback onSkip; // 건너뛰기 버튼 클릭 시 콜백
  final String title;        // 다이얼로그 제목
  final String confirmLabel; // 확인 버튼 텍스트
  final String skipLabel;    // 건너뛰기 버튼 텍스트
  
  // 새로 획득한 보상 표시를 위한 파라미터 (선택)
  final Map<String, dynamic>? earnedReward;
  final int? earnedBonus;

  const StatDistributionDialog({
    super.key,
    required this.availablePoints,
    required this.currentStats,
    required this.onConfirm,
    required this.onSkip,
    this.title = "스탯 분배",
    this.confirmLabel = "확인",
    this.skipLabel = "나중에 하기",
    this.earnedReward,
    this.earnedBonus,
  });

  @override
  State<StatDistributionDialog> createState() => _StatDistributionDialogState();
}

class _StatDistributionDialogState extends State<StatDistributionDialog> {
  late int remainingPoints; // 남은 포인트 (UI 표시용)
  late Map<String, int> allocated; // 이번 팝업에서 새로 할당한 포인트들

  @override
  void initState() {
    super.initState();
    remainingPoints = widget.availablePoints;
    
    // 할당된 포인트 초기화 (모든 스탯 0부터 시작)
    allocated = {
      "strength": 0,
      "intelligence": 0,
      "stamina": 0,
      "happiness": 0,
      "health": 0,
    };
  }

  // [로직] 포인트 할당 (+ 버튼 클릭 시)
  void _allocate(String stat) {
    if (remainingPoints > 0) {
      setState(() {
        allocated[stat] = (allocated[stat] ?? 0) + 1;
        remainingPoints--;
      });
    }
  }

  // [로직] 할당 취소 (버튼 길게 누르기 시)
  void _deallocate(String stat) {
    if ((allocated[stat] ?? 0) > 0) {
       setState(() {
        allocated[stat] = allocated[stat]! - 1;
        remainingPoints++;
      });
    }
  }

  // 획득 보상 메시지 위젯 생성
  Widget _buildRewardInfo() {
    if (widget.earnedReward == null || widget.earnedReward!.isEmpty) {
      return const SizedBox.shrink(); // 보상 정보 없으면 표시 안함
    }
    
    final String statType = widget.earnedReward!['stat_type'] ?? '??';
    final int statValue = widget.earnedReward!['value'] ?? 0;
    final int bonus = widget.earnedBonus ?? 0;
    
    String rewardText = "기본 보상: ${statType.toUpperCase()} +$statValue";
    if (bonus > 0) {
      rewardText += ", 보너스: +$bonus";
    }

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Text(
        rewardText,
        style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold),
      ),
    );
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
             
             // 획득한 보상 정보 표시
             _buildRewardInfo(),

             // 현재 남은 포인트 수량 표시
             Text("분배 가능 포인트: $remainingPoints", 
               style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
             const SizedBox(height: 5),
             const Text("차트 옆 + 버튼을 눌러 스탯을 올리세요!\n(길게 누르면 취소)", 
               textAlign: TextAlign.center,
               style: TextStyle(fontSize: 12, color: Colors.grey)),
             const SizedBox(height: 20),
             
             // [메인 레이아웃] 레이더 차트 + 스탯 제어 버튼 (Stack 활용)
             Expanded(
               child: Stack(
                 children: [
                   // 1. 중앙 레이더 차트 (실시간 반영)
                   Positioned.fill(
                     child: Padding(
                       padding: const EdgeInsets.all(30.0), // 버튼이 배치될 공간 확보
                       child: _buildRadarChart(),
                     ),
                   ),
                   // 2. 각 방향별 스탯 제어 위젯
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
             
             // [하단 버튼] 건너뛰기 또는 적용(확인)
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
                     // 모든 포인트를 소모해야 확인 가능하도록 설정 (선택 사항)
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
  
  // 개별 스탯 제어 버튼 생성 위젯
  Widget _buildStatCtrl(String label, String key, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
        InkWell(
           onTap: remainingPoints > 0 ? () => _allocate(key) : null,
           onLongPress: () => _deallocate(key), // 길게 누르면 투자한 포인트 회수
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
        // 이번에 몇 포인트 투자했는지 표시 (+1, +2...)
        Text("+${allocated[key] ?? 0}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
  
  // 레이더 차트 위젯: 현재 스탯에 새로 투자한 포인트를 합산하여 시각화
  Widget _buildRadarChart() {
    final data = [
      (widget.currentStats["strength"]! + (allocated["strength"] ?? 0)).toDouble(),
      (widget.currentStats["intelligence"]! + (allocated["intelligence"] ?? 0)).toDouble(),
      (widget.currentStats["happiness"]! + (allocated["happiness"] ?? 0)).toDouble(),
      (widget.currentStats["stamina"]! + (allocated["stamina"] ?? 0)).toDouble(),
    ];
    
    return RadarChart(
      RadarChartData(
        radarTouchData: RadarTouchData(enabled: false), // 인터랙션은 외부 버튼으로 처리
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
        titleTextStyle: const TextStyle(color: Colors.transparent), // 레이블은 수동으로 배치함
        tickCount: 1,
        ticksTextStyle: const TextStyle(color: Colors.transparent),
        gridBorderData: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
    );
  }
}
