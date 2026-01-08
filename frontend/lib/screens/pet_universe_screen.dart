import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:jwt_decode/jwt_decode.dart';

import '../api_config.dart';
import '../widgets/cute_avatar.dart';
import '../services/auth_service.dart';

// --- Models ---
class Comment {
  final int id;
  final String content;
  final String nickname;
  final String? petType;
  final int userId;

  Comment({required this.id, required this.content, required this.nickname, this.petType, required this.userId});

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      content: json['content'],
      nickname: json['nickname'] ?? '익명',
      petType: json['pet_type'] ?? 'dog',
      userId: json['user_id'] ?? 0,
    );
  }
}

// --- Main Screen ---
class PetUniverseScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const PetUniverseScreen({super.key, required this.user});

  @override
  State<PetUniverseScreen> createState() => _PetUniverseScreenState();
}

class _PetUniverseScreenState extends State<PetUniverseScreen> with SingleTickerProviderStateMixin {
  late String petType;
  List<dynamic> _diaries = [];
  bool _isLoading = false;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    petType = widget.user['pet_type'] ?? 'dog';
    _fetchDiaries();
  }


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

  Future<void> _toggleLike(int index) async {
    final diary = _diaries[index];
    final int diaryId = diary['id'];
    
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

  void _showAddDiarySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddDiarySheet(
        petType: petType,
        onSave: (newDiary) {
           setState(() {
             _diaries.insert(0, newDiary);
           });
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("일기가 저장되었습니다!")));
        },
      ),
    );
  }

  // --- Comment Feature ---
  void _showCommentsSheet(int diaryId, int diaryIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommentsSheet(
        diaryId: diaryId,
        diaryAuthorId: widget.user['id'],
        onCommentPosted: () {
          setState(() {
            _diaries[diaryIndex]['comments_count'] = (_diaries[diaryIndex]['comments_count'] ?? 0) + 1;
          });
        },
        onCommentDeleted: () {
          setState(() {
            _diaries[diaryIndex]['comments_count'] = (_diaries[diaryIndex]['comments_count'] ?? 1) - 1;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E6),
      appBar: AppBar(
        title: Text(
          "${widget.user['nickname']}의 미니홈피",
          style: GoogleFonts.jua(
            color: const Color(0xFF5D4037),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF5D4037)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDiarySheet,
        backgroundColor: const Color(0xFF5D4037),
        shape: const StadiumBorder(),
        icon: const Icon(Icons.edit, color: Colors.white),
        label: Text("오늘의 기록",
            style: GoogleFonts.jua(color: Colors.white, fontSize: 16)),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/login_bg.png'),
            fit: BoxFit.cover,
            opacity: 0.2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Column(
              children: [
                _buildMiniProfile(),
                _buildTabs(),
                const Divider(height: 1, color: Color(0xFFF5EFE6)),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _diaries.isEmpty
                          ? const Center(
                              child:
                                  Text("아직 기록된 추억이 없어요.\n첫 일기를 작성해보세요!",
                                      textAlign: TextAlign.center,
                                    ))
                          : RefreshIndicator(
                              onRefresh: _fetchDiaries,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _diaries.length,
                                itemBuilder: (context, index) =>
                                    _buildFeedCard(index),
                              ),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniProfile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF5D4037),
            child: Padding(
              padding: const EdgeInsets.all(3.0),
              child: ClipOval(
                child: CuteAvatar(
                  petType: petType,
                  size: 74,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user['nickname'],
                  style: GoogleFonts.jua(fontSize: 22, color: const Color(0xFF4E342E)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9E6),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFD7CCC8)),
                  ),
                  child: Text(
                    "🐶 오늘은 산책 가는 날!",
                    style: GoogleFonts.jua(fontSize: 13, color: const Color(0xFF795548)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildTabItem(index: 0, label: "전체글"),
          _buildTabItem(index: 1, label: "사진첩"),
          _buildTabItem(index: 2, label: "방명록"),
        ],
      ),
    );
  }

  Widget _buildTabItem({required int index, required String label}) {
    bool isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF5D4037) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFBCAAA4)),
        ),
        child: Text(
          label,
          style: GoogleFonts.jua(
            color: isSelected ? Colors.white : const Color(0xFF795548),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFeedCard(int index) {
    final diary = _diaries[index];
    final dynamic diaryImage = diary['image_url'];
    final bool isLiked = diary['isLiked'] ?? false;
    final int commentsCount = diary['comments_count'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25.0),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (diaryImage != null && diaryImage.toString().isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 10,
                child:
                    (diaryImage is XFile)
                        ? (kIsWeb
                            ? Image.network(diaryImage.path, fit: BoxFit.cover, filterQuality: FilterQuality.high)
                            : Image.file(File(diaryImage.path), fit: BoxFit.cover, filterQuality: FilterQuality.high))
                        : (diaryImage is File
                            ? Image.file(diaryImage, fit: BoxFit.cover, filterQuality: FilterQuality.high)
                            : Image.network(
                                diaryImage.toString().startsWith('/')
                                    ? "${AppConfig.serverBaseUrl}${diaryImage}"
                                    : diaryImage.toString(),
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (ctx, err, stack) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),
                              )),
              ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${diary['created_at'].toString().substring(0, 10)}의 기록",
                    style: GoogleFonts.jua(color: Colors.grey[400], fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    diary['content'],
                    style: GoogleFonts.jua(
                      fontSize: 16,
                      color: const Color(0xFF5D4037),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => _toggleLike(index),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Icon(
                                isLiked ? Icons.favorite : Icons.favorite_border,
                                color: isLiked ? const Color(0xFFE57373) : const Color(0xFFBCAAA4),
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "${diary['likes'] ?? 0}",
                                style: GoogleFonts.jua(color: const Color(0xFF795548)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => _showCommentsSheet(diary['id'], index),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              const Icon(Icons.mode_comment_outlined, color: Color(0xFFBCAAA4), size: 20),
                              const SizedBox(width: 6),
                              Text(
                                "$commentsCount",
                                style: GoogleFonts.jua(color: const Color(0xFF795548)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Add Diary Sheet (Original) ---
class _AddDiarySheet extends StatefulWidget {
  final String petType;
  final Function(dynamic) onSave;
  const _AddDiarySheet({required this.petType, required this.onSave});

  @override
  State<_AddDiarySheet> createState() => _AddDiarySheetState();
}

class _AddDiarySheetState extends State<_AddDiarySheet> {
  XFile? _image;
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
            var bytes = await _image!.readAsBytes();
            var multipartFile = http.MultipartFile.fromBytes('image', bytes, filename: _image!.name);
            request.files.add(multipartFile);
        } else {
            var multipartFile = await http.MultipartFile.fromPath('image', _image!.path);
            request.files.add(multipartFile);
        }
      }

      var response = await request.send();

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final newDiary = jsonDecode(respStr);
        
        widget.onSave(newDiary);
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
    // Original build method for _AddDiarySheet...
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20, right: 20, top: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF9E6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("오늘의 추억 기록", style: GoogleFonts.jua(fontSize: 20, color: const Color(0xFF5D4037))), 
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _pickImage,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  color: const Color(0xFFF5EFE6),
                  child: _image == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, size: 40, color: Color(0xFFBCAAA4)),
                            SizedBox(height: 8),
                            Text("사진 추가하기", style: TextStyle(color: Color(0xFF8D6E63)))
                          ],
                        )
                      : (kIsWeb
                          ? Image.network(_image!.path, fit: BoxFit.cover)
                          : Image.file(File(_image!.path), fit: BoxFit.cover)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              style: GoogleFonts.jua(color: const Color(0xFF5D4037)),
              decoration: InputDecoration(
                hintText: "우리 아이와 어떤 일이 있었나요?",
                hintStyle: GoogleFonts.jua(color: const Color(0xFFBCAAA4)),
                filled: true,
                fillColor: const Color(0xFFF5EFE6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isUploading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5D4037),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const StadiumBorder(),
              ),
              child: _isUploading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                  : Text("기록하기", style: GoogleFonts.jua(color: Colors.white, fontSize: 18)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// --- Comments Sheet ---
class _CommentsSheet extends StatefulWidget {
  final int diaryId;
  final int diaryAuthorId;
  final VoidCallback onCommentPosted;
  final VoidCallback onCommentDeleted;

  const _CommentsSheet({required this.diaryId, required this.diaryAuthorId, required this.onCommentPosted, required this.onCommentDeleted});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  List<Comment> _comments = [];
  bool _isLoading = true;
  bool _isPosting = false;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser().then((_) {
      _fetchComments();
    });
  }

  Future<void> _loadCurrentUser() async {
    final token = await AuthService().getToken();
    if (token == null) return;
    try {
      final payload = Jwt.parseJwt(token);
      if (mounted) {
        setState(() {
          _currentUserId = int.tryParse(payload['sub'].toString());
        });
      }
    } catch (e) {
      print("Error decoding token: $e");
    }
  }

  Future<void> _fetchComments() async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/diaries/${widget.diaryId}/comments'),
        headers: {"Authorization": "Bearer $token"},
      );
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final List<dynamic> data = jsonDecode(responseBody);
        if (mounted) {
          setState(() {
            _comments = data.map((item) => Comment.fromJson(item)).toList();
          });
        }
      }
    } catch (e) {
      print("Error fetching comments: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _postComment() async {
    if (_commentController.text.trim().isEmpty) return;
    setState(() => _isPosting = true);

    try {
      final token = await AuthService().getToken();
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/diaries/${widget.diaryId}/comments'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"content": _commentController.text.trim()}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          _commentController.clear();
          widget.onCommentPosted();
          await _fetchComments();
        }
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("댓글 작성 실패")));
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("에러: $e")));
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _deleteComment(int commentId) async {
    final bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFF9E6),
        title: Text('댓글 삭제', style: GoogleFonts.jua(color: const Color(0xFF5D4037))),
        content: Text('정말로 이 댓글을 삭제하시겠어요?', style: GoogleFonts.jua(color: const Color(0xFF795548))),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('취소', style: GoogleFonts.jua(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text('삭제', style: GoogleFonts.jua(color: const Color(0xFFE57373)))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final token = await AuthService().getToken();
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/diaries/${widget.diaryId}/comments/$commentId'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (mounted) {
          setState(() {
            _comments.removeWhere((c) => c.id == commentId);
          });
          widget.onCommentDeleted();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("댓글이 삭제되었습니다.")));
          }
        }
      } else {
         if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("삭제에 실패했습니다.")));
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("에러: $e")));
    }
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF9E6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text("댓글", style: GoogleFonts.jua(fontSize: 20, color: const Color(0xFF5D4037))), 
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? const Center(child: Text("첫 댓글을 남겨보세요!"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          final comment = _comments[index];
                          final bool isAuthor = comment.userId == widget.diaryAuthorId && comment.userId != 0;
                          final bool isMyComment = comment.userId == _currentUserId && comment.userId != 0;
                          
                          return ListTile(
                            leading: CuteAvatar(petType: comment.petType ?? 'dog', size: 40),
                            title: Row(
                              children: [
                                Text(comment.nickname, style: GoogleFonts.jua(fontWeight: FontWeight.bold, color: const Color(0xFF4E342E))),
                                if (isAuthor)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6.0),
                                    child: FaIcon(FontAwesomeIcons.crown, color: Colors.amber[600], size: 14),
                                  ),
                              ],
                            ),
                            subtitle: Text(comment.content, style: GoogleFonts.jua(color: const Color(0xFF795548))),
                            trailing: isMyComment
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                                    onPressed: () => _deleteComment(comment.id),
                                  )
                                : null,
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: -5, blurRadius: 10)],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    style: GoogleFonts.jua(),
                    decoration: InputDecoration(
                      hintText: "따뜻한 댓글을 남겨주세요...",
                      hintStyle: GoogleFonts.jua(color: const Color(0xFFBCAAA4)),
                      border: InputBorder.none,
                    ),
                    maxLines: 1,
                  ),
                ),
                IconButton(
                  icon: _isPosting 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : const Icon(Icons.send, color: Color(0xFF5D4037)),
                  onPressed: _isPosting ? null : _postComment,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}