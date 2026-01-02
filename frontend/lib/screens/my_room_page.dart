import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'camera_screen.dart';
import '../providers/char_provider.dart';
import '../widgets/stat_distribution_dialog.dart';
import '../widgets/common/stat_widgets.dart';
import '../widgets/char_message_bubble.dart'; // Import ChatBubble
import '../config/theme.dart'; // Import AppTheme

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
    
    // Auto-show bubble initially
    Future.delayed(const Duration(milliseconds: 500), () {
        if(mounted) setState(() => _showBubble = true);
    });
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  void _onCharacterTap(CharProvider provider) {
    // 1. Haptic feedback or sound could go here
    // 2. Change message
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
    
    // Auto-hide bubble after few seconds to simulate conversation flow
    // (Optional, currently keeping it visible until next tap or permanent)
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.softCharcoal),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("MY ROOM", style: TextStyle(color: AppColors.softCharcoal, fontWeight: FontWeight.w900, fontSize: 22)),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.settings, color: AppColors.softCharcoal))
        ],
      ),
      body: Stack(
        children: [
          // 1. Background (Gradient)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                   Color(0xFFFFF0F5), // Lavender Blush
                   Color(0xFFE0F7FA), // Cyan Mist
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
                   imageWidget = Image.network(
                     provider.character!.frontUrl!,
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

    final statsMap = {
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
        color: Colors.white.withOpacity(0.8), // Milk Glass
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
                  Text("EXP ${stat.exp}/100", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
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
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
             borderRadius: BorderRadius.circular(10),
             child: LinearProgressIndicator(value: stat.exp / 100, backgroundColor: Colors.grey[200], color: AppColors.secondaryPink, minHeight: 10),
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
    for (int i=0; i<amount; i++) {
      provider.allocateStatSpecific(type); 
    }
  }
}
