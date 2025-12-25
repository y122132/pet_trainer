import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pet_trainer_frontend/config.dart';
import 'package:pet_trainer_frontend/providers/char_provider.dart';
import 'package:pet_trainer_frontend/models/skill_data.dart';

class BattlePage extends StatefulWidget {
  const BattlePage({super.key});

  @override
  State<BattlePage> createState() => _BattlePageState();
}

class _BattlePageState extends State<BattlePage> with TickerProviderStateMixin {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  List<String> _battleLogs = [];
  
  // 배틀 상태
  int? _myId;
  int? _opponentId;
  
  int _myHp = 100;
  int _myMaxHp = 100;
  int _oppHp = 100;
  int _oppMaxHp = 100;
  
  String _oppName = "Opponent";
  bool _isMyTurn = true; // 선택 가능 여부
  String _statusMessage = "Connecting to server...";
  bool _opponentSelecting = false;
  List<String> _myStatuses = []; // Status list from server updates (Optional future work)
  List<String> _oppStatuses = []; // [New] Opponent Statuses
  List<Map<String, dynamic>> _mySkills = []; // [New] Server-synced skills

  // [Fix] Game Over Queue State
  bool _isProcessingTurn = false;
  Map<String, dynamic>? _pendingGameOverData;

  // Animation Controllers
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  
  // Dash Animation (New)
  late AnimationController _dashController;
  late Animation<Offset> _dashAnimation;
  int? _attackerId; // Who is attacking?

  // Idle Animation (Breathing)
  late AnimationController _idleController;
  late Animation<double> _idleAnimation;

  // Floating Texts
  final List<FloatingTextItem> _floatingTexts = [];
  int _floatingTextIdCounter = 0;
  
  @override
  void initState() {
    super.initState();
    // Shake
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnimation = Tween<double>(begin: 0, end: 24).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeController);
    _shakeController.addStatusListener((status) {
       if (status == AnimationStatus.completed) _shakeController.reset();
    });

    // Idle (Breathing)
    _idleController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _idleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(CurvedAnimation(parent: _idleController, curve: Curves.easeInOut));
    _idleController.repeat(reverse: true); // Breathe in and out endlessly

