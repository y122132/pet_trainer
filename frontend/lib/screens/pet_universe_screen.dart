import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api_config.dart';
import '../config/theme.dart';
import '../widgets/cute_avatar.dart';
import '../services/auth_service.dart';

class PetUniverseScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const PetUniverseScreen({super.key, required this.user});

  @override
  State<PetUniverseScreen> createState() => _PetUniverseScreenState();
}

class _PetUniverseScreenState extends State<PetUniverseScreen> {
  late String petType;
  List<dynamic> _diaries = []; // 실제 일기 데이터 리스트
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    petType = widget.user['pet_type'] ?? 'dog';
    _fetchDiaries();
  }
  void _toggleLike(int index) {
    setState(() {
      final diary = _diaries[index];
      // 서버 연동 전 로컬 상태 변경
      if (diary['isLiked'] == true) {
        diary['isLiked'] = false;
        diary['likes'] = (diary['likes'] ?? 1) - 1;
      } else {
        diary['isLiked'] = true;
        diary['likes'] = (diary['likes'] ?? 0) + 1;
      }
    });
    // TODO: 서버에 좋아요 API 호출 (POST /diaries/{id}/like)
  }

  // 1. 서버에서 일기 목록 가져오기
  Future<void> _fetchDiaries() async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/diaries/${widget.user['id']}'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        setState(() {
          _diaries = jsonDecode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      print("일기 로드 실패: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 2. 일기 작성용 BottomSheet 호출
  void _showAddDiarySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddDiarySheet(
        petType: petType,
        onSave: (newDiary) {
          setState(() => _diaries.insert(0, newDiary)); // 목록 최상단에 추가
        },
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2),
      appBar: AppBar(
        title: Text("${widget.user['nickname']}의 성장기록", 
            style: const TextStyle(color: Color(0xFF4E342E), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddDiarySheet, // 버튼 기능 구현
          backgroundColor: _getThemeColor(),
          icon: const Icon(Icons.edit, color: Colors.white),
          label: const Text("오늘의 일기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildScrapbookHeader()),
                
                _diaries.isEmpty 
                ? const SliverFillRemaining(
                    child: Center(child: Text("아직 기록된 추억이 없어요.\n첫 일기를 작성해보세요!", textAlign: TextAlign.center))
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildDiaryCard(index),
                      childCount: _diaries.length,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
      );
    }

  // --- UI 컴포넌트들 ---
  Widget _buildDiaryCard(int index) {
    final diary = _diaries[index];
    final dynamic diaryImage = diary['image']; 
    final bool isLiked = diary['isLiked'] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.brown.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(diary),
          
          AspectRatio(
            aspectRatio: 1.5,
            child: diaryImage != null 
              ? (diaryImage is File 
                  ? Image.file(diaryImage, fit: BoxFit.cover) 
                  : Image.network(diaryImage, fit: BoxFit.cover))
              : _buildDefaultImage(),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(diary['content'], style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5)),
                const SizedBox(height: 12),
                const Divider(),
                Row(
                  children: [IconButton(
                      onPressed: () => _toggleLike(index),
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.redAccent : Colors.grey,
                      ),
                    ),
                    Text("${diary['likes'] ?? 0}명이 응원해요", 
                      style: TextStyle(
                        fontWeight: isLiked ? FontWeight.bold : FontWeight.normal,
                        color: isLiked ? Colors.redAccent : Colors.black54
                      )
                    ),
                  ],
                ),
              ],
            ),
          ),
        ]
      ),
    );
  }
  Widget _buildCardHeader(dynamic diary) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          _getPetIcon(),
          const SizedBox(width: 10),
          Text(diary['created_at'].toString().substring(0, 10), 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF4E342E))),
          const Spacer(),
          _tagCard(diary['tag'] ?? "일상", _getThemeColor().withOpacity(0.1), _getThemeColor()),
        ],
      ),
    );
  }

  // 사진 없을 때 기본 캐릭터 배경
  Widget _buildDefaultImage() {
    return Container(
      color: _getThemeColor().withOpacity(0.05),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CuteAvatar(petType: petType, size: 70),
            const SizedBox(height: 10),
            Text("기억하고 싶은 순간", style: TextStyle(color: _getThemeColor(), fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // --- 종별 테마 및 데이터 분기 처리 ---

  Color _getThemeColor() {
    if (petType == 'dog') return Colors.orange[400]!;
    if (petType == 'cat') return Colors.purple[300]!;
    return Colors.lightBlue[400]!;
  }

  Widget _getPetIcon() {
    IconData icon = FontAwesomeIcons.paw;
    if (petType == 'cat') icon = FontAwesomeIcons.cat;
    if (petType == 'bird') icon = FontAwesomeIcons.dove;
    return FaIcon(icon, color: _getThemeColor(), size: 20);
  }

  Widget _tagCard(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: textCol, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildScrapbookHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          CuteAvatar(petType: petType, size: 80),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.user['nickname'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text("Lv.${widget.user['level']} | 성장 중인 우리 아이", style: TextStyle(color: Colors.grey[600])),
            ],
          )
        ],
      ),
    );
  }
}
class _AddDiarySheet extends StatefulWidget {
  final String petType;
  final Function(dynamic) onSave;
  const _AddDiarySheet({required this.petType, required this.onSave});

  @override
  State<_AddDiarySheet> createState() => _AddDiarySheetState();
}

class _AddDiarySheetState extends State<_AddDiarySheet> {
  File? _image;
  final TextEditingController _contentController = TextEditingController();
  bool _isUploading = false;

  String _getAutomaticTag() {
    if (widget.petType == 'dog') return "산책완료";
    if (widget.petType == 'cat') return "사냥놀이";
    return "비행성공";
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _image = File(pickedFile.path));
  }
  Future<void> _submit() async {
    if (_contentController.text.isEmpty) return;
    setState(() => _isUploading = true);

    await Future.delayed(const Duration(milliseconds: 500));   
    widget.onSave({
      "image": _image,
      "content": _contentController.text,
      "tag": _getAutomaticTag(),
      "created_at": DateTime.now().toString(),
      "isLiked": false,
      "likes": 0,
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("오늘의 추억 기록", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _pickImage,
              child: _image == null 
                ? Container(height: 200, color: Colors.grey[200], child: const Icon(Icons.add_a_photo, size: 50))
                : Image.file(_image!, height: 200, fit: BoxFit.cover),
            ),
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(hintText: "우리 아이와 어떤 일이 있었나요?"),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isUploading ? null : _submit,
              child: _isUploading ? const CircularProgressIndicator() : const Text("기록하기"),
            )
          ],
        ),
      ),
    );
  }
}
