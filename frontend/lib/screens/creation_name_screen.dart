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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onNext() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    // 2단계(사진 등록)로 이름 데이터 전달
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreationImageScreen(characterName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCreamColor,
      appBar: AppBar(
        title: Text("1단계: 이름 짓기", style: GoogleFonts.jua(color: kBrown)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, // 첫 화면이므로 뒤로가기 없음 (로그아웃 등 필요 시 추가)
      ),
      body: Stack(
        children: [
          // 배경 장식 (동물 친구들)
          Align(
            alignment: Alignment.bottomCenter,
            child: Opacity(
              opacity: 0.3, 
              child: Image.asset(
                'assets/images/동물이름.png',
                fit: BoxFit.fitWidth,
                width: MediaQuery.of(context).size.width,
              ),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start, // [Modified] 위에서 시작
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 1), // [Modified] 상단 여백 (1/3 지점 배치를 위해)
                  
                  Text(
                    "반려동물의 이름을\n지어주세요!",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jua(fontSize: 28, color: kDarkBrown),
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
                        borderSide: const BorderSide(color: kLightBrown),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: kDarkBrown, width: 3),
                      ),
                    ),
                    onSubmitted: (_) => _onNext(),
                  ),
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
                      "다음으로",
                      style: GoogleFonts.jua(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),

                  const Spacer(flex: 2), // [Modified] 하단 여백 (상단보다 2배 더 주어 위로 올림)
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
