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
            try {
              if (event.message != null && event.message!.isNotEmpty) {
                 _showRewardDialog(jsonDecode(event.message!));
              } else {
                 _showGameOverDialog(true); 
              }
            } catch (e) {
               _showGameOverDialog(true);
            }
            break;
         case BattleEventType.defeat:
            _showGameOverDialog(false);
            break;
         default:
            break;
       }
    });
  }

  void _triggerDash(int attackerId) async {
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
    return Consumer<BattleController>(
      builder: (context, controller, child) {
        final state = controller.state;
        final charProvider = Provider.of<CharProvider>(context);
        final String myPetType = charProvider.currentPetType;
        final myId = charProvider.character?.userId ?? 0;

        List<Map<String, dynamic>?> displaySkills = List<Map<String, dynamic>?>.from(state.mySkills);
        while (displaySkills.length < 4) displaySkills.add(null);
        if (displaySkills.length > 4) displaySkills = displaySkills.sublist(0, 4);

        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.black, // Fallback
          appBar: AppBar(
             title: const Text("BATTLE ARENA", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(2,2))])),
             centerTitle: true,
             backgroundColor: Colors.transparent,
             elevation: 0,
             leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ),
          body: Stack(
            children: [
              // 0. Background & Stage
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.2),
                      radius: 1.3,
                      colors: [Color(0xFF4A148C), Color(0xFF0D47A1), Color(0xFF000000)],
                      stops: [0.1, 0.6, 1.0]
                    )
                  ),
                ),
              ),
              // Stage Floor
              Positioned(
                 bottom: 0, 
                 left: 0, right: 0, 
                 height: MediaQuery.of(context).size.height * 0.45,
                 child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.0)],
                        stops: const [0.0, 0.4]
                      ),
                      border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1))
                    ),
                 ),
              ),

              // 1. OPPONENT (Top Right Layout)
              // Avatar (Centered slightly right/top)
              Positioned(top: 140, right: 60, child: Transform.scale(scale: 0.9,
                child: AnimatedBuilder(animation: _dashAnimation, builder: (ctx, child) {
                   Offset off = (_attackerId != myId) ? _dashAnimation.value : Offset.zero;
                   return Transform.translate(offset: off, child: child);
                }, child: BattleAvatarWidget(
                   petType: state.oppPetType, idleAnimation: _idleAnimation, damageOpacity: 0.0,
                )))
              ),
              // HUD (Top Right Corner)
              Positioned(
                 top: 100, right: 20,
                 child: SafeArea(
                    child: BattleHudWidget(
                      name: state.oppName, hp: state.oppHp, maxHp: state.oppMaxHp, isMe: false,
                      isThinking: state.isOpponentThinking, statuses: state.oppStatuses,
                    )
                 )
              ),

              // 2. PLAYER (Bottom Left Layout)
              // Avatar (Centered slightly left/bottom)
              Positioned(bottom: 330, left: 60, child: Transform.scale(scale: 1.2,
                child: AnimatedBuilder(animation: Listenable.merge([_shakeAnimation, _dashAnimation]), builder: (ctx, child) {
                   Offset off = (_attackerId == myId) ? _dashAnimation.value : Offset.zero;
                   return Transform.translate(offset: Offset(_shakeAnimation.value, 0) + off, child: child);
                }, child: BattleAvatarWidget(
                   petType: myPetType, idleAnimation: _idleAnimation, customImagePath: charProvider.imagePath, damageOpacity: 0.0,
                )))
              ),
              // HUD (Bottom Left Corner) - Above Skill Panel
              Positioned(
                 bottom: 300, left: 20, // Adjust based on Skill Panel height
                 child: BattleHudWidget(
                    name: "YOU", hp: state.myHp, maxHp: state.myMaxHp, isMe: true, statuses: state.myStatuses,
                 )
              ),

              // 3. LOGS (Top Center - Ticker Style)
              Positioned(
                 top: 90, left: 20, right: 20, 
                 height: 80, // Increased from 40 to 80 to prevent overflow
                 child: Center(
                    child: BattleLogWidget(logs: state.logs)
                 )
              ),
              
              // 4. SKILLS
              Positioned(bottom: 0, left: 0, right: 0, child: SkillPanelWidget(
                 skills: displaySkills, isMyTurn: state.isMyTurn, isConnected: state.isConnected, 
                 statusMessage: state.statusMessage, onSkillSelected: controller.sendMove
              )),

              // 5. OVERLAYS (Damage Text, Waiting Banner)
              IgnorePointer(child: FloatingTextOverlay(items: _floatingTexts, myId: myId)),
              
              if (state.isOpponentThinking && state.isConnected) 
                 Positioned(
                    bottom: 310, right: 20, // Bottom right, unobtrusive
                    child: Container(
                       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                       decoration: BoxDecoration(
                         color: Colors.black.withOpacity(0.7),
                         borderRadius: BorderRadius.circular(20),
                         border: Border.all(color: Colors.white24)
                       ),
                       child: Row(
                         children: const [
                           SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white))),
                           SizedBox(width: 8),
                           Text("Opponent is thinking...", style: TextStyle(color: Colors.white, fontSize: 12))
                         ],
                       )
                    )
                 ),
            ],
          ),
        );
      },
    );
  }

  void _showRewardDialog(Map<String, dynamic> reward) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2742), // Dark theme dialog
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white24)),
        title: const Text("VICTORY! 🏆", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("획득 경험치: ${reward['exp_gained']} EXP", style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            if (reward['level_up'] == true)
              const Text("레벨업! Level Up! 🎉", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 18)),
            if ((reward['new_skills'] as List).isNotEmpty)
              ...[
                const SizedBox(height: 16),
                const Text("새로운 기술 습득:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                const SizedBox(height: 8),
                ...((reward['new_skills'] as List).map((id) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text("- ${SKILL_DATA[id]?['name'] ?? 'Unknown'}", style: const TextStyle(color: Colors.white70)),
                ))),
              ]
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Dialog
              Navigator.pop(context); // Page
            },
            child: const Text("확인", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
  
  void _showGameOverDialog(bool iWon) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2742),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.white24)),
        title: Text(iWon ? "VICTORY! 🏆" : "DEFEAT... 💀", style: TextStyle(color: iWon ? Colors.amber : Colors.grey, fontWeight: FontWeight.bold)),
        content: Text(iWon ? "승리했습니다!" : "아쉽게 패배했습니다. 다음 기회에...", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
             onPressed: () {
               Navigator.pop(context);
               Navigator.pop(context);
             },
             child: const Text("나가기", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
}
