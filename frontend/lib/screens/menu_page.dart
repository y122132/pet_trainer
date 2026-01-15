import 'dart:io';
import 'dart:async'; 
import 'battle_page.dart';
import 'dart:math' as math;
import 'login_screen.dart'; 
import 'my_room_page.dart';

import 'user_list_screen.dart';
import 'mode_select_page.dart';
import 'pet_universe_screen.dart';
import 'battle_lobby_screen.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../providers/char_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/battle_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'notice_list_screen.dart';
import 'package:pet_trainer_frontend/api_config.dart'; 
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/notice_model.dart';

import '../config/design_system.dart';
import 'character_image_update_screen.dart';
import '../widgets/cute_avatar.dart';
import '../widgets/common/bone_widget.dart'; // Added
import 'package:flutter/material.dart';
import 'camera_screen.dart';
import 'chat_screen.dart';
import 'skill_management_screen.dart';
import 'package:pet_trainer_frontend/config/theme.dart';
import 'package:pet_trainer_frontend/config/design_system.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> with SingleTickerProviderStateMixin {
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;
  StreamSubscription? _chatSubscription;
  bool _hasNewNotice = false; // [New]

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
    _breathingAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );
    _breathingController.repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
        final charProvider = Provider.of<CharProvider>(context, listen: false);
        // Don't fetch if there's a temporary image or if character is already loaded nicely
        if (charProvider.tempFrontImage == null && charProvider.character == null) {
          charProvider.fetchMyCharacter();
        }
        
        _initChatConnection(); // [New]
        _checkForNewNotices(); // [New]
    });
  }

  Future<void> _checkForNewNotices() async {
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/notices/'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data.isNotEmpty) {
          final notices = data.map((item) => NoticeModel.fromJson(item)).toList();
          final latestNoticeId = notices.first.id;

          final prefs = await SharedPreferences.getInstance();
          final lastSeenId = prefs.getInt('last_seen_notice_id') ?? 0;

          setState(() {
            _hasNewNotice = latestNoticeId > lastSeenId;
          });
        }
      }
    } catch (e) {
      print("Error checking for new notices: $e");
    }
  }

  Future<void> _initChatConnection() async {
    final auth = AuthService();
    final idStr = await auth.getUserId();
    if (idStr != null && mounted) {
      final myId = int.parse(idStr);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      chatProvider.connect(myId);

      _chatSubscription = chatProvider.messageStream.listen((msg) {
        if (msg['type'] == 'BATTLE_INVITE') {
          _showInviteDialog(msg);
        }
      });
    }
  }

  void _showInviteDialog(Map<String, dynamic> msg) {
    if (!mounted) return;
    final roomId = msg['room_id'];
    final message = msg['message'] ?? "Battle Invite!";
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
            title: Row(children: [
              const FaIcon(FontAwesomeIcons.khanda, color: AppColors.primary),
              const SizedBox(width: 12),
              Text("도전장 도착!", style: AppTextStyles.title.copyWith(fontSize: 22)),
            ]),
            content: Text(message, style: AppTextStyles.body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("거절", style: AppTextStyles.body),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (roomId != null) {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider(
                                create: (_) => BattleProvider()..setRoomId(roomId),
                                child: const BattleView())));
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius)),
                child: Text("수락", style: AppTextStyles.button),
              )
            ],
          );
        });
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("설정", style: AppTextStyles.title.copyWith(fontSize: 20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: AppColors.info),
              title: Text("캐릭터 사진 변경", style: AppTextStyles.body),
              onTap: () {
                Navigator.pop(context); // Close the dialog
                final charProvider = Provider.of<CharProvider>(context, listen: false);
                if (charProvider.character != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => CharacterImageUpdateScreen(character: charProvider.character!)));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: Text("로그아웃", style: AppTextStyles.body.copyWith(color: AppColors.danger)),
              onTap: () => _handleLogout(context),
            ),
            // [추가 가능] 알림 설정, 다크모드 등 ListTile을 여기에 추가
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _handleLogout(BuildContext context) async {
    Provider.of<ChatProvider>(context, listen: false).disconnect();
    Provider.of<CharProvider>(context, listen: false).clearData();

    final auth = AuthService();
    await auth.logout();

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("안전하게 로그아웃 되었습니다."),
          backgroundColor: AppColors.textMain,
        )
      );
    }
  }
  @override
  void dispose() {
    _chatSubscription?.cancel();
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final charProvider = Provider.of<CharProvider>(context);
    final characterName = charProvider.character?.name ?? "펫";
    final characterType = charProvider.character?.petType ?? "dog";
    dynamic characterImage;
    if (charProvider.tempFrontImage != null) {
      characterImage = charProvider.tempFrontImage!;
    } else if (charProvider.character?.frontUrl != null &&
        charProvider.character!.frontUrl!.isNotEmpty) {
      characterImage = charProvider.character!.frontUrl!;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. [Background] Spotlight Studio Atmosphere
          // 1. [Background] Exact Friend Page Style
          Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              image: DecorationImage(
                image: AssetImage('assets/images/login_bg.png'),
                fit: BoxFit.cover,
                opacity: 0.3,
              ),
            ),
          ),



          // 3. [Main Content]
          Positioned.fill(
             child: SafeArea(
               bottom: false,
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   // Header
                   _buildHeader(characterName, characterType),
                   
                   const Spacer(flex: 2),
                   
                   // Character Centerpiece
                   _buildCenterpiece(characterImage),
                   
                   const Spacer(flex: 3),
                   
                   // Training Action Button
                   _buildTrainingButton(context),
                   
                   const Spacer(flex: 4), // Space for Bottom Nav
                   const SizedBox(height: 100), // Placeholder for floating nav
                 ],
               ),
             ),
          ),

          // 4. [Floating Navigation Bar]
          Positioned(
            left: 24, 
            right: 24, 
            bottom: MediaQuery.of(context).padding.bottom + 20,
            child: _buildFloatingBottomBar(context),
          )
        ],
      ),
    );
  }

  Widget _buildHeader(String name, String type) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          BoneWidget(text: '$name ($type)'),
          Row(
            children: [
              GestureDetector(
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const NoticeListScreen()));
                  // Refresh badge status when coming back from notice list
                  _checkForNewNotices();
                },
                child: Stack(
                  children: [
                    _buildHeaderIcon(FontAwesomeIcons.bell),
                    if (_hasNewNotice)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 12,
                            minHeight: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _showSettingsDialog,
                child: _buildHeaderIcon(Icons.settings),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon) {
    return Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8), 
        shape: BoxShape.circle,
        boxShadow: [
           BoxShadow(
             color: AppColors.primary.withOpacity(0.1),
             blurRadius: 8,
             offset: const Offset(0, 2)
           )
        ],
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5)
      ),
      child: Center(
        child: FaIcon(icon, color: AppColors.primary, size: 18),
      ),
    );
  }

  Widget _buildCenterpiece(dynamic image) {
    Widget imageWidget;
    if (image is XFile) {
        if (kIsWeb) {
            imageWidget = Image.network(
                image.path, 
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.pets, color: Colors.grey, size: 40),
            );
        } else {
            imageWidget = Image.file(File(image.path), fit: BoxFit.cover,);
        }
    } else if (image is String && image.isNotEmpty) {
        String imageUrl = image;
        if (imageUrl.startsWith('/')) {
            imageUrl = "${AppConfig.serverBaseUrl}$imageUrl";
        } else if (imageUrl.contains('localhost')) {
            imageUrl = imageUrl.replaceFirst('localhost', AppConfig.serverIp);
        }
        imageWidget = Image.network(
            imageUrl, 
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.pets, color: Colors.grey, size: 40),
        );
    } else {
      imageWidget = Image.asset('assets/images/단팥 기본.png', fit: BoxFit.contain);
    }

    return AnimatedBuilder(
      animation: _breathingAnimation,
      builder: (context, child) => Transform.scale(scale: _breathingAnimation.value, child: child),
      child: SizedBox(
        width: 280, // Larger presence
        height: 280,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // No strong circle border - let it blend nicely or use thin border
            Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.3), // Subtle halo
                boxShadow: const [
                   BoxShadow(
                     color: Colors.white,
                     blurRadius: 30,
                     spreadRadius: -5,
                   )
                ],
              ),
            ),
            // The Image
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3), // Clean rim
              ),
              child: ClipOval(child: imageWidget),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainingButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
        borderRadius: BorderRadius.circular(30),
      ),
      child: ElevatedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ModeSelectPage())),
        icon: const FaIcon(FontAwesomeIcons.dumbbell, color: Colors.white, size: 24),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("TRAINING", style: AppTextStyles.title.copyWith(color: Colors.white, fontSize: 20)),
              Text("여기를 눌러 훈련하기", style: GoogleFonts.jua(color: Colors.white.withOpacity(0.9), fontSize: 12)),
            ],
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildFloatingBottomBar(BuildContext context) {
    final charProvider = Provider.of<CharProvider>(context, listen: false);

    final myData = {
      "id": charProvider.character?.userId ?? 0,
      "nickname": charProvider.character?.name ?? "나의 펫",
      "pet_type": charProvider.character?.petType ?? "dog",
      "level": charProvider.character?.stat?.level ?? 1,
    };

    return Container(
      height: 70, // Compact height
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9), // Glass-like
        borderRadius: BorderRadius.circular(35), // Pill shape
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 5)
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavIcon(
            context: context,
            icon: FontAwesomeIcons.houseUser,
            label: "MY ROOM",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyRoomPage())),
          ),
          _buildNavIcon(
            context: context,
            icon: FontAwesomeIcons.earthAmericas,
            label: "UNIVERSE",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PetUniverseScreen(user: myData))),
          ),
          _buildNavIcon(
            context: context,
            icon: FontAwesomeIcons.userGroup,
            label: "FRIENDS",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UserListScreen())),
          ),
          _buildNavIcon(
            context: context,
            icon: FontAwesomeIcons.khanda,
            label: "BATTLE",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BattleLobbyScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildNavIcon({required BuildContext context, required IconData icon, required String label, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(30),
      child: Padding( // Wider touch area
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, color: AppColors.primary, size: 20),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.jua(color: AppColors.textSub, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

