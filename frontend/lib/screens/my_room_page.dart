import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'camera_screen.dart';
import '../providers/char_provider.dart';
import '../widgets/stat_distribution_dialog.dart';
import 'package:camera/camera.dart';

// --- 마이룸 페이지 (MyRoomPage) ---
// 반려동물의 상세 스탯을 확인하고, 획득한 포인트를 분배하며 휴식하는 공간입니다.
class MyRoomPage extends StatelessWidget {
  const MyRoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA), // 부드러운 연한 회색 배경
      body: SafeArea(
        child: Column(
          children: [
            // [헤더 영역] 상단 커스텀 앱바 (뒤로가기 버튼 포함)
            Padding(
               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   IconButton(
                     icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black54),
                     onPressed: () => Navigator.pop(context),
                   ),
                   const Text("마이룸", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                   const SizedBox(width: 48), // 중앙 정렬 유지를 위한 빈 공간
                 ],
               ),
            ),
            
            Expanded(
              child: Consumer<CharProvider>(
                builder: (context, provider, child) {
                  return Column(
                    children: [
                      // 1. 상단 정보 바 (사용자 칭호 및 알림)
                      _buildTopBar(provider),

                      // 2. 메인 레이아웃 (캐릭터 영역 40% : 스탯 영역 60% 분할)
                      Expanded(
                        child: Row(
                          children: [
                            // [왼쪽] 캐릭터 비주얼 영역
                            Expanded(
                              flex: 4,
                              child: _buildCharacterArea(provider),
                            ),
                            
                            // [오른쪽] 스탯 수치 및 레이더 차트 영역
                            Expanded(
                              flex: 6,
                              child: _buildStatsArea(context, provider),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20), // 하단 여백
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 상단 바 위젯: 사용자의 현재 칭호와 알림 아이콘 표시
  Widget _buildTopBar(CharProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 칭호 배지 (예: 근육대장님, 초보 트레이너)
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.stars_rounded, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      // 캐릭터 스탯 정보가 50을 넘으면 호칭 변경
                      provider.character?.stat?.strength != null && provider.character!.stat!.strength > 50 
                          ? "근육대장님" 
                          : "초보 트레이너",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 알림/메시지함 버튼
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                 BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.mail_outline_rounded, color: Colors.grey),
              onPressed: () {
                // TODO: 시스템 알림 또는 캐릭터 메시지함 기능 구현 예정
              },
            ),
          ),
        ],
      ),
    );
  }

  // 캐릭터 영역: 캐릭터 이미지와 HP/EXP 바 표시
  Widget _buildCharacterArea(CharProvider provider) {
    final stat = provider.character?.stat;
    final maxHealth = 100; // 최대 체력 기준값
    final currentHealth = stat?.health ?? 100;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 반려동물 이미지 (AnimatedSwitcher로 표정 변화 시 부드럽게 전환)
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Image.asset(
              provider.character?.imageUrl ?? 'assets/images/characters/닌자옷.png',
              key: ValueKey<String>(provider.character?.imageUrl ?? 'normal'),
              fit: BoxFit.contain,
            ),
          ),
        ),
        
        const SizedBox(height: 10),

        // [HP 바] 체력 상태 표시
        SizedBox(
          width: 140,
          child: Column(
            children: [
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   const Text("HP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.pinkAccent)),
                   Text("$currentHealth/$maxHealth", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black54)),
                 ],
               ),
               const SizedBox(height: 4),
               ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (currentHealth / maxHealth).clamp(0.0, 1.0),
                    backgroundColor: Colors.pink.withOpacity(0.1),
                    color: Colors.pinkAccent,
                    minHeight: 6,
                  ),
               ),
            ],
          ),
        ),

        const SizedBox(height: 15),
        
        // [정보창] 이름, 레벨, 경험치(EXP)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
            boxShadow: [
               BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))
            ]
          ),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "Lv.${stat?.level ?? 1}",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      provider.character?.name ?? "이름없음",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // [EXP 바] 경험치 진행률
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ((stat?.exp ?? 0) / 100.0).clamp(0.0, 1.0),
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    color: Colors.blueAccent,
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "EXP ${stat?.exp ?? 0}/100", 
                style: TextStyle(fontSize: 8, color: Colors.grey[600]),
              )
            ],
          ),
        ),
      ],
    );
  }

  // 스탯 영역: 레이더 차트와 세부 수치, 스탯 분배 기능 포함
  Widget _buildStatsArea(BuildContext context, CharProvider provider) {
    if (provider.character == null || provider.character!.stat == null) {
      return const Center(child: Text("데이터 로딩 중..."));
    }

    final stat = provider.character!.stat!;
    final statsMap = {
      "STR": stat.strength,
      "INT": stat.intelligence,
      "DEX": stat.agility, 
      "DEF": stat.defense,
      "LUK": stat.luck,
      "HAP": stat.happiness
    };
    final keys = statsMap.keys.toList();
    
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 10, 20, 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          // 1. [스탯 분배 버튼] 포인트가 남아있을 때만 노출됨
          if (provider.unusedStatPoints > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upgrade, size: 16),
                label: Text("스탯 분배 (${provider.unusedStatPoints}P)"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigoAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: () {
                   // 팝업을 띄워 원하는 스탯에 포인트 투자
                   showDialog(
                     context: context,
                     builder: (context) => StatDistributionDialog(
                       availablePoints: provider.unusedStatPoints,
                       currentStats: {
                          "strength": stat.strength,
                          "intelligence": stat.intelligence,
                          "agility": stat.agility,
                          "defense": stat.defense,
                          "luck": stat.luck,
                       },
                       title: "미사용 포인트 분배",
                       confirmLabel: "적용",
                       skipLabel: "취소",
                       onConfirm: (allocated, remaining) {
                          // 선택한 스탯만큼 반복해서 Provider 업데이트 호출
                          _applyAllocated(provider, 'strength', allocated['strength']!);
                          _applyAllocated(provider, 'intelligence', allocated['intelligence']!);
                          _applyAllocated(provider, 'agility', allocated['agility']!);
                          _applyAllocated(provider, 'defense', allocated['defense']!);
                          _applyAllocated(provider, 'luck', allocated['luck']!);
                          
                          Navigator.pop(context);
                       },
                       onSkip: () => Navigator.pop(context),
                     ),
                   );
                },
              ),
            ),

          // 2. [레이더 차트] 시각적인 능력치 밸런스 확인
          AspectRatio(
            aspectRatio: 1.3,
            child: _buildRadarChart(statsMap),
          ),
          
          const Spacer(),
          
          // 3. [세부 스탯 바] 각 능력치별 진행도 표시
          ...keys.map((key) {
            return _buildStatRow(key, statsMap[key] ?? 0);
          }).toList(),
        ],
      ),
    );
  }
  
  // 포인트 할당 적용 로직
  void _applyAllocated(CharProvider provider, String type, int amount) {
    for (int i=0; i<amount; i++) {
      provider.allocateStatSpecific(type); // 1포인트씩 소모하며 스탯 증가
    }
  }
  
  // 레이더 차트 위젯 빌더
  Widget _buildRadarChart(Map<String, int> stats) {
    List<RadarEntry> entries = stats.values.map((v) => RadarEntry(value: v.toDouble())).toList();
    
    return RadarChart(
      RadarChartData(
        radarTouchData: RadarTouchData(enabled: false),
        dataSets: [
          RadarDataSet(
            fillColor: Colors.blueAccent.withOpacity(0.2),
            borderColor: Colors.blueAccent,
            entryRadius: 2,
            dataEntries: entries,
            borderWidth: 2,
          ),
        ],
        radarBackgroundColor: Colors.transparent,
        borderData: FlBorderData(show: false),
        radarBorderData: const BorderSide(color: Colors.transparent),
        titlePositionPercentageOffset: 0.2,
        titleTextStyle: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
        getTitle: (index, angle) {
            if (index < stats.keys.length) {
               return RadarChartTitle(text: stats.keys.elementAt(index));
            }
            return const RadarChartTitle(text: "");
        },
        tickCount: 1,
        ticksTextStyle: const TextStyle(color: Colors.transparent),
        gridBorderData: BorderSide(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
    );
  }

  // 개별 스탯 바 위젯 빌더
  Widget _buildStatRow(String label, int value) {
    Color color = Colors.grey;
    if (label == "STR") color = Colors.redAccent;     // 근력: 빨강
    if (label == "INT") color = Colors.blueAccent;    // 지능: 파랑
    if (label == "DEX") color = Colors.greenAccent;   // 민첩: 초록
    if (label == "HAP") color = Colors.pinkAccent;    // 행복: 핑크
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          SizedBox(
            width: 40, 
            child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color))
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (value / 100).clamp(0.0, 1.0), // 100을 최대치로 가정
                backgroundColor: Colors.grey.shade100,
                color: color,
                minHeight: 8,
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