    // Dash
    _dashController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _dashAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(_dashController);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectSocket();
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _shakeController.dispose();
    _dashController.dispose(); // Dispose dash
    _idleController.dispose(); // Dispose idle
    super.dispose();
  }

  // Asset Mapping Logic
  String _getAssetPath(String petType) {
    switch (petType.toLowerCase()) {
      case 'dog': 
        return "assets/images/characters/멜빵옷.png"; // Dog -> Overalls
      case 'cat': 
        return "assets/images/characters/공주옷.png"; // Cat -> Princess
      case 'banana':
        return "assets/images/characters/바나나옷.png"; // Banana -> Banana
      case 'ninja':
        return "assets/images/characters/닌자옷.png"; // Ninja -> Ninja
      default: 
        return "assets/images/characters/닌자옷.png"; // Default -> Ninja
    }
  }

  // HP Bar Color Logic (Smooth Transition)
  Color _getHpColor(double pct) {
    if (pct > 0.5) {
      return Color.lerp(Colors.yellow, Colors.green, (pct - 0.5) * 2)!;
    } else {
      return Color.lerp(Colors.red, Colors.yellow, pct * 2)!;
    }
  }

  void _triggerDamageEffect(int targetId) {
    if (targetId == _myId) {
      _myDamageOpacity = 0.6;
      _shakeController.forward(); // Shake self
    } else {
      _oppDamageOpacity = 0.6;
    }
    
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          if (targetId == _myId) _myDamageOpacity = 0.0;
          else _oppDamageOpacity = 0.0;
        });
      }
    });
  }

  void _showSkillInfo(String name, String type, Map<String, dynamic>? skill) {
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
       )
     );
  }

  void _showFloatingText(String text, bool isCrit, int targetId, {bool isHeal = false}) {
    if (!mounted) return;
    int id = _floatingTextIdCounter++;
    setState(() {
      _floatingTexts.add(FloatingTextItem(id: id, text: text, isCrit: isCrit, targetId: targetId, isHeal: isHeal));
    });

    // Auto remove after animation duration
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _floatingTexts.removeWhere((item) => item.id == id);
        });
      }
    });
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

  @override
  Widget build(BuildContext context) {
    final charProvider = Provider.of<CharProvider>(context);
    final myPetType = charProvider.currentPetType; 
    
    // Ensure 4 slots for grid
    List<Map<String, dynamic>?> displaySkills = List<Map<String, dynamic>?>.from(_mySkills);
    while (displaySkills.length < 4) {
      displaySkills.add(null);
    }
    if (displaySkills.length > 4) displaySkills = displaySkills.sublist(0, 4);

    return Scaffold(
      extendBodyBehindAppBar: true, // For fullscreen feel
      appBar: AppBar(
        title: const Text("BATTLE ARENA", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // 0. Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)], // Deep Space Blue to Cyan
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          
          // 1. Perspective: Opponent (Far / Top Right)
          Positioned(
            top: 100,
            right: 40,
            child: Transform.scale(
              scale: 0.8, // Make it look further away
              child: AnimatedBuilder(
                animation: _dashAnimation,
                builder: (context, child) {
                    // Check if Opponent is dashing
                    Offset dashOffset = (_attackerId == _opponentId && _opponentId != null) ? _dashAnimation.value : Offset.zero;
                    return Transform.translate(
                        offset: dashOffset, // Only dash, no shake for now (or add shake later)
                        child: child,
                    );
                },
                child: _buildCharacterObject(
                  name: _oppName, 
                  hp: _oppHp, 
                  maxHp: _oppMaxHp, 
                  petType: _oppPetType, 
                  isMe: false,
                  damageOpacity: _oppDamageOpacity,
                  isThinking: _opponentSelecting,
                  statuses: _oppStatuses // [New] Pass statuses
                ),
              ),
            ),
          ),
          
          // 2. Perspective: Me (Close / Bottom Left)
          Positioned(
            bottom: 320, // Moved up to avoid overlap with Skills Panel (height 300)
            left: 20,
            child: Transform.scale(
              scale: 1.1,
            child: AnimatedBuilder(
                animation: Listenable.merge([_shakeAnimation, _dashAnimation]),
                builder: (context, child) {
                    // Check if I am the one dashing
                    Offset dashOffset = (_attackerId == _myId) ? _dashAnimation.value : Offset.zero;
                    return Transform.translate(
                        offset: Offset(_shakeAnimation.value, 0) + dashOffset,
                        child: child,
                    );
                },
                child: _buildCharacterObject(
                  name: "YOU", 
                  hp: _myHp, 
                  maxHp: _myMaxHp, 
                  petType: myPetType, 
                  isMe: true,
                  damageOpacity: _myDamageOpacity,
                  customImagePath: charProvider.imagePath, // Use exact image from provider
                  statuses: _myStatuses // Status list
                ),
              ),
            ),
          ),
          
          // 3. Battle Log overlay (Floating Top Left)
          Positioned(
            top: 100,
            left: 20,
            width: 250,
            height: 200,
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                 return const LinearGradient(
                   begin: Alignment.topCenter,
                   end: Alignment.bottomCenter,
                   colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                   stops: [0.0, 0.1, 0.9, 1.0], // Fade top and bottom
                 ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                reverse: true, // Bubbles stack up
                itemCount: _battleLogs.length,
                itemBuilder: (context, index) {
                  return _buildLogBubble(_battleLogs[index]);
                },
              ),
            ),
          ),

          // 4. Fixed Skill Panel (Bottom)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
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
                           Text(_statusMessage, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Column(
                        children: [
                          SizedBox(
                            height: 80, // Fixed height for consistent look and fit
                            child: Row(
                              children: [
                                Expanded(child: _buildSkillButton(displaySkills[0])),
                                const SizedBox(width: 15),
                                Expanded(child: _buildSkillButton(displaySkills[1])),
                              ],
                            ),
                          ),
                          const SizedBox(height: 15),
                          SizedBox(
                            height: 80, // Fixed height for consistent look and fit
                            child: Row(
                              children: [
                                Expanded(child: _buildSkillButton(displaySkills[2])),
                                const SizedBox(width: 15),
                                Expanded(child: _buildSkillButton(displaySkills[3])),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // WAITING Overlay
          if (!_isMyTurn && !_isConnected) // Actually logic could be improved, but 'Waiting' banner is good
             Center(child: Container(
               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
               decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
               child: Text(_statusMessage, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
             )),
        ],
      ),
    );
  }

  // --- Widget Builders ---

  Widget _buildCharacterObject({
    required String name, 
    required int hp, 
    required int maxHp, 
    required String petType, 
    required bool isMe,
    double damageOpacity = 0.0,
    bool isThinking = false,
    String? customImagePath, // Optional direct path
    List<String> statuses = const [], // Pokemon-style statuses
  }) {
    // 3D-ish Stand with Shadow
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Floating HP Bar + Name
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54, 
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 1)
          ),
          child: Column(
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              if (isThinking) 
                 const Text("Thinking...", style: TextStyle(color: Colors.yellowAccent, fontSize: 10)),
              const SizedBox(height: 4),
              _buildHpBar(hp, maxHp),
              const SizedBox(height: 2),
              Text("$hp / $maxHp", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              if (statuses.isNotEmpty) ...[
                 const SizedBox(height: 4),
                 Row(
                   mainAxisSize: MainAxisSize.min,
                   children: statuses.map((s) => Container(
                     margin: const EdgeInsets.only(right: 2),
                     padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                     decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(4)),
                     child: Text(s, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                   )).toList()
                 )
              ]
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Character + Shadow
        Stack(
           alignment: Alignment.bottomCenter,
           children: [
             // Shadow
             Transform.translate(
               offset: const Offset(0, 5),
               child: Container(
                 width: 80, height: 20,
                 decoration: BoxDecoration(
                   color: Colors.black.withOpacity(0.3),
                   borderRadius: BorderRadius.circular(100), // Ellipse shadow
                   boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                 ),
               ),
             ),
             // Image
             ScaleTransition(
               scale: _idleAnimation,
               alignment: Alignment.bottomCenter,
               child: _buildCharImage(petType, damageOpacity, 160, customPath: customImagePath),
             ),
           ],
        )
      ],
    );
  }

  Widget _buildCharImage(String petType, double opacity, double size, {String? customPath}) {
    String imagePath = customPath ?? _getAssetPath(petType);
    return Stack(
      children: [
        Image.asset(imagePath, height: size, fit: BoxFit.contain),
        AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 100),
          child: Image.asset(imagePath, height: size, color: Colors.red, colorBlendMode: BlendMode.srcATop),
        )
      ],
    );
  }

  Widget _buildHpBar(int current, int max) {
    double pct = (max == 0) ? 0 : (current / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 80,
      height: 6,
      child: Stack(
        children: [
          Container(decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(3))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            width: 80 * pct,
            decoration: BoxDecoration(
              color: _getHpColor(pct),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogBubble(String log) {
    bool isDamage = log.contains("피해") || log.contains("damage");
    bool isCrit = log.contains("크리티컬");
    
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCrit ? Colors.amber[800]!.withOpacity(0.9) : (isDamage ? Colors.redAccent.withOpacity(0.8) : Colors.black54),
        borderRadius: BorderRadius.circular(15),
        border: isCrit ? Border.all(color: Colors.yellowAccent, width: 2) : null,
        boxShadow: isCrit ? [const BoxShadow(color: Colors.amber, blurRadius: 10)] : null,
      ),
      child: Text(
        log, 
        style: TextStyle(
            color: Colors.white, 
            fontSize: isCrit ? 16 : 12, 
            fontWeight: isCrit ? FontWeight.w900 : FontWeight.bold
        )
      ),
    );
      ),
    );
  }

  Widget _buildSkillButton(Map<String, dynamic>? skill) {
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

    // var skill = SKILL_DATA[skillId]; -> No longer used
    int skillId = skill['id'];
    String name = skill['name'] ?? "Unknown";
    String type = skill['type'] ?? "normal";
    Color typeColor = _getTypeColor(type);
    
    return GestureDetector(
      onLongPress: () => _showSkillInfo(name, type, skill),
      child: ElevatedButton(
        onPressed: (_isConnected && _isMyTurn) ? () => _sendMove(skillId) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: typeColor,
          elevation: 4,
          shadowColor: typeColor.withOpacity(0.3),
          padding: const EdgeInsets.all(0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: typeColor.withOpacity(0.5), width: 2)
          ),
        ),
        child: Stack(
          children: [
             // Background Icon watermark
             Positioned(
               right: -10, bottom: -10,
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
                     child: Text(type.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: typeColor)),
                   )
                 ],
               ),
             ),
          ],
        ),
      ),
    );
  }

  void _connectSocket() {
    final charProvider = Provider.of<CharProvider>(context, listen: false);
    final userChar = charProvider.character;
    
    if (userChar == null) {
      setState(() => _statusMessage = "Character not found.");
      return;
    }

    _myId = userChar.userId; // user_id (not char_id)
    // 임시 룸 ID: arena_1
    final String roomId = "arena_1";
    final String url = "${AppConfig.battleSocketUrl}/$roomId/$_myId";
    
    print("Connecting to Battle Socket: $url");
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;
      
      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          print("Socket Error: $error");
          setState(() {
            _statusMessage = "Connection Error";
            _isConnected = false;
          });
        },
        onDone: () {
          print("Socket Closed");
          setState(() {
            _statusMessage = "Disconnected";
            _isConnected = false;
          });
        },
      );
    } catch (e) {
      print("Connection Failed: $e");
      setState(() => _statusMessage = "Connection Failed");
    }
  }
  
  String _oppPetType = "dog"; // 기본값

  void _handleMessage(dynamic message) async {
    if (message is! String) return;
    
    final Map<String, dynamic> data = jsonDecode(message);
    final String type = data['type'];
    
    switch (type) {
      case "JOIN":
        setState(() {
           _addLog(data['message']);
        });
        break;
        
      case "BATTLE_START":
        final players = data['players'] as Map<String, dynamic>;
        players.forEach((key, value) {
          int uid = int.parse(key);
          if (uid != _myId) {
            setState(() {
              _opponentId = uid;
              _oppName = value['name'];
              _oppHp = value['hp'];
              _oppMaxHp = value['max_hp'];
              _oppPetType = value['pet_type'] ?? "dog"; // 펫 타입 설정
            });
          } else {
             final List<dynamic> skillList = value['skills'] ?? [];
             setState(() {
               _myHp = value['hp'];
               _myMaxHp = value['max_hp'];
               _mySkills = skillList.map((e) => e as Map<String, dynamic>).toList();
             });
          }
        });
        setState(() {
          _statusMessage = "Battle Started!";
          _opponentSelecting = false;
        });
        break;
        
      case "WAITING":
        setState(() {
          _statusMessage = data['message'];
          _isMyTurn = false; 
        });
        break;
        
      case "OPPONENT_SELECTING":
        setState(() {
          _opponentSelecting = true;
          _addLog("Opponent is thinking..."); // Shorten for UI
        });
        break;
        
      case "TURN_RESULT":
        bool isGameOver = data['is_game_over'] ?? false;
        
        // [New] State Sync Parse
        if (data['player_states'] != null) {
           final pStates = data['player_states'] as Map<String, dynamic>;
           pStates.forEach((uid, state) {
              int u = int.parse(uid);
              List<String> statuses = [];
              if (state['status'] != null) statuses.addAll(List<String>.from(state['status']));
              if (state['volatile'] != null) statuses.addAll(List<String>.from(state['volatile']));
              
              if (u == _myId) {
                  _myStatuses = statuses;
              } else {
                  _oppStatuses = statuses;
              }
           });
        }

        setState(() {
          _opponentSelecting = false;
          _isProcessingTurn = true; // [Fix] Set processing flag
        });
        
        await _processTurnResult(data['results']);
        
        if (mounted) {
           setState(() => _isProcessingTurn = false); // [Fix] Clear flag
           
           if (_pendingGameOverData != null) {
              // Process queued Game Over
              _handleGameOver(_pendingGameOverData!);
              _pendingGameOverData = null;
           } else if (!isGameOver) {
               // Only enable input if game is continuing
               setState(() => _isMyTurn = true);
           }
        }
        break;
        
      case "GAME_OVER":
        if (_isProcessingTurn) {
           // Queue if animating
           _pendingGameOverData = data;
        } else {
           _handleGameOver(data);
        }
        break;
        
      case "LEAVE":
        setState(() {
          _addLog(data['message']);
          _statusMessage = "Opponent Left";
        });
        break;
        
      case "ERROR":
        setState(() {
           _addLog("Error: ${data['message']}");
           _isMyTurn = true; // 에러 발생 시 다시 선택 가능하게 복구
        });
        break;
    }
  }

  // 데미지 효과 투명도 (0.0: 투명, 0.5: 붉은색)
  double _myDamageOpacity = 0.0;
  double _oppDamageOpacity = 0.0;

  Future<void> _processTurnResult(List<dynamic> results) async {
    for (var res in results) {
       // 각 턴 사이의 간격 (약간 줄임)
       await Future.delayed(const Duration(milliseconds: 600));
       
       String type = res['type'] ?? 'unknown';
       
       if (type == 'turn_event') {
          String eventType = res['event_type'];
          
          if (eventType == 'attack_start') {
             // 1. 공격 선언 및 이동 연출 (Attack Start)
             int attacker = res['attacker'];
             int moveId = res['move_id'];
             String moveType = res['move_type'] ?? 'normal'; // [New] Move Type
             String moveName = SKILL_DATA[moveId]?['name'] ?? "Unknown Move";
             String attackerName = (attacker == _myId) ? "You" : _oppName;
             
             setState(() => _addLog("$attackerName used $moveName!"));
             
             // [Fix] Animation Branching
             if (moveType == 'heal' || moveType == 'evade' || moveType == 'stat_change') {
                 // Self Buff Animation (No Dash)
                 // Simply wait or show a scale effect
                 await Future.delayed(const Duration(milliseconds: 500));
             } else {
                 // Attack Dash Animation
                 setState(() => _attackerId = attacker);
                 
                 // Define Dash Tween based on attacker
                 if (attacker == _myId) {
                   _dashAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(50, -50)).animate(CurvedAnimation(parent: _dashController, curve: Curves.easeInOut));
                 } else {
                   _dashAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(-50, 50)).animate(CurvedAnimation(parent: _dashController, curve: Curves.easeInOut));
                 }
                 
                 if (attacker == _myId) {
                    await _dashController.forward();
                    await Future.delayed(const Duration(milliseconds: 100));
                    await _dashController.reverse();
                 } else {
                    await Future.delayed(const Duration(milliseconds: 400));
                 }
             }
             
          } else if (eventType == 'hit_result') {
             // 2. 명중 결과 판정 (Hit/Miss)
             String result = res['result']; // 'hit' or 'miss'
             
             if (result == 'miss') {
                 // [New] Miss Floating Text
                 int defenderId = res['defender'] ?? (_attackerId == _myId ? _opponentId : _myId);
                 if (defenderId != null) _showFloatingText("MISS", false, defenderId);

                 setState(() => _addLog("공격이 빗나갔습니다!"));
                 await Future.delayed(const Duration(milliseconds: 500));
             } else {
                 bool isCrit = res['is_critical'] ?? false;
                 if (isCrit) {
                     // [New] Crit Text
                     int defenderId = res['defender'] ?? (_attackerId == _myId ? _opponentId : _myId); 
                     if (defenderId != null) _showFloatingText("CRITICAL!", true, defenderId);

                     setState(() => _addLog("크리티컬 히트!!!"));
                     await Future.delayed(const Duration(milliseconds: 300));
                 }
             }

          } else if (eventType == 'damage_apply') {
             // 3. 데미지 적용 (Damage Apply)
             int target = res['target'];
             int damage = res['damage'];
             
             if (damage > 0) {
                 if (mounted) {
                   setState(() {
                     _triggerDamageEffect(target); // Shake + Red Overlay
                     _updateHp(target, damage); // HP Bar Animation
                     
                     // [New] Damage Floating Text
                     _showFloatingText(damage.toString(), false, target);

                      if (target == _myId) {
                        _addLog("앗! $damage의 피해를 입었습니다... 😭");
                      } else {
                        _addLog("나이스! $_oppName에게 $damage의 피해를 입혔습니다! 💥");
                      }
                   });
                 }
                 // 피격 연출 및 HP 애니메이션 대기
                 await Future.delayed(const Duration(milliseconds: 600));
             }

          } else if (eventType == 'effect_apply' || eventType == 'stat_change' || eventType == 'status_ailment' || eventType == 'heal') {
             // 4. 부가 효과 (Effect / Stat / Status / Heal)
             String msg = res['message'];
             if (activeStr(msg)) {
                setState(() => _addLog(msg));
             }
             
             if (eventType == 'heal') {
                 // [Fix] Target Resolution
                 var targetRaw = res['target'];
                 int safeMyId = _myId ?? 0; // Ensure non-null int
                 int targetId = safeMyId; 

                 if (targetRaw == 'self') {
                     targetId = (res['attacker'] as int?) ?? safeMyId;
                 } else if (targetRaw == 'enemy') {
                     targetId = (res['defender'] as int?) ?? _opponentId ?? safeMyId;
                 } else if (targetRaw is int) {
                     targetId = targetRaw;
                 }

                 int healAmount = res['value'] ?? 0;
                 
                 // HP Bar Increase Animation
                 if (targetId == _myId) {
                    setState(() {
                         _myHp = (_myHp + healAmount).clamp(0, _myMaxHp);
                         _showFloatingText("+$healAmount", false, targetId, isHeal: true);
                         _addLog("체력이 $healAmount 회복되었습니다! ✨");
                    });
                 } else {
                    setState(() {
                         _oppHp = (_oppHp + healAmount).clamp(0, _oppMaxHp);
                         _showFloatingText("+$healAmount", false, targetId, isHeal: true);
                    });
                 }
                 await Future.delayed(const Duration(milliseconds: 500));
             }
             await Future.delayed(const Duration(milliseconds: 400));

          } else if (eventType == 'immobile') {
             // 행동 불가
             String msg = res['message'];
             setState(() => _addLog(msg));
             await Future.delayed(const Duration(milliseconds: 800));
             
          } else if (eventType == 'status_damage' || eventType == 'status_recover') {
             // 턴 종료 시 상태 데미지
             int target = res['target'];
             int damage = res['damage']; 
             String msg = res['message'];
             
             setState(() => _addLog(msg));
             
             if (damage > 0) {
                if (mounted) {
                   setState(() {
                      _triggerDamageEffect(target);
                      _updateHp(target, damage); 
                   });
                }
                await Future.delayed(const Duration(milliseconds: 500));
             }
          }
       }
    }
  }

  bool activeStr(String? s) => s != null && s.isNotEmpty;

  void _updateHp(int userId, int damage) {
    if (userId == _myId) {
      _myHp = (_myHp - damage).clamp(0, _myMaxHp);
    } else {
      _oppHp = (_oppHp - damage).clamp(0, _oppMaxHp);
    }
  }

  void _addLog(String msg) {
    setState(() {
      _battleLogs.insert(0, msg);
      if (_battleLogs.length > 50) _battleLogs.removeLast();
    });
  }

  void _sendMove(int moveId) {
    if (!_isConnected || !_isMyTurn) return;
    _isMyTurn = false; // 중복 클릭 방지
    _channel!.sink.add(jsonEncode({
      "action": "select_move",
      "move_id": moveId
    }));
  }
  
  void _handleGameOver(Map<String, dynamic> data) {
      String result = data['result']; // WIN or LOSE
      bool iWon = (result == "WIN");
      
      setState(() {
         _statusMessage = iWon ? "Victory! 🏆" : "Defeat... 💀";
         _addLog("Game Over: $_statusMessage");
      });

      if (iWon && data['reward'] != null) {
        _showRewardDialog(data['reward']);
      } else {
        _showGameOverDialog(iWon);
      }
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

class FloatingTextItem {
  final int id;
  final String text;
  final bool isCrit;
  final bool isHeal;
  final int targetId; 

  FloatingTextItem({
    required this.id, 
    required this.text, 
    required this.isCrit, 
    required this.targetId,
    this.isHeal = false,
  });
}
