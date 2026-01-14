import 'dart:io';
import 'dart:ui'; 
import '../api_config.dart';
import '../config/theme.dart';
import 'skill_management_screen.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/char_provider.dart';
import '../providers/chat_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../widgets/common/stat_widgets.dart'; 
import '../widgets/char_message_bubble.dart'; 
import '../widgets/cute_avatar.dart'; 
import '../widgets/stat_distribution_dialog.dart';
import '../config/global_settings.dart';
import '../config/design_system.dart';

class MyRoomPage extends StatefulWidget {
  const MyRoomPage({super.key});

  @override
  State<MyRoomPage> createState() => _MyRoomPageState();
}

class _MyRoomPageState extends State<MyRoomPage> with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;
  
  late AnimationController _messageController;
  late Animation<double> _messageAnimation;

  bool _showMessage = false;
  String _currentMessage = "오늘도 힘내자! 멍!";

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000));
    _breathingAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );
    _breathingController.repeat(reverse: true);

    _messageController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _messageAnimation = CurvedAnimation(parent: _messageController, curve: Curves.easeIn);

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _showBubbleWithMsg("어서오세요! 기다리고 있었어요!");
    });
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // --- Logic Methods ---

  void _handleTouchKey() {
    final provider = Provider.of<CharProvider>(context, listen: false);
    _onCharacterTap(provider);
  }

  void _showBubbleWithMsg(String msg) {
    if (!mounted) return;
    setState(() {
      _currentMessage = msg;
      _showMessage = true;
    });
    _messageController.forward();

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _messageController.reverse().then((_) {
          if (mounted) setState(() => _showMessage = false);
        });
      }
    });
  }

  void _onCharacterTap(CharProvider provider) {
    if (provider.hasNewSkillAlert) {
      _showBubbleWithMsg("새로운 기술을 배웠어요!");
      return; 
    }

    List<String> messages = [
      "오늘 운동은 언제 하시나요?",
      "간식이 먹고 싶어요! 멍!",
      "쓰담쓰담 해주세요~",
      "같이 놀아요!",
      "항상 고마워요!"
    ];
    String randomMsg = (messages..shuffle()).first;
    _showBubbleWithMsg(randomMsg);
  }

  Future<void> _handleLevelUp(BuildContext context, CharProvider charProvider) async {
    final result = await charProvider.manualLevelUp();
    if (!context.mounted || result == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("🎉 레벨업을 축하합니다!", style: GoogleFonts.jua(color: Colors.white, fontSize: 16)),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      )
    );

    if (charProvider.unusedStatPoints > 0) {
       // Optional: Notify user they have points, but don't force dialog if mereka don't want
       // _showStatDialog(context, charProvider);
    }
  }

  void _showStatDialog(BuildContext context, CharProvider provider) {
      final Map<String, int> statsMap = {
        "strength": provider.strength,
        "intelligence": provider.intelligence,
        "luck": provider.luck,
        "defense": provider.defense,
        "agility": provider.agility,
      };

      showDialog(
        context: context,
        builder: (context) => StatDistributionDialog(
          availablePoints: provider.unusedStatPoints,
          currentStats: statsMap,
          title: "스탯 성장",
          confirmLabel: "적용",
          skipLabel: "닫기",
          onConfirm: (allocated, remaining) {
             _applyAllocated(provider, 'strength', allocated['strength']!);
             _applyAllocated(provider, 'intelligence', allocated['intelligence']!);
             _applyAllocated(provider, 'agility', allocated['agility']!);
             _applyAllocated(provider, 'defense', allocated['defense']!);
             _applyAllocated(provider, 'luck', allocated['luck']!);
             Navigator.pop(context);
          },
          onSkip: () => Navigator.pop(context),
        ),
      );
  }
  
  void _applyAllocated(CharProvider provider, String type, int amount) {
    for (int i=0; i<amount; i++) {
      provider.allocateStatSpecific(type); 
    }
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 24),
                Text("설정", style: GoogleFonts.jua(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                const SizedBox(height: 16),
                const Divider(),
                StatefulBuilder(
                  builder: (BuildContext context, StateSetter setModalState) {
                     return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("Edge AI 모드 (Beta)", style: GoogleFonts.jua(fontSize: 18, color: AppColors.textMain)),
                        subtitle: Text("기기 내부에서 추론하여 서버 부하를 줄입니다.", style: GoogleFonts.jua(fontSize: 12, color: AppColors.textSub)),
                        value: GlobalSettings.useEdgeAI,
                        activeColor: AppColors.primary,
                        onChanged: (bool value) async {
                           await GlobalSettings.setEdgeAI(value);
                           setModalState(() {}); 
                        },
                     );
                  }
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
                  title: Text("로그아웃", style: GoogleFonts.jua(color: AppColors.danger, fontSize: 18)),
                  onTap: () => _handleLogout(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleLogout(BuildContext context) async {
    Provider.of<ChatProvider>(context, listen: false).disconnect();
    Provider.of<CharProvider>(context, listen: false).clearData();
    final auth = AuthService();
    await auth.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  // --- UI Build Methods ---

  @override
  Widget build(BuildContext context) {
    final charProvider = Provider.of<CharProvider>(context);
    final character = charProvider.character;
    final stat = character?.stat; 
    
    final Map<String, int> statsMap = {
      "strength": stat?.strength ?? 0,
      "intelligence": stat?.intelligence ?? 0,
      "luck": stat?.luck ?? 0,
      "defense": stat?.defense ?? 0,
      "agility": stat?.agility ?? 0,
    };
    
    final int level = stat?.level ?? 1;
    final int currentExp = stat?.exp ?? 0;
    final int maxExp = level * 100;
    final double expPercent = (maxExp > 0) ? (currentExp / maxExp).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. [Background] Exact Friend Page Style (No layered Stack, use BoxDecoration)
          Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              image: DecorationImage(
                image: AssetImage('assets/images/login_bg.png'),
                fit: BoxFit.cover,
                opacity: 0.3, // Match Friend (UserListScreen: 0.3)
              ),
            ),
          ),
          
          // 2. [Character] 
          Positioned(
            top: MediaQuery.of(context).size.height * 0.14, 
            left: 0, right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _handleTouchKey,
                child: ScaleTransition(
                  scale: _breathingAnimation, 
                  child: Hero(
                    tag: 'character_avatar',
                    child: SizedBox(
                      width: 280, height: 280,
                      child: _buildCharacterDisplay(character),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // 3. [Speech Bubble]
          if (_showMessage)
            Positioned(
               top: MediaQuery.of(context).size.height * 0.08,
               left: 0, right: 0,
               child: Center(
                 child: FadeTransition(
                   opacity: _messageAnimation,
                   child: ConstrainedBox(
                     constraints: const BoxConstraints(maxWidth: 220),
                     child: CharMessageBubble(message: _currentMessage),
                   ),
                 ),
               ),
            ),
            
          // 4. [Header] Back / Title / Settings
          Positioned(
            top: 0, left: 0, right: 0,
            child: _buildHeader(context),
          ),

          // 5. [Floating Buttons Area]
          Positioned(
             top: MediaQuery.of(context).size.height * 0.15,
             right: 20,
             child: Column(
                children: [
                   _buildCircleButton(
                      icon: FontAwesomeIcons.bookOpen,
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SkillManagementScreen())),
                      label: "스킬도감",
                   ),
                   const SizedBox(height: 12),
                   _buildCircleButton(
                      icon: Icons.flash_on_rounded,
                      onPressed: () => _handleLevelUp(context, charProvider),
                      label: "레벨업(테스트)",
                      color: AppColors.accent,
                   ),
                ],
             ),
          ),

          // 6. [Stats Card] Floating Card
          Positioned(
            left: 16, right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            top: MediaQuery.of(context).size.height * 0.46, 
            child: Container(
              decoration: BoxDecoration(
                 color: Colors.white, // Pure white for flat look
                 borderRadius: BorderRadius.circular(32),
                 boxShadow: [
                   BoxShadow(
                     color: Colors.black.withOpacity(0.05), // Flat shadow
                     blurRadius: 20,
                     offset: const Offset(0, 10),
                   )
                 ],
                 border: Border.all(color: Colors.white, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Header Area
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _buildLevelBadge(level),
                            const SizedBox(width: 8),
                            Text(character?.name ?? '나의 캐릭터', style: GoogleFonts.jua(fontSize: 22, color: AppColors.textMain)),
                          ],
                        ),
                        if (charProvider.unusedStatPoints > 0)
                          ElevatedButton(
                            onPressed: () => _showStatDialog(context, charProvider),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              minimumSize: const Size(80, 40),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: Text("포인트 분배", style: GoogleFonts.jua(color: Colors.white, fontSize: 13)),
                          )
                        else
                          Text("Next Lv. ${level + 1}", style: GoogleFonts.jua(color: AppColors.textSub, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildExpBar(currentExp, maxExp, expPercent),
                    
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    
                    // Radar & Bars
                    Expanded(
                      child: Row(
                        children: [
                           Expanded(
                             flex: 4,
                             child: AspectRatio(
                               aspectRatio: 1,
                               child: StatRadarChart(stats: statsMap, showLabels: false),
                             ),
                           ),
                           const SizedBox(width: 16),
                           Expanded(
                             flex: 5,
                             child: SingleChildScrollView(
                               child: Column(
                                  children: [
                                    _buildStatTile("근력", statsMap['strength']!, AppColors.danger),
                                    _buildStatTile("지능", statsMap['intelligence']!, AppColors.info),
                                    _buildStatTile("민첩", statsMap['agility']!, AppColors.success),
                                    _buildStatTile("방어", statsMap['defense']!, AppColors.warning),
                                    _buildStatTile("운", statsMap['luck']!, AppColors.accent),
                                  ],
                               ),
                             ),
                           ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterDisplay(dynamic character) {
    String? imageUrl = character?.frontUrl;
    
    // Create the circular frame wrapper
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white,
          width: 8,
        ),
      ),
      child: ClipOval(
        child: _getImageWidget(imageUrl, character),
      ),
    );
  }

  Widget _getImageWidget(String? imageUrl, dynamic character) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      if (imageUrl.startsWith('/')) {
        imageUrl = "${AppConfig.serverBaseUrl}$imageUrl";
      } else if (imageUrl.contains('localhost')) {
        imageUrl = imageUrl.replaceFirst('localhost', AppConfig.serverIp);
      }
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => CuteAvatar(
          petType: character?.petType ?? "dog",
          size: 280,
        ),
      );
    } else {
      return CuteAvatar(
        petType: character?.petType ?? "dog",
        size: 280,
      );
    }
  }

  Widget _buildCircleButton({required IconData icon, required VoidCallback onPressed, required String label, Color color = Colors.white}) {
     return Column(
        children: [
           GestureDetector(
             onTap: onPressed,
             child: Container(
               width: 50, height: 50,
               decoration: BoxDecoration(
                 color: color,
                 shape: BoxShape.circle,
                 boxShadow: [
                   BoxShadow(
                     color: Colors.black.withOpacity(0.08),
                     blurRadius: 8,
                     offset: const Offset(0, 4),
                   )
                 ],
                 border: Border.all(color: color == Colors.white ? AppColors.border : Colors.white.withOpacity(0.5), width: 1.5),
               ),
               child: Center(child: FaIcon(icon, color: color == Colors.white ? AppColors.primary : Colors.white, size: 20)),
             ),
           ),
           const SizedBox(height: 4),
           Text(label, style: GoogleFonts.jua(fontSize: 10, color: AppColors.textMain)),
        ],
     );
  }

  Widget _buildLevelBadge(int level) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
      child: Text("Lv.$level", style: GoogleFonts.jua(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatTile(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.jua(fontSize: 11, color: AppColors.textMain)),
              Text(value.toString(), style: GoogleFonts.jua(fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100,
              backgroundColor: Colors.brown.withOpacity(0.05),
              color: color.withOpacity(0.7),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           _buildHeaderIconButton(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
           Text("MY ROOM", style: GoogleFonts.jua(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textMain)),
           _buildHeaderIconButton(Icons.settings_rounded, () => _showSettingsSheet(context)),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton(IconData icon, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, color: AppColors.textMain, size: 20),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.8),
        padding: const EdgeInsets.all(12),
        shape: const CircleBorder(),
      ),
    );
  }

  Widget _buildExpBar(int currentExp, int maxExp, double percent) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("EXPERIENCE", style: GoogleFonts.jua(color: AppColors.textSub, fontSize: 10)),
            Text("$currentExp / $maxExp", style: GoogleFonts.jua(color: AppColors.textMain, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 8,
          decoration: BoxDecoration(color: Colors.brown.withOpacity(0.05), borderRadius: BorderRadius.circular(4)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: percent, backgroundColor: Colors.transparent, color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}