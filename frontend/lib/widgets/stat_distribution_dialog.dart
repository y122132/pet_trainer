import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'common/stat_widgets.dart'; // [New]

// --- 스탯 분배 다이얼로그 (StatDistributionDialog) ---
class StatDistributionDialog extends StatefulWidget {
  final int availablePoints; // 분배 가능한 총 포인트
  final Map<String, int> currentStats; // 현재 캐릭터의 스탯 정보
  final Function(Map<String, int> allocated, int remaining) onConfirm; // 확인 버튼 클릭 시 콜백
  final VoidCallback onSkip; // 건너뛰기 버튼 클릭 시 콜백
  final String title;        // 다이얼로그 제목
  final String confirmLabel; // 확인 버튼 텍스트
  final String skipLabel;    // 건너뛰기 버튼 텍스트
  final String continueLabel; // [NEW] 계속하기 버튼 라벨
  
  // 새로 획득한 보상 표시를 위한 파라미터 (선택)
  final Map<String, dynamic>? earnedReward;
  final int? earnedBonus;
  final VoidCallback? onContinue; // [NEW] 계속하기 콜백
  
  const StatDistributionDialog({
    super.key,
    required this.availablePoints,
    required this.currentStats,
    required this.onConfirm,
    required this.onSkip,
    this.title = "스탯 분배",
    this.confirmLabel = "확인",
    this.skipLabel = "나중에 하기",
    this.continueLabel = "한 번 더 하기",
    this.earnedReward,
    this.earnedBonus,
    this.onContinue,
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
    
    // 할당된 포인트 초기화
    allocated = {
      "strength": 0,
      "intelligence": 0,
      "agility": 0,
      "defense": 0,
      "luck": 0,
    };
  }

  void _allocate(String stat) {
    if (remainingPoints > 0) {
      setState(() {
        allocated[stat] = (allocated[stat] ?? 0) + 1;
        remainingPoints--;
      });
    }
  }

  void _deallocate(String stat) {
    if ((allocated[stat] ?? 0) > 0) {
       setState(() {
        allocated[stat] = allocated[stat]! - 1;
        remainingPoints++;
      });
    }
  }

  Widget _buildRewardInfo() {
    if (widget.earnedReward == null || widget.earnedReward!.isEmpty) {
      return const SizedBox.shrink();
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
    // 실시간으로 변하는 스탯 합산
    final currentMap = {
      "strength": widget.currentStats["strength"]! + (allocated["strength"] ?? 0),
      "intelligence": widget.currentStats["intelligence"]! + (allocated["intelligence"] ?? 0),
      "luck": widget.currentStats["luck"]! + (allocated["luck"] ?? 0),
      "defense": widget.currentStats["defense"]! + (allocated["defense"] ?? 0),
      "agility": widget.currentStats["agility"]! + (allocated["agility"] ?? 0),
    };

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
             
             _buildRewardInfo(),

             Text("분배 가능 포인트: $remainingPoints", 
               style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
             const SizedBox(height: 5),
             const Text("차트 옆 + 버튼을 눌러 스탯을 올리세요!\n(길게 누르면 취소)", 
               textAlign: TextAlign.center,
               style: TextStyle(fontSize: 12, color: Colors.grey)),
             const SizedBox(height: 20),
             
             Expanded(
               child: Stack(
                 children: [
                   // 1. 공용 레이더 차트 사용
                   Positioned.fill(
                     child: Padding(
                       padding: const EdgeInsets.all(30.0), 
                       child: StatRadarChart(stats: currentMap, showLabels: false), // 라벨 없이
                     ),
                   ),
                   // 2. 각 방향별 스탯 제어 위젯 (위치는 유지)
                   Align(
                     alignment: Alignment.topCenter,
                     child: _buildStatCtrl("근력", "strength"),
                   ),
                   Align(
                     alignment: Alignment.centerRight,
                     child: _buildStatCtrl("지능", "intelligence"),
                   ),
                   Align(
                     alignment: Alignment.bottomRight,
                     child: _buildStatCtrl("운", "luck"),
                   ),
                   Align(
                     alignment: Alignment.bottomLeft,
                     child: _buildStatCtrl("방어", "defense"),
                   ),
                   Align(
                     alignment: Alignment.centerLeft,
                     child: _buildStatCtrl("민첩", "agility"),
                   ),
                 ],
               ),
             ),
             
             const SizedBox(height: 20),
             
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onSkip,
                child: Text(widget.skipLabel, style: const TextStyle(color: Colors.grey)),
              ),
              if (widget.onContinue != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: widget.onContinue,
                  child: Text(widget.continueLabel, style: const TextStyle(color: Colors.indigo)),
                ),
              ],
              const SizedBox(width: 8),
              ElevatedButton(
                // 변경: 남은 포인트가 있어도 적용 가능하도록 수정
                onPressed: () {
                  widget.onConfirm(allocated, remainingPoints);
                }, 
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(widget.confirmLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
           ],
         ),
       ),
    );
  }
  
  Widget _buildStatCtrl(String label, String key) {
    // 색상은 Mapper에서 가져옴
    Color color = StatColorMapper.getColor(key);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 감소 버튼 (-)
            InkWell(
              onTap: (allocated[key] ?? 0) > 0 ? () => _deallocate(key) : null,
              child: Container(
                decoration: BoxDecoration(
                  color: (allocated[key] ?? 0) > 0 ? Colors.redAccent.withOpacity(0.8) : Colors.grey[300], 
                  shape: BoxShape.circle
                ),
                width: 28, height: 28,
                alignment: Alignment.center,
                child: const Icon(Icons.remove, size: 18, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            // 증가 버튼 (+)
            InkWell(
               onTap: remainingPoints > 0 ? () => _allocate(key) : null,
               onLongPress: () => _deallocate(key), // 롱프레스 감소 기능 유지
               child: Container(
                 decoration: BoxDecoration(
                   color: remainingPoints > 0 ? color : Colors.grey[300], 
                   shape: BoxShape.circle
                 ),
                 width: 32, height: 32,
                 child: const Icon(Icons.add, size: 20, color: Colors.white),
               ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text("+${allocated[key] ?? 0}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
