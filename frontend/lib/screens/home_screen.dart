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
              ],
              _buildBottomButton(context),
            );
          },
          _buildBottomButton(context),
        ),
      );
    )
  };
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
                if (!context.mounted) return;
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
