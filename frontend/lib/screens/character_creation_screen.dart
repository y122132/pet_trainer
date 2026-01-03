import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/screens/menu_page.dart';
import 'package:pet_trainer_frontend/widgets/camera_screen.dart';
import 'package:provider/provider.dart';

// --- 색상 상수 ---
const Color kCreamColor = Color(0xFFFFF9E6);
const Color kBrown = Color(0xFF4E342E);
const Color kLightBrown = Color(0xFF8D6E63);
const Color kDarkBrown = Color(0xFF5D4037);

class CharacterCreationScreen extends StatefulWidget {
  const CharacterCreationScreen({super.key});

  @override
  _CharacterCreationScreenState createState() => _CharacterCreationScreenState();
}

class _CharacterCreationScreenState extends State<CharacterCreationScreen> {
  final _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  // 4면 사진 저장
  final Map<String, XFile?> _images = {
    'Front': null,
    'Back': null,
    'Side': null,
    'Face': null,
  };
  final Map<String, String> _labels = {
    'Front': '정면',
    'Back': '후면',
    'Side': '옆면',
    'Face': '얼굴',
  };

  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // 사진 선택 방식 (액션시트)
  void _showImageSourceActionSheet(String key) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('카메라로 촬영'),
                onTap: () {
                  Navigator.of(context).pop();
                  _takePicture(key);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('갤러리에서 선택'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImageFromGallery(key);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _takePicture(String key) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );

    if (result is XFile) {
      setState(() {
        _images[key] = result;
      });
    }
  }

  Future<void> _pickImageFromGallery(String key) async {
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _images[key] = pickedFile;
        });
      }
    } catch (e) {
      print("Gallery Error: $e");
    }
  }

  // 모든 정보가 입력되었는지 확인
  bool _isValid() {
    bool nameOk = _nameController.text.trim().isNotEmpty;
    bool photosOk = _images.values.every((image) => image != null);
    return nameOk && photosOk;
  }

  // 제출 로직 (Provider 호출)
  Future<void> _submit() async {
    if (!_isValid()) return;

    setState(() => _isLoading = true);

    try {
      final provider = Provider.of<CharProvider>(context, listen: false);
      
      bool success = await provider.createCharacterWithImages(
        _nameController.text.trim(),
        _images,
      );

      if (!mounted) return;

      if (success) {
        // 성공 시 메인 로비로 이동
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MenuPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(provider.statusMessage ?? "생성 실패")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("오류가 발생했습니다: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCreamColor,
      appBar: AppBar(
        title: Text("캐릭터 생성", style: GoogleFonts.jua(color: kBrown)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, // 뒤로가기 방지
      ),
      body: Stack(
        children: [
          // 배경 이미지 (하단 동물들)
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  // 1. 이름 입력
                  Text(
                    "1. 반려동물의 이름을 지어주세요",
                    style: GoogleFonts.jua(fontSize: 18, color: kDarkBrown),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    onChanged: (v) => setState(() {}),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jua(color: kDarkBrown, fontSize: 18),
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
                        borderSide: const BorderSide(color: kDarkBrown, width: 2),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // 2. 사진 등록
                  Text(
                    "2. 사진을 4장 등록해주세요 (AI 학습용)",
                    style: GoogleFonts.jua(fontSize: 18, color: kDarkBrown),
                  ),
                  const SizedBox(height: 15),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.0,
                    children: _images.keys.map((String key) {
                      return _buildPhotoSlot(key);
                    }).toList(),
                  ),

                  const SizedBox(height: 40),

                  // 3. 완료 버튼
                  ElevatedButton(
                    onPressed: (_isValid() && !_isLoading) ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kDarkBrown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 5,
                    ),
                    child: _isLoading 
                      ? const SizedBox(
                          height: 24, width: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          "캐릭터 생성 완료!",
                          style: GoogleFonts.jua(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSlot(String key) {
    XFile? image = _images[key];
    String label = _labels[key]!;

    return GestureDetector(
      onTap: () => _showImageSourceActionSheet(key),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: image != null ? kDarkBrown : Colors.grey.shade300,
            width: image != null ? 2 : 1,
          ),
          boxShadow: [
             BoxShadow(
               color: Colors.black.withOpacity(0.05),
               blurRadius: 5,
               offset: const Offset(0, 3)
             )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                kIsWeb
                    ? Image.network(image.path, fit: BoxFit.cover)
                    : Image.file(File(image.path), fit: BoxFit.cover)
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, size: 30, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(label, style: GoogleFonts.jua(color: Colors.grey[600], fontSize: 16)),
                  ],
                ),
              
              // 체크 표시
              if (image != null)
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: kDarkBrown,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.check, size: 16, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
