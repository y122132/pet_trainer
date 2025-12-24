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

class _BattlePageState extends State<BattlePage> with SingleTickerProviderStateMixin {
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
  List<String> _myStatuses = ["ATK UP", "SPD UP"]; // Example Dummy Statuses for UI Testing

  // Animation Controllers
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  
  @override
  void initState() {
    super.initState();
    // Shake Animation Setup
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnimation = Tween<double>(begin: 0, end: 10).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeController);
    
    _shakeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _shakeController.reset();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectSocket();
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _shakeController.dispose();
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
             Text(skill?['description'] ?? "No description available.", style: const TextStyle(color: Colors.black54)),
           ],
         ),
         actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE"))],
       )
     );
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
    
    List<int> skills = charProvider.character?.learnedSkills ?? [1]; 
    if (skills.isEmpty) skills = [1]; 
    
    // Ensure 4 slots for grid
    List<int?> displaySkills = List<int?>.from(skills);
    while (displaySkills.length < 4) {
      displaySkills.add(null);
    }
    if (displaySkills.length > 4) displaySkills = displaySkills.sublist(0, 4);
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
              child: _buildCharacterObject(
                name: _oppName, 
                hp: _oppHp, 
                maxHp: _oppMaxHp, 
                petType: _oppPetType, 
                isMe: false,
                damageOpacity: _oppDamageOpacity,
                isThinking: _opponentSelecting
              ),
            ),
          ),
          
          // 2. Perspective: Me (Close / Bottom Left)
          Positioned(
            bottom: 230,
            left: 20,
            child: Transform.scale(
              scale: 1.1,
              child: AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) => Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                ),
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
              height: 240, // Increased height slightly
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
              ),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600), // Layout constraint for PC
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
                      Expanded(
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.8, // Squarer aspect ratio (User Request)
                            crossAxisSpacing: 15,
                            mainAxisSpacing: 15,
                          ),
                          itemCount: 4, // Fixed 4 slots
                          itemBuilder: (context, index) {
                            return _buildSkillButton(displaySkills[index]);
                          },
                        ),
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
             _buildCharImage(petType, damageOpacity, 160, customPath: customImagePath),
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
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(15), 
          topRight: Radius.circular(15), 
          bottomRight: Radius.circular(15), 
          bottomLeft: Radius.circular(4)
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2))],
      ),
      child: Text(
        log, 
        style: TextStyle(
          fontSize: 12, 
          color: isDamage ? Colors.red[800] : Colors.black87,
          fontWeight: isCrit ? FontWeight.bold : FontWeight.w500
        )
      ),
    );
  }

  Widget _buildSkillButton(int? skillId) {
    // Empty Slot
    if (skillId == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Center(child: Icon(Icons.block, color: Colors.grey, size: 20)),
      );
    }

    var skill = SKILL_DATA[skillId];
    String name = skill?['name'] ?? "Unknown";
    String type = skill?['type'] ?? "normal";
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
             setState(() {
               _myHp = value['hp'];
               _myMaxHp = value['max_hp'];
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
        setState(() {
          _opponentSelecting = false;
          // _isMyTurn = true; // 연출 종료 후 true로 변경
        });
        await _processTurnResult(data['results']);
        if (mounted) {
           setState(() {
             _isMyTurn = true; 
           });
        }
        break;
        
      case "GAME_OVER":
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
       // 각 턴 사이의 간격
       await Future.delayed(const Duration(milliseconds: 800));
       
       String type = res['type'] ?? 'unknown';
       
       if (type == 'turn_event') {
          String eventType = res['event_type'];
          
          if (eventType == 'attack') {
             // 1. 공격 선언 (로그)
             int attacker = res['attacker'];
             int defender = res['defender'];
             int moveId = res['move_id'];
             String moveName = SKILL_DATA[moveId]?['name'] ?? "Unknown Move";
             String attackerName = (attacker == _myId) ? "You" : _oppName;
             
             setState(() => _addLog("$attackerName used $moveName!"));
             
             // 2. 공격 연출 (잠시 대기 or 애니메이션 트리거)
             await Future.delayed(const Duration(milliseconds: 500));
             
             // 3. 데미지 및 피격 연출
             int damage = res['damage'];
             bool isCrit = res['is_critical'];
             int defenderHp = res['defender_hp']; // 서버에서 계산된 최종 체력
             
             if (damage > 0) {
                if (mounted) {
                  setState(() {
                    _triggerDamageEffect(defender); // 흔들림 + 붉은 효과
                    _updateHp(defender, damage); // HP 바 감소 (애니메이션 적용됨)
                    
                    String dmgLog = "Dealt $damage damage!";
                    if (isCrit) dmgLog += " (Critical!)";
                    _addLog(dmgLog);
                  });
                }
                // 피격 연출 시간 대기
                await Future.delayed(const Duration(milliseconds: 600));
             } else {
                setState(() => _addLog("It had no effect..."));
                await Future.delayed(const Duration(milliseconds: 500));
             }
             
             // 4. 부가 효과 (Effects)
             List<dynamic> effects = res['effects'] ?? [];
             for (var effect in effects) {
                String effMsg = effect['message'] ?? "";
                if (activeStr(effMsg)) {
                   setState(() => _addLog(effMsg));
                   await Future.delayed(const Duration(milliseconds: 400));
                }
             }

          } else if (eventType == 'immobile') {
             // 행동 불가
             String msg = res['message'];
             setState(() => _addLog(msg));
             await Future.delayed(const Duration(milliseconds: 800));
             
          } else if (eventType == 'status_damage' || eventType == 'status_recover') {
             // 상태 이상 데미지 / 회복
             int target = res['target'];
             int damage = res['damage']; // 회복일 경우 0일 수 있음 (현재 로직상)
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
             } else if (eventType == 'status_recover') {
                // 회복 연출 등 (필요 시 추가)
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
