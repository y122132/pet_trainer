import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
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
    if (_diaries.isEmpty) setState(() => _isLoading = true);
    
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/diaries/user/${widget.user['id']}'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _diaries = jsonDecode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      print("Error fetching diaries: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. 좋아요 토글
  Future<void> _toggleLike(int index) async {
    final diary = _diaries[index];
    final int diaryId = diary['id'];
    
    // Optimistic Update
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
        if (mounted) {
          setState(() {
            diary['likes'] = data['likes'];
            diary['isLiked'] = data['isLiked'];
          });
        }
      } else {
        _revertLike(index, wasLiked, oldLikes);
      }
    } catch (e) {
      _revertLike(index, wasLiked, oldLikes);
    }
  }

  void _revertLike(int index, bool wasLiked, int oldLikes) {
    if (mounted) {
      setState(() {
        _diaries[index]['isLiked'] = wasLiked;
        _diaries[index]['likes'] = oldLikes;
      });
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
        onSave: (newDiary) {
           // [Optimization] Insert new diary at the top immediately
           setState(() {
             _diaries.insert(0, newDiary);
           });
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("일기가 저장되었습니다!")));
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
        iconTheme: const IconThemeData(color: Color(0xFF4E342E)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDiarySheet,
        backgroundColor: _getThemeColor(),
        icon: const Icon(Icons.edit, color: Colors.white),
        label: const Text("오늘의 일기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDiaries,
        color: _getThemeColor(),
        child: _isLoading && _diaries.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
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

  // UI Components
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
                "${AppConfig.serverBaseUrl}$imageUrl", 
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
                      style: TextStyle(fontWeight: isLiked ? FontWeight.bold : FontWeight.normal, color: isLiked ? Colors.redAccent : Colors.black54)
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
          Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF4E342E))),
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

// 4. 독립적인 작성 모달 (API 직접 호출 + Web Support)
class _AddDiarySheet extends StatefulWidget {
  final String petType;
  final Function(dynamic) onSave; // 성공 객체 반환
  const _AddDiarySheet({required this.petType, required this.onSave});

  @override
  State<_AddDiarySheet> createState() => _AddDiarySheetState();
}

class _AddDiarySheetState extends State<_AddDiarySheet> {
  XFile? _image; // Use XFile for cross-platform
  final TextEditingController _contentController = TextEditingController();
  bool _isUploading = false;

  String _getAutomaticTag() {
    if (widget.petType == 'dog') return "산책완료";
    if (widget.petType == 'cat') return "사냥놀이";
    return "비행성공";
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _image = pickedFile);
  }
  
  Future<void> _submit() async {
    if (_contentController.text.isEmpty) return;
    setState(() => _isUploading = true);
    
    try {
      final token = await AuthService().getToken();
      var uri = Uri.parse("${AppConfig.baseUrl}/diaries/");
      var request = http.MultipartRequest("POST", uri);
      
      request.headers.addAll({"Authorization": "Bearer $token"});
      request.fields['content'] = _contentController.text;
      request.fields['tag'] = _getAutomaticTag();
      
      if (_image != null) {
        if (kIsWeb) {
            // Web: Bytes
            var bytes = await _image!.readAsBytes();
            var multipartFile = http.MultipartFile.fromBytes('image', bytes, filename: _image!.name);
            request.files.add(multipartFile);
        } else {
            // Mobile: Path
            var multipartFile = await http.MultipartFile.fromPath('image', _image!.path);
            request.files.add(multipartFile);
        }
      }

      var response = await request.send();

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final newDiary = jsonDecode(respStr);
        
        widget.onSave(newDiary); // Pass back the new diary object
        if(mounted) Navigator.pop(context);
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("업로드 실패")));
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("에러: $e")));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
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
                ? Container(
                    height: 150, 
                    width: double.infinity,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[300]!)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_a_photo, size: 40, color: Colors.grey), SizedBox(height:5), Text("사진 추가 (선택)", style: TextStyle(color: Colors.grey))]))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(15), 
                    child: kIsWeb 
                        ? Image.network(_image!.path, height: 200, width: double.infinity, fit: BoxFit.cover) 
                        : Image.file(File(_image!.path), height: 200, width: double.infinity, fit: BoxFit.cover)
                  ),
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
                onPressed: _isUploading ? null : _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[400], 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                child: _isUploading 
                   ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                   : const Text("기록하기", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
