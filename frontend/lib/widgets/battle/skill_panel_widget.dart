import 'package:flutter/material.dart';
import 'package:pet_trainer_frontend/config/theme.dart';

class SkillPanelWidget extends StatelessWidget {
  final List<Map<String, dynamic>?> skills;
  final bool isMyTurn;
  final bool isConnected;
  final String statusMessage;
  final Function(int) onSkillSelected;

  const SkillPanelWidget({
    super.key,
    required this.skills,
    required this.isMyTurn,
    required this.isConnected,
    required this.statusMessage,
    required this.onSkillSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Ensure we display 4 slots layout even if list is short (though parent handles this usually)
    // Here we assume parent passes exactly 4 items (some null)
    List<Map<String, dynamic>?> displaySkills = skills;
    
    return Container(
      height: 300, 
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        boxShadow: [BoxShadow(color: AppColors.primaryMint.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("SKILLS", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.softCharcoal, letterSpacing: 1.0)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isMyTurn ? AppColors.success : AppColors.secondaryPink.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(statusMessage, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _buildSkillButton(context, displaySkills.length > 0 ? displaySkills[0] : null)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildSkillButton(context, displaySkills.length > 1 ? displaySkills[1] : null)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _buildSkillButton(context, displaySkills.length > 2 ? displaySkills[2] : null)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildSkillButton(context, displaySkills.length > 3 ? displaySkills[3] : null)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkillButton(BuildContext context, Map<String, dynamic>? skill) {
    // Empty Slot
    if (skill == null) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.neutral.withOpacity(0.3), 
          borderRadius: BorderRadius.circular(30), // Pebble shape
          border: Border.all(color: Colors.transparent, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.lock_outline_rounded, color: Colors.white, size: 32),
        ),
      );
    }

    int skillId = skill['id'];
    String name = skill['name'] ?? "Unknown";
    String type = skill['type'] ?? "normal";
    
    // [New] PP Logic
    int currentPp = skill['pp'] ?? 20;
    int maxPp = skill['max_pp'] ?? 20;
    
    Color typeColor = _getTypeColor(type);
    // Adjust logic: if connected and my turn, usable. Also check PP.
    bool canPress = isConnected && isMyTurn && currentPp > 0;

    return GestureDetector(
      onLongPress: () => _showSkillInfo(context, name, type, skill),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: canPress ? 1.0 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24), // Pebble
            color: Colors.white,
            boxShadow: [
              if (canPress) BoxShadow(color: typeColor.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))
            ],
            border: Border.all(color: canPress ? typeColor : Colors.grey.withOpacity(0.3), width: 3)
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canPress ? () => onSkillSelected(skillId) : null,
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  // Cute Type Icon in Background
                  Positioned(
                    right: -10, bottom: -10,
                    child: Icon(_getTypeIcon(type), size: 60, color: typeColor.withOpacity(0.1)),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                         Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.softCharcoal)),
                         
                         // Type Tag (Small Pill)
                         Container( 
                           margin: const EdgeInsets.symmetric(vertical: 4),
                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                           decoration: BoxDecoration(color: typeColor.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                           child: Text(type.toUpperCase(), style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
                         ),
                         
                         // PP
                         Text("PP $currentPp/$maxPp", 
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: currentPp > 0 ? Colors.grey : AppColors.danger)
                         )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'fire': return Icons.local_fire_department_rounded;
      case 'water': return Icons.water_drop_rounded;
      case 'grass': return Icons.grass_rounded;
      case 'electric': return Icons.bolt_rounded;
      default: return Icons.pets;
    }
  }

  void _showSkillInfo(BuildContext context, String name, String type, Map<String, dynamic>? skill) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(children: [
                Icon(Icons.flash_on, color: _getTypeColor(type)),
                const SizedBox(width: 8),
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold))
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow("Type", type),
                  _buildInfoRow("Power", "${skill?['power'] ?? 0}"),
                  if (skill?['scaling_stat'] != null) 
                    _buildInfoRow("Scaling", "${skill?['scaling_stat']} x${skill?['scaling_factor'] ?? 1.0}"),
                  if (skill?['accuracy'] != null) _buildInfoRow("Acc", "${skill?['accuracy']}%"),
                  const SizedBox(height: 12),
                  Text(skill?['desc'] ?? skill?['description'] ?? "No description available.", style: const TextStyle(color: Colors.black54, fontSize: 14)),
                ],
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE"))],
            ));
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          Text(value.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'fire': return const Color(0xFFFFAEBC);
      case 'water': return const Color(0xFFB4F8C8); // Minty Blue
      case 'grass': return const Color(0xFFA0E7E5); // Pastel Green
      case 'electric': return const Color(0xFFFBE7C6); // Pastel Yellow
      case 'dark': return Colors.purpleAccent.withOpacity(0.7);
      case 'psychic': return Colors.pinkAccent.withOpacity(0.7);
      case 'fighting': return Colors.orangeAccent;
      case 'heal': return Colors.tealAccent;
      default: return Colors.grey;
    }
  }
}
