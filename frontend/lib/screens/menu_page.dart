import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io'; // Required for File
import 'package:flutter/foundation.dart' show kIsWeb; // Required for kIsWeb
import 'package:image_picker/image_picker.dart';
import 'my_room_page.dart';
import 'mode_select_page.dart';
import 'battle_page.dart';
import 'battle_lobby_screen.dart'; // [New]
import 'user_list_screen.dart'; // [New]
import '../providers/char_provider.dart';
import '../config/theme.dart';
import '../providers/chat_provider.dart'; // [New]
import '../services/auth_service.dart'; // [New]
import '../providers/battle_provider.dart'; // [New]
import 'dart:async'; // [New]
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pet_trainer_frontend/api_config.dart'; // [Fix] Import AppConfig
import 'login_screen.dart'; // [New] For Logout


class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> with SingleTickerProviderStateMixin {
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;
  StreamSubscription? _chatSubscription; // [New]

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _breathingAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );
    _breathingController.repeat(reverse: true);
    
    // Auto-fetch data and connect chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
        final charProvider = Provider.of<CharProvider>(context, listen: false);
        // Don't fetch if there's a temporary image or if character is already loaded nicely
        if (charProvider.tempFrontImage == null && charProvider.character == null) {
          charProvider.fetchMyCharacter();
        }
        
        _initChatConnection(); // [New]
    });
  }

  Future<void> _initChatConnection() async {
      final auth = AuthService();
      final idStr = await auth.getUserId();
      if (idStr != null && mounted) {
          final myId = int.parse(idStr);
          final chatProvider = Provider.of<ChatProvider>(context, listen: false);
          chatProvider.connect(myId);
          
          // Listen for global invites
          _chatSubscription = chatProvider.messageStream.listen((msg) {
              if (msg['type'] == 'BATTLE_INVITE') {
                  _showInviteDialog(msg); // [Fix] Use Dialog instead of SnackBar
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
        barrierDismissible: false, // Must accept or decline
        builder: (context) {
           return AlertDialog(
             backgroundColor: AppColors.navy,
             shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppColors.cyberYellow, width: 2)
             ),
             title: const Row(
               children: [
                 Icon(Icons.sports_kabaddi, color: AppColors.cyberYellow),
                 SizedBox(width: 10),
                 Text("도전장 도착!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
               ],
             ),
             content: Text(
               message, 
               style: const TextStyle(color: Colors.white70, fontSize: 16)
             ),
             actions: [
               TextButton(
                 onPressed: () => Navigator.pop(context),
                 child: const Text("거절", style: TextStyle(color: Colors.grey)),
               ),
               ElevatedButton(
                 onPressed: () {
                    Navigator.pop(context); // Close dialog
                    if (roomId != null) {
                       Navigator.push(
                         context, 
                         MaterialPageRoute(
                           builder: (_) => ChangeNotifierProvider(
                             create: (_) => BattleProvider()..setRoomId(roomId),
                             child: const BattleView(),
                           )
                         )
                       );
                    }
                 },
                 style: ElevatedButton.styleFrom(
                   backgroundColor: AppColors.danger,
                   foregroundColor: Colors.white
                 ),
                 child: const Text("수락 (FIGHT!)", style: TextStyle(fontWeight: FontWeight.bold)),
               )
             ],
           );
        }
      );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("설정", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("로그아웃"),
              onTap: () async {
                 await AuthService().logout();
                 if (mounted) {
                   Navigator.of(context).pushAndRemoveUntil(
                     MaterialPageRoute(builder: (_) => const LoginScreen()),
                     (route) => false
                   );
                 }
              },
            ),
             // 추후 사운드 설정 등 추가 가능
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("닫기"))
        ],
      )
    );
  }

  @override
  void dispose() {
    _chatSubscription?.cancel(); // [New]
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
    } else if (charProvider.character?.frontUrl != null && charProvider.character!.frontUrl!.isNotEmpty) {
        characterImage = charProvider.character!.frontUrl!;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E6),
      body: Stack(
        children: [
          _buildBackgroundPattern(),
          SafeArea(
            bottom: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildHeader(characterName, characterType),
                const Spacer(flex: 1),
                _buildCenterpiece(characterImage),
                const Spacer(flex: 1),
                _buildTrainingButton(context),
                const Spacer(flex: 3),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundPattern() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 80,
          crossAxisSpacing: 80,
        ),
        itemBuilder: (context, index) {
          bool isPaw = index % 3 == 0;
          return Transform.rotate(
            angle: isPaw ? -math.pi / 12 : math.pi / 6,
            child: Icon(
              isPaw ? FontAwesomeIcons.paw : FontAwesomeIcons.bone,
              color: Colors.brown.withOpacity(0.05),
              size: 40,
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(String name, String type) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildBoneContainer(name, type),
          Row(
            children: [
              _buildHeaderIcon(FontAwesomeIcons.envelope),
              const SizedBox(width: 12),
              _buildHeaderIcon(FontAwesomeIcons.bell),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _showSettingsDialog,
                child: _buildHeaderIcon(Icons.settings), // Use standard icon for settings
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildBoneContainer(String name, String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: const StadiumBorder(),
        shadows: [
          BoxShadow(
            color: Colors.brown.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Text(
        '$name ($type)',
        style: GoogleFonts.jua(
          color: const Color(0xFF4E342E),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: FaIcon(icon, color: const Color(0xFF4E342E), size: 20),
    );
  }

  Widget _buildCenterpiece(dynamic image) {
    Widget imageWidget;
    if (image is XFile) {
        if (kIsWeb) {
            imageWidget = Image.network(image.path, fit: BoxFit.cover,);
        } else {
            imageWidget = Image.file(File(image.path), fit: BoxFit.cover,);
        }
    } else if (image is String && image.isNotEmpty) {
        // [Fix] 상대 경로(/uploads/...) 및 로컬호스트 레거시 데이터 처리
        String imageUrl = image;
        if (imageUrl.startsWith('/')) {
            imageUrl = "${AppConfig.serverBaseUrl}$imageUrl";
        } else if (imageUrl.contains('localhost')) {
            imageUrl = imageUrl.replaceFirst('localhost', AppConfig.serverIp);
        }
        imageWidget = Image.network(imageUrl, fit: BoxFit.cover,);
    } else {
        imageWidget = Image.asset('assets/images/단팥 기본.png', fit: BoxFit.contain,);
    }
    
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF5D4037),
        boxShadow: [
          BoxShadow(
              color: Colors.brown.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Center(
        child: ClipOval(
          child: Container(
            width: 180,
            height: 180,
            color: Colors.white,
            child: ClipOval(
                child: imageWidget
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrainingButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
              color: Colors.brown.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 8))
        ],
        borderRadius: BorderRadius.circular(50),
      ),
      child: ElevatedButton.icon(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ModeSelectPage())),
        icon: const FaIcon(FontAwesomeIcons.dumbbell, color: Colors.white, size: 28),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "TRAINING",
                style: GoogleFonts.jua(
                  fontSize: 32,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              Text(
                "스탯을 성장시키세요",
                style: GoogleFonts.jua(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5D4037),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF6D4C41), // Wood color
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
        border: Border(
          top: BorderSide(color: Colors.black.withOpacity(0.1), width: 2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBottomNavButton(
            context: context,
            icon: FontAwesomeIcons.houseUser,
            label: "MY ROOM",
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (context) => const MyRoomPage())),
          ),
          _buildBottomNavButton(
            context: context,
            icon: FontAwesomeIcons.userGroup,
            label: "FRIENDS",
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => const UserListScreen())),
          ),
          _buildBottomNavButton(
            context: context,
            icon: FontAwesomeIcons.khanda,
            label: "BATTLE",
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (context) => BattleLobbyScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavButton(
      {required BuildContext context,
      required IconData icon,
      required String label,
      required VoidCallback onPressed}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: const Color(0xFF4E342E),
            padding: const EdgeInsets.all(20),
            side: const BorderSide(color: Colors.white, width: 2),
          ),
          child: FaIcon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.jua(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
