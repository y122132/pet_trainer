import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import '../../config/theme.dart';
import '../../config/design_system.dart'; // Import Design System
import '../game/game_assets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pet_trainer_frontend/api_config.dart'; 
import 'package:pet_trainer_frontend/models/battle_state.dart'; 
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/providers/battle_provider.dart';

import 'package:pet_trainer_frontend/widgets/battle/battle_log_widget.dart';
import 'package:pet_trainer_frontend/widgets/battle/skill_panel_widget.dart';
import 'package:pet_trainer_frontend/widgets/battle/floating_text_overlay.dart';
import 'package:pet_trainer_frontend/widgets/battle/battle_character_widget.dart';
import 'package:pet_trainer_frontend/widgets/stat_distribution_dialog.dart';
import 'skill_management_screen.dart';

class BattlePage extends StatelessWidget {
  const BattlePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BattleProvider(),
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
  late BattleProvider _controller;

  // Anim Controllers
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _dashController;
  late Animation<Offset> _dashAnimation;
  late AnimationController _idleController;
  late Animation<double> _idleAnimation;
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;

  // Battle State
  final List<FloatingTextItem> _floatingTexts = [];
  int _floatingTextIdCounter = 0;
  int? _attackerId;
  int? _shakeTargetId;
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _initAnimations();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller = Provider.of<BattleProvider>(context, listen: false);
      final charProvider = Provider.of<CharProvider>(context, listen: false);

