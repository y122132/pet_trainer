import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'creation_image_screen.dart';

// --- 색상 상수 (기존 유지) ---
const Color kCreamColor = Color(0xFFFFF9E6);
const Color kBrown = Color(0xFF4E342E);
const Color kLightBrown = Color(0xFF8D6E63);
const Color kDarkBrown = Color(0xFF5D4037);

class CreationNameScreen extends StatefulWidget {
  const CreationNameScreen({super.key});

  @override
  State<CreationNameScreen> createState() => _CreationNameScreenState();
}

class _CreationNameScreenState extends State<CreationNameScreen> {
  final _nameController = TextEditingController();
  String _selectedPetType = "danpat"; // [New] 기본선택: 단팥

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onNext() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('이름을 입력해주세요!', style: GoogleFonts.jua()),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // 펫 종류 매핑 (danpat -> dog, etc)
    String realPetType = "dog";
    if (_selectedPetType == 'shushu') realPetType = 'cat';
    if (_selectedPetType == 'anko') realPetType = 'bird';

    // 2단계(사진 등록)로 이름, 펫 종류, 프리셋 ID 전달
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreationImageScreen(
          characterName: name, 
          petType: realPetType, // 백엔드용 (dog, cat, bird)
          presetId: _selectedPetType, // 프리셋 로딩용 (danpat, shushu, anko)
        ),
      ),
    );
  }

  Widget _buildCharacterCard(String type, String label, String imagePath) {
    final bool isSelected = _selectedPetType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPetType = type;
        });
      },
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isSelected ? kCreamColor : Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isSelected ? kDarkBrown : Colors.transparent,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                imagePath,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.pets, color: kLightBrown);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.jua(
              fontSize: 16,
              color: isSelected ? kDarkBrown : Colors.grey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCreamColor,
      appBar: AppBar(
        title: Text("1단계: 캐릭터 생성", style: GoogleFonts.jua(color: kBrown)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, 
      ),
      body: Stack(
        children: [
          // 배경 장식
          Align(
            alignment: Alignment.bottomCenter,
            child: Opacity(
              opacity: 0.3,
              child: Image.asset(
                'assets/images/동물이름.png',
                fit: BoxFit.fitWidth,
                width: MediaQuery.of(context).size.width,
                errorBuilder: (c, e, s) => const SizedBox(),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),
                  Text(
                    "반려동물의 종을 선택하고\n이름을 지어주세요!",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jua(fontSize: 28, color: kDarkBrown, height: 1.3),
                  ),
                  const SizedBox(height: 40),
                  
                  // 펫 종류 선택 섹션
                  Text(
                    "어떤 친구와 함께할까요?",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jua(fontSize: 18, color: kDarkBrown.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildCharacterCard("danpat", "단팥", "assets/images/단팥_정면.JPG"),
                      const SizedBox(width: 15),
                      _buildCharacterCard("shushu", "슈슈", "assets/images/슈슈_정면.JPG"),
                      const SizedBox(width: 15),
                      _buildCharacterCard("anko", "앙꼬", "assets/images/앙꼬_정면.JPG"),
                    ],
                  ),
                  
                  const SizedBox(height: 40),

                  TextField(
                    controller: _nameController,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jua(color: kDarkBrown, fontSize: 24),
                    decoration: InputDecoration(
                      hintText: "예: 독고",
                      hintStyle: GoogleFonts.jua(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: kLightBrown, width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: kLightBrown, width: 2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: kDarkBrown, width: 3),
                      ),
                    ),
                    onSubmitted: (_) => _onNext(),
                  ),
                  const SizedBox(height: 30),
                  
                  const SizedBox(height: 40),

                  ElevatedButton(
                    onPressed: _onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kDarkBrown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 5,
                    ),
                    child: Text(
                      "다음 단계로",
                      style: GoogleFonts.jua(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),

                  const Spacer(flex: 2), 
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}