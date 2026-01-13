import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/char_provider.dart';
import '../game/game_assets.dart';

class SkillManagementScreen extends StatelessWidget {
  const SkillManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final charProvider = Provider.of<CharProvider>(context);
    final char = charProvider.currentCharacter;
    if (char == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Filter skills by pet type
    final allSkills = GameAssets.MOVE_DATA.entries
        .where((entry) {
          final skillPetType = entry.value['pet_type'] ?? 'shared';
          return skillPetType == 'shared' || skillPetType == char.petType;
        })
        .map((entry) => entry.key)
        .toList()
        ..sort();

    const Color bgColor = Color(0xFFFFF9E6);
    const Color primaryText = Color(0xFF4E342E);
    const Color secondaryText = Color(0xFF5D4037);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text("SKILL BOOK", 
          style: GoogleFonts.jua(color: primaryText, fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: primaryText),
      ),
      body: Column(
        children: [
          // 1. ACTIVE LOADOUT (전투 장착 영역)
          _buildActiveLoadout(context, char.equippedSkills),

          // 2. 도감 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("SKILL LIBRARY", 
                  style: GoogleFonts.jua(color: secondaryText, fontSize: 16)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: secondaryText.withOpacity(0.3)),
                  ),
                  child: Text("${char.learnedSkills.length} / ${allSkills.length} UNLOCKED", 
                    style: GoogleFonts.jua(color: Colors.blueAccent, fontSize: 12)),
                ),
              ],
            ),
          ),

          // 3. 도감 리스트 (그리드)
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
              ),
              child: GridView.builder(
                padding: const EdgeInsets.all(24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85,
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
    const Color secondaryText = Color(0xFF5D4037);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
                  color: hasSkill ? Colors.white : Colors.brown.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: hasSkill ? _getTypeColor(info?['type']) : secondaryText.withOpacity(0.1),
                    width: 3,
                  ),
                  boxShadow: hasSkill ? [
                    BoxShadow(color: _getTypeColor(info?['type']).withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))
                  ] : [],
                ),
                child: Center(
                  child: hasSkill 
                    ? Icon(_getTypeIcon(info?['type']), color: _getTypeColor(info?['type']), size: 36)
                    : Icon(Icons.pets, color: secondaryText.withOpacity(0.1), size: 30),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 75,
                child: Text(hasSkill ? "${info?['name']}" : "EMPTY",
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jua(fontSize: 12, color: hasSkill ? secondaryText : secondaryText.withOpacity(0.3))),
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
    const Color primaryText = Color(0xFF4E342E);
    const Color secondaryText = Color(0xFF5D4037);

    return GestureDetector(
      onTap: () {
        if (isLearned) {
          charProvider.toggleSkillEquip(skillId);
        } else {
          _showSkillInfoSheet(context, skillId, isLearned);
        }
      },
      onLongPress: () => _showSkillInfoSheet(context, skillId, isLearned),

      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isEquipped ? Colors.orangeAccent : Colors.brown.withOpacity(0.1),
            width: isEquipped ? 3 : 1.5,
          ),
          boxShadow: [
            BoxShadow(color: Colors.brown.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _getTypeColor(type).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_getTypeIcon(type), 
                      color: isLearned ? _getTypeColor(type) : Colors.brown.withOpacity(0.15), size: 32),
                    ),
                    const SizedBox(height: 12),
                    Text(isLearned ? "${info['name']}" : "Locked", 
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jua(color: isLearned ? primaryText : primaryText.withOpacity(0.3), fontSize: 16)),
                    const SizedBox(height: 4),
                    
                    if (isLearned)
                      Text(isEquipped ? "EQUIPPED" : "LEARNED", 
                        style: GoogleFonts.jua(
                          color: isEquipped ? Colors.orangeAccent : Colors.blueGrey.withOpacity(0.5), 
                          fontSize: 10)),
                    
                    if (!isLearned)
                      Text("Lv.${info['unlock_level'] ?? skillId}", 
                        style: GoogleFonts.jua(color: Colors.orangeAccent, fontSize: 12)),
                  ],
                ),
              ),
              if (isEquipped)
                const Positioned(
                  top: 10, right: 10, 
                  child: Icon(Icons.check_circle, color: Colors.orangeAccent, size: 24)
                  ),
              Positioned(
                bottom: 4, right: 4,
                child: IconButton(
                  icon: Icon(Icons.info_outline, color: secondaryText.withOpacity(0.2), size: 18),
                  onPressed: () => _showSkillInfoSheet(context, skillId, isLearned),
                ),
              ),  
              if (!isLearned)
                Center(child: Icon(Icons.lock, color: secondaryText.withOpacity(0.05), size: 50)),
            ],
          ),
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
    const Color primaryText = Color(0xFF4E342E);
    const Color secondaryText = Color(0xFF5D4037);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _getTypeColor(type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Icon(_getTypeIcon(type), color: _getTypeColor(type), size: 48),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isLearned ? "${info['name']}" : "Locked Skill", 
                          style: GoogleFonts.jua(color: primaryText, fontSize: 32)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getTypeColor(type).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(type.toString().toUpperCase(), 
                            style: GoogleFonts.jua(color: _getTypeColor(type), fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Text("설명", style: GoogleFonts.jua(color: secondaryText.withOpacity(0.5), fontSize: 14)),
              const SizedBox(height: 8),
              Text(isLearned ? "${info['description']}" : "레벨 ${info['unlock_level'] ?? skillId} 달성 시 기술의 진실이 밝혀집니다.", 
                style: GoogleFonts.jua(color: primaryText, fontSize: 18, height: 1.5)),
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
                height: 65,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !isLearned ? Colors.grey[200] : secondaryText,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    elevation: 0,
                  ),
                  onPressed: !isLearned ? null : () {
                    charProvider.toggleSkillEquip(skillId);
                    Navigator.pop(context);
                  },
                  child: Text(
                    !isLearned ? "LOCKED (LV.${info['unlock_level'] ?? skillId})" : (isEquipped ? "EQUIPMENT REMOVE" : "EQUIP TO SLOT"),
                    style: GoogleFonts.jua(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
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
    const Color primaryText = Color(0xFF4E342E);
    const Color secondaryText = Color(0xFF5D4037);
    return Column(
      children: [
        Text(label, style: GoogleFonts.jua(color: secondaryText.withOpacity(0.4), fontSize: 12)),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.jua(color: primaryText, fontSize: 24)),
      ],
    );
  }

  // --- [Helper] 타입 정의 ---
  Color _getTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'fire': return Colors.orangeAccent;
      case 'water': return Colors.lightBlueAccent;
      case 'wind':
      case 'flying': return Colors.lightBlueAccent;
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
      case 'wind':
      case 'flying': return Icons.air_rounded;
      case 'heal': return Icons.favorite_rounded;
      case 'psychic': return Icons.auto_fix_high_rounded;
      case 'fighting': return Icons.fitness_center_rounded;
      case 'dark': return Icons.dark_mode_rounded;
      case 'dragon': return Icons.workspace_premium_rounded;
      default: return Icons.bolt_rounded;
    }
  }
}