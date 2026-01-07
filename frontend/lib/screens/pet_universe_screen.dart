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
  List<dynamic> _diaries = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    petType = widget.user['pet_type'] ?? 'dog';
    _fetchDiaries();
  }

  // 1. 서버에서 일기 목록 가져오기
  Future<void> _fetchDiaries() async {
    // If loading for first time, show indicator. If refreshing, don't necessarily wipe screen.
    if (_diaries.isEmpty) setState(() => _isLoading = true);
    
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        // TODO: 현재는 내 일기만 보거나(프로필용), 추후 /diaries/ (전체)로 확장 가능
        // 계획에 따라: GET /v1/diaries/user/{id}
        Uri.parse('${AppConfig.baseUrl}/diaries/user/${widget.user['id']}'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _diaries = jsonDecode(utf8.decode(response.bodyBytes));
        });
      } else {
        print("일기 로드 실패: ${response.statusCode}");
      }
    } catch (e) {
      print("일기 로드 에러: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. 좋아요 토글
  Future<void> _toggleLike(int index) async {
    final diary = _diaries[index];
    final int diaryId = diary['id'];
    
    // Optimistic UI Update (먼저 반영)
    final bool wasLiked = diary['isLiked'] ?? false;
    final int oldLikes = diary['likes'] ?? 0;
    
    setState(() {
      diary['isLiked'] = !wasLiked;
      diary['likes'] = wasLiked ? oldLikes - 1 : oldLikes + 1;
    });

    try {
      final token = await AuthService().getToken();
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/diaries/$diaryId/like'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // 서버의 최신 카운트로 동기화
        if (mounted) {
          setState(() {
            diary['likes'] = data['likes'];
            diary['isLiked'] = data['isLiked'];
          });
        }
      } else {
        // 실패 시 롤백
        if (mounted) {
           setState(() {
            diary['isLiked'] = wasLiked;
            diary['likes'] = oldLikes;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("좋아요 실패")));
        }
      }
    } catch (e) {
      print("Like Error: $e");
      // 실패 시 롤백
      if (mounted) {
          setState(() {
          diary['isLiked'] = wasLiked;
          diary['likes'] = oldLikes;
        });
      }
    }
  }

  // 3. 일기 작성 모달
  void _showAddDiarySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddDiarySheet(
        petType: petType,
        onSave: (File? image, String content, String tag) async {
           await _submitDiary(image, content, tag);
        },
      ),
    );
  }

  // 4. 일기 업로드 (API)
  Future<void> _submitDiary(File? image, String content, String tag) async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthService().getToken();
      var uri = Uri.parse("${AppConfig.baseUrl}/diaries/");
      var request = http.MultipartRequest("POST", uri);
      
      request.headers.addAll({"Authorization": "Bearer $token"});
      request.fields['content'] = content;
      request.fields['tag'] = tag;
      
      if (image != null) {
        var stream = http.ByteStream(image.openRead());
        var length = await image.length();
        var multipartFile = http.MultipartFile('image', stream, length, filename: image.path.split("/").last);
        request.files.add(multipartFile);
      }

      var response = await request.send();

      if (response.statusCode == 200) {
        // 성공 시 목록 새로고침
        await _fetchDiaries();
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("일기가 저장되었습니다!")));
      } else {
        final respStr = await response.stream.bytesToString();
        print("Upload Failed: $respStr");
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("업로드 실패: $respStr")));
      }
    } catch (e) {
      print("Upload Error: $e");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("에러 발생: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
        iconTheme: const IconThemeData(color: Color(0xFF4E342E)), // Back button color
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDiarySheet,
        backgroundColor: _getThemeColor(),
        icon: const Icon(Icons.edit, color: Colors.white),
        label: const Text("오늘의 일기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDiaries, // Pull-to-Refresh 연결
        color: _getThemeColor(),
        child: _isLoading && _diaries.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(), // 내용이 적어도 스크롤/리프레시 가능하게
              slivers: [
                SliverToBoxAdapter(child: _buildScrapbookHeader()),
                
                _diaries.isEmpty 
                ? const SliverFillRemaining(
                    hasScrollBody: false,
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
      ),
    );
  }

  // --- UI 컴포넌트들 ---
  Widget _buildDiaryCard(int index) {
    final diary = _diaries[index];
    final String? imageUrl = diary['image_url']; 
    final bool isLiked = diary['isLiked'] ?? false;
    final int likeCount = diary['likes'] ?? 0;

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
          
          if (imageUrl != null && imageUrl.isNotEmpty)
            AspectRatio(
              aspectRatio: 1.5,
              child: Image.network(
                "${AppConfig.baseUrl}$imageUrl", 
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) => _buildDefaultImage(),
              )
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
                  children: [
                    IconButton(
                      onPressed: () => _toggleLike(index),
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.redAccent : Colors.grey,
                      ),
                    ),
                    Text("$likeCount명이 응원해요", 
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
  
  // 나머지 UI (Header, DefaultImage, Theme)는 기존 유지
  Widget _buildCardHeader(dynamic diary) {
    // 날짜 포맷팅 안전하게
    String dateStr = "";
    if (diary['created_at'] != null) {
        dateStr = diary['created_at'].toString().substring(0, 10);
    }
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          _getPetIcon(),
          const SizedBox(width: 10),
          Text(dateStr, 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF4E342E))),
          const Spacer(),
          _tagCard(diary['tag'] ?? "일상", _getThemeColor().withOpacity(0.1), _getThemeColor()),
        ],
      ),
    );
  }

  Widget _buildDefaultImage() {
    return Container(
      height: 200,
      width: double.infinity,
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
              Text(widget.user['nickname'] ?? "Unknown", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text("Lv.${widget.user['level'] ?? 1} | 성장 중인 우리 아이", style: TextStyle(color: Colors.grey[600])),
            ],
          )
        ],
      ),
    );
  }
}

class _AddDiarySheet extends StatefulWidget {
  final String petType;
  final Function(File?, String, String) onSave; // Signature Changed
  const _AddDiarySheet({required this.petType, required this.onSave});

  @override
  State<_AddDiarySheet> createState() => _AddDiarySheetState();
}

class _AddDiarySheetState extends State<_AddDiarySheet> {
  File? _image;
  final TextEditingController _contentController = TextEditingController();
  bool _isUploading = false; // Parent handles loading actually, but can keep for UI lock

  String _getAutomaticTag() {
    if (widget.petType == 'dog') return "산책완료";
    if (widget.petType == 'cat') return "사냥놀이";
    return "비행성공";
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _image = File(pickedFile.path));
  }
  
  void _submit() {
    if (_contentController.text.isEmpty) return;
    
    // Pass data to parent logic
    widget.onSave(
        _image, 
        _contentController.text, 
        _getAutomaticTag() // Or add tag selector later
    );
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
                // [Modified] 사진 필수 아님 -> 힌트 텍스트 변경
                ? Container(
                    height: 150, 
                    width: double.infinity,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[300]!)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_a_photo, size: 40, color: Colors.grey), SizedBox(height:5), Text("사진 추가 (선택)", style: TextStyle(color: Colors.grey))]))
                : ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(_image!, height: 200, width: double.infinity, fit: BoxFit.cover)),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                hintText: "우리 아이와 어떤 일이 있었나요?",
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12)
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[400], // Temp color, logic in parent
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                child: const Text("기록하기", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
