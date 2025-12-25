import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:pet_trainer_frontend/config.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/providers/battle_controller.dart';
import 'package:pet_trainer_frontend/models/battle_state.dart';
import 'package:pet_trainer_frontend/models/skill_data.dart';
import 'package:pet_trainer_frontend/widgets/battle/battle_character_widget.dart';
import 'package:pet_trainer_frontend/widgets/battle/battle_log_widget.dart';
import 'package:pet_trainer_frontend/widgets/battle/skill_panel_widget.dart';
import 'package:pet_trainer_frontend/widgets/battle/floating_text_overlay.dart';

class BattlePage extends StatelessWidget {
  const BattlePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BattleController(),
      child: const BattleView(),
    );
  }
}

class BattleView extends StatefulWidget {
  const BattleView({super.key});

  @override
  State<BattleView> createState() => _BattleViewState();
}

class _BattleViewState extends State<BattleView> with TickerProviderStateMixin {
  late BattleController _controller;
  
  // Animation Controllers (View Concerns)
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _dashController;
  late Animation<Offset> _dashAnimation;
  late AnimationController _idleController;
  late Animation<double> _idleAnimation;

  // Floating Text State (Local UI State)
  final List<FloatingTextItem> _floatingTexts = [];
  int _floatingTextIdCounter = 0;
  int? _attackerId; // For Dash Direction

  @override
  void initState() {
    super.initState();
    // 1. Initialize Animations
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnimation = Tween<double>(begin: 0, end: 24).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeController);
    _shakeController.addStatusListener((status) {
       if (status == AnimationStatus.completed) _shakeController.reset();
    });

    _idleController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _idleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(CurvedAnimation(parent: _idleController, curve: Curves.easeInOut));
    _idleController.repeat(reverse: true);

    _dashController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _dashAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(_dashController);

    // 2. Connect to Controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller = Provider.of<BattleController>(context, listen: false);
      final charProvider = Provider.of<CharProvider>(context, listen: false);
      
