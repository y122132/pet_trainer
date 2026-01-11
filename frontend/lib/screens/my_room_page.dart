// frontend/lib/screens/my_room_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../providers/char_provider.dart';
import '../providers/chat_provider.dart';
import '../services/auth_service.dart';

import '../widgets/common/stat_widgets.dart';
import '../widgets/char_message_bubble.dart';
import '../widgets/stat_distribution_dialog.dart';
import '../api_config.dart';
import '../config/theme.dart'; // AppColors를 위해 유지

class MyRoomPage extends StatefulWidget {
  const MyRoomPage({super.key});

  @override
  State<MyRoomPage> createState() => _MyRoomPageState();
}

class _MyRoomPageState extends State<MyRoomPage> with SingleTickerProviderStateMixin {
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;
  bool _showBubble = false;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000));
    _breathingAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );
    _breathingController.repeat(reverse: true);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showBubble = true);
    });
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  void _onCharacterTap(CharProvider provider) {
    List<String> messages = [
      "오늘 운동은 언제 하시나요?",
      "간식이 먹고 싶어요! 멍!",
      "쓰담쓰담 해주세요~",
      "같이 놀아요!",
      "근육이 불끈불끈!"
    ];
    String randomMsg = (messages..shuffle()).first;
    provider.updateStatusMessage(randomMsg);
    setState(() => _showBubble = true);
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Text("설정", style: GoogleFonts.jua(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF4E342E))),
                const SizedBox(height: 10),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: Text("로그아웃", style: GoogleFonts.jua(color: Colors.redAccent, fontSize: 18)),
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
      ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("로그아웃 되었습니다."))
      );
    }
  }



  void _showStatDialog(BuildContext context, CharProvider provider, Map<String, int> currentStats) {
      showDialog(
        context: context,
        builder: (context) => StatDistributionDialog(
          availablePoints: provider.unusedStatPoints,
          currentStats: currentStats,
          title: "스탯 분배",
          confirmLabel: "적용",
          skipLabel: "취소",
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

  @override
  Widget build(BuildContext context) {
    final charProvider = Provider.of<CharProvider>(context);
    final character = charProvider.character;
    final stat = character?.stat;

    final statsMap = (stat != null)
        ? {
            "strength": stat.strength, "intelligence": stat.intelligence,
            "agility": stat.agility, "defense": stat.defense, "luck": stat.luck,
          }
        : {"strength": 0, "intelligence": 0, "agility": 0, "defense": 0, "luck": 0};
    
    Widget imageWidget;
    if (charProvider.tempFrontImage != null) {
      if (kIsWeb) {
        imageWidget = Image.network(charProvider.tempFrontImage!.path, fit: BoxFit.cover);
      } else {
        imageWidget = Image.file(File(charProvider.tempFrontImage!.path), fit: BoxFit.cover);
      }
    } else if (character?.frontUrl != null && character!.frontUrl!.isNotEmpty) {
      String imageUrl = character.frontUrl!;
      if (imageUrl.startsWith('/')) {
        imageUrl = "${AppConfig.serverBaseUrl}$imageUrl";
      } else if (imageUrl.contains('localhost')) {
        imageUrl = imageUrl.replaceFirst('localhost', AppConfig.serverIp);
      }
      imageWidget = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.pets, color: Colors.grey, size: 80),
      );
    } else {
      imageWidget = const Icon(Icons.pets, color: Colors.grey, size: 80);
    }

    Widget statBar(String label, int value, Color color, {int maxValue = 100}) {
      double percentage = (maxValue > 0) ? value / maxValue : 0.0;
      if (percentage < 0) percentage = 0;
      if (percentage > 1.0) percentage = 1.0;
      
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.jua(fontSize: 14, color: const Color(0xFF4E342E)),
            ),
            const SizedBox(height: 4),
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: percentage,
                    child: Container(color: color),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // [Restore battle_rolling Logic] Calculate maxExp based on level
    final int maxExp = (stat?.level ?? 1) * 100;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E6),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // 1. Header Title with Back and Settings buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                     IconButton(
                       icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF4E342E), size: 24),
                       onPressed: () => Navigator.of(context).pop(),
                     ),
                     Container(
                       padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
                       decoration: BoxDecoration(
                         color: Colors.white,
                         borderRadius: BorderRadius.circular(40),
                         border: Border.all(color: const Color(0xFF5D4037), width: 2.0),
                         boxShadow: [
                           BoxShadow(
                             color: Colors.brown.withOpacity(0.2),
                             spreadRadius: 2,
                             blurRadius: 5,
                             offset: const Offset(0, 3),
                           )
                         ],
                       ),
                       child: Text(
                         "MY ROOM",
                         style: GoogleFonts.jua(fontSize: 20, color: const Color(0xFF4E342E), fontWeight: FontWeight.bold),
                       ),
                     ),
                     IconButton(
                       icon: const Icon(Icons.settings, color: Color(0xFF4E342E), size: 28),
                       onPressed: () => _showSettingsSheet(context),
                     ),
                  ],
                ),
                const SizedBox(height: 20),

                // Character Message
                Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  alignment: Alignment.center,
                  child: _showBubble
                      ? ChatBubble(message: charProvider.statusMessage.isNotEmpty ? charProvider.statusMessage : "...", isAnalyzing: false)
                      : const SizedBox(height: 60),
                ),
                const SizedBox(height: 20),
                
                // 2. Character Frame
                GestureDetector(
                  onTap: () => _onCharacterTap(charProvider),
                  child: AnimatedBuilder(
                    animation: _breathingAnimation,
                    builder: (context, child) => Transform.scale(scale: _breathingAnimation.value, child: child),
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.6,
                      height: MediaQuery.of(context).size.width * 0.6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFF5D4037), width: 10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.brown.withOpacity(0.3),
                            spreadRadius: 5,
                            blurRadius: 10,
                          )
                        ],
                      ),
                      child: ClipOval(child: imageWidget),
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // 3. Stats Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.brown.withOpacity(0.2),
                        spreadRadius: 3,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Card Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              "Lv.${stat?.level ?? 1} ${character?.name ?? '캐릭터'}",
                              style: GoogleFonts.jua(fontSize: 24, color: const Color(0xFF4E342E), fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.upgrade, color: Color(0xFFE91E63)),
                                tooltip: "레벨업 (테스트)",
                                onPressed: () async {
                                   await charProvider.manualLevelUp();
                                   if (context.mounted) {
                                     ScaffoldMessenger.of(context).showSnackBar(
                                       const SnackBar(content: Text("레벨업되었습니다!"))
                                     );
                                   }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.grey),
                                tooltip: "스탯 초기화",
                                onPressed: () {
                                   showDialog(
                                     context: context,
                                     builder: (context) => AlertDialog(
                                       title: const Text("스탯 초기화"),
                                       content: const Text("모든 스탯을 초기화하고 포인트를 되돌려받으시겠습니까?\n(기본 스탯 제외)"),
                                       actions: [
                                         TextButton(
                                           onPressed: () => Navigator.pop(context),
                                           child: const Text("취소"),
                                         ),
                                         TextButton(
                                           onPressed: () {
                                             charProvider.resetStats();
                                             Navigator.pop(context);
                                             if (context.mounted) {
                                               ScaffoldMessenger.of(context).showSnackBar(
                                                 const SnackBar(content: Text("스탯이 초기화되었습니다."))
                                               );
                                             }
                                           },
                                           child: const Text("초기화", style: TextStyle(color: Colors.red)),
                                         ),
                                       ],
                                     )
                                   );
                                },
                              ),
                              if (charProvider.unusedStatPoints > 0)
                                ElevatedButton(
                                  onPressed: () => _showStatDialog(context, charProvider, statsMap),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF5D4037),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  child: Text(
                                    "${charProvider.unusedStatPoints}P 성장",
                                    style: GoogleFonts.jua(color: Colors.white, fontSize: 14),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: (stat?.exp ?? 0) / maxExp,
                              backgroundColor: Colors.brown[100],
                              color: Colors.brown[400],
                              minHeight: 18,
                            ),
                          ),
                          Text(
                            "EXP ${stat?.exp ?? 0} / $maxExp",
                            style: GoogleFonts.jua(
                              color: Colors.white,
                              fontSize: 11, 
                              fontWeight: FontWeight.bold,
                              shadows: [
                                const Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 2.0,
                                  color: Color(0x80000000),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Card Body (Radar Chart and Stats)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left: Radar Chart (must be in Expanded)
                          Expanded(
                            flex: 5,
                            child: AspectRatio(
                              aspectRatio: 1.0,
                              child: StatRadarChart(stats: statsMap, showLabels: true),
                            ),
                          ),
                          const SizedBox(width: 20),

                          // Right: Stats List (must be in Expanded)
                          Expanded(
                            flex: 5,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                statBar("STR", stat?.strength ?? 0, Colors.red.shade400),
                                statBar("INT", stat?.intelligence ?? 0, Colors.blue.shade400),
                                statBar("DEX", stat?.agility ?? 0, Colors.green.shade400),
                                statBar("DEF", stat?.defense ?? 0, Colors.brown.shade400),
                                statBar("LUK", stat?.luck ?? 0, Colors.amber.shade400),
                                const Divider(height: 10, color: Colors.transparent),
                                statBar("HP", stat?.health ?? 0, Colors.pink.shade300, maxValue: 100), // ERROR FIXED
                              ],
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
        ),
      ),
    );
  }
}