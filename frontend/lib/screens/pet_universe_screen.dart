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
import '../models/guestbook_entry_model.dart';
import '../widgets/cute_avatar.dart';
import '../services/auth_service.dart';

// --- Models ---
class Comment {
  final int id;
  final String content;
  final String nickname;
  final String? petType;
  final int userId;
  final int? parentId;
  final List<Comment> replies;

  Comment({
    required this.id,
    required this.content,
    required this.nickname,
    this.petType,
    required this.userId,
    this.parentId,
    this.replies = const [],
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      content: json['content'],
      nickname: json['nickname'] ?? '익명',
      petType: json['pet_type'] ?? 'dog',
      userId: json['user_id'] ?? 0,
      parentId: json['parent_id'],
      replies: [], // Replies will be populated in a separate step
    );
  }

  Comment copyWith({
    int? id,
    String? content,
    String? nickname,
    String? petType,
    int? userId,
    int? parentId,
    List<Comment>? replies,
  }) {
    return Comment(
      id: id ?? this.id,
      content: content ?? this.content,
      nickname: nickname ?? this.nickname,
      petType: petType ?? this.petType,
      userId: userId ?? this.userId,
      parentId: parentId ?? this.parentId,
      replies: replies ?? this.replies,
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

  int _selectedTabIndex = 0;

  int? _currentUserId;



  // Data for each tab

  List<dynamic> _diaries = [];

  List<GuestbookEntry> _guestbookEntries = [];

  

  // Getter for photo diaries

  List<dynamic> get _photoDiaries => _diaries.where((d) {

    final imageUrl = d['image_url'];

    return imageUrl != null && imageUrl.toString().isNotEmpty;

  }).toList();



  // Loading states

  bool _isDiariesLoading = false;

  bool _isGuestbookLoading = false;





  @override

  void initState() {

    super.initState();

    petType = widget.user['pet_type'] ?? 'dog';

    _loadCurrentUser();

    // Fetch initial data for the first tab

    _fetchDiaries();

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



  void _onTabChanged(int index) {

    if (!mounted) return;

    setState(() {

      _selectedTabIndex = index;

    });



    // Fetch data if the list for the selected tab is empty

    if (index == 0 && _diaries.isEmpty) {

      _fetchDiaries();

    } else if (index == 1 && _diaries.isEmpty) {

      // Photo album uses the same data as diaries

      _fetchDiaries();

    } else if (index == 2 && _guestbookEntries.isEmpty) {

      _fetchGuestbookEntries();

    }

  }





    Future<void> _fetchDiaries() async {





      if (_isDiariesLoading) return;





      if (_diaries.isEmpty) setState(() => _isDiariesLoading = true);





      





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





        if (mounted) setState(() => _isDiariesLoading = false);





      }





    }



    Future<void> _fetchGuestbookEntries() async {



      if (_isGuestbookLoading) return;



      setState(() => _isGuestbookLoading = true);



      



      try {



        final token = await AuthService().getToken();



        final response = await http.get(



          Uri.parse('${AppConfig.baseUrl}/guestbook/user/${widget.user['id']}'),



          headers: {"Authorization": "Bearer $token"},



        );



  



        if (response.statusCode == 200) {



          if (!mounted) return;



          final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));



          setState(() {



            _guestbookEntries = data.map((item) => GuestbookEntry.fromJson(item)).toList();



          });



        }



      } catch (e) {



        print("Error fetching guestbook: $e");



      } finally {



        if (mounted) {



          setState(() {



            _isGuestbookLoading = false;



          });



        }



      }



    }