      if (charProvider.character != null) {
         _controller.connect(charProvider.character!.userId);
         _listenToEvents();
      }
    });
  }

  void _listenToEvents() {
    _controller.eventStream.listen((event) {
       if (!mounted) return;
       
       switch (event.type) {
         case BattleEventType.shake:
           // Logic to check connection/target if needed, currently generic shake
           _shakeController.forward();
           break;
         case BattleEventType.attack:
           _triggerDash(event.actorId!);
           break;
         case BattleEventType.miss:
           _showFloatingText("MISS", false, event.targetId!);
           break;
         case BattleEventType.crit:
           _showFloatingText("CRITICAL!", true, event.targetId!);
           break;
         case BattleEventType.damage:
           _showFloatingText("${event.value}", false, event.targetId!);
           break;
         case BattleEventType.heal:
           _showFloatingText("+${event.value}", false, event.targetId!, isHeal: true);
           break;
         case BattleEventType.victory:
            // Show Victory Dialog
            // Note: event.message contains json encoded reward
            // Dialog implementation remains in View
            // Skipped for brevity in this snippet to keep under 200 lines
            try {
              if (event.message != null && event.message!.isNotEmpty) {
                 _showRewardDialog(jsonDecode(event.message!));
              } else {
                 _showGameOverDialog(true); // Fallback if no reward data
              }
            } catch (e) {
               print("Reward Parse Error: $e");
               _showGameOverDialog(true);
            }
            break;
         case BattleEventType.defeat:
            // Show Defeat Dialog
            _showGameOverDialog(false);
            break;
         default:
            break;
       }
    });
  }

  void _triggerDash(int attackerId) async {
     // Determine direction based on attackerId (Me vs Opponent)
     // Since controller doesn't expose ID directly in simple state, we assume:
     // If attacker is NOT me in CharProvider, it's opponent.
     final myId = Provider.of<CharProvider>(context, listen: false).character?.userId;
     
     setState(() => _attackerId = attackerId);
     
     if (attackerId == myId) {
       _dashAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(50, -50)).animate(CurvedAnimation(parent: _dashController, curve: Curves.easeInOut));
     } else {
       _dashAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(-50, 50)).animate(CurvedAnimation(parent: _dashController, curve: Curves.easeInOut));
     }
     
     await _dashController.forward();
     await Future.delayed(const Duration(milliseconds: 100));
     await _dashController.reverse();
  }

  void _showFloatingText(String text, bool isCrit, int targetId, {bool isHeal = false}) {
    if (!mounted) return;
    int id = _floatingTextIdCounter++;
    setState(() {
      _floatingTexts.add(FloatingTextItem(id: id, text: text, isCrit: isCrit, targetId: targetId, isHeal: isHeal));
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _floatingTexts.removeWhere((item) => item.id == id));
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _idleController.dispose();
    _dashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Consumer rebuilds when BattleController notifies changes
    return Consumer<BattleController>(
      builder: (context, controller, child) {
        final state = controller.state;
        final charProvider = Provider.of<CharProvider>(context);
        final String myPetType = charProvider.currentPetType;
        final myId = charProvider.character?.userId ?? 0;

        // Skill Grid Logic (View Concern: Formatting for UI)
        List<Map<String, dynamic>?> displaySkills = List<Map<String, dynamic>?>.from(state.mySkills);
        while (displaySkills.length < 4) displaySkills.add(null);
        if (displaySkills.length > 4) displaySkills = displaySkills.sublist(0, 4);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text("BATTLE ARENA", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: Stack(
            children: [
              // 0. Background
              Container(decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)], begin: Alignment.topCenter, end: Alignment.bottomCenter))),

              // 1. Opponent
              Positioned(top: 100, right: 40, child: Transform.scale(scale: 0.8,
                child: AnimatedBuilder(animation: _dashAnimation, builder: (ctx, child) {
                   Offset off = (_attackerId != myId) ? _dashAnimation.value : Offset.zero;
                   return Transform.translate(offset: off, child: child);
                }, child: BattleCharacterWidget(
                   name: state.oppName, hp: state.oppHp, maxHp: state.oppMaxHp, petType: state.oppPetType, isMe: false,
                   damageOpacity: 0.0, // Damage opacity is not directly managed by BattleController
                   isThinking: state.isOpponentThinking, statuses: state.oppStatuses, idleAnimation: _idleAnimation
                )))
              ),

              // 2. Player
              Positioned(bottom: 320, left: 20, child: Transform.scale(scale: 1.1,
                child: AnimatedBuilder(animation: Listenable.merge([_shakeAnimation, _dashAnimation]), builder: (ctx, child) {
                   Offset off = (_attackerId == myId) ? _dashAnimation.value : Offset.zero;
                   return Transform.translate(offset: Offset(_shakeAnimation.value, 0) + off, child: child);
                }, child: BattleCharacterWidget(
                   name: "YOU", hp: state.myHp, maxHp: state.myMaxHp, petType: myPetType, isMe: true,
                   damageOpacity: 0.0, // Damage opacity is not directly managed by BattleController
                   customImagePath: charProvider.imagePath, statuses: state.myStatuses, idleAnimation: _idleAnimation
                )))
              ),

              // 3. Logic & Skill
              Positioned(top: 100, left: 20, width: 250, height: 200, child: BattleLogWidget(logs: state.logs)),
              Positioned(bottom: 0, left: 0, right: 0, child: SkillPanelWidget(
                 skills: displaySkills, isMyTurn: state.isMyTurn, isConnected: state.isConnected, 
                 statusMessage: state.statusMessage, onSkillSelected: controller.sendMove
              )),

              // 4. Overlays
              IgnorePointer(child: FloatingTextOverlay(items: _floatingTexts, myId: myId)),
              if (!state.isMyTurn && state.isConnected) 
                 Center(child: Container(
                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                   decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                   child: Text(state.statusMessage, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                 )),
            ],
          ),
        );
      },
    );
  }

  void _showRewardDialog(Map<String, dynamic> reward) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Victory! 🏆"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("획득 경험치: ${reward['exp_gained']} EXP"),
            if (reward['level_up'] == true)
              Text("레벨업! Lv.${reward['new_level']} 달성! 🎉", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            if ((reward['new_skills'] as List).isNotEmpty)
              ...[
                const SizedBox(height: 10),
                const Text("새로운 기술 습득:", style: TextStyle(fontWeight: FontWeight.bold)),
                ...((reward['new_skills'] as List).map((id) => Text("- ${SKILL_DATA[id]?['name'] ?? 'Unknown'}"))),
              ]
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Dialog close
              Navigator.pop(context); // Page close
            },
            child: const Text("확인"),
          )
        ],
      ),
    );
  }
  
  void _showGameOverDialog(bool iWon) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(iWon ? "Victory! 🏆" : "Defeat..."),
        content: Text(iWon ? "승리했습니다!" : "아쉽게 패배했습니다. 다음 기회에..."),
        actions: [
          TextButton(
             onPressed: () {
               Navigator.pop(context);
               Navigator.pop(context);
             },
             child: const Text("나가기"),
          )
        ],
      ),
    );
  }
}
