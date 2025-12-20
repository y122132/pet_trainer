import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'camera_screen.dart';
import '../providers/char_provider.dart';
import 'package:camera/camera.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 캐릭터 데이터 로드 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CharProvider>(context, listen: false).fetchCharacter(1);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA), // 연한 회색 배경
      body: SafeArea(
        child: Consumer<CharProvider>(
          builder: (context, provider, child) {
            return Column(
              children: [
                // 1. 상단 바 (타이틀 + 메시지 버튼)
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
                
                // 3. 하단 액션 버튼 (고정됨)
                _buildBottomButton(context),
              ],
            );
          },
        ),
      ),
    );
  }

  // 상단 바 위젯 생성
  Widget _buildTopBar(CharProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 타이틀 배지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.stars_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text(
                  // 근력(STR)을 기준으로 한 단순 칭호 로직
                  provider.strength > 50 ? "근육대장님" : "초보 트레이너",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
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
                // TODO: 메시지 보관함 열기 기능 구현
              },
            ),
          ),
        ],
      ),
    );
  }

  // 캐릭터 표시 영역 위젯
  Widget _buildCharacterArea(CharProvider provider) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 캐릭터 이미지 (애니메이션 효과 포함)
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Image.asset(
              provider.imagePath,
              key: ValueKey<String>(provider.imagePath),
              fit: BoxFit.contain,
            ),
          ),
        ),
        
        // 닉네임 표시 박스
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
          ),
          child: const Text(
            "라이프고치",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent),
          ),
        ),
      ],
    );
  }

  // 스탯 차트 영역 위젯
  Widget _buildStatsArea(BuildContext context, CharProvider provider) {
    final stats = provider.statsMap;
    final keys = stats.keys.toList();
    
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
          // 레이더 차트 (육각형 스탯 그래프)
          AspectRatio(
            aspectRatio: 1.3,
            child: _buildRadarChart(stats),
          ),
          
          const Spacer(),
          
          // 개별 스탯 바 (Stat Bars)
          ...keys.map((key) {
            return _buildStatRow(key, stats[key] ?? 0);
          }).toList(),
        ],
      ),
    );
  }
  
  // 레이더 차트 생성 헬퍼
  Widget _buildRadarChart(Map<String, int> stats) {
    // 차트 데이터 정규화 (필요시 0-100 범위로 조정)
    List<RadarEntry> entries = stats.values.map((v) => RadarEntry(value: v.toDouble())).toList();
    
    return RadarChart(
      RadarChartData(
        radarTouchData: RadarTouchData(enabled: false), // 터치 비활성화
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

  // 개별 스탯 바 생성 헬퍼
  Widget _buildStatRow(String label, int value) {
    Color color = Colors.grey;
    if (label == "STR") color = Colors.redAccent;
    if (label == "INT") color = Colors.blueAccent;
    if (label == "DEX") color = Colors.greenAccent;
    
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
                value: value / 100, // 100 기준 퍼센트 계산
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

  // 하단 버튼 ("오늘의 운동 시작하기")
  Widget _buildBottomButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () async {
             try {
                // 사용 가능한 카메라 확인 후 이동
                final cameras = await availableCameras();
                if (cameras.isEmpty) return;
                Navigator.push(context, MaterialPageRoute(builder: (c) => CameraScreen(cameras: cameras)));
             } catch (e) {
                print("Camera Error: $e");
             }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigoAccent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text("오늘의 운동 시작하기", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
