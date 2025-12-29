import 'package:flutter/material.dart';
import 'package:pet_trainer_frontend/screens/customize_character_page.dart'; // OutfitConfig를 위해 import

// OutfitConfig 모델을 여기에 정의하거나, 별도의 파일로 분리할 수 있습니다.
// 현재는 이 파일 내에 정의하여 예시를 만듭니다.
// (CustomizeCharacterPage.dart에 이미 정의되어 있다면 이 부분은 삭제하거나, import 하여 사용합니다.)
/*
class OutfitConfig {
  final String imagePath;
  final Rect faceArea;

  const OutfitConfig({required this.imagePath, required this.faceArea});
}
*/

class OutfitSelectionPage extends StatefulWidget {
  const OutfitSelectionPage({super.key});

  @override
  _OutfitSelectionPageState createState() => _OutfitSelectionPageState();
}

class _OutfitSelectionPageState extends State<OutfitSelectionPage> {
  // 옷 이미지와 얼굴 영역 정보를 함께 가지는 OutfitConfig 리스트
  final List<OutfitConfig> _outfitConfigs = [
    // 닌자 옷: 예시 좌표
    OutfitConfig(
      imagePath: 'assets/images/characters/닌자옷.png', // 실제 이미지 경로로 변경
      faceArea: Rect.fromLTWH(120, 180, 180, 200), // 닌자 옷의 얼굴 구멍 위치 (left, top, width, height)
    ),
    // 공주 옷: 예시 좌표
    OutfitConfig(
      imagePath: 'assets/images/characters/공주옷.png', // 실제 이미지 경로로 변경
      faceArea: Rect.fromLTWH(100, 200, 220, 220), // 공주 옷의 얼굴 구멍 위치
    ),
    // 멜빵 옷: 예시 좌표
    OutfitConfig(
      imagePath: 'assets/images/characters/멜빵옷.png', // 실제 이미지 경로로 변경
      faceArea: Rect.fromLTWH(130, 90, 140, 140), // 멜빵 옷의 얼굴 구멍 위치
    ),
    // 바나나 옷: 예시 좌표
    OutfitConfig(
      imagePath: 'assets/images/characters/바나나옷.png', // 실제 이미지 경로로 변경
      faceArea: Rect.fromLTWH(160, 120, 110, 110), // 바나나 옷의 얼굴 구멍 위치
    ),
    // 기존 이미지 리스트에 맞춰 다른 OutfitConfig 추가 (공주옷, 멜빵옷, 바나나옷 등)
  ];

  int _selectedOutfitIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('의상 선택'),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              itemCount: _outfitConfigs.length,
              onPageChanged: (index) {
                setState(() {
                  _selectedOutfitIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return Image.asset(_outfitConfigs[index].imagePath);
              },
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // 선택된 OutfitConfig 객체를 반환
              Navigator.pop(context, _outfitConfigs[_selectedOutfitIndex]);
            },
            child: const Text('이 의상 선택'),
          ),
        ],
      ),
    );
  }
}
