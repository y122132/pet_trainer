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
      height: 300, // Increased height slightly
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600), // Layout constraint for PC
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40), // Increased padding to reduce button height
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("SKILLS", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  Text(statusMessage, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 15),
              Column(
                children: [
                  SizedBox(
                    height: 80, // Fixed height for consistent look and fit
                    child: Row(
                      children: [
                        Expanded(child: _buildSkillButton(context, displaySkills.length > 0 ? displaySkills[0] : null)),
                        const SizedBox(width: 15),
                        Expanded(child: _buildSkillButton(context, displaySkills.length > 1 ? displaySkills[1] : null)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    height: 80, // Fixed height for consistent look and fit
                    child: Row(
                      children: [
                        Expanded(child: _buildSkillButton(context, displaySkills.length > 2 ? displaySkills[2] : null)),
                        const SizedBox(width: 15),
                        Expanded(child: _buildSkillButton(context, displaySkills.length > 3 ? displaySkills[3] : null)),
                      ],
                    ),
                  ),
                ],
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
          color: Colors.grey[200], // Darker grey for visibility
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey[400]!), // Darker border
        ),
      );
    }

    int skillId = skill['id'];
    String name = skill['name'] ?? "Unknown";
    String type = skill['type'] ?? "normal";
    Color typeColor = _getTypeColor(type);

    return GestureDetector(
      onLongPress: () => _showSkillInfo(context, name, type, skill),
      child: ElevatedButton(
        onPressed: (isConnected && isMyTurn) ? () => onSkillSelected(skillId) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: typeColor,
          elevation: 4,
          shadowColor: typeColor.withOpacity(0.3),
          padding: const EdgeInsets.all(0),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15), side: BorderSide(color: typeColor.withOpacity(0.5), width: 2)),
        ),
        child: Stack(
          children: [
            // Background Icon watermark
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(Icons.flash_on, size: 60, color: typeColor.withOpacity(0.05)),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(type.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: typeColor)),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSkillInfo(BuildContext context, String name, String type, Map<String, dynamic>? skill) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                  const SizedBox(height: 10),
                  Text(skill?['desc'] ?? "No description available.", style: const TextStyle(color: Colors.black54)),
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
      case 'electric': return Colors.yellow[700]!;
      case 'dark': return Colors.purple;
      case 'psychic': return Colors.pinkAccent;
      case 'fighting': return Colors.orange;
      case 'heal': return Colors.teal;
      case 'evade': return Colors.indigo;
      default: return Colors.grey;
    }
  }
}
