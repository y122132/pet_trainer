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
  String _selectedPetType = "dog"; // [New] 기본선택: 강아지

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

    // 2단계(사진 등록)로 이름과 펫 종류 전달
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreationImageScreen(
          characterName: name, 
          petType: _selectedPetType, // [Modified] Pass selected type
        ),
      ),
    );
  }

  Widget _buildPetTypeButton(String petType, String label) {
    final bool isSelected = _selectedPetType == petType;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedPetType = petType;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? kDarkBrown : Colors.white,
        foregroundColor: isSelected ? Colors.white : kDarkBrown,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: kDarkBrown),
        ),
        elevation: isSelected ? 4 : 0,
      ),
      child: Text(label, style: GoogleFonts.jua()),
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
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildPetTypeButton("dog", "🐶 강아지"),
                      const SizedBox(width: 10),
                      _buildPetTypeButton("cat", "🐱 고양이"),
                      const SizedBox(width: 10),
                      _buildPetTypeButton("bird", "🐦 새"),
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