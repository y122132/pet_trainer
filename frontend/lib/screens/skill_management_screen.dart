import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/char_provider.dart';
import '../game/game_assets.dart';

class SkillManagementScreen extends StatelessWidget {
  const SkillManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final charProvider = Provider.of<CharProvider>(context);
    final char = charProvider.currentCharacter;
    if (char == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final allSkills = GameAssets.MOVE_DATA.keys.toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFF1A1C20), // 딥 다크 배경 (게임 느낌)
      appBar: AppBar(
        title: const Text("SKILL BOOK", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // 1. ACTIVE LOADOUT (전투 장착 영역)
          _buildActiveLoadout(context, char.equippedSkills),

          // 2. 도감 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("SKILL LIBRARY", 
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
                Text("${char.learnedSkills.length} / ${allSkills.length} UNLOCKED", 
                  style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),

          // 3. 도감 리스트 (그리드)
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF25282F),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.82,
                ),
                itemCount: allSkills.length,
                itemBuilder: (context, index) {
                  int skillId = allSkills[index];
                  bool isLearned = char.learnedSkills.contains(skillId);
                  bool isEquipped = char.equippedSkills.contains(skillId);
                  return _buildEncyclopediaCard(context, skillId, isLearned, isEquipped);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- [상단] 전투 장착 슬롯 (Deck) ---
  Widget _buildActiveLoadout(BuildContext context, List<int> equippedIds) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(4, (index) {
          bool hasSkill = index < equippedIds.length;
          final skillId = hasSkill ? equippedIds[index] : null;
          final info = skillId != null ? GameAssets.MOVE_DATA[skillId] : null;

          return Column(
            children: [
              Container(
                width: 75, height: 75,
                decoration: BoxDecoration(
                  color: hasSkill ? _getTypeColor(info?['type']).withOpacity(0.2) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hasSkill ? _getTypeColor(info?['type']) : Colors.white12,
                    width: 2,
                  ),
                  boxShadow: hasSkill ? [
                    BoxShadow(color: _getTypeColor(info?['type']).withOpacity(0.3), blurRadius: 12)
                  ] : [],
                ),
                child: Center(
                  child: hasSkill 
                    ? Icon(_getTypeIcon(info?['type']), color: _getTypeColor(info?['type']), size: 32)
                    : const Icon(Icons.add, color: Colors.white24),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 75,
                child: Text(hasSkill ? "${info?['name']}" : "EMPTY",
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: hasSkill ? Colors.white : Colors.white24, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }),
      ),
    );
  }

  // --- [하단] 도감 카드 디자인 ---
  Widget _buildEncyclopediaCard(BuildContext context, int skillId, bool isLearned, bool isEquipped) {
    final charProvider = Provider.of<CharProvider>(context, listen: false);
    final info = GameAssets.MOVE_DATA[skillId] ?? {};
    final type = info['type'] ?? 'normal';

    return GestureDetector(
      onTap: () {
        if (isLearned) {
          charProvider.toggleSkillEquip(skillId);
        } else {
          _showSkillInfoSheet(context, skillId, isLearned);
        }
      },
      onLongPress: () => _showSkillInfoSheet(context, skillId, isLearned),

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: const Color(0xFF2F333C),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isEquipped ? Colors.blueAccent : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isEquipped ? [
            BoxShadow(color: Colors.blueAccent.withOpacity(0.2), blurRadius: 8, spreadRadius: 1)
          ] : [],
        ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getTypeColor(type).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_getTypeIcon(type), 
                      color: isLearned ? _getTypeColor(type) : Colors.white10, size: 28),
                    ),
                    const SizedBox(height: 12),
                    Text(isLearned ? "${info['name']}" : "LOCKED", 
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, 
                      fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    // 미니 스탯 바
                    if (isLearned)
                      Text(isEquipped ? "REMOVE" : "EQUIP", 
                        style: TextStyle(
                          color: isEquipped ? Colors.redAccent : Colors.blueAccent, 
                          fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    
                    if (!isLearned)
                      Text("Lv.$skillId", style: const TextStyle(color: Colors.orangeAccent, fontSize: 10)),
                  ],
                ),
              ),
              if (isEquipped)
                const Positioned(
                  top: 12, right: 12, 
                  child: Icon(Icons.check_circle, color: Colors.blueAccent, size: 20)
                  ),
              Positioned(
                bottom: 8, right: 8,
                child: IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.white10, size: 18),
                  onPressed: () => _showSkillInfoSheet(context, skillId, isLearned),
                ),
              ),  
              if (!isLearned)
                const Center(child: Icon(Icons.lock_outline, color: Colors.white10, size: 40)),
            ],
          ),
      ),
    );
  }

  Widget _buildMiniStatRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("$label ", style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
          Text("${value ?? 0}", style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- [팝업] 스킬 상세 정보 카드 ---
  void _showSkillInfoSheet(BuildContext context, int skillId, bool isLearned) {
    final charProvider = Provider.of<CharProvider>(context, listen: false);
    final char = charProvider.currentCharacter!;
    final info = GameAssets.MOVE_DATA[skillId] ?? {};
    final type = info['type'] ?? 'normal';
    final bool isEquipped = char.equippedSkills.contains(skillId);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1C20),
            borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _getTypeColor(type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(_getTypeIcon(type), color: _getTypeColor(type), size: 40),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isLearned ? "${info['name']}" : "Locked Skill", 
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(type.toString().toUpperCase(), 
                          style: TextStyle(color: _getTypeColor(type), fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 2)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const Text("EFFECT DESCRIPTION", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(isLearned ? "${info['description']}" : "레벨 $skillId 달성 시 기술의 진실이 밝혀집니다.", 
                style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6)),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailStat("POWER", "${info['power']}"),
                  _buildDetailStat("ACCURACY", "${info['accuracy']}%"),
                  _buildDetailStat("MAX PP", "${info['max_pp']}"),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !isLearned ? Colors.white10 : (isEquipped ? Colors.redAccent : Colors.blueAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: !isLearned ? null : () {
                    charProvider.toggleSkillEquip(skillId);
                    Navigator.pop(context);
                  },
                  child: Text(
                    !isLearned ? "LOCKED (LV.$skillId)" : (isEquipped ? "REMOVE FROM SLOT" : "EQUIP TO SLOT"),
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
      ],
    );
  }

  // --- [Helper] 타입 정의 ---
  Color _getTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'fire': return Colors.orangeAccent;
      case 'water': return Colors.lightBlueAccent;
      case 'wind': return Colors.greenAccent;
      case 'heal': return Colors.pinkAccent;
      case 'psychic': return Colors.purpleAccent;
      case 'fighting': return Colors.redAccent;
      case 'dark': return Colors.deepPurpleAccent;
      case 'dragon': return Colors.amberAccent;
      default: return Colors.blueGrey;
    }
  }

  IconData _getTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'fire': return Icons.local_fire_department_rounded;
      case 'water': return Icons.water_drop_rounded;
      case 'wind': return Icons.cyclone_rounded;
      case 'heal': return Icons.favorite_rounded;
      case 'psychic': return Icons.auto_fix_high_rounded;
      case 'fighting': return Icons.fitness_center_rounded;
      case 'dark': return Icons.dark_mode_rounded;
      case 'dragon': return Icons.workspace_premium_rounded;
      default: return Icons.bolt_rounded;
    }
  }
}