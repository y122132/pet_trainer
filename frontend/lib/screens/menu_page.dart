import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../config/design_system.dart';
import 'my_room_page.dart';
import 'mode_select_page.dart';
import 'battle_page.dart';
import 'battle_lobby_screen.dart';
import 'user_list_screen.dart';
import '../providers/char_provider.dart';
import '../providers/chat_provider.dart';
import '../services/auth_service.dart';
import '../providers/battle_provider.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> with SingleTickerProviderStateMixin {
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;
  StreamSubscription? _chatSubscription;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
    _breathingAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );
    _breathingController.repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final charProvider = Provider.of<CharProvider>(context, listen: false);
      if (charProvider.tempFrontImage == null) {
        charProvider.fetchMyCharacter();
      }
      _initChatConnection();
    });
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
              const FaIcon(FontAwesomeIcons.khanda, color: AppColors.primaryBrown),
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
                    backgroundColor: AppColors.statStr,
                    shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius)),
                child: Text("수락", style: AppTextStyles.button),
              )
            ],
          );
        });
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
      body: ThemedBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHeader(characterName, characterType),
              const Spacer(flex: 2),
              _buildCenterpiece(characterImage),
              const Spacer(flex: 2),
              _buildTrainingButton(context),
              const Spacer(flex: 4),
              _buildBottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String name, String type) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _BoneWidget(text: '$name ($type)'),
          Row(
            children: [
              _buildHeaderIcon(FontAwesomeIcons.envelope),
              const SizedBox(width: 18),
              _buildHeaderIcon(FontAwesomeIcons.bell),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: AppDecorations.cardShadow,
        border: Border.all(color: AppColors.secondaryBrown.withOpacity(0.5), width: 1)
      ),
      child: FaIcon(icon, color: AppColors.secondaryBrown, size: 22),
    );
  }

  Widget _buildCenterpiece(dynamic image) {
    Widget imageWidget;
    if (image is XFile) {
      if (kIsWeb) {
        imageWidget = Image.network(image.path, fit: BoxFit.cover, filterQuality: FilterQuality.high);
      } else {
        imageWidget = Image.file(File(image.path), fit: BoxFit.cover, filterQuality: FilterQuality.high);
      }
    } else if (image is String && image.isNotEmpty) {
      imageWidget = Image.network(image, fit: BoxFit.cover, filterQuality: FilterQuality.high);
    } else {
      imageWidget = Image.asset('assets/images/단팥 기본.png', fit: BoxFit.contain);
    }

    return AnimatedBuilder(
      animation: _breathingAnimation,
      builder: (context, child) => Transform.scale(scale: _breathingAnimation.value, child: child),
      child: SizedBox(
        width: 250,
        height: 250,
        child: CustomPaint(
          painter: FlowerFramePainter(),
          child: Center(
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: AppDecorations.cardShadow,
              ),
              child: ClipOval(child: imageWidget),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrainingButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: AppDecorations.cardShadow,
        borderRadius: AppDecorations.cardRadius,
      ),
      child: ElevatedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ModeSelectPage())),
        icon: const FaIcon(FontAwesomeIcons.dumbbell, color: Colors.white, size: 32),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("TRAINING", style: AppTextStyles.title.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              Text("스탯을 성장시키세요", style: AppTextStyles.body.copyWith(color: Colors.white70)),
            ],
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBrown,
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.cardRadius),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      height: 150,
      padding: const EdgeInsets.only(top: 10, bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF6D4C41), // Placeholder for wood texture
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, -5))],
        border: Border(top: BorderSide(color: Colors.black.withOpacity(0.1), width: 2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildBottomNavButton(context: context, icon: FontAwesomeIcons.houseUser, label: "MY ROOM", onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MyRoomPage()))),
          _buildBottomNavButton(context: context, icon: FontAwesomeIcons.userGroup, label: "FRIENDS", onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UserListScreen()))),
          _buildBottomNavButton(context: context, icon: FontAwesomeIcons.khanda, label: "BATTLE", onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => BattleLobbyScreen()))),
        ],
      ),
    );
  }

  Widget _buildBottomNavButton({required BuildContext context, required IconData icon, required String label, required VoidCallback onPressed}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: AppDecorations.cardShadow,
          ),
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: AppColors.primaryBrown,
              padding: const EdgeInsets.all(24),
              side: const BorderSide(color: Colors.white, width: 2),
            ),
            child: FaIcon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: AppTextStyles.button.copyWith(fontSize: 14)),
      ],
    );
  }
}

// Custom painter for the bone shape
class _BoneWidget extends StatelessWidget {
  final String text;
  const _BoneWidget({required this.text});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: BoneShapePainter(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
        child: Text(text, style: AppTextStyles.base.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class BoneShapePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final shadowPaint = Paint()
      ..color = Colors.black12
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final double boneEndRadius = size.height / 2;
    final Rect body = Rect.fromLTWH(boneEndRadius, 0, size.width - size.height, size.height);
    final Path path = Path()..addRect(body);

    // Left bone end
    path.addOval(Rect.fromCircle(center: Offset(boneEndRadius, boneEndRadius), radius: boneEndRadius));
    // Right bone end
    path.addOval(Rect.fromCircle(center: Offset(size.width - boneEndRadius, boneEndRadius), radius: boneEndRadius));

    canvas.drawPath(path.shift(const Offset(0, 4)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FlowerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;
    final paint = Paint()..color = AppColors.primaryBrown;
    final shadowPaint = Paint()
      ..color = Colors.brown.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    
    int petals = 12;
    final Path path = Path();

    for (var i = 0; i < petals; i++) {
      final double angle = (i / petals) * 2 * math.pi;
      final offset = Offset(center.dx + math.cos(angle) * radius * 0.8, center.dy + math.sin(angle) * radius * 0.8);
      path.addOval(Rect.fromCircle(center: offset, radius: radius * 0.4));
    }
    path.addOval(Rect.fromCircle(center: center, radius: radius * 0.9));

    canvas.drawPath(path.shift(const Offset(0, 8)), shadowPaint);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
