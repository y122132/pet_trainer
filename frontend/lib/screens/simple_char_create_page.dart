import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pet_trainer_frontend/screens/pet_photo_reg_page.dart';
import 'menu_page.dart';

// --- 색상 상수 (전역) ---
const Color kCreamColor = Color(0xFFFFF9E6);
const Color kBrown = Color(0xFF4E342E);
const Color kLightBrown = Color(0xFF8D6E63);
const Color kDarkBrown = Color(0xFF5D4037);

class SimpleCharCreatePage extends StatefulWidget {
  const SimpleCharCreatePage({super.key});

  @override
  State<SimpleCharCreatePage> createState() => _SimpleCharCreatePageState();
}

class _SimpleCharCreatePageState extends State<SimpleCharCreatePage> {
  final _nameController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _isLoading = false;

  Future<void> _createCharacter() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("캐릭터 이름을 입력해주세요.", style: GoogleFonts.jua()),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    // setState(() => _isLoading = true); // 로딩 인디케이터 제거

    // The original character creation logic is commented out to navigate to the photo registration page first.
    // The actual character creation can be moved to the photo registration page later.
    /*
    try {
      final token = await _storage.read(key: 'jwt_token');
      final userId = await _storage.read(key: 'user_id');

      if (token == null || userId == null) {
        throw Exception("로그인 정보가 없습니다.");
      }
      
      final response = await http.post(
        Uri.parse("${AppConfig.charactersUrl}/"),
        headers: {
          "Content-Type": "application/json; charset=UTF-8",
          "Authorization": "Bearer $token"
        },
        body: jsonEncode({
          "user_id": int.parse(userId),
          "name": _nameController.text,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        final createdId = responseData['id'];

        if (createdId != null) {
          await _storage.write(
              key: 'character_id', value: createdId.toString());
        }

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("캐릭터가 생성되었습니다!", style: GoogleFonts.jua())));
            
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MenuPage()),
        );
      } else {
        throw Exception(
            "캐릭터 생성 실패 (${response.statusCode}): ${utf8.decode(response.bodyBytes)}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("오류 발생: $e", style: GoogleFonts.jua())),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    */

    // Navigate to the photo registration page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PetPhotoRegistrationPage(petName: _nameController.text),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 1. 화면 방향 고정
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    // 화면을 나갈 때 방향 고정을 해제하려면 아래 주석을 해제합니다.
    // SystemChrome.setPreferredOrientations([
    //   DeviceOrientation.landscapeRight,
    //   DeviceOrientation.landscapeLeft,
    //   DeviceOrientation.portraitUp,
    //   DeviceOrientation.portraitDown,
    // ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 2. 새로운 배경 전략 적용
      body: Stack(
        children: [
          // Layer 1: 화면 전체 배경색
          Container(color: kCreamColor),

          // Layer 2: 하단에 깔리는 배경 이미지
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              'assets/images/동물이름.png',
              fit: BoxFit.fitWidth, // 가로폭 맞춤
              width: MediaQuery.of(context).size.width,
            ),
          ),

          // Layer 3: UI 요소
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Column(
                children: [
                  const SizedBox(height: 50.0),
                  // 4. 로고
                  Image.asset(
                    'assets/images/독고 표지 이름.png',
                    width: MediaQuery.of(context).size.width * 0.4,
                  ),
                  const SizedBox(height: 20),

                  // 4. 타이틀 텍스트
                  Text(
                    '나만의 반려견 만들기',
                    style: GoogleFonts.jua(
                      fontSize: 28,
                      color: kDarkBrown,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // 5. 이름 입력창
                  TextField(
                    controller: _nameController,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jua(color: kDarkBrown, fontSize: 18),
                    decoration: InputDecoration(
                      hintText: "캐릭터 이름",
                      hintStyle: GoogleFonts.jua(color: kLightBrown),
                      prefixIcon: const Icon(Icons.pets, color: kDarkBrown),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.95),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: kDarkBrown, width: 2.0),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: kDarkBrown, width: 2.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: kDarkBrown, width: 2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 5. 생성 버튼
                  _isLoading
                      ? const CircularProgressIndicator(color: kDarkBrown)
                      : ElevatedButton.icon(
                          onPressed: _createCharacter,
                          icon: const Icon(Icons.check, color: Colors.white),
                          label: Text(
                            '캐릭터 생성',
                            style: GoogleFonts.jua(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kDarkBrown,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 5,
                          ),
                        ),
                  
                  // 하단 UI가 이미지를 가리지 않도록 밀어 올리는 역할
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
