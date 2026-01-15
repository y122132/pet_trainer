// frontend/lib/screens/battle_page.dart
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
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
  final String roomId;
  const BattlePage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    debugPrint("🍎 [BattlePage] 생성! 방 ID: $roomId");

    return ChangeNotifierProvider(
      create: (_) => BattleProvider()..setRoomId(roomId),
      child: BattleView(roomId: roomId),
    );
  }
}

class BattleView extends StatefulWidget {
  final String? roomId; 
  const BattleView({super.key, this.roomId});

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
        debugPrint("🍋 [BattleView] 소켓 연결 시도!");
        debugPrint("   - 내 유저 ID: ${charProvider.character!.userId}");
        debugPrint("   - 넘겨줄 roomId: ${widget.roomId}");

        _controller.connect(
          charProvider.character!.userId, 
          roomId: widget.roomId
        );
        _listenToEvents();
      } else {
        debugPrint("❌ [BattleView] 캐릭터 정보가 없어 소켓 연결을 실패했습니다.");
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
                    
                    // --- Opponent Area (Top Left for HUD, Top Right for Avatar) ---
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 110, // Lowered to make room for logs
                      left: constraints.maxWidth * 0.05,
                      right: constraints.maxWidth * 0.05,
                      child: _buildAvatarWithHud(
                        isMe: false, 
                        state: state, 
                        myId: myId, 
                        charProvider: charProvider
                      ),
                    ),

                    // --- Player Area (Middle for HUD, Bottom Left for Avatar) ---
                    Positioned(
                      bottom: 350, // Raised slightly more as requested
                      left: constraints.maxWidth * 0.05,
                      right: constraints.maxWidth * 0.05,
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
    final String name = isMe ? "ME" : state.oppName;
    final int hp = isMe ? state.myHp : state.oppHp;
    final int maxHp = isMe ? state.myMaxHp : state.oppMaxHp;
    final List<dynamic> statuses = isMe ? state.myStatuses : state.oppStatuses;
    final String? faceUrl = isMe ? charProvider.character?.faceUrl : state.oppFaceUrl;
    final String petType = isMe ? charProvider.currentPetType : state.oppPetType;
    final String? sideUrl = isMe ? charProvider.character?.sideUrl : state.oppSideUrl;
    
    // Layout: Avatar on one side, HUD on the other to maximize space
    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.start : MainAxisAlignment.end,
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: isMe 
        ? [
            // My Avatar
            _buildAnimatedAvatar(petType, sideUrl, isMe, myId, state, 140),
            const SizedBox(width: 12),
            // My HUD
            Expanded(child: _buildGlassHud(name: name, hp: hp, maxHp: maxHp, statuses: statuses, faceUrl: faceUrl, isMe: true)),
          ]
        : [
            // Opponent HUD
            Expanded(child: _buildGlassHud(name: name, hp: hp, maxHp: maxHp, statuses: statuses, faceUrl: faceUrl, isMe: false)),
            const SizedBox(width: 12),
            // Opponent Avatar
            _buildAnimatedAvatar(petType, sideUrl, isMe, myId, state, 110),
          ],
    );
  }

  Widget _buildAnimatedAvatar(String petType, String? url, bool isMe, int myId, dynamic state, double size) {
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
        damageOpacity: 0.0,
        size: size, // [New] Passing the size
      ),
    );
  }

  Widget _buildBattleLogArea(List<String> logs, double maxHeight) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60, // Below AppBar Title
      left: 70, 
      right: 70, 
      child: Center(
        child: GlassContainer(
           padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4), // Reduced vertical padding
           opacity: 0.1,
           blur: 15,
           borderRadius: BorderRadius.circular(30),
           border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
           boxShadow: [], // Remove shadow to reduce visual volume
           child: BattleLogWidget(logs: logs)
        )
      )
    );
  }

  Widget _buildSkillPanel(List<Map<String, dynamic>?> skills, dynamic state, BattleProvider controller) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: GlassContainer(
        padding: const EdgeInsets.only(bottom: 20, top: 10),
        opacity: 0.4, // Natural transparency
        blur: 10,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
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

  Widget _buildGlassHud({
    required String name, 
    required int hp, 
    required int maxHp, 
    required List<dynamic> statuses, 
    String? faceUrl,
    required bool isMe
  }) {
    double hpPercent = (maxHp > 0) ? (hp / maxHp).clamp(0.0, 1.0) : 0.0;
    
    // Premium Gradient Colors for HP Bar
    final List<Color> hpGradient = hpPercent > 0.5 
      ? [const Color(0xFF81C784), const Color(0xFF4CAF50)] // Success Green
      : (hpPercent > 0.2 
          ? [const Color(0xFFFFD54F), const Color(0xFFFFA000)] // Warning Yellow
          : [const Color(0xFFE57373), const Color(0xFFD32F2F)]); // Danger Red
    
    final String fullImageUrl = faceUrl != null && faceUrl.isNotEmpty
        ? "${AppConfig.baseUrl.replaceFirst('/v1', '')}$faceUrl"
        : "";

    return GlassContainer(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(24),
      opacity: 0.7,
      blur: 12,
      border: Border.all(
        color: isMe ? AppColors.primaryMint.withOpacity(0.4) : Colors.white.withOpacity(0.4),
        width: 2
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Circular Face
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, 
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]
                ),
                child: ClipOval(
                  child: fullImageUrl.isNotEmpty
                      ? Image.network(fullImageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 18))
                      : const Icon(Icons.person, size: 18, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: GoogleFonts.jua(fontSize: 14, color: AppColors.softCharcoal, fontWeight: FontWeight.bold)),
                    Text("$hp / $maxHp", style: GoogleFonts.jua(fontSize: 11, color: AppColors.softCharcoal.withOpacity(0.6))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Premium HP Bar
          Stack(
            children: [
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                height: 10,
                width: 200 * hpPercent, // Relative width
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: hpGradient),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    BoxShadow(color: hpGradient.last.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))
                  ]
                ),
              ),
            ],
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