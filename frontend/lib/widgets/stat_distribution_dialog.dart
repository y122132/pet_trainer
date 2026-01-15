import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // [NEW] Font
import 'common/stat_widgets.dart';
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/config/design_system.dart'; // [NEW] Design System


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
  final String? specialMessage; // [NEW] 스킬 획득 등 추가 메시
  
  const StatDistributionDialog({
    super.key,
    required this.availablePoints,
    required this.currentStats,
    required this.onConfirm,
    required this.onSkip,
    this.title = "스탯 성장", // Title Change
    this.confirmLabel = "성장 완료",
    this.skipLabel = "나중에",
    this.continueLabel = "계속 성장",
    this.earnedReward,
    this.earnedBonus,
    this.onContinue,
    this.specialMessage, 
  });

  @override
  State<StatDistributionDialog> createState() => _StatDistributionDialogState();
}

class _StatDistributionDialogState extends State<StatDistributionDialog> {
  late int remainingPoints;
  late Map<String, int> allocated;
  bool isDirectInput = false; // [NEW] 숫자 직접 입력 모드 여부

  // [NEW] 입력을 위한 컨트롤러들
  final Map<String, TextEditingController> _controllers = {};

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

    // 컨트롤러 초기화
    for (var key in allocated.keys) {
      _controllers[key] = TextEditingController(text: "0");
      _controllers[key]!.addListener(() => _onTextChanged(key));
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onTextChanged(String key) {
    if (!isDirectInput) return;
    
    final value = int.tryParse(_controllers[key]!.text) ?? 0;
    _updateAllocatedDirectly(key, value);
  }

  void _updateAllocatedDirectly(String key, int newValue) {
    if (newValue < 0) newValue = 0;

    // 다른 스탯들의 현재 할당량 합산
    int otherAllocatedSum = 0;
    allocated.forEach((k, v) {
      if (k != key) otherAllocatedSum += v;
    });

    // 새로 설정하려는 값이 총 포인트를 넘는지 체크
    if (otherAllocatedSum + newValue > widget.availablePoints) {
      newValue = widget.availablePoints - otherAllocatedSum;
      // 텍스트 필드 값 보정 (필요시 시점을 늦춰야 함)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controllers[key]!.text != newValue.toString()) {
          _controllers[key]!.text = newValue.toString();
          _controllers[key]!.selection = TextSelection.fromPosition(TextPosition(offset: _controllers[key]!.text.length));
        }
      });
    }

    setState(() {
      allocated[key] = newValue;
      remainingPoints = widget.availablePoints - (otherAllocatedSum + newValue);
    });
  }

  void _allocate(String stat) {
    if (remainingPoints > 0) {
      setState(() {
        allocated[stat] = (allocated[stat] ?? 0) + 1;
        remainingPoints--;
        // 컨트롤러 업데이트
        _controllers[stat]!.text = allocated[stat].toString();
      });
    }
  }

  void _deallocate(String stat) {
    if ((allocated[stat] ?? 0) > 0) {
       setState(() {
        allocated[stat] = allocated[stat]! - 1;
        remainingPoints++;
        // 컨트롤러 업데이트
        _controllers[stat]!.text = allocated[stat].toString();
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success),
      ),
      child: Text(
        rewardText,
        style: GoogleFonts.jua(color: AppColors.textMain, fontWeight: FontWeight.bold),
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
       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32.0)),
       backgroundColor: Colors.transparent, // Transparent to use custom container
       elevation: 0,
       child: Container(
         padding: const EdgeInsets.all(24),
         constraints: const BoxConstraints(maxHeight: 700),
         decoration: BoxDecoration(
           borderRadius: BorderRadius.circular(32),
           color: AppColors.white,
           boxShadow: AppDecorations.softShadow, // Warm shadow
         ),
         child: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             // Header
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 const SizedBox(width: 48), // Balance for icon
                 Text(widget.title, style: GoogleFonts.jua(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                 Container(
                   decoration: BoxDecoration(
                     color: AppColors.background,
                     shape: BoxShape.circle,
                   ),
                   child: IconButton(
                     icon: Icon(isDirectInput ? Icons.radar : Icons.edit_note_rounded, color: AppColors.primary),
                     tooltip: isDirectInput ? "차트 보기" : "직접 입력",
                     onPressed: () => setState(() => isDirectInput = !isDirectInput),
                   ),
                 ),
               ],
             ),
             const SizedBox(height: 16),
             
             _buildRewardInfo(),
             
             if (widget.specialMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(widget.specialMessage!, 
                     textAlign: TextAlign.center,
                     style: GoogleFonts.jua(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 14)
                  ),
                ),

             // Remaining Points Card
             Container(
               padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
               decoration: BoxDecoration(
                 color: AppColors.primary,
                 borderRadius: BorderRadius.circular(20),
                 boxShadow: [
                   BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
                 ]
               ),
               child: Column(
                 children: [
                   Text("성장 포인트", style: GoogleFonts.jua(color: Colors.white, fontSize: 12)),
                   Text("$remainingPoints P", style: GoogleFonts.jua(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                 ],
               ),
             ),
             const SizedBox(height: 12),
             Text(
               "차트 옆 + 버튼을 눌러 스탯을 올리세요!", 
               textAlign: TextAlign.center,
               style: GoogleFonts.jua(fontSize: 13, color: AppColors.textSub)
             ),
             const SizedBox(height: 20),
             
             Expanded(
               child: isDirectInput 
                 ? ListView(
                     padding: const EdgeInsets.symmetric(vertical: 10),
                     children: allocated.keys.map((key) => _buildDirectInputRow(key)).toList(),
                   )
                 : Stack(
                     children: [
                       // 1. 공용 레이더 차트 (배경)
                       Positioned.fill(
                         child: Padding(
                           padding: const EdgeInsets.all(30.0), 
                           child: StatRadarChart(stats: currentMap, showLabels: false), 
                         ),
                       ),
                       // 2. 각 방향별 스탯 제어 위젯 (배치 유지 + 수치 표시)
                       Align(alignment: Alignment.topCenter, child: _buildStatCtrl("근력", "strength", currentMap["strength"]!)),
                       Align(alignment: Alignment.centerRight, child: _buildStatCtrl("지능", "intelligence", currentMap["intelligence"]!)),
                       Align(alignment: Alignment.bottomRight, child: _buildStatCtrl("운", "luck", currentMap["luck"]!)),
                       Align(alignment: Alignment.bottomLeft, child: _buildStatCtrl("방어", "defense", currentMap["defense"]!)),
                       Align(alignment: Alignment.centerLeft, child: _buildStatCtrl("민첩", "agility", currentMap["agility"]!)),
                     ],
                   ),
             ),
             
             const SizedBox(height: 24),
             
             // Buttons
             Row(
               children: [
                 Expanded(
                   child: TextButton(
                     onPressed: widget.onSkip,
                     style: TextButton.styleFrom(
                       padding: const EdgeInsets.symmetric(vertical: 16),
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                     ),
                     child: Text(widget.skipLabel, style: GoogleFonts.jua(color: AppColors.textSub, fontSize: 16)),
                   ),
                 ),
                 if (widget.onContinue != null) ...[
                   const SizedBox(width: 8),
                   Expanded(
                     child: TextButton(
                       onPressed: widget.onContinue,
                        style: TextButton.styleFrom(
                         padding: const EdgeInsets.symmetric(vertical: 16),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                       ),
                        child: Text(widget.continueLabel, style: GoogleFonts.jua(color: AppColors.primary, fontSize: 16)),
                     ),
                   ),
                 ],
                 const SizedBox(width: 8),
                 Expanded(
                   child: ElevatedButton(
                     onPressed: () {
                       widget.onConfirm(allocated, remainingPoints);
                     }, 
                     style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textMain,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                     ),
                     child: Text(widget.confirmLabel, style: GoogleFonts.jua(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                   ),
                 ),
               ],
             ),
           ],
         ),
       ),
    );
  }
  
  Widget _buildStatCtrl(String label, String key, int currentValue) {
    Color color = StatColorMapper.getColor(key);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label with Value [NEW]
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3))
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: GoogleFonts.jua(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
              const SizedBox(width: 4),
              Text("$currentValue", style: GoogleFonts.jua(fontWeight: FontWeight.bold, color: AppColors.textMain, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 감소 버튼 (-)
            InkWell(
              onTap: (allocated[key] ?? 0) > 0 ? () => _deallocate(key) : null,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  color: (allocated[key] ?? 0) > 0 ? AppColors.textSub.withOpacity(0.2) : AppColors.background, 
                  shape: BoxShape.circle
                ),
                width: 32, height: 32,
                alignment: Alignment.center,
                child: const Icon(Icons.remove, size: 16, color: AppColors.textMain),
              ),
            ),
            const SizedBox(width: 8),
            // 증가 버튼 (+)
            InkWell(
               onTap: remainingPoints > 0 ? () => _allocate(key) : null,
               onLongPress: () => _deallocate(key), 
               borderRadius: BorderRadius.circular(20),
               child: Container(
                 decoration: BoxDecoration(
                   color: remainingPoints > 0 ? color : AppColors.background, 
                   shape: BoxShape.circle,
                   boxShadow: remainingPoints > 0 ? [
                     BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))
                   ] : []
                 ),
                 width: 40, height: 40,
                 child: const Icon(Icons.add_rounded, size: 24, color: Colors.white),
               ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        // Allocation Count
        if ((allocated[key] ?? 0) > 0)
          Text("+${allocated[key] ?? 0}", style: GoogleFonts.jua(fontSize: 12, color: color, fontWeight: FontWeight.bold))
        else 
          const SizedBox(height: 14), // Placeholder to prevent jump
      ],
    );
  }

  // 직접 수치 입력 행 빌더
  Widget _buildDirectInputRow(String key) {
    Color color = StatColorMapper.getColor(key);
    String label = "";
    switch(key) {
      case "strength": label = "근력 (STR)"; break;
      case "intelligence": label = "지능 (INT)"; break;
      case "agility": label = "민첩 (DEX)"; break;
      case "defense": label = "방어 (DEF)"; break;
      case "luck": label = "운 (LUK)"; break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16)
        ),
        child: Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: GoogleFonts.jua(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textMain))),
            Text("${widget.currentStats[key]!} + ", style: GoogleFonts.jua(color: AppColors.textSub, fontSize: 14)),
            
            SizedBox(
              width: 70,
              child: TextField(
                controller: _controllers[key],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: GoogleFonts.jua(fontWeight: FontWeight.bold, color: color, fontSize: 18),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.primary, width: 2)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
