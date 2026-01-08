import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/char_provider.dart';
import '../game/game_assets.dart';

class SkillManagementScreen extends StatelessWidget {
  const SkillManagementScreen({super.key});

  // --- [핵심] 상세 설명 및 장착 버튼이 포함된 팝업 ---
  void _showSkillDetail(BuildContext context, int skillId, bool isLearned) {
    final charProvider = Provider.of<CharProvider>(context, listen: false);
    final char = charProvider.currentCharacter!;
    final info = GameAssets.MOVE_DATA[skillId] ?? {};
    final type = info['type'] ?? 'normal';
    final bool isEquipped = char.equippedSkills.contains(skillId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 내용에 따라 높이 조절
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        return StatefulBuilder( // 팝업 내 버튼 상태 변경을 위해 사용
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 상단 바 (Handle)
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: _getTypeColor(type).withOpacity(0.1),
                          child: Icon(_getTypeIcon(type), color: _getTypeColor(type), size: 30),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(info['name'] ?? '알 수 없음', 
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                              Text(type.toString().toUpperCase(), 
                                style: TextStyle(color: _getTypeColor(type), fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                        ),
                        if (!isLearned)
                          _buildInfoChip("해금 조건", "Lv.$skillId", Colors.orange)
                        else if (isEquipped)
                          _buildInfoChip("장착 중", "ACTIVE", Colors.blue),
                      ],
                    ),
                    const SizedBox(height: 25),
                    const Text("기술 설명", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      info['description'] ?? '설명이 등록되지 않은 기술입니다.',
                      style: const TextStyle(fontSize: 17, height: 1.5, color: Colors.black87),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatBox("위력", "${info['power']}"),
                        _buildStatBox("명중", "${info['accuracy']}%"),
                        _buildStatBox("최대 PP", "${info['max_pp']}"),
                      ],
                    ),
                    const SizedBox(height: 35),
                    // 장착/해제 버튼
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !isLearned ? Colors.grey : (isEquipped ? Colors.redAccent : Colors.blueAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        onPressed: !isLearned ? null : () async {
                          await charProvider.toggleSkillEquip(skillId);
                          Navigator.pop(context); // 작업 후 닫기
                        },
                        child: Text(
                          !isLearned ? "미해금 기술 (Lv.$skillId 필요)" : (isEquipped ? "장착 해제" : "기술 장착하기"),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  // --- [Helper] 보조 위젯들 ---
  Widget _buildStatBox(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text("$label $value", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final charProvider = Provider.of<CharProvider>(context);
    final char = charProvider.currentCharacter;
    if (char == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final allSkills = [5, 10, 15, 25, 30, 45, 50, 65, 75, 90, 100];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("기술 관리", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0, centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          _buildEquippedSlots(char.equippedSkills),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: Colors.blueGrey),
                SizedBox(width: 8),
                Text("나의 기술 도감", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.9,
              ),
              itemCount: allSkills.length,
              itemBuilder: (context, index) {
                int skillId = allSkills[index];
                bool isLearned = char.learnedSkills.contains(skillId);
                bool isEquipped = char.equippedSkills.contains(skillId);
                return _buildSkillCard(context, skillId, isLearned, isEquipped);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquippedSlots(List<int> equippedIds) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15)],
      ),
      child: Column(
        children: [
          const Text("현재 장착 중인 기술", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(4, (index) {
              bool hasSkill = index < equippedIds.length;
              int? sId = hasSkill ? equippedIds[index] : null;
              return Container(
                width: 65, height: 65,
                decoration: BoxDecoration(
                  color: hasSkill ? Colors.blue[50] : Colors.grey[50],
                  border: Border.all(color: hasSkill ? Colors.blue : Colors.grey[200]!, width: 2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: hasSkill 
                    ? Text("$sId", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.blue))
                    : const Icon(Icons.add, color: Colors.grey),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillCard(BuildContext context, int skillId, bool isLearned, bool isEquipped) {
    final info = GameAssets.MOVE_DATA[skillId] ?? {};
    final type = info['type'] ?? 'normal';
    final name = isLearned ? (info['name'] ?? "???") : "잠겨있음";

    return GestureDetector(
      onTap: () => _showSkillDetail(context, skillId, isLearned), // [변경] 이제 짧게 눌러도 설명창이 뜸
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: !isLearned ? Colors.grey[100] : (isEquipped ? Colors.blue[50] : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isEquipped ? Colors.blue : Colors.transparent, width: 2.5),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_getTypeIcon(type), color: isLearned ? _getTypeColor(type) : Colors.grey[400], size: 32),
                const SizedBox(height: 10),
                Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (!isLearned) Text("Lv.$skillId 필요", style: const TextStyle(fontSize: 11, color: Colors.orange)),
              ],
            ),
            if (isEquipped) const Positioned(top: 0, right: 0, child: Icon(Icons.check_circle, color: Colors.blue, size: 22)),
            if (!isLearned) const Center(child: Icon(Icons.lock_outline, color: Colors.black12, size: 40)),
          ],
        ),
      ),
    );
  }

  // --- [Helper] 타입 색상 및 아이콘 ---
  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'fire': return Colors.orange;
      case 'water': return Colors.blue;
      case 'wind': return Colors.green;
      case 'heal': return Colors.pinkAccent;
      case 'psychic': return Colors.purple;
      case 'fighting': return Colors.redAccent;
      case 'dark': return Colors.indigo;
      case 'dragon': return Colors.amber[800]!;
      default: return Colors.blueGrey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'fire': return Icons.local_fire_department;
      case 'water': return Icons.water_drop;
      case 'wind': return Icons.air;
      case 'heal': return Icons.favorite;
      case 'psychic': return Icons.remove_red_eye;
      case 'fighting': return Icons.fitness_center;
      case 'dark': return Icons.brightness_3;
      case 'dragon': return Icons.auto_awesome;
      default: return Icons.bolt;
    }
  }
}