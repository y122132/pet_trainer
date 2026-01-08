// frontend/lib/screens/battle_page.dart
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import '../../config/theme.dart';
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
  
  // Animation Controllers
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _dashController;
  late Animation<Offset> _dashAnimation;
  late AnimationController _idleController;
  late Animation<double> _idleAnimation;
  
  // [NEW] Flash Effect Controller (Critical Hit)
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;

  // Floating Text State
  final List<FloatingTextItem> _floatingTexts = [];
  int _floatingTextIdCounter = 0;
  int? _attackerId; 

  // [Fix] Stream Subscription for cleanup
  StreamSubscription? _eventSubscription; 

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
    
    // Flash Effect (Fast Fade Out)
    _flashController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _flashAnimation = Tween<double>(begin: 0.0, end: 0.8).animate(CurvedAnimation(parent: _flashController, curve: Curves.easeOut));
    _flashController.addStatusListener((status) {
       if (status == AnimationStatus.completed) _flashController.reverse();
    });

    // 2. Connect to Controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller = Provider.of<BattleProvider>(context, listen: false);
      final charProvider = Provider.of<CharProvider>(context, listen: false);
      
      if (charProvider.character != null) {
         _controller.connect(charProvider.character!.userId);
         _listenToEvents();
      }
    });
  }

  void _listenToEvents() {
    _eventSubscription?.cancel(); // Cancel existing if any
    _eventSubscription = _controller.eventStream.listen((event) {
       if (!mounted) return;
       
       switch (event.type) {
         case BattleEventType.shake:
           _triggerShake(event.targetId!);
           break;
         case BattleEventType.attack:
           _triggerDash(event.actorId!);
           break;
         case BattleEventType.miss:
           _showFloatingText("MISS", false, event.targetId!);
           break;
         case BattleEventType.crit:
           _showFloatingText("CRITICAL!", true, event.targetId!);
           _flashController.forward(); // Trigger Flash!
           _triggerShake(event.targetId!); // Stronger shake
           break;
         case BattleEventType.damage:
           _showFloatingText("${event.value}", false, event.targetId!);
           break;
         case BattleEventType.heal:
           _showFloatingText("+${event.value}", false, event.targetId!, isHeal: true);
           break;
         case BattleEventType.victory:
            try {
              if (event.message != null) {
                final reward = jsonDecode(event.message!);

                final charProvider = Provider.of<CharProvider>(context, listen: false);
                if (reward['new_exp'] != null) {
                  charProvider.updateExperience(
                    reward['new_exp'], 
                    reward['new_level'] ?? charProvider.character!.stat!.level
                    );
                }
                if (reward['reason'] == 'opponent_fled') {
                  _showGameOverDialog(true, specialMessage: "상대방이 접속을 끊었습니다.\n당신의 기권승입니다!");
                } else {
                  _showRewardDialog(reward);
                }
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
  
  // [Fix] Shake Logic
  int? _shakeTargetId;
  void _triggerShake(int targetId) {
      setState(() => _shakeTargetId = targetId);
      _shakeController.forward();
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
    _eventSubscription?.cancel(); // [Fix] Cancel stream
    _shakeController.dispose();
    _idleController.dispose();
    _dashController.dispose();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BattleProvider>(
      builder: (context, controller, child) {
        final state = controller.state;
        final charProvider = Provider.of<CharProvider>(context);
        final String myPetType = charProvider.currentPetType;
        final myId = charProvider.character?.userId ?? 0;

        

        List<Map<String, dynamic>?> displaySkills = List<Map<String, dynamic>?>.from(state.mySkills);
        while (displaySkills.length < 4) displaySkills.add(null);
        if (displaySkills.length > 4) displaySkills = displaySkills.sublist(0, 4);

        return PopScope(
          canPop: false, // 시스템 뒤로가기로 바로 나가는 것을 방지
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;

            // 다이얼로그 띄우기
            final bool shouldLeave = await _showExitConfirmationDialog(context);
            if (shouldLeave && context.mounted) {
              _handleForfeit(context); // 기권 처리 및 나가기
            }
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
                onPressed: () async {
                  final bool shouldLeave = await _showExitConfirmationDialog(context);
                  if (shouldLeave && context.mounted) {
                    _handleForfeit(context);
                  }
                },
              ),
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFD4EAC8),
                          Color(0xFFE8F6F3), 
                        ],
                        stops: [0.3, 1.0]
                      )
                    ),
                  ),
                ),
                Positioned(top: 50, left: 30, child: Icon(Icons.cloud, size: 60, color: Colors.white.withOpacity(0.6))),
                Positioned(top: 80, right: 50, child: Icon(Icons.cloud, size: 40, color: Colors.white.withOpacity(0.4))),
                
                // Ground Effect (Rounded Hill)
                Positioned(
                  bottom: -50, left: 0, right: 0, height: 200,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFC1DFC4).withOpacity(0.6), // Darker Sage Hill
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(100))
                    ),
                  ),
                ),

                // 1. OPPONENT (Top Right)
                Positioned(top: 130, right: 40, child: Transform.scale(scale: 0.9,
                  child: AnimatedBuilder(animation: Listenable.merge([_dashAnimation, _shakeAnimation]), builder: (ctx, child) {
                    Offset dashOff = (_attackerId != myId) ? _dashAnimation.value : Offset.zero;
                    double shakeX = (_shakeTargetId != null && _shakeTargetId != myId) ? _shakeAnimation.value : 0.0;
                    
                    return Transform.translate(offset: dashOff + Offset(shakeX, 0), child: child);
                  }, child: BattleAvatarWidget(
                    petType: state.oppPetType,
                    idleAnimation: _idleAnimation,
                    imageType: 'side',
                    sideUrl: state.oppSideUrl,
                    damageOpacity: 0.0,
                  )))
                ),
                Positioned(
                  top: 100, left: 20, right: 20,
                  child: SafeArea(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildGlassHud(
                            name: state.oppName, 
                            hp: state.oppHp, 
                            maxHp: state.oppMaxHp, 
                            isMe: false, 
                            statuses: state.oppStatuses
                          ),
                        ],
                      )
                  )
                ),
                Positioned(bottom: 350, left: 50, child: Transform.scale(scale: 1.1,
                  child: AnimatedBuilder(animation: Listenable.merge([_shakeAnimation, _dashAnimation]), builder: (ctx, child) {
                    Offset dashOff = (_attackerId == myId) ? _dashAnimation.value : Offset.zero;
                    double shakeX = (_shakeTargetId == myId) ? _shakeAnimation.value : 0.0;
                    
                    return Transform.translate(offset: dashOff + Offset(shakeX, 0), child: child);
                  }, child: BattleAvatarWidget(
                    petType: myPetType, 
                    idleAnimation: _idleAnimation, 
                    imageType: 'side', 
                    sideUrl: charProvider.character?.sideUrl,
                    damageOpacity: 0.0,
                  )))
                ),
                Positioned(
                  bottom: 330, left: 20, right: 20,
                  child: Row(
                    children: [
                      _buildGlassHud(
                        name: "YOU", 
                        hp: state.myHp, 
                        maxHp: state.myMaxHp, 
                        isMe: true, 
                        statuses: state.myStatuses
                      ),
                    ],
                  )
                ),
                Positioned(
                  top: 150, left: 40, right: 40, 
                  height: 40, 
                  child: Center(
                      child: BattleLogWidget(logs: state.logs)
                  )
                ),
                Positioned(bottom: 0, left: 0, right: 0, child: SkillPanelWidget(
                  skills: displaySkills, isMyTurn: state.isMyTurn, isConnected: state.isConnected, 
                  statusMessage: state.statusMessage, onSkillSelected: controller.sendMove
                )),
                IgnorePointer(child: FloatingTextOverlay(items: _floatingTexts, myId: myId)),
                AnimatedBuilder(
                  animation: _flashAnimation,
                  builder: (context, child) {
                    return IgnorePointer(
                      child: Container(
                        color: Colors.white.withOpacity(_flashAnimation.value < 0.5 ? _flashAnimation.value : (1.0 - _flashAnimation.value)),
                      ),
                    );
                  },
                ),
                if (state.isOpponentThinking && state.isConnected) 
                  Positioned(
                      bottom: 310, right: 20,
                      child: _buildThinkingIndicator()
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  Widget _buildGlassHud({required String name, required int hp, required int maxHp, required bool isMe, required List<dynamic> statuses}) {
    double hpPercent = (hp / maxHp).clamp(0.0, 1.0);
    Color barColor = hpPercent > 0.5 ? AppColors.success : (hpPercent > 0.2 ? Colors.orange : AppColors.danger);
    
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppColors.softCharcoal.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(color: AppColors.softCharcoal, fontWeight: FontWeight.bold, fontSize: 16)),
              Text("$hp/$maxHp", style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(height: 12, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10))),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 12, 
                width: 156 * hpPercent,
                decoration: BoxDecoration(
                  color: barColor, 
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: barColor.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))]
                ),
              ),
            ],
          ),
          if (statuses.isNotEmpty) ...[
             const SizedBox(height: 4),
             Row(children: statuses.map((s) => const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.bolt, color: AppColors.accentYellow, size: 16))).toList())
          ]
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Container(
       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
       decoration: BoxDecoration(
         color: Colors.white,
         borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20)),
         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(2, 2))]
       ),
       child: const Row(
         children: [
           SizedBox(
             width: 12, height: 12,
             child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondaryPink),
           ),
           SizedBox(width: 8),
           Text("고민 중...", style: TextStyle(color: AppColors.softCharcoal, fontSize: 12, fontWeight: FontWeight.bold)),
         ],
       )
    );
  }

  void _showRewardDialog(Map<String, dynamic> reward) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Center(child: Text("VICTORY! 🏆", style: TextStyle(color: AppColors.secondaryPink, fontWeight: FontWeight.w900, fontSize: 28))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Text("+${reward['exp_gained']} EXP", style: const TextStyle(color: AppColors.softCharcoal, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (reward['level_up'] == true)
                    const Text("LEVEL UP! 🎉", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.success, fontSize: 18)),
                ],
              ),
            ),
            if ((reward['new_skills'] as List).isNotEmpty)
                const Padding(padding: EdgeInsets.only(top: 8), child: Text("새로운 스킬을 배웠습니다!", style: TextStyle(color: AppColors.secondaryPink))),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryMint, 
                  foregroundColor: AppColors.softCharcoal,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
              ),
              onPressed: () {
                Navigator.pop(context); // Dialog
                Navigator.pop(context); // Page
              },
              child: const Text("멋져요!", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
  void _showGameOverDialog(bool iWon, {String? specialMessage}) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(iWon ? "VICTORY! 🏆" : "DEFEAT... 💀", 
        style: TextStyle(
          color: iWon ? AppColors.secondaryPink : Colors.grey, 
          fontWeight: FontWeight.w900, 
          fontSize: 24),
          ),
        content: Text(
          specialMessage ?? (iWon ? "승리했습니다! 정말 대단해요!" : "아쉽게 패배했습니다.\n다음에 다시 도전해보세요!"), 
          style: const TextStyle(color: AppColors.softCharcoal), 
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: TextButton(
               onPressed: () {
                 Navigator.pop(context);
                 Navigator.pop(context);
               },
               style: TextButton.styleFrom(
                 foregroundColor: AppColors.softCharcoal,
                 textStyle: const TextStyle(fontWeight: FontWeight.bold)
               ),
               child: const Text("나가기"),
            ),
          )
        ],
      ),
    );
  }
  void _handleForfeit(BuildContext context) {
  //BattleProvider에 서버로 기권을 알리는 메서드가 필요합니다.
  // 예: _controller.sendForfeit();
  // 지금은 일단 이전 화면으로 나가는 처리를 합니다.
  Navigator.of(context).pop(); 
  }
  Future<bool> _showExitConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("배틀 포기", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.softCharcoal)),
          ],
        ),
        content: const Text(
          "정말 대전에서 나가시겠습니까?\n지금 중단하면 패배로 기록됩니다.",
          style: TextStyle(fontSize: 16, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // 아니오
            child: const Text("계속하기", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true), // 예
            child: const Text("포기하기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }
}
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.purple.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double i = 0; i < size.height; i += 30) {
       canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
    for (double i = 0; i < size.width; i += 40) {
       canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
