import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/char_provider.dart';
import 'menu_page.dart';

// --- 색상 상수 ---
const Color kCreamColor = Color(0xFFFFF9E6);
const Color kBrown = Color(0xFF4E342E);
const Color kLightBrown = Color(0xFF8D6E63);
const Color kDarkBrown = Color(0xFF5D4037);

class CreationImageScreen extends StatefulWidget {
  final String characterName; 
  final String petType;      
  final String presetId;     

  const CreationImageScreen({
    super.key, 
    required this.characterName, 
    required this.petType,
    required this.presetId, 
  });

  @override
  State<CreationImageScreen> createState() => _CreationImageScreenState();
}

class _CreationImageScreenState extends State<CreationImageScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _profileImage; // [New] Single profile image
  bool _isLoading = false;

  // 이미지 선택 (갤러리/카메라)
  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt, color: kBrown),
                title: Text('카메라로 촬영', style: GoogleFonts.jua(fontSize: 16)),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? image = await _picker.pickImage(source: ImageSource.camera);
                  if (image != null) {
                    setState(() => _profileImage = image);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: kBrown),
                title: Text('갤러리에서 선택', style: GoogleFonts.jua(fontSize: 16)),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    setState(() => _profileImage = image);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_profileImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("프로필 사진을 등록해주세요!")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final provider = Provider.of<CharProvider>(context, listen: false);
      
      bool success = await provider.createCharacterWithProfile(
        widget.characterName, 
        widget.petType, 
        widget.presetId,
        _profileImage!,
      );

      if (!mounted) return;

      if (success) {
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
          SnackBar(content: Text("오류: $e")),
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
        title: Text("2단계: 프로필 등록", style: GoogleFonts.jua(color: kBrown)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: kBrown),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "${widget.characterName}(이)의\n대표 사진을 등록해주세요!",
                textAlign: TextAlign.center,
                style: GoogleFonts.jua(fontSize: 22, color: kDarkBrown),
              ),
              const SizedBox(height: 10),
              Text(
                "(이 사진은 홈 화면과 프로필에 사용됩니다)",
                textAlign: TextAlign.center,
                style: GoogleFonts.jua(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 40),

              // --- 원형 프로필 이미지 업로더 ---
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: kBrown, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: ClipOval(
                    child: _profileImage != null
                        ? (kIsWeb 
                            ? Image.network(_profileImage!.path, fit: BoxFit.cover)
                            : Image.file(File(_profileImage!.path), fit: BoxFit.cover))
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_a_photo, size: 50, color: Colors.grey),
                              const SizedBox(height: 8),
                              Text("터치하여 추가", style: GoogleFonts.jua(color: Colors.grey)),
                            ],
                          ),
                  ),
                ),
              ),
              // -----------------------------

              const SizedBox(height: 60),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: !_isLoading ? _submit : null,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
