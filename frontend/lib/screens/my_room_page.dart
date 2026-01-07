// frontend/lib/screens/my_room_page.dart
import 'login_screen.dart';
import 'camera_screen.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../models/character_model.dart';
import '../providers/char_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/common/stat_widgets.dart';
import '../widgets/char_message_bubble.dart'; 
import '../widgets/stat_distribution_dialog.dart'; // New from frontend_1
import 'package:pet_trainer_frontend/api_config.dart'; // [Fix] Import AppConfig

// Note: This version is a complete rewrite focusing on stability with standard widgets and inline styles.
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
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _breathingAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }
  // Business logic methods are preserved
  void _onCharacterTap(CharProvider provider) {
    List<String> messages = [
      "오늘 운동은 언제 하시나요?", "간식이 먹고 싶어요! 멍!", "쓰담쓰담 해주세요~", "같이 놀아요!", "근육이 불끈불끈!"
    ];
    String randomMsg = (messages..shuffle()).first;
    provider.updateStatusMessage(randomMsg);
    
    setState(() => _showBubble = true);
    
    // Auto-hide bubble after few seconds to simulate conversation flow
    // (Optional, currently keeping it visible until next tap or permanent)
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text("설정", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.softCharcoal)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text("로그아웃", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                onTap: () => _handleLogout(context),
              ),
              const SizedBox(height: 20),
            ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.softCharcoal),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "MY ROOM", 
          style: TextStyle(
            color: AppColors.softCharcoal, 
            fontWeight: FontWeight.w900, 
            fontSize: 22
            )),
        actions: [
          IconButton(
            onPressed: () => _showSettingsSheet(context),
            icon: const Icon(Icons.settings, color: AppColors.softCharcoal))
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                   Color(0xFFFFF0F5),
                   Color(0xFFE0F7FA),
                ],
              ),
            ),
          ),
          
          // 2. Content
          SafeArea(
            child: Consumer<CharProvider>(
              builder: (context, provider, child) {
                 Widget imageWidget;
                 // Prioritize temporary image if it exists
                 if (provider.tempFrontImage != null) {
                   if (kIsWeb) {
                     imageWidget = Image.network(
                       provider.tempFrontImage!.path,
                       fit: BoxFit.contain,
                       width: MediaQuery.of(context).size.width * 0.8,
                     );
                   } else {
                     imageWidget = Image.file(
                       File(provider.tempFrontImage!.path),
                       fit: BoxFit.contain,
                       width: MediaQuery.of(context).size.width * 0.8,
                     );
                   }
                 } else if (provider.character?.frontUrl != null && provider.character!.frontUrl!.isNotEmpty) {
                   // Fallback to the image from the server
                   String imageUrl = provider.character!.frontUrl!;
                   if (imageUrl.startsWith('/')) {
                       imageUrl = "${AppConfig.serverBaseUrl}$imageUrl";
                   } else if (imageUrl.contains('localhost')) {
                       imageUrl = imageUrl.replaceFirst('localhost', AppConfig.serverIp);
                   }
                   imageWidget = Image.network(
                     imageUrl,
                     fit: BoxFit.contain,
                     width: MediaQuery.of(context).size.width * 0.8,
                   );
                 } else {
                   // Fallback to the default asset
                   imageWidget = Image.asset(
                     'assets/images/characters/닌자옷.png',
                     fit: BoxFit.contain,
                     width: MediaQuery.of(context).size.width * 0.8,
                   );
                 }

                 return Column(
                   children: [
                     // Top Spacer
                     const SizedBox(height: 10),
                     
                     // Message Bubble Area
                     Container(
                       constraints: const BoxConstraints(minHeight: 80),
                       width: double.infinity,
                       alignment: Alignment.center,
                       child: _showBubble 
                           ? ChatBubble(
                               message: provider.statusMessage.isNotEmpty ? provider.statusMessage : "안녕하세요!", 
                               isAnalyzing: false 
                             )
                           : const SizedBox(height: 80),
                     ),

                     // Character Area (Expanded)
                     Expanded(
                       flex: 5,
                       child: GestureDetector(
                         onTap: () => _onCharacterTap(provider),
                         child: Center(
                            child: AnimatedBuilder(
                              animation: _breathingAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _breathingAnimation.value,
                                  child: child,
                                );
                              },
                              child: imageWidget,
                            ),
                         ),
                       ),
                     ),

                     // Stats Panel (Bottom Sheet Style)
                     Expanded(
                       flex: 5, // 50% height
                       child: _buildStatsPanel(context, provider),
                     ),
                   ],
                 );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsPanel(BuildContext context, CharProvider provider) {
    final stat = provider.character?.stat;
    if (stat == null) {
       return const Center(child: Text("Loading...", style: TextStyle(color: Colors.white)));
    }

    final int maxExp = stat.level * 100;
    final Map<String, int> statsMap = {
      "strength": stat.strength,
      "intelligence": stat.intelligence,
      "agility": stat.agility, 
      "defense": stat.defense,
      "luck": stat.luck,
    };
    
    // Glassmorphism Container (Light)
    return Container(
      margin: const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8), 
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        boxShadow: [
          BoxShadow(color: AppColors.secondaryPink.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -5))
        ],
        border: Border.all(color: Colors.white, width: 2)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Name & Level
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text("Lv.${stat.level}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.secondaryPink)),
                      const SizedBox(width: 8),
                      Text(provider.character?.name ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.softCharcoal)),
                    ],
                  ),
                  Text("EXP ${stat.exp} / $maxExp",
                    style: const TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold)),
                ],
              ),
              // Unused Points Button
              if (provider.unusedStatPoints > 0)
                ElevatedButton.icon(
                  onPressed: () => _showStatDialog(context, provider, statsMap),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                  label: Text("${provider.unusedStatPoints}P 성장"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentYellow, 
                      foregroundColor: AppColors.softCharcoal,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 2
                  ),
                ),
                
              // [New] Manual Level Up Button (Test)
              IconButton(
                icon: const Icon(Icons.upgrade, color: AppColors.secondaryPink),
                tooltip: "레벨업 (테스트)",
                onPressed: () async {
                   await provider.manualLevelUp();
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text("레벨업되었습니다!"))
                   );
                },
              ),
                
              // [New] Stat Reset Button
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
                             provider.resetStats();
                             Navigator.pop(context);
                             ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(content: Text("스탯이 초기화되었습니다."))
                             );
                           },
                           child: const Text("초기화", style: TextStyle(color: Colors.red)),
                         ),
                       ],
                     )
                   );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
             borderRadius: BorderRadius.circular(10),
             child: LinearProgressIndicator(
              value: (stat.exp / maxExp).clamp(0.0, 1.0),
              backgroundColor: Colors.grey[200], 
              color: AppColors.secondaryPink, minHeight: 10),
          ),
          const SizedBox(height: 24),

          // Content: Radar Chart vs Progress Bars via Tab or Split
          // Using Split View for now
          Expanded(
            child: Row(
               children: [
                  // Left: Radar Chart
                  Expanded(
                    flex: 4,
                    child: StatRadarChart(stats: statsMap, showLabels: false),
                  ),
                  const SizedBox(width: 20),
                  // Right: Stats List
                  Expanded(
                    flex: 6,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                           StatProgressBar(label: "STR", value: stat.strength),
                           StatProgressBar(label: "INT", value: stat.intelligence),
                           StatProgressBar(label: "DEX", value: stat.agility),
                           StatProgressBar(label: "DEF", value: stat.defense),
                           StatProgressBar(label: "LUK", value: stat.luck),
                           const Divider(height: 20),
                           StatProgressBar(label: "HP", value: stat.health, maxValue: 100), // HP
                        ],
                      ),
                    ),
                  )
               ],
            ),
          )
        ],
      ),
    );
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
    for (int i = 0; i < amount; i++) {
      provider.allocateStatSpecific(type);
    }
  }
}