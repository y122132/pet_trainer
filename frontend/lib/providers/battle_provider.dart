import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart'; // [New]
import 'package:pet_trainer_frontend/models/battle_state.dart';
import 'package:pet_trainer_frontend/services/battle_socket_service.dart';
import 'package:pet_trainer_frontend/game/battle_animation_manager.dart';

class BattleProvider extends ChangeNotifier {
  // State
  BattleUIState _state = BattleUIState();
  BattleUIState get state => _state;

  // Services
  final BattleSocketService _socketService = BattleSocketService();
  late BattleAnimationManager _animationManager;
  final Map<String, dynamic> _skillData = {}; // Mutable container

  // Event Stream (Forward from AnimationManager)
  Stream<BattleEvent> get eventStream => _animationManager.eventStream;

  // Queue
  bool _isProcessingTurn = false;
  Map<String, dynamic>? _pendingGameOverData;

  int? _myId;
  int? _opponentId;

  BattleProvider() {
    // Init Manager with reference to mutable map
    _animationManager = BattleAnimationManager(skillData: _skillData);
    _loadSkillData();
  }

  Future<void> _loadSkillData() async {
    try {
      final String jsonStr = await rootBundle.loadString('assets/data/skills.json');
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      _skillData.addAll(data);
      debugPrint("BattleProvider: Loaded ${_skillData.length} skills.");
    } catch (e) {
      debugPrint("BattleProvider: Failed to load skills: $e");
    }
  }

  @override
  void dispose() {
    _socketService.dispose();
    _animationManager.dispose();
    super.dispose();
  }

  // --- ACTIONS ---

  void connect(int userId) {
    if (_state.isConnected) return;
    
    _myId = userId;
    _state = _state.copyWith(statusMessage: "Connecting to server...");
    notifyListeners();

    // Setup Socket Listeners
    _socketService.setConnectionListener((isConnected) {
       _state = _state.copyWith(
          isConnected: isConnected,
          statusMessage: isConnected ? "Connected!" : "Connection lost. Reconnecting..."
       );
       notifyListeners();
    });

    _socketService.messageStream.listen(_handleMessage);

    final String roomId = _presetRoomId ?? "arena_1"; 
    // AppConfig.battleSocketUrl 뒤에 실제 유저 ID가 붙어 경로가 구성됨
    // [Fix] Token 추가
    final authService = AuthService(); // Need import
    authService.getToken().then((token) {
        if (token != null) {
            final String url = "${AppConfig.battleSocketUrl}/$roomId/$_myId?token=$token";
            _socketService.connect(url);
        } else {
            debugPrint("BattleProvider: No token found, cannot connect.");
        }
    });
  }

  void sendMove(int moveId) {
    if (!_state.isConnected || !_state.isMyTurn) return;
    
    // [Temp] Client-side Simulation for new skills
    if (moveId >= 300) {
        _simulateLocalTurn(moveId);
        return;
    }

    _state = _state.copyWith(isMyTurn: false); // Lock input
    notifyListeners();

    _socketService.sendMessage({
      "action": "select_move",
      "move_id": moveId
    });
  }

  // [Temp] Simulate Turn Locally
  void _simulateLocalTurn(int moveId) async {
      _state = _state.copyWith(isMyTurn: false);
      notifyListeners();

      // 1. My Attack
      final skill = _skillData[moveId.toString()] ?? _skillData[moveId] ?? {};
      String moveName = skill['name'] ?? 'Unknown';
      int power = skill['power'] ?? 0;
      
      // Stat Scaling Calculation (Mock)
      // Since we don't have CharProvider here, we assume default stats or fetch if possible.
      // Ideally pass stats in connect(), but for now use defaults.
      int strength = 20; // Default
      int intelligence = 20; // Default
      int happiness = 20; // Default
      
      double factor = (skill['scaling_factor'] ?? 1.0).toDouble();
      String statType = skill['scaling_stat'] ?? 'strength';
      
      int scalingDamage = 0;
      if (statType == 'strength') scalingDamage = (strength * factor).round();
      else if (statType == 'intelligence') scalingDamage = (intelligence * factor).round();
      else if (statType == 'happiness') scalingDamage = (happiness * factor).round();

      int finalDamage = power + scalingDamage;
      String type = skill['type'] ?? 'normal';

      _addLog("You used $moveName!");
      
      if (type == 'heal') {
           int healAmount = (finalDamage * 1.5).round(); // Heal is stronger
           _handleHpChange(_myId!, healAmount);
           _animationManager.emitEvent(BattleEvent(type: BattleEventType.heal, targetId: _myId, value: healAmount));
           _addLog("Recovered $healAmount HP!");
      } else {
           // Attack
           _animationManager.emitEvent(BattleEvent(type: BattleEventType.attack, actorId: _myId));
           await Future.delayed(const Duration(milliseconds: 500));
           
           _animationManager.emitEvent(BattleEvent(type: BattleEventType.shake, targetId: _opponentId));
           _animationManager.emitEvent(BattleEvent(type: BattleEventType.damage, targetId: _opponentId, value: finalDamage));
           _handleHpChange(_opponentId!, -finalDamage);
           
           _addLog("Hit! Dealt $finalDamage damage! ($statType x$factor)");
      }

      await Future.delayed(const Duration(milliseconds: 1000));

      // 2. Opponent Turn (Mock)
      if (_state.oppHp > 0) {
         _addLog("${_state.oppName} attacks!");
         await Future.delayed(const Duration(milliseconds: 500));
         
         int oppDmg = 15;
         _animationManager.emitEvent(BattleEvent(type: BattleEventType.attack, actorId: _opponentId));
         await Future.delayed(const Duration(milliseconds: 500));
         
         _animationManager.emitEvent(BattleEvent(type: BattleEventType.shake, targetId: _myId));
         _animationManager.emitEvent(BattleEvent(type: BattleEventType.damage, targetId: _myId, value: oppDmg));
         _handleHpChange(_myId!, -oppDmg);
         _addLog("Took $oppDmg damage!");
      }

      // 3. End Turn
      if (_state.myHp <= 0) {
          _handleGameOver({'result': 'LOSE'});
      } else if (_state.oppHp <= 0) {
          _handleGameOver({'result': 'WIN', 'reward': {'exp_gained': 100, 'level_up': false, 'new_skills': []}});
      } else {
          _state = _state.copyWith(isMyTurn: true);
          notifyListeners();
      }
  }

  // [New] For Matchmaking
  String? _presetRoomId;
  void setRoomId(String roomId) {
    _presetRoomId = roomId;
  }

  // --- INTERNALS ---

  void _addLog(String msg) {
    List<String> newLogs = List.from(_state.logs)..insert(0, msg);
    if (newLogs.length > 50) newLogs.removeLast();
    _state = _state.copyWith(logs: newLogs);
    notifyListeners();
  }

  void _handleMessage(dynamic message) async {
    if (message is! String) return;
    final data = jsonDecode(message);
    final String type = data['type'];

    switch (type) {
      case "JOIN":
        _addLog(data['message']);
        break;
        
      case "BATTLE_START":
        _handleBattleStart(data);
        break;
        
      case "WAITING":
        _state = _state.copyWith(
          statusMessage: data['message'],
          isMyTurn: false
        );
        notifyListeners();
        break;
        
      case "OPPONENT_SELECTING":
        _state = _state.copyWith(isOpponentThinking: true);
        _addLog("Opponent is thinking...");
        notifyListeners();
        break;
        
      case "TURN_RESULT":
        bool isGameOver = data['is_game_over'] ?? false;
        final pendingStates = data['player_states'];

        _state = _state.copyWith(isOpponentThinking: false);
        _isProcessingTurn = true;
        notifyListeners();

        // Delegate to Animation Manager
        await _animationManager.processTurnResult(
          data['results'], 
          _myId!, 
          _state.oppName,
          _opponentId,
          _addLog, 
          _handleHpChange
        );

        // Sync State
        _parseStateSync(pendingStates);
        
        _isProcessingTurn = false;
        
        if (_pendingGameOverData != null) {
           _handleGameOver(_pendingGameOverData!);
           _pendingGameOverData = null;
        } else if (!isGameOver) {
           _state = _state.copyWith(isMyTurn: true); 
           notifyListeners();
        }
        break;
        
      case "GAME_OVER":
        if (_isProcessingTurn) {
          _pendingGameOverData = data;
        } else {
          _handleGameOver(data);
        }
        break;
        
      case "LEAVE":
        _addLog(data['message']);
        _state = _state.copyWith(statusMessage: "Opponent Left");
        notifyListeners();
        break;
        
      case "ERROR":
        _addLog("Error: ${data['message']}");
        _state = _state.copyWith(isMyTurn: true); // Recover Input
        notifyListeners();
        break;
    }
  }

  void _handleBattleStart(Map<String, dynamic> data) {
    final players = data['players'] as Map<String, dynamic>;
    players.forEach((key, value) {
       int uid = int.parse(key);
       if (uid != _myId) {
         _opponentId = uid;
         _state = _state.copyWith(
           oppName: value['name'],
           oppHp: value['hp'],
           oppMaxHp: value['max_hp'],
           oppPetType: value['pet_type'] ?? 'dog',
           oppFrontUrl: value['front_url'],
           oppBackUrl: value['back_url'],
           oppSideUrl: value['side_url'],
           oppFaceUrl: value['face_url'],
         );
       } else {
         final skills = (value['skills'] ?? []).map<Map<String,dynamic>>((e) => e as Map<String,dynamic>).toList();

           // [Temp] Inject new skills for testing (Force Add)
           final newSkillIds = ["301", "302", "303"];
           for (var id in newSkillIds) {
               if (_skillData.containsKey(id)) {
                   var s = Map<String, dynamic>.from(_skillData[id]);
                   s['id'] = int.parse(id); 
                   s['pp'] = 20; 
                   s['max_pp'] = 20;
                   skills.add(s);
               }
           }

         _state = _state.copyWith(
            myHp: value['hp'],
            myMaxHp: value['max_hp'],
            mySkills: skills
         );
       }
    });

    _state = _state.copyWith(
      statusMessage: "Battle Started!",
      isOpponentThinking: false,
      isMyTurn: true 
    );
    notifyListeners();
  }

  void _parseStateSync(dynamic playerStates) {
     if (playerStates == null) return;
     final pStates = playerStates as Map<String, dynamic>;
     pStates.forEach((uid, state) {
        int u = int.parse(uid);
        List<String> statuses = [];
        if (state['status'] != null) statuses.addAll(List<String>.from(state['status']));
        if (state['volatile'] != null) statuses.addAll(List<String>.from(state['volatile']));
        
        if (u == _myId) {
           List<Map<String, dynamic>> updatedSkills = List.from(_state.mySkills);
           
           if (state['pp'] != null) {
              final ppMap = state['pp']; 
              updatedSkills = updatedSkills.map((s) {
                 final newS = Map<String, dynamic>.from(s);
                 final sid = newS['id'].toString();
                 if (ppMap[sid] != null) {
                    newS['pp'] = ppMap[sid];
                 }
                 return newS;
              }).toList();
           }

            debugPrint("[BattleProvider] Syncing MyHP: ${_state.myHp} -> ${state['hp']}");
            _state = _state.copyWith(
               myStatuses: statuses,
               mySkills: updatedSkills,
               myHp: state['hp']
            );
        } else {
            debugPrint("[BattleProvider] Syncing OppHP: ${_state.oppHp} -> ${state['hp']}");
            _state = _state.copyWith(
                oppStatuses: statuses,
                oppHp: state['hp']
            );
        }
     });
  }

  void _handleHpChange(int target, int delta) {
      debugPrint("[BattleProvider] _handleHpChange: Target $target, Delta $delta, Current MyHP ${_state.myHp}");
      if (target == _myId) {
         int newHp = (_state.myHp + delta).clamp(0, _state.myMaxHp);
         _state = _state.copyWith(myHp: newHp);
      } else {
         int newHp = (_state.oppHp + delta).clamp(0, _state.oppMaxHp);
         _state = _state.copyWith(oppHp: newHp);
      }
      notifyListeners();
  }

  void _handleGameOver(Map<String, dynamic> data) {
      String result = data['result']; 
      bool iWon = (result == "WIN");
      
      _state = _state.copyWith(statusMessage: iWon ? "Victory! 🏆" : "Defeat... 💀");
      notifyListeners();

      if (iWon) {
         _animationManager.emitEvent(BattleEvent(type: BattleEventType.victory, message: jsonEncode(data['reward'])));
      } else {
         _animationManager.emitEvent(BattleEvent(type: BattleEventType.defeat));
      }
  }
}