  Future<void> _toggleLike(int index) async {

    // This function works on the _diaries list. 

    // We need to find the correct diary object.

    final list = _selectedTabIndex == 1 ? _photoDiaries : _diaries;

    final diary = list[index];

    final int diaryId = diary['id'];



    // Find the original diary in the main _diaries list to modify it

    final originalDiaryIndex = _diaries.indexWhere((d) => d['id'] == diaryId);

    if (originalDiaryIndex == -1) return;

    

    final bool wasLiked = _diaries[originalDiaryIndex]['isLiked'] ?? false;

    final int oldLikes = _diaries[originalDiaryIndex]['likes'] ?? 0;

    

    setState(() {

      _diaries[originalDiaryIndex]['isLiked'] = !wasLiked;

      _diaries[originalDiaryIndex]['likes'] = wasLiked ? oldLikes - 1 : oldLikes + 1;

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

            _diaries[originalDiaryIndex]['likes'] = data['likes'];

            _diaries[originalDiaryIndex]['isLiked'] = data['isLiked'];

          });

        }

      } else {

        _revertLike(originalDiaryIndex, wasLiked, oldLikes);

      }

    } catch (e) {

      _revertLike(originalDiaryIndex, wasLiked, oldLikes);

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



  void _showSheetForCurrentTab() {

    if (_selectedTabIndex == 0) { // 전체글

      _showAddDiarySheet(isImageRequired: false);

    } else if (_selectedTabIndex == 1) { // 사진첩

      _showAddDiarySheet(isImageRequired: true);

    } else if (_selectedTabIndex == 2) {

      // Guestbook posting logic

      _showAddGuestbookEntrySheet();

    }

  }



  void _showAddDiarySheet({required bool isImageRequired}) {

    showModalBottomSheet(

      context: context,

      isScrollControlled: true,

      backgroundColor: Colors.transparent,

      builder: (context) => _AddDiarySheet(

        petType: petType,

        isImageRequired: isImageRequired,

        onSave: (newDiary) {

           setState(() {

             _diaries.insert(0, newDiary);

           });

           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("일기가 저장되었습니다!")));

        },

      ),

    );

  }



    void _showAddGuestbookEntrySheet() {



      showModalBottomSheet(



        context: context,



        isScrollControlled: true,



        backgroundColor: Colors.transparent,



        builder: (context) => _AddGuestbookEntrySheet(



          userId: widget.user['id'],



          onSave: (newEntry) {



            setState(() {



              _guestbookEntries.insert(0, newEntry);



            });



          },



        ),



      );



    }





  // --- Comment Feature ---

  void _showCommentsSheet(int diaryId, int diaryIndex) {

    // Find the original diary in the main _diaries list to modify it

    final list = _selectedTabIndex == 1 ? _photoDiaries : _diaries;

    final diary = list[diaryIndex];

    final originalDiaryIndex = _diaries.indexWhere((d) => d['id'] == diary['id']);

    if (originalDiaryIndex == -1) return;



    showModalBottomSheet(

      context: context,

      isScrollControlled: true,

      backgroundColor: Colors.transparent,

      builder: (context) => _CommentsSheet(

        diaryId: diaryId,

        diaryAuthorId: widget.user['id'],

        onCommentPosted: () {

          setState(() {

            _diaries[originalDiaryIndex]['comments_count'] = (_diaries[originalDiaryIndex]['comments_count'] ?? 0) + 1;

          });

        },

        onCommentDeleted: () {

          setState(() {

            _diaries[originalDiaryIndex]['comments_count'] = (_diaries[originalDiaryIndex]['comments_count'] ?? 1) - 1;

          });

        },

      ),

    );

  }



  @override

  Widget build(BuildContext context) {

    bool isMyPage = _currentUserId == widget.user['id'];



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

      floatingActionButton: _buildFloatingActionButton(isMyPage),

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

                Expanded(child: _buildTabContent()),

              ],

            ),

          ),

        ),

      ),

    );

  }



  Widget? _buildFloatingActionButton(bool isMyPage) {

    if (_selectedTabIndex == 2) { // Guestbook

      return isMyPage 

        ? null 

        : FloatingActionButton.extended(

            onPressed: _showAddGuestbookEntrySheet,

            backgroundColor: const Color(0xFF5D4037),

            shape: const StadiumBorder(),

            icon: const Icon(Icons.rate_review, color: Colors.white),

            label: Text("방명록 남기기", style: GoogleFonts.jua(color: Colors.white, fontSize: 16)),

          );

    }

    

    // FAB for Diary and Photo Album (only on my page)

    return isMyPage 

      ? FloatingActionButton.extended(

          onPressed: _showSheetForCurrentTab,

          backgroundColor: const Color(0xFF5D4037),

          shape: const StadiumBorder(),

          icon: Icon(_selectedTabIndex == 1 ? Icons.add_a_photo : Icons.edit, color: Colors.white),

          label: Text(_selectedTabIndex == 1 ? "사진 기록" : "오늘의 기록",

              style: GoogleFonts.jua(color: Colors.white, fontSize: 16)),

        )

      : null;

  }



  Widget _buildTabContent() {

    switch (_selectedTabIndex) {

      case 0:

        return _buildDiaryFeed();

      case 1:

        return _buildPhotoAlbumGrid();

      case 2:

        return _buildGuestbookList();

      default:

        return _buildDiaryFeed();

    }

  }



  Widget _buildDiaryFeed() {

    if (_isDiariesLoading) {

      return const Center(child: CircularProgressIndicator(color: Color(0xFF5D4037)));

    }

    if (_diaries.isEmpty) {

      return RefreshIndicator(

        onRefresh: _fetchDiaries,

        child: ListView(

          children: const [

            SizedBox(height: 150),

            Center(

              child: Text("아직 기록된 추억이 없어요.\n첫 일기를 작성해보세요!",

                textAlign: TextAlign.center,

              )

            ),

          ],

        )

      );

    }

    return RefreshIndicator(

      onRefresh: _fetchDiaries,

      child: ListView.builder(

        padding: const EdgeInsets.all(16),

        itemCount: _diaries.length,

        itemBuilder: (context, index) =>

            _buildFeedCard(index),

      ),

    );

  }



  Widget _buildPhotoAlbumGrid() {

    if (_isDiariesLoading) {

      return const Center(child: CircularProgressIndicator(color: Color(0xFF5D4037)));

    }

    if (_photoDiaries.isEmpty) {

       return RefreshIndicator(

        onRefresh: _fetchDiaries,

        child: ListView(

          children: [

            const SizedBox(height: 150),

            Center(

              child: Text(

                "아직 사진이 없어요.\n멋진 순간을 사진으로 남겨보세요!",

                textAlign: TextAlign.center,

                style: GoogleFonts.jua(color: const Color(0xFF795548)),

              ),

            ),

          ],

        )

      );

    }

    return RefreshIndicator(

      onRefresh: _fetchDiaries,

      child: GridView.builder(

        padding: const EdgeInsets.all(16),

        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(

          crossAxisCount: 3,

          crossAxisSpacing: 8,

          mainAxisSpacing: 8,

        ),

        itemCount: _photoDiaries.length,

        itemBuilder: (context, index) {

          final diary = _photoDiaries[index];

          final dynamic diaryImage = diary['image_url'];

          return ClipRRect(

            borderRadius: BorderRadius.circular(15.0),

            child: GridTile(

              footer: Container(

                padding: const EdgeInsets.all(8.0),

                color: Colors.black.withOpacity(0.5),

                child: Text(

                  diary['content'],

                  style: GoogleFonts.jua(color: Colors.white, fontSize: 12),

                  maxLines: 1,

                  overflow: TextOverflow.ellipsis,

                ),

              ),

              child: Image.network(

                diaryImage.toString().startsWith('/')

                    ? "${AppConfig.serverBaseUrl}${diaryImage}"

                    : diaryImage.toString(),

                fit: BoxFit.cover,

                filterQuality: FilterQuality.high,

                errorBuilder: (ctx, err, stack) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),

              ),

            ),

          );

        },

      ),

    );

  }



  Widget _buildGuestbookList() {

    if (_isGuestbookLoading) {

      return const Center(child: CircularProgressIndicator(color: Color(0xFF5D4037)));

    }

    if (_guestbookEntries.isEmpty) {

      return RefreshIndicator(

        onRefresh: _fetchGuestbookEntries,

        child: ListView(

          children: [

            const SizedBox(height: 150),

            Center(

              child: Text(

                "아직 방문 기록이 없어요!\n첫 방명록을 기다리고 있어요.",

                textAlign: TextAlign.center,

                style: GoogleFonts.jua(color: const Color(0xFF795548)),

              ),

            ),

          ],

        )

      );

    }

    

    return RefreshIndicator(

      onRefresh: _fetchGuestbookEntries,

      child: ListView.builder(

        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), // FAB space

        itemCount: _guestbookEntries.length,

        itemBuilder: (context, index) {

          return _buildGuestbookCard(_guestbookEntries[index]);

        },

      ),

    );

  }



  Widget _buildGuestbookCard(GuestbookEntry entry) {

    return Container(

      margin: const EdgeInsets.only(bottom: 16),

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(

        color: const Color(0xFFFFF9E6).withOpacity(0.5),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: const Color(0xFFF5EFE6)),

      ),

      child: Row(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          CuteAvatar(petType: entry.authorPetType ?? 'dog', size: 44),

          const SizedBox(width: 16),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(

                  entry.authorNickname,

                  style: GoogleFonts.jua(fontSize: 16, color: const Color(0xFF4E342E), fontWeight: FontWeight.bold),

                ),

                const SizedBox(height: 8),

                Text(

                  entry.content,

                  style: GoogleFonts.jua(fontSize: 15, color: const Color(0xFF795548), height: 1.5),

                ),

                const SizedBox(height: 8),

                Text(

                  entry.createdAt.substring(0, 10), // Just date part

                  style: GoogleFonts.jua(fontSize: 12, color: Colors.grey[400]),

                ),

              ],

            ),

          ),

        ],

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

      onTap: () => _onTabChanged(index),

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

  final bool isImageRequired;

  const _AddDiarySheet({required this.petType, required this.onSave, this.isImageRequired = false});



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

    if (_contentController.text.isEmpty) {

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("내용을 입력해주세요.")));

      return;

    }

    if (widget.isImageRequired && _image == null) {

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("사진을 추가해야 합니다.")));

      return;

    }



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

            Text(widget.isImageRequired ? "사진 기록하기" : "오늘의 추억 기록", style: GoogleFonts.jua(fontSize: 20, color: const Color(0xFF5D4037))), 

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

                hintText: widget.isImageRequired ? "사진에 대한 설명을 남겨주세요." : "우리 아이와 어떤 일이 있었나요?",

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



// --- Add Guestbook Entry Sheet ---

class _AddGuestbookEntrySheet extends StatefulWidget {

  final int userId;

  final Function(GuestbookEntry) onSave;



  const _AddGuestbookEntrySheet({required this.userId, required this.onSave});



  @override

  State<_AddGuestbookEntrySheet> createState() => _AddGuestbookEntrySheetState();

}



class _AddGuestbookEntrySheetState extends State<_AddGuestbookEntrySheet> {

  final TextEditingController _contentController = TextEditingController();

  bool _isSubmitting = false;



  Future<void> _submit() async {

    if (_contentController.text.trim().isEmpty) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(content: Text("내용을 입력해주세요.")),

      );

      return;

    }



    setState(() => _isSubmitting = true);



    try {

      final token = await AuthService().getToken();

      final response = await http.post(

        Uri.parse('${AppConfig.baseUrl}/guestbook/user/${widget.userId}'),

        headers: {

          'Authorization': 'Bearer $token',

          'Content-Type': 'application/json; charset=UTF-8',

        },

        body: jsonEncode({'content': _contentController.text.trim()}),

      );



      if (response.statusCode >= 200 && response.statusCode < 300) {

        final newEntry = GuestbookEntry.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

        widget.onSave(newEntry);

        if (mounted) {

          Navigator.pop(context);

          ScaffoldMessenger.of(context).showSnackBar(

            const SnackBar(content: Text("방명록이 저장되었습니다!")),

          );

        }

      } else {

        if (mounted) {

          ScaffoldMessenger.of(context).showSnackBar(

            SnackBar(content: Text("저장에 실패했습니다. (${response.statusCode})")),

          );

        }

      }

    } catch (e) {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(content: Text("에러가 발생했습니다: $e")),

        );

      }

    } finally {

      if (mounted) {

        setState(() => _isSubmitting = false);

      }

    }

  }



  @override

  Widget build(BuildContext context) {

    return Container(

      decoration: const BoxDecoration(

        color: Color(0xFFFFF9E6),

        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),

      ),

      padding: EdgeInsets.only(

        bottom: MediaQuery.of(context).viewInsets.bottom,

        left: 20,

        right: 20,

        top: 24,

      ),

      child: SingleChildScrollView(

        child: Column(

          mainAxisSize: MainAxisSize.min,

          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [

            Text(

              "방명록 남기기",

              style: GoogleFonts.jua(fontSize: 20, color: const Color(0xFF5D4037)),

            ),

            const SizedBox(height: 24),

            TextField(

              controller: _contentController,

              autofocus: true,

              style: GoogleFonts.jua(color: const Color(0xFF5D4037)),

              decoration: InputDecoration(

                hintText: "따뜻한 응원의 메시지를 남겨주세요...",

                hintStyle: GoogleFonts.jua(color: const Color(0xFFBCAAA4)),

                filled: true,

                fillColor: const Color(0xFFF5EFE6),

                border: OutlineInputBorder(

                  borderRadius: BorderRadius.circular(15),

                  borderSide: BorderSide.none,

                ),

              ),

              maxLines: 5,

            ),

            const SizedBox(height: 24),

            ElevatedButton(

              onPressed: _isSubmitting ? null : _submit,

              style: ElevatedButton.styleFrom(

                backgroundColor: const Color(0xFF5D4037),

                padding: const EdgeInsets.symmetric(vertical: 16),

                shape: const StadiumBorder(),

              ),

              child: _isSubmitting

                  ? const SizedBox(

                      width: 24,

                      height: 24,

                      child: CircularProgressIndicator(color: Colors.white),

                    )

                  : Text(

                      "남기기",

                      style: GoogleFonts.jua(color: Colors.white, fontSize: 18),

                    ),

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

  final FocusNode _commentFocusNode = FocusNode();

  List<Comment> _comments = [];

  bool _isLoading = true;

  bool _isPosting = false;

  int? _currentUserId;



  int? _replyToCommentId;

  String? _replyToNickname;





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

    if(!mounted) return;

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

        final List<Comment> allComments = data.map((item) => Comment.fromJson(item)).toList();

        

        // --- Build Nested Structure (Immutable) ---

        Map<int?, List<Comment>> commentsByParent = {};

        for (var comment in allComments) {

          commentsByParent.putIfAbsent(comment.parentId, () => []).add(comment);

        }



        List<Comment> buildReplies(int? parentId) {

          final children = commentsByParent[parentId] ?? [];

          return children.map((child) {

            return child.copyWith(replies: buildReplies(child.id));

          }).toList();

        }



        final List<Comment> nestedComments = buildReplies(null);

        // --- End of Build ---



        if (mounted) {

          setState(() {

            _comments = nestedComments;

          });

        }

      }

    } catch (e) {

      print("Error fetching comments: $e");

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("댓글을 불러오는데 실패했습니다.")));

    } finally {

      if (mounted) setState(() => _isLoading = false);

    }

  }



  Future<void> _postComment() async {

    if (_commentController.text.trim().isEmpty) return;

    if (!mounted) return;

    setState(() => _isPosting = true);



    try {

      final token = await AuthService().getToken();

      final body = {

        "content": _commentController.text.trim(),

        if (_replyToCommentId != null) "parent_id": _replyToCommentId,

      };



      final response = await http.post(

        Uri.parse('${AppConfig.baseUrl}/diaries/${widget.diaryId}/comments'),

        headers: {

          "Authorization": "Bearer $token",

          "Content-Type": "application/json",

        },

        body: jsonEncode(body),

      );



      if (response.statusCode == 200 || response.statusCode == 201) {

        if (mounted) {

          _commentController.clear();

           _cancelReply();

          widget.onCommentPosted();

          await _fetchComments();

        }

      } else {

        final error = jsonDecode(response.body);

        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("댓글 작성 실패: ${error['detail']}")));

      }

    } catch (e) {

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("에러: $e")));

    } finally {

      if (mounted) setState(() => _isPosting = false);

    }

  }



  void _startReply(Comment comment) {

    if (!mounted) return;

    setState(() {

      _replyToCommentId = comment.id;

      _replyToNickname = comment.nickname;

      _commentFocusNode.requestFocus();

    });

  }



  void _cancelReply() {

    if (!mounted) return;

    setState(() {

      _replyToCommentId = null;

      _replyToNickname = null;

      _commentFocusNode.unfocus();

    });

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

          widget.onCommentDeleted();

          await _fetchComments(); // Re-fetch to get the correct state

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

      height: MediaQuery.of(context).size.height * 0.8,

      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),

      decoration: const BoxDecoration(

        color: Color(0xFFFFF9E6),

        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),

      ),

      child: Column(

        children: [

          Padding(

            padding: const EdgeInsets.symmetric(vertical: 16.0),

            child: Text("댓글", style: GoogleFonts.jua(fontSize: 20, color: const Color(0xFF5D4037))),

          ),

          const Divider(height: 1),

          Expanded(

            child: _isLoading

                ? const Center(child: CircularProgressIndicator(color: Color(0xFF5D4037)))

                : _comments.isEmpty

                    ? Center(child: Text("첫 댓글을 남겨보세요!", style: GoogleFonts.jua(color: const Color(0xFF795548))))

                    : RefreshIndicator(

                      onRefresh: _fetchComments,

                      child: ListView(

                        padding: const EdgeInsets.all(16),

                        children: _buildCommentWidgets(_comments),

                      ),

                    ),

          ),

          _buildCommentInput(),

        ],

      ),

    );

  }



  List<Widget> _buildCommentWidgets(List<Comment> comments, {int depth = 0}) {

    List<Widget> widgets = [];

    for (var comment in comments) {

      widgets.add(_buildCommentTile(comment, depth: depth));

      if (comment.replies.isNotEmpty) {

        widgets.addAll(_buildCommentWidgets(comment.replies, depth: depth + 1));

      }

    }

    return widgets;

  }



  Widget _buildCommentTile(Comment comment, {int depth = 0}) {

    final bool isAuthor = comment.userId == widget.diaryAuthorId && comment.userId != 0;

    final bool isMyComment = comment.userId == _currentUserId && comment.userId != 0;

    final double indent = 20.0 * depth;



    return Padding(

      padding: EdgeInsets.only(left: indent, top: 8, bottom: 8),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Row(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              CuteAvatar(petType: comment.petType ?? 'dog', size: 36),

              const SizedBox(width: 12),

              Expanded(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Row(

                      children: [

                        Text(comment.nickname, style: GoogleFonts.jua(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF4E342E))),

                        if (isAuthor)

                          Padding(

                            padding: const EdgeInsets.only(left: 6.0),

                            child: FaIcon(FontAwesomeIcons.crown, color: Colors.amber[600], size: 14),

                          ),

                      ],

                    ),

                    const SizedBox(height: 4),

                    Text(comment.content, style: GoogleFonts.jua(color: const Color(0xFF795548), fontSize: 14)),

                  ],

                ),

              ),

              if (isMyComment)

                SizedBox(

                  width: 30,

                  height: 30,

                  child: IconButton(

                    padding: EdgeInsets.zero,

                    icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 18),

                    onPressed: () => _deleteComment(comment.id),

                  ),

                ),

            ],

          ),

          Padding(

            padding: const EdgeInsets.only(left: 48, top: 4),

            child: InkWell(

              onTap: () => _startReply(comment),

              child: Text(

                "답글 달기",

                style: GoogleFonts.jua(fontSize: 12, color: Colors.grey[600]),

              ),

            ),

          ),

        ],

      ),

    );

  }



  Widget _buildCommentInput() {

    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

      decoration: BoxDecoration(

        color: Colors.white,

        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: -5, blurRadius: 10)],

      ),

      child: Column(

        mainAxisSize: MainAxisSize.min,

        children: [

          if (_replyToCommentId != null)

            Padding(

              padding: const EdgeInsets.only(bottom: 8.0, left: 4),

              child: Row(

                children: [

                  Text(

                    "'${_replyToNickname ?? ''}'님에게 답글 남기는 중...",

                    style: GoogleFonts.jua(color: Colors.grey[600], fontSize: 12),

                  ),

                  const Spacer(),

                  SizedBox(

                    height: 24,

                    child: IconButton(

                      padding: EdgeInsets.zero,

                      icon: const Icon(Icons.close, size: 16, color: Colors.grey),

                      onPressed: _cancelReply,

                    ),

                  )

                ],

              ),

            ),

          Row(

            children: [

              Expanded(

                child: TextField(

                  controller: _commentController,

                  focusNode: _commentFocusNode,

                  style: GoogleFonts.jua(),

                  decoration: InputDecoration(

                    hintText: "따뜻한 댓글을 남겨주세요...",

                    hintStyle: GoogleFonts.jua(color: const Color(0xFFBCAAA4)),

                    border: InputBorder.none,

                    isDense: true,

                    contentPadding: const EdgeInsets.symmetric(vertical: 8)

                  ),

                  maxLines: 1,

                  onSubmitted: (_) => _postComment(),

                ),

              ),

              IconButton(

                icon: _isPosting

                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5D4037)))

                    : const Icon(Icons.send, color: Color(0xFF5D4037)),

                onPressed: _isPosting ? null : _postComment,

              ),

            ],

          ),

        ],

      ),

    );

  }

}