import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pet_trainer_frontend/config.dart';
import 'package:pet_trainer_frontend/models/battle_state.dart';
import 'package:pet_trainer_frontend/models/skill_data.dart'; // Direct access to local Data

class BattleController extends ChangeNotifier {
  // State
  BattleUIState _state = BattleUIState();
  BattleUIState get state => _state;

  // Event Stream (for View animations)
  final _eventController = StreamController<BattleEvent>.broadcast();
  Stream<BattleEvent> get eventStream => _eventController.stream;

  // Socket
  WebSocketChannel? _channel;
  int? _myId;
  int? _opponentId;
  
  // Game Over Queue
  bool _isProcessingTurn = false;
  Map<String, dynamic>? _pendingGameOverData;

  @override
  void dispose() {
    _channel?.sink.close();
    _eventController.close();
    super.dispose();
  }

  // --- ACTIONS ---

  void connect(int userId) {
    if (_state.isConnected) return;
    
    _myId = userId;
    _state = _state.copyWith(statusMessage: "Connecting to server...");
    notifyListeners();

    final String roomId = "arena_1";
    final String url = "${AppConfig.battleSocketUrl}/$roomId/$_myId";
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _state = _state.copyWith(isConnected: true, statusMessage: "Connected!");
      notifyListeners();

      _channel!.stream.listen(_handleMessage, 
        onError: (e) => _updateStatus("Connection Error", isConnected: false),
        onDone: () => _updateStatus("Disconnected", isConnected: false)
      );
    } catch (e) {
      _updateStatus("Connection Failed", isConnected: false);
    }
  }

  void sendMove(int moveId) {
    if (!_state.isConnected || !_state.isMyTurn) return;
    
    _state = _state.copyWith(isMyTurn: false); // Lock input
    notifyListeners();

    _channel!.sink.add(jsonEncode({
      "action": "select_move",
      "move_id": moveId
    }));
  }

  // --- INTERNALS ---

  void _updateStatus(String msg, {bool? isConnected}) {
    _state = _state.copyWith(
      statusMessage: msg, 
      isConnected: isConnected ?? _state.isConnected
    );
    notifyListeners();
  }
  
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

    // [Socket Event Flow]
    // 서버로부터 오는 메시지를 처리하는 중앙 라우터입니다.
    switch (type) {
      case "JOIN":
        // 상대방 입장 알림
        _addLog(data['message']);
        break;
        
      case "BATTLE_START":
        // [초기화] 캐릭터 데이터(Hp, Name) 세팅 및 턴 시작
        _handleBattleStart(data);
        break;
        
      case "WAITING":
        // 턴 대기 메시지 (예: "Waiting for opponent...")
        _state = _state.copyWith(
          statusMessage: data['message'],
          isMyTurn: false
        );
        notifyListeners();
        break;
        
      case "OPPONENT_SELECTING":
        // [UI] 상대방 생각 중 말풍선 표시
        _state = _state.copyWith(isOpponentThinking: true);
        _addLog("Opponent is thinking...");
        notifyListeners();
        break;
        
      case "TURN_RESULT":
        // [CORE] 턴 결과 처리 (가장 중요)
        // 1. 서버 상태 동기화 (_parseStateSync): 상태이상/버프 즉시 반영
        // 2. 애니메이션 재생 (_processTurnResult): 공격/히트/데미지 순차 재생 (Delay)
        // 3. 턴 제어: 애니메이션 종료 후 내 턴 활성화
        
        bool isGameOver = data['is_game_over'] ?? false;
        // 1. 상태 동기화 데이터 임시 저장 (즉시 적용 X)
        // 나중에 _parseStateSync를 호출하여 최종 상태를 맞춥니다.
        final pendingStates = data['player_states'];

        _state = _state.copyWith(isOpponentThinking: false);
        _isProcessingTurn = true;
        notifyListeners();

        // 2. 비동기 애니메이션 시퀀스 실행 (약 3~5초 소요)
        // 이 과정에서 _handleHpChange가 호출되어 시각적으로 HP가 감소합니다.
        await _processTurnResult(data['results']);

        // 3. 애니메이션 종료 후 최종 상태 동기화 (HP 오차 보정, 상태이상 적용 등)
        _parseStateSync(pendingStates);
        
        _isProcessingTurn = false;
        
        // Handle Queued Game Over logic
        if (_pendingGameOverData != null) {
           _handleGameOver(_pendingGameOverData!);
           _pendingGameOverData = null;
        } else if (!isGameOver) {
           _state = _state.copyWith(isMyTurn: true); 
           notifyListeners();
        }
        break;
        
      case "GAME_OVER":
        // 승리/패배 다이얼로그 출력 (보상 처리 포함)
        if (_isProcessingTurn) {
          _pendingGameOverData = data;
        } else {
          _handleGameOver(data);
        }
        break;
        
      case "LEAVE":
        _addLog(data['message']);
        _updateStatus("Opponent Left");
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
         );
       } else {
         final skills = (value['skills'] ?? []).map<Map<String,dynamic>>((e) => e as Map<String,dynamic>).toList();
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
      isMyTurn: true // Enable input for new turn
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
           _state = _state.copyWith(myStatuses: statuses);
        } else {
           _state = _state.copyWith(oppStatuses: statuses);
        }
     });
     // Note: We don't notify here, we might do it after animation or immediately. 
     // For now, doing it immediately is fine but ideally syncs with animation frame.
  }

  Future<void> _processTurnResult(List<dynamic> results) async {
    for (var res in results) {
       await Future.delayed(const Duration(milliseconds: 600));
       
       String type = res['type'] ?? 'unknown';
       if (type == 'turn_event') {
          String eventType = res['event_type'];
          
          if (eventType == 'attack_start') {
              int attacker = res['attacker'];
              int moveId = res['move_id'];
              String moveName = SKILL_DATA[moveId]?['name'] ?? "Unknown Move";
              String moveType = res['move_type'] ?? 'normal';
              String attackerName = (attacker == _myId) ? "You" : _state.oppName;

              _addLog("$attackerName used $moveName!");
              
              if (moveType == 'heal' || moveType == 'evade' || moveType == 'stat_change') {
                 // Buff Animation
              } else {
                 // Dash Animation Trigger
                 _eventController.add(BattleEvent(type: BattleEventType.attack, actorId: attacker));
                 await Future.delayed(const Duration(milliseconds: 500));
              }

          } else if (eventType == 'hit_result') {
              String result = res['result'];
              if (result == 'miss') {
                 int target = res['defender'] ?? (_opponentId); // Fallback
                 _eventController.add(BattleEvent(type: BattleEventType.miss, targetId: target));
                 _addLog("Missed!");
              } else if (res['is_critical'] == true) {
                 int target = res['defender'] ?? (_opponentId);
                 _eventController.add(BattleEvent(type: BattleEventType.crit, targetId: target));
                 _addLog("CRITICAL HIT!");
              }
              await Future.delayed(const Duration(milliseconds: 500));

          } else if (eventType == 'damage_apply') {
              int target = res['target'];
              int damage = res['damage'];
              
              if (damage > 0) {
                 // Trigger Shake
                 _eventController.add(BattleEvent(type: BattleEventType.shake, targetId: target));
                 
                 // Trigger Floating Text
                 _eventController.add(BattleEvent(type: BattleEventType.damage, targetId: target, value: damage));

                 // Update HP Logic
                 _handleHpChange(target, -damage);

                 if (target == _myId) {
                   _addLog("Ouch! Took $damage damage!");
                 } else {
                   _addLog("Hit! Dealt $damage damage!");
                 }
                 await Future.delayed(const Duration(milliseconds: 600));
              }

          } else if (eventType == 'heal') {
              int target = _resolveTarget(res);
              int amount = res['value'] ?? 0;
              
              _handleHpChange(target, amount);
              _eventController.add(BattleEvent(type: BattleEventType.heal, targetId: target, value: amount));
              _addLog("Recovered $amount HP!");
              await Future.delayed(const Duration(milliseconds: 500));

          } else if (res['message'] != null) {
              _addLog(res['message']);
          }
       }
    }
  }

  int _resolveTarget(Map<String, dynamic> res) {
      // Logic to resolve 'self'/'enemy' to ID
      var targetRaw = res['target'];
      int safeMyId = _myId ?? 0;
      if (targetRaw == 'self') return (res['attacker'] as int?) ?? safeMyId;
      if (targetRaw == 'enemy') return (res['defender'] as int?) ?? _opponentId ?? safeMyId;
      if (targetRaw is int) return targetRaw;
      return safeMyId;
  }

  void _handleHpChange(int target, int delta) {
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
      _updateStatus(iWon ? "Victory! 🏆" : "Defeat... 💀");
      
      if (iWon) {
         _eventController.add(BattleEvent(type: BattleEventType.victory, message: jsonEncode(data['reward'])));
      } else {
         _eventController.add(BattleEvent(type: BattleEventType.defeat));
      }
  }
}
