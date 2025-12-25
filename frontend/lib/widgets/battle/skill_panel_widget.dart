import 'package:flutter/material.dart';

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
      height: 280, 
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600), // Layout constraint for PC
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("SKILLS", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.indigo, letterSpacing: 1.0)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isMyTurn ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(statusMessage, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isMyTurn ? Colors.green : Colors.red)),
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
          color: Colors.grey[100], 
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!, width: 2),
        ),
        child: Center(
          child: Icon(Icons.lock_outline, color: Colors.grey[400], size: 32),
        ),
      );
    }

    int skillId = skill['id'];
    String name = skill['name'] ?? "Unknown";
    String type = skill['type'] ?? "normal";
    Color typeColor = _getTypeColor(type);
    bool canPress = isConnected && isMyTurn;

    return GestureDetector(
      onLongPress: () => _showSkillInfo(context, name, type, skill),
      child: Opacity(
        opacity: canPress ? 1.0 : 0.6,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
               begin: Alignment.topLeft, end: Alignment.bottomRight,
               colors: [Colors.white, typeColor.withOpacity(0.1)]
            ),
            boxShadow: [
              if (canPress) BoxShadow(color: typeColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
            ],
            border: Border.all(color: canPress ? typeColor : Colors.grey, width: 2)
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canPress ? () => onSkillSelected(skillId) : null,
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Positioned(
                    right: -5, bottom: -5,
                    child: Icon(Icons.flash_on, size: 64, color: typeColor.withOpacity(0.1)),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                         Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                         const SizedBox(height: 4),
                         Container( 
                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                           decoration: BoxDecoration(color: typeColor, borderRadius: BorderRadius.circular(8)),
                           child: Text(type.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
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
                  if (skill?['accuracy'] != null) _buildInfoRow("Acc", "${skill?['accuracy']}%"),
                  const SizedBox(height: 12),
                  Text(skill?['desc'] ?? "No description available.", style: const TextStyle(color: Colors.black54, fontSize: 14)),
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
      case 'fire': return Colors.red;
      case 'water': return Colors.blue;
      case 'grass': return Colors.green;
      case 'electric': return Colors.amber[700]!;
      case 'dark': return Colors.deepPurple;
      case 'psychic': return Colors.pinkAccent;
      case 'fighting': return Colors.orange;
      case 'heal': return Colors.teal;
      case 'evade': return Colors.indigo;
      default: return Colors.grey;
    }
  }
}
