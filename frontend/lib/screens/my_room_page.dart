import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../models/character_model.dart';
import '../providers/char_provider.dart';
import '../widgets/stat_distribution_dialog.dart';

// Note: This version is a complete rewrite focusing on stability with standard widgets and inline styles.
class MyRoomPage extends StatefulWidget {
  const MyRoomPage({super.key});

  @override
  State<MyRoomPage> createState() => _MyRoomPageState();
}

class _MyRoomPageState extends State<MyRoomPage> {
  // Business logic methods are preserved
  void _onCharacterTap(CharProvider provider) {
    List<String> messages = [
      "오늘 운동은 언제 하시나요?", "간식이 먹고 싶어요! 멍!", "쓰담쓰담 해주세요~", "같이 놀아요!", "근육이 불끈불끈!"
    ];
    String randomMsg = (messages..shuffle()).first;
    provider.updateStatusMessage(randomMsg);
  }

  void _showStatDialog(
      BuildContext context, CharProvider provider, Map<String, int> currentStats) {
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

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CharProvider>(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF5D4037)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Background Pattern
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/login_bg.png'),
                fit: BoxFit.cover,
                opacity: 0.4,
              ),
            ),
          ),
          // Main Scrollable Content
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  _buildHeader(),
                  const SizedBox(height: 30),
                  _buildCharacterArea(provider),
                  const SizedBox(height: 30),
                  _buildStatsCard(context, provider),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF5D4037), width: 3),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Text("MY ROOM", style: GoogleFonts.jua(fontSize: 28, color: const Color(0xFF5D4037), fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCharacterArea(CharProvider provider) {
    ImageProvider imageProvider;
    dynamic characterImage = provider.tempFrontImage ?? (provider.character?.frontUrl != null && provider.character!.frontUrl!.isNotEmpty ? provider.character!.frontUrl! : null);

    if (characterImage is XFile) {
      imageProvider = kIsWeb ? NetworkImage(characterImage.path) : FileImage(File(characterImage.path)) as ImageProvider;
    } else if (characterImage is String) {
      imageProvider = NetworkImage(characterImage);
    } else {
      imageProvider = const AssetImage('assets/images/단팥 기본.png');
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))]),
          child: Text(
            provider.statusMessage.isNotEmpty ? provider.statusMessage : "대기 중...",
            style: GoogleFonts.jua(color: const Color(0xFF5D4037), fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => _onCharacterTap(provider),
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF5D4037),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
            ),
            child: CircleAvatar(
              radius: 95,
              backgroundColor: Colors.white,
              child: CircleAvatar(
                radius: 88,
                backgroundImage: imageProvider,
                onBackgroundImageError: (_, __) {},
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                      image: imageProvider,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatsCard(BuildContext context, CharProvider provider) {
    final stat = provider.character?.stat;
    if (stat == null) return const Center(child: CircularProgressIndicator());

    final statsMap = {"strength": stat.strength, "intelligence": stat.intelligence, "agility": stat.agility, "defense": stat.defense, "luck": stat.luck};

    return Card(
      elevation: 8.0,
      shadowColor: Colors.black.withOpacity(0.2),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _buildStatsCardHeader(context, provider, stat, statsMap),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(flex: 3, child: _StyledRadarChart(stats: statsMap)),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: _buildStatBars(stat)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCardHeader(BuildContext context, CharProvider provider, Stat stat, Map<String, int> statsMap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text("Lv.${stat.level} ${provider.character?.name ?? ''}",
            style: GoogleFonts.jua(color: const Color(0xFF5D4037), fontSize: 24, fontWeight: FontWeight.bold)),
        if (provider.unusedStatPoints > 0)
          ElevatedButton(
            onPressed: () => _showStatDialog(context, provider, statsMap),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5D4037),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text("${provider.unusedStatPoints}P 성장",
                style: GoogleFonts.jua(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
  
  Widget _buildStatBars(Stat stat) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _StatBar(label: "STR", value: stat.strength, color: const Color(0xFFFF8A80)),
        _StatBar(label: "INT", value: stat.intelligence, color: const Color(0xFF82B1FF)),
        _StatBar(label: "DEX", value: stat.agility, color: const Color(0xFFB9F6CA)),
        _StatBar(label: "HAP", value: stat.happiness, color: const Color(0xFFD7CCC8)),
      ],
    );
  }
}

// --- Inlined Helper Widgets ---

class _StyledRadarChart extends StatelessWidget {
  final Map<String, int> stats;
  const _StyledRadarChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final keys = ['strength', 'intelligence', 'luck', 'defense', 'agility'];
    final labels = ['STR', 'INT', 'LUK', 'DEF', 'DEX'];
    List<RadarEntry> entries = keys.map((k) => RadarEntry(value: (stats[k] ?? 0).toDouble())).toList();

    return RadarChart(
      RadarChartData(
        dataSets: [
          RadarDataSet(
            fillColor: const Color(0xFF8D6E63).withOpacity(0.2),
            borderColor: const Color(0xFF5D4037),
            entryRadius: 2.5,
            dataEntries: entries,
            borderWidth: 2,
          ),
        ],
        radarBackgroundColor: Colors.transparent,
        borderData: FlBorderData(show: false),
        radarBorderData: const BorderSide(color: Colors.transparent),
        titlePositionPercentageOffset: 0.2,
        titleTextStyle: GoogleFonts.jua(color: const Color(0xFF5D4037), fontSize: 16, fontWeight: FontWeight.bold),
        getTitle: (index, angle) => RadarChartTitle(text: labels[index]),
        tickCount: 4,
        ticksTextStyle: const TextStyle(color: Colors.transparent),
        gridBorderData: BorderSide(color: Colors.grey.withOpacity(0.4), width: 1),
        tickBorderData: const BorderSide(color: Colors.transparent),
      ),
    );
  }
}

class _StatBar extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 45, child: Text(label, style: GoogleFonts.jua(color: color, fontSize: 16, fontWeight: FontWeight.bold))),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), color: Colors.black.withOpacity(0.08)),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double percentage = (value / 100).clamp(0.0, 1.0);
                return Row(
                  children: [
                    Container(
                      width: constraints.maxWidth * percentage,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), color: color),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text("$value", style: GoogleFonts.jua(fontSize: 14, color: const Color(0xFF8D6E63), fontWeight: FontWeight.bold)),
      ],
    );
  }
}