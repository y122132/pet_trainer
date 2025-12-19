import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'camera_screen.dart';
import '../providers/char_provider.dart';
import '../widgets/stat_distribution_dialog.dart';
import 'package:camera/camera.dart';

class MyRoomPage extends StatelessWidget {
  const MyRoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA), // 연한 회색 배경
      body: SafeArea(
        child: Column(
          children: [
            // 상단 커스텀 앱바 (뒤로가기 포함)
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
                   const SizedBox(width: 48), // 타이틀 중앙 정렬을 위한 여백 균형
                 ],
               ),
            ),
            
            Expanded(
              child: Consumer<CharProvider>(
                builder: (context, provider, child) {
                  return Column(
                    children: [
                      // 1. 상단 정보 바 (타이틀, 메시지)
                      _buildTopBar(provider),

                      // 2. 메인 콘텐츠 (좌우 분할 레이아웃)
                      Expanded(
                        child: Row(
                          children: [
                            // 왼쪽: 캐릭터 영역 (40%)
                            Expanded(
                              flex: 4,
                              child: _buildCharacterArea(provider),
                            ),
                            
                            // 오른쪽: 스탯 및 차트 영역 (60%)
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

  // 상단 바 위젯
  Widget _buildTopBar(CharProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 타이틀 배지 (Flexible로 감싸서 오버플로우 방지)
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
                      // 단순 타이틀 로직 (근력 기준) 추후 고도화 필요
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
          
          // 메시지 버튼 (알림함)
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
                // TODO: 메시지함 열기
              },
            ),
          ),
        ],
      ),
    );
  }

  // 캐릭터 표시 영역
  Widget _buildCharacterArea(CharProvider provider) {
    // 안전장치: 캐릭터 정보가 없을 때 로딩
    final stat = provider.character?.stat;
    final maxHealth = 100; // 임시 상수
    final currentHealth = stat?.health ?? 100;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 캐릭터 이미지
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Image.asset(
              provider.character?.imageUrl ?? 'assets/images/characters/char_default.png',
              key: ValueKey<String>(provider.character?.imageUrl ?? 'normal'),
              fit: BoxFit.contain,
            ),
          ),
        ),
        
        const SizedBox(height: 10),

        // 체력 바 (HP)
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
        
        // 닉네임 및 레벨 표시
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
              // 경험치 바 (EXP)
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

  // 스탯 및 차트 표시 영역
  Widget _buildStatsArea(BuildContext context, CharProvider provider) {
    if (provider.character == null || provider.character!.stat == null) {
      return const Center(child: Text("데이터 로딩 중..."));
    }

    final stat = provider.character!.stat!;
    final statsMap = {
      "STR": stat.strength,
      "INT": stat.intelligence,
      "DEX": stat.stamina, // DEX로 표기
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
          // 1. 미사용 포인트 분배 버튼 (포인트가 있을 때만 표시)
          if (provider.unusedStatPoints > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upgrade, size: 16),
                label: Text("스탯 분배 (${provider.unusedStatPoints})"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigoAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: () {
                   showDialog(
                     context: context,
                     builder: (context) => StatDistributionDialog(
                       availablePoints: provider.unusedStatPoints,
                       currentStats: {
                          "strength": stat.strength,
                          "intelligence": stat.intelligence,
                          "stamina": stat.stamina,
                          "happiness": stat.happiness,
                          "health": stat.health,
                       },
                       title: "미사용 포인트 분배",
                       confirmLabel: "적용",
                       skipLabel: "취소",
                       onConfirm: (allocated, remaining) {
                          // 할당된 포인트 적용 (Provider 호출 루프)
                          _applyAllocated(provider, 'strength', allocated['strength']!);
                          _applyAllocated(provider, 'intelligence', allocated['intelligence']!);
                          _applyAllocated(provider, 'stamina', allocated['stamina']!);
                          _applyAllocated(provider, 'happiness', allocated['happiness']!);
                          _applyAllocated(provider, 'health', allocated['health']!);
                          
                          // 남은 포인트 업데이트 로직
                          // 방법 1: 소모한 만큼 unusedStatPoints 차감
                          // 현재 provider.allocateStatSpecific()은 1 증가를 시키지만,
                          // unusedPoints를 직접 감소시키는 로직이 provider 내부에 있는지 확인해야 함.
                          // CharProvider 코드(`step 1971`)를 보면 `_unusedStatPoints -= 1` 코드가 있음.
                          // 따라서 `allocateStatSpecific` 호출 시 자동으로 차감됨.
                          
                          Navigator.pop(context);
                       },
                       onSkip: () {
                          Navigator.pop(context);
                       },
                     ),
                   );
                },
              ),
            ),

          // 2. 레이더 차트 (간소화된 뷰)
          AspectRatio(
            aspectRatio: 1.3,
            child: _buildRadarChart(statsMap),
          ),
          
          const Spacer(),
          
          // 3. 스탯 바 (Stat Bars)
          ...keys.map((key) {
            return _buildStatRow(key, statsMap[key] ?? 0);
          }).toList(),
        ],
      ),
    );
  }
  
  void _applyAllocated(CharProvider provider, String type, int amount) {
    for (int i=0; i<amount; i++) {
      provider.allocateStatSpecific(type); // 하나씩 증가 (내부에서 unused 포인트 차감)
    }
  }
  
  // 레이더 차트 위젯
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

  // 개별 스탯 바
  Widget _buildStatRow(String label, int value) {
    Color color = Colors.grey;
    if (label == "STR") color = Colors.redAccent;
    if (label == "INT") color = Colors.blueAccent;
    if (label == "DEX") color = Colors.greenAccent;
    if (label == "HAP") color = Colors.pinkAccent;
    
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
                value: (value / 100).clamp(0.0, 1.0), // 100 기준 퍼센트 (임시)
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
