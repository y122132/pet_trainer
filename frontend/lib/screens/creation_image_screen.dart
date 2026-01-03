import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/char_provider.dart';
import 'menu_page.dart';
import '../widgets/camera_screen.dart';

// --- 색상 상수 (통일감을 위해 유지) ---
const Color kCreamColor = Color(0xFFFFF9E6);
const Color kBrown = Color(0xFF4E342E);
const Color kLightBrown = Color(0xFF8D6E63);
const Color kDarkBrown = Color(0xFF5D4037);

class CreationImageScreen extends StatefulWidget {
  final String characterName; // 1단계에서 받은 이름

  const CreationImageScreen({super.key, required this.characterName});

  @override
  State<CreationImageScreen> createState() => _CreationImageScreenState();
}

class _CreationImageScreenState extends State<CreationImageScreen> {
  final ImagePicker _picker = ImagePicker();
  
  // 4면 사진 저장용 맵
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
      debugPrint("Gallery Error: $e");
    }
  }

  bool _isAllPhotosTaken() {
    return _images.values.every((image) => image != null);
  }

  // 최종 제출 (Atomic Submit)
  Future<void> _submit() async {
    if (!_isAllPhotosTaken()) return;

    setState(() => _isLoading = true);

    try {
      final provider = Provider.of<CharProvider>(context, listen: false);
      
      // 1단계 이름 + 2단계 사진을 합쳐서 한번에 전송
      bool success = await provider.createCharacterWithImages(
        widget.characterName, // 전달받은 이름 사용
        _images,
      );

      if (!mounted) return;

      if (success) {
        // 성공 시 메인 로비로 이동 (기존 스택 제거)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MenuPage()),
          (route) => false,
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
        title: Text("2단계: 사진 등록", style: GoogleFonts.jua(color: kBrown)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton( // 뒤로가기 허용 (이름 수정 가능하도록)
          icon: const Icon(Icons.arrow_back, color: kBrown),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
           Align(
            alignment: Alignment.bottomCenter,
            child: Opacity(
              opacity: 0.3, 
              child: Image.asset(
                'assets/images/동물이름.png', // 기존 에셋 재사용
                fit: BoxFit.fitWidth,
                width: MediaQuery.of(context).size.width,
                errorBuilder: (c, o, s) => const SizedBox(), // 에셋 없을 경우 대비
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "${widget.characterName}(이)의 사진을\n4장 등록해주세요",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jua(fontSize: 22, color: kDarkBrown),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "(AI가 분석하여 캐릭터를 생성합니다)",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jua(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 30),

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

                  ElevatedButton(
                    onPressed: (_isAllPhotosTaken() && !_isLoading) ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kDarkBrown,
                      disabledBackgroundColor: Colors.grey,
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