      if (charProvider.character != null) {
        _controller.connect(charProvider.character!.userId);
        _listenToEvents();
      }
    });
  }

  void _initAnimations() {
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnimation = Tween<double>(begin: 0, end: 24).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeController);
    
    _idleController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _idleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(CurvedAnimation(parent: _idleController, curve: Curves.easeInOut));
    _idleController.repeat(reverse: true);

    _dashController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _dashAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(_dashController);

    _flashController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _flashAnimation = Tween<double>(begin: 0.0, end: 0.8).animate(CurvedAnimation(parent: _flashController, curve: Curves.easeOut));
    _flashController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _flashController.reverse();
    });
  }

  void _listenToEvents() {
    _eventSubscription?.cancel();
    _eventSubscription = _controller.eventStream.listen((event) {
      if (!mounted) return;
      switch (event.type) {
        case BattleEventType.shake: _triggerShake(event.targetId!); break;
        case BattleEventType.attack: _triggerDash(event.actorId!); break;
        case BattleEventType.miss: _showFloatingText("MISS", false, event.targetId!); break;
        case BattleEventType.crit:
          _showFloatingText("CRITICAL!", true, event.targetId!);
          _flashController.forward();
          _triggerShake(event.targetId!);
          break;
        case BattleEventType.damage: _showFloatingText("${event.value}", false, event.targetId!); break;
        case BattleEventType.heal: _showFloatingText("+${event.value}", false, event.targetId!, isHeal: true); break;
        case BattleEventType.victory: _handleGameOver(true, event.message); break;
        case BattleEventType.defeat: _showGameOverDialog(false); break;
        default: break;
      }
    });
  }

  // Simplified Dash Logic 
  void _triggerDash(int attackerId) async {
    final myId = Provider.of<CharProvider>(context, listen: false).character?.userId;
    setState(() => _attackerId = attackerId);

    // Note: Dash distance is now relative to visual perception, but for Animation<Offset>, 
    // it's usually pixel based or size based. Keeping simple fixed value for now or 
    // improving to be screen-relative would require deeper refactor of BattleAvatarWidget.
    // Keeping logic similar but potentially adjustable.
    const double moveX = 120.0; 
    const double moveY = 60.0;

    _dashAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: attackerId == myId 
        ? const Offset(moveX, -moveY)
        : const Offset(-moveX, moveY),
    ).animate(CurvedAnimation(
      parent: _dashController,
      curve: Curves.easeOutBack
    ));

    await _dashController.forward();
    await Future.delayed(const Duration(milliseconds: 50));
    await _dashController.reverse();
  }

  void _triggerShake(int targetId) {
    setState(() => _shakeTargetId = targetId);
    _shakeController.forward();
  }

  void _showFloatingText(String text, bool isCrit, int targetId, {bool isHeal = false}) {
    if (!mounted) return;
    int id = _floatingTextIdCounter++;
    setState(() => _floatingTexts.add(FloatingTextItem(id: id, text: text, isCrit: isCrit, targetId: targetId, isHeal: isHeal)));
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _floatingTexts.removeWhere((item) => item.id == id));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BattleProvider>(
      builder: (context, controller, child) {
        final state = controller.state;
        final charProvider = Provider.of<CharProvider>(context);
        final char = charProvider.character;
        final myId = char?.userId ?? 0;

        // Skills Preparation
        List<Map<String, dynamic>?> displaySkills = [];
        if (char != null) {
          displaySkills = char.equippedSkills.map((id) {
            final moveData = GameAssets.MOVE_DATA[id];
            return moveData != null ? {...moveData, 'id': id} : null;
          }).cast<Map<String, dynamic>?>().toList();
        }
        while (displaySkills.length < 4) { displaySkills.add(null); }
        if (displaySkills.length > 4) { displaySkills = displaySkills.sublist(0, 4); }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (await _showExitConfirmationDialog(context)) Navigator.of(context).pop();
          },
          child: Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: Colors.black, // Fallback
            appBar: AppBar(
              title: const Text("PET BATTLE", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, color: AppColors.softCharcoal)),
              centerTitle: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: Container(
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), shape: BoxShape.circle),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.softCharcoal, size: 20),
                  onPressed: () async { if (await _showExitConfirmationDialog(context)) Navigator.of(context).pop(); },
                ),
              ),
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    _buildBackground(),
                    
                    // --- Opponent Area (Top Right) ---
                    Positioned(
                      top: constraints.maxHeight * 0.15,
                      right: constraints.maxWidth * 0.1,
                      child: _buildAvatarWithHud(
                        isMe: false, 
                        state: state, 
                        myId: myId, 
                        charProvider: charProvider
                      ),
                    ),

                    // --- Player Area (Bottom Left) ---
                    Positioned(
                      bottom: constraints.maxHeight * 0.35, // Give room for skills
                      left: constraints.maxWidth * 0.1,
                      child: _buildAvatarWithHud(
                        isMe: true, 
                        state: state, 
                        myId: myId, 
                        charProvider: charProvider
                      ),
                    ),

                    // Logs
                    _buildBattleLogArea(state.logs, constraints.maxHeight),
                    
                    // Skills
                    _buildSkillPanel(displaySkills, state, controller),
                    
                    // Effects Overlay
                    _buildEffects(myId, state),
                  ],
                );
              }
            ),
          ),
        );
      },
    );
  }

  // --- Components ---

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFD4EAC8), Color(0xFFE8F6F3)], stops: [0.3, 1.0])))),
        Positioned(top: 50, left: 30, child: Icon(Icons.cloud, size: 80, color: Colors.white.withOpacity(0.6))),
        Positioned(bottom: -50, left: 0, right: 0, height: 200, child: Container(decoration: BoxDecoration(color: const Color(0xFFC1DFC4).withOpacity(0.6), borderRadius: const BorderRadius.vertical(top: Radius.circular(100))))),
      ],
    );
  }

  Widget _buildAvatarWithHud({
    required bool isMe,
    required dynamic state,
    required int myId,
    required CharProvider charProvider,
  }) {
    // Extract Data
    final String name = isMe ? "ME" : state.oppName;
    final int hp = isMe ? state.myHp : state.oppHp;
    final int maxHp = isMe ? state.myMaxHp : state.oppMaxHp;
    final List<dynamic> statuses = isMe ? state.myStatuses : state.oppStatuses;
    final String? faceUrl = isMe ? charProvider.character?.faceUrl : state.oppFaceUrl;
    
    // Avatar Logic
    final String petType = isMe ? charProvider.currentPetType : state.oppPetType;
    final String? sideUrl = isMe ? charProvider.character?.sideUrl : state.oppSideUrl;
    
    // Reverse layout for opponent? No, keeping consistent HUD above/below might be better.
    // Let's stack HUD above Avatar for Opponent, and HUD below Avatar for Player?
    // Or simpler: HUD always "outside" the center.
    // Opponent: HUD top-right relative to avatar
    // Player: HUD bottom-left relative to avatar
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        if (!isMe) _buildGlassHud(name: name, hp: hp, maxHp: maxHp, statuses: statuses, faceUrl: faceUrl),
        if (!isMe) const SizedBox(height: 10),
        
        // Avatar Wrapper
        Transform.scale(
          scale: isMe ? 1.2 : 0.9,
          child: _buildAnimatedAvatar(petType, sideUrl, isMe, myId, state),
        ),
        
        if (isMe) const SizedBox(height: 10),
        if (isMe) _buildGlassHud(name: name, hp: hp, maxHp: maxHp, statuses: statuses, faceUrl: faceUrl),
      ],
    );
  }

  Widget _buildAnimatedAvatar(String petType, String? url, bool isMe, int myId, dynamic state) {
    final String fullUrl = (url != null && url.isNotEmpty)
      ? (url.startsWith('http') ? url : "${AppConfig.baseUrl.replaceFirst('/v1', '')}$url")
      : "";

    return AnimatedBuilder(
      animation: Listenable.merge([_dashAnimation, _shakeAnimation]),
      builder: (ctx, child) {
        // final int targetId = isMe ? myId : (state.oppId ?? 0);
        Offset dashOff = (_attackerId == (isMe ? myId : state.oppId)) ? _dashAnimation.value : Offset.zero;
        double shakeX = (_shakeTargetId == (isMe ? myId : state.oppId)) ? _shakeAnimation.value : 0.0;
        
        return Transform.translate(offset: dashOff + Offset(shakeX, 0), child: child);
      },
      child: BattleAvatarWidget(
        petType: petType, 
        idleAnimation: _idleAnimation, 
        imageType: 'side', 
        sideUrl: fullUrl, 
        damageOpacity: 0.0
      ),
    );
  }

  Widget _buildBattleLogArea(List<String> logs, double maxHeight) {
    return Positioned(
      top: maxHeight * 0.12, 
      left: 60, 
      right: 60, 
      height: 40,
      child: Center(
        child: GlassContainer(
           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
           opacity: 0.8,
           borderRadius: BorderRadius.circular(20),
           child: BattleLogWidget(logs: logs)
        )
      )
    );
  }

  Widget _buildSkillPanel(List<Map<String, dynamic>?> skills, dynamic state, BattleProvider controller) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.only(bottom: 20, top: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
             begin: Alignment.topCenter, end: Alignment.bottomCenter,
             colors: [Colors.transparent, Colors.white.withOpacity(0.9)]
          )
        ),
        child: SkillPanelWidget(
          skills: skills,
          isMyTurn: state.isMyTurn,
          isConnected: state.isConnected,
          statusMessage: state.statusMessage,
          onSkillSelected: (dynamic skill) {
            if (skill != null) {
              final int skillId = (skill is Map) ? (skill['id'] as int) : (skill as int);
              controller.sendMove(skillId);
            }
          },
        ),
      ),
    );
  }

  Widget _buildEffects(int myId, dynamic state) {
    return Stack(
      children: [
        IgnorePointer(child: FloatingTextOverlay(items: _floatingTexts, myId: myId)),
        AnimatedBuilder(
          animation: _flashAnimation,
          builder: (context, child) => IgnorePointer(child: Container(color: Colors.white.withOpacity(_flashAnimation.value < 0.5 ? _flashAnimation.value : (1.0 - _flashAnimation.value)))),
        ),
        if (state.isOpponentThinking && state.isConnected)
          Align(
            alignment: const Alignment(0.6, 0.4),
            child: _buildThinkingIndicator()
          ),
      ],
    );
  }

  Widget _buildGlassHud({required String name, required int hp, required int maxHp, required List<dynamic> statuses, String? faceUrl}) {
    double hpPercent = (maxHp > 0) ? (hp / maxHp).clamp(0.0, 1.0) : 0.0;
    Color barColor = hpPercent > 0.5 ? AppColors.success : (hpPercent > 0.2 ? AppColors.warning : AppColors.danger);
    
    final String fullImageUrl = faceUrl != null && faceUrl.isNotEmpty
        ? "${AppConfig.baseUrl.replaceFirst('/v1', '')}$faceUrl"
        : "";

    return GlassContainer(
      width: 200, padding: const EdgeInsets.all(10),
      borderRadius: BorderRadius.circular(30),
      opacity: 0.85,
      child: Row(
        children: [
          // Circle Avatar
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), color: Colors.grey[200]),
            child: ClipOval(
              child: fullImageUrl.isNotEmpty
                  ? Image.network(fullImageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 20))
                  : const Icon(Icons.person, size: 20, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textMain)), Text("$hp/$maxHp", style: const TextStyle(fontSize: 10, color: AppColors.textSub))]),
                const SizedBox(height: 6),
                Stack(children: [
                    Container(height: 6, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(5))), 
                    AnimatedContainer(duration: const Duration(milliseconds: 300), height: 6, width: 120 * hpPercent, decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(5)))
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
           SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondaryPink)), 
           SizedBox(width: 8), 
           Text("고민 중...", style: TextStyle(color: AppColors.textMain, fontSize: 12, fontWeight: FontWeight.bold))
        ]
      )
    );
  }

  void _handleGameOver(bool iWon, String? message) {
    try {
      if (message != null) {
        final reward = jsonDecode(message);
        final charProvider = Provider.of<CharProvider>(context, listen: false);
        if (reward['new_exp'] != null) charProvider.updateExperience(reward['new_exp'], reward['new_level'] ?? charProvider.character!.stat!.level);
        if (reward['reason'] == 'opponent_fled') _showGameOverDialog(true, specialMessage: "상대방이 접속을 끊었습니다.\n당신의 기권승입니다!");
        else _showRewardDialog(reward);
      } else { _showGameOverDialog(iWon); }
    } catch (e) { _showGameOverDialog(iWon); }
  }

  Future<void> _showRewardDialog(Map<String, dynamic> reward) async {
    final charProvider = Provider.of<CharProvider>(context, listen: false);
    
    // 1. Stat Dialog
    final currentStats = {
      "strength": charProvider.strength,
      "intelligence": charProvider.intelligence,
      "agility": charProvider.agility,
      "defense": charProvider.defense,
      "luck": charProvider.luck,
    };

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatDistributionDialog(
        availablePoints: charProvider.unusedStatPoints,
        currentStats: currentStats,
        title: "전투 승리!",
        earnedReward: {'stat_type': 'EXP', 'value': reward['exp_gained']}, 
        earnedBonus: 0, 
        confirmLabel: "확인",
        skipLabel: "닫기",
        onConfirm: (allocated, remaining) {
             ['strength','intelligence','agility','defense','luck'].forEach((key) {
                for(int i=0; i < (allocated[key]??0); i++) charProvider.allocateStatSpecific(key);
             });
             Navigator.pop(ctx);
        },
        onSkip: () => Navigator.pop(ctx),
      ),
    );

    // 2. Skills
    if (reward['acquired_skills_details'] != null) {
      final skills = reward['acquired_skills_details'] as List;
      if (skills.isNotEmpty) {
          String msg = "";
          for (var s in skills) {
             msg += "'${s['name']}' ";
          }
          msg += "스킬을 획득했습니다!\n스킬 창으로 이동하시겠습니까?";

          showDialog(
             context: context,
             barrierDismissible: false,
             builder: (context) => AlertDialog(
                 title: const Text("스킬 획득!"),
                 content: Text(msg),
                 
                 // Apply Theme Style manually if needed or rely on Theme
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                 actions: [
                    TextButton(
                       onPressed: () { 
                          Navigator.pop(context); 
                          Navigator.pop(context); // Exit Battle
                       },
                       child: const Text("아니오 (나가기)", style: TextStyle(color: AppColors.textSub)),
                    ),
                    ElevatedButton(
                       onPressed: () {
                          Navigator.pop(context); 
                          Navigator.pop(context); // Exit Battle
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const SkillManagementScreen()));
                       },
                       child: const Text("예 (이동)"),
                    ),
                 ]
             )
          );
          return;
      }
    }
    
    Navigator.pop(context); 
  }

  void _showGameOverDialog(bool iWon, {String? specialMessage}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(iWon ? "승리" : "패배"),
        content: Text(specialMessage ?? (iWon ? "축하합니다!" : "아쉽네요.")),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pop();
          },
          child: const Text("나가기", style: TextStyle(color: AppColors.primaryMint))
        )],
      ),
    );
  }

  Future<bool> _showExitConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("배틀 종료"),
        content: const Text("대전에서 나가시겠습니까?\n지금 중단하면 패배로 기록됩니다."),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("아니오", style: TextStyle(color: AppColors.textMain))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("네", style: TextStyle(color: AppColors.danger))),
        ],
      ),
    ) ?? false;
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _shakeController.dispose();
    _idleController.dispose();
    _dashController.dispose();
    _flashController.dispose();
    super.dispose();
  }
}