// frontend/lib/screens/battle_page.dart
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import '../../config/theme.dart';
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

  // 애니메이션 컨트롤러
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _dashController;
  late Animation<Offset> _dashAnimation;
  late AnimationController _idleController;
  late Animation<double> _idleAnimation;
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;

  // 배틀 상태 관리
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

  void _triggerDash(int attackerId) async {
    final myId = Provider.of<CharProvider>(context, listen: false).character?.userId;
    setState(() => _attackerId = attackerId);

    const double moveX = 160.0; 
    const double moveY = 80.0;

    _dashAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: attackerId == myId 
        ? const Offset(moveX, -moveY)   // 나: 오른쪽 위로 돌진 (X+, Y-)
        : const Offset(-moveX, moveY),  // 상대: 왼쪽 아래로 돌진 (X-, Y+)
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
            backgroundColor: Colors.black,
            appBar: AppBar(
              title: const Text("PET BATTLE", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, color: AppColors.softCharcoal)),
              centerTitle: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.softCharcoal),
                onPressed: () async { if (await _showExitConfirmationDialog(context)) Navigator.of(context).pop(); },
              ),
            ),
            body: Stack(
              children: [
                _buildBackground(),
                _buildOpponentArea(state, myId),
                _buildPlayerArea(state, myId, charProvider),
                _buildBattleLogArea(state.logs),
                _buildSkillPanel(displaySkills, state, controller),
                _buildEffects(myId, state),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- UI 컴포넌트 헬퍼 함수들 (클래스 내부) ---

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFD4EAC8), Color(0xFFE8F6F3)], stops: [0.3, 1.0])))),
        Positioned(top: 50, left: 30, child: Icon(Icons.cloud, size: 60, color: Colors.white.withOpacity(0.6))),
        Positioned(bottom: -50, left: 0, right: 0, height: 200, child: Container(decoration: BoxDecoration(color: const Color(0xFFC1DFC4).withOpacity(0.6), borderRadius: const BorderRadius.vertical(top: Radius.circular(100))))),
      ],
    );
  }

  Widget _buildOpponentArea(dynamic state, int myId) {
    return Stack(
      children: [
        Positioned(
          top: 250, 
          right: 40, 
          child: Transform.scale(
            scale: 0.9, 
            child: _buildAnimatedAvatar(
              state.oppPetType, 
              state.oppSideUrl, 
              false, 
              myId,
              state
            )
          )
        ),
        Positioned(
          top: 140, 
          left: 20, 
          right: 20, 
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end, 
              children: [
                _buildGlassHud(
                  name: state.oppName, 
                  hp: state.oppHp, 
                  maxHp: state.oppMaxHp, 
                  statuses: state.oppStatuses,
                  faceUrl: state.oppFaceUrl,
                )
              ]
            )
          )
        ),
      ],
    );
  }

  Widget _buildPlayerArea(dynamic state, int myId, CharProvider charProvider) {
    return Stack(
      children: [
        Positioned(
          bottom: 430, 
          left: 20, 
          child: Transform.scale(
            scale: 1.1, 
            child: _buildAnimatedAvatar(
              charProvider.currentPetType, 
              charProvider.character?.sideUrl, 
              true, 
              myId, 
              state
            )
          )
        ),
        Positioned(
          bottom: 340, left: 20, right: 20, 
          child: Row(
            children: [
              _buildGlassHud(
                name: "YOU", 
                hp: state.myHp, 
                maxHp: state.myMaxHp, 
                statuses: state.myStatuses,
                faceUrl: charProvider.character?.faceUrl,
              )
            ]
          )
        )
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
        final int targetId = isMe ? myId : (state.oppId ?? 0);

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

  Widget _buildBattleLogArea(List<String> logs) {
    return Positioned(
      top: 160, 
      left: 40, 
      right: 40, 
      height: 40, 
      child: Center(child: BattleLogWidget(logs: logs)));
  }

  Widget _buildSkillPanel(List<Map<String, dynamic>?> skills, dynamic state, BattleProvider controller) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
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
          Positioned(bottom: 310, right: 20, child: _buildThinkingIndicator()),
      ],
    );
  }

  // --- [핵심] 캐릭터 얼굴 이미지가 포함된 HUD 위젯 ---
  Widget _buildGlassHud({required String name, required int hp, required int maxHp, required List<dynamic> statuses, String? faceUrl}) {
    double hpPercent = (maxHp > 0) ? (hp / maxHp).clamp(0.0, 1.0) : 0.0;
    Color barColor = hpPercent > 0.5 ? AppColors.success : (hpPercent > 0.2 ? Colors.orange : AppColors.danger);
    
    // 이미지 주소 생성
    final String fullImageUrl = faceUrl != null && faceUrl.isNotEmpty
        ? "${AppConfig.baseUrl.replaceFirst('/v1', '')}$faceUrl"
        : "";

    return Container(
      width: 220, padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
      child: Row(
        children: [
          // 동그란 얼굴 이미지
          Container(
            width: 45, height: 45,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey[300]!, width: 2)),
            child: ClipOval(
              child: fullImageUrl.isNotEmpty
                  ? Image.network(fullImageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 20))
                  : const Icon(Icons.person, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text("$hp/$maxHp", style: const TextStyle(fontSize: 10, color: Colors.grey))]),
                const SizedBox(height: 5),
                Stack(children: [Container(height: 8, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5))), AnimatedContainer(duration: const Duration(milliseconds: 300), height: 8, width: 140 * hpPercent, decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(5)))]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(2, 2))]), child: const Row(children: [SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondaryPink)), SizedBox(width: 8), Text("고민 중...", style: TextStyle(color: AppColors.softCharcoal, fontSize: 12, fontWeight: FontWeight.bold))]));
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
    
    // 1. Show Level Up / Reward Stat Dialog
    // Battle rewards might not have specific stat types like training, usually just EXP.
    // If 'exp_gained' is present, we assume it's added.
    // We utilize StatDistributionDialog to show current status and allow point distribution if level up happened.
    
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
        // Pass a simple map for earned reward message if needed, or just rely on title/exp
        // The dialog builds reward info based on 'earnedReward'. 
        // We can create a dummy one or pass null if only EXP matters.
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

    // 2. Check Skills & Navigate
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
                 actions: [
                    TextButton(
                       onPressed: () { 
                          Navigator.pop(context); 
                          Navigator.pop(context); // Exit Battle
                       },
                       child: const Text("아니오 (나가기)"),
                    ),
                    TextButton(
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
    
    // If no skills, just exit
    Navigator.pop(context); 
  }

  void _showGameOverDialog(bool iWon, {String? specialMessage}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(iWon ? "승리" : "패배"),
        content: Text(specialMessage ?? (iWon ? "축하합니다!" : "아쉽네요.")),
        actions: [TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pop();
          },
          child: const Text("나가기")
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("아니오")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("네")),
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