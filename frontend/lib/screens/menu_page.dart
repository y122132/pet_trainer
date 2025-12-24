import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'my_room_page.dart';
import 'mode_select_page.dart';
import 'battle_page.dart';
import '../providers/char_provider.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 앱 시작 시 초기 데이터 로드 (캐릭터 정보)
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   Provider.of<CharProvider>(context, listen: false).fetchCharacter(1);
    // });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Text(
              "PetTrainer",
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
            const SizedBox(height: 10),
            const Text(
              "지구 최강의 생명체를 키워보세요!",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 상태 표시 (Debug info)
                    Consumer<CharProvider>(
                      builder: (context, provider, child) {
                        if (provider.character != null) {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "✅ 접속됨: ${provider.character!.name} (ID: ${provider.character!.userId}, ${provider.character!.petType})",
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          );
                        } else {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "❌ 연결 안됨: ${provider.statusMessage}",
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    
                    // 테스트용 유저 변경 버튼 (런타임에 각각 다른 유저로 로그인하기 위함)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                             Provider.of<CharProvider>(context, listen: false).fetchCharacter(1);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[100]),
                          child: const Text("User 1 (Dog)"),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () {
                             Provider.of<CharProvider>(context, listen: false).fetchCharacter(2);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.pink[100]),
                          child: const Text("User 2 (Cat)"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 메인 메뉴 버튼들
                    _buildMenuButton(
                      context,
                      "🏠 마이룸",
                      "캐릭터 상태 확인 및 휴식",
                      Colors.orangeAccent,
                      () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyRoomPage())),
                    ),
                    _buildMenuButton(
                      context,
                      "🏋️ 훈련장",
                      "운동하고 스탯을 올리세요!",
                      Colors.blueAccent,
                      () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ModeSelectPage())),
                    ),
                    _buildMenuButton(
                      context,
                      "⚔️ 전투",
                      "다른 몬스터와 경쟁하세요",
                      Colors.redAccent,
                      () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BattlePage())),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // 메뉴 버튼 위젯 생성 헬퍼
  Widget _buildMenuButton(BuildContext context, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.5), width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward_ios, color: color),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 5),
                Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
