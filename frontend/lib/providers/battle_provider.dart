import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart';
import 'package:pet_trainer_frontend/models/battle_state.dart';
import 'package:pet_trainer_frontend/services/battle_socket_service.dart';
import 'package:pet_trainer_frontend/game/battle_animation_manager.dart';

class BattleProvider extends ChangeNotifier {
  // 1. [상태 관리 변수]
  BattleUIState _state = BattleUIState();
  final Map<String, dynamic> _skillData = {};
  
  // 2. [서비스 클래스]
  final BattleSocketService _socketService = BattleSocketService();
  final AuthService _authService = AuthService();
  late BattleAnimationManager _animationManager;

  // 3. [구독 및 제어 변수]
  StreamSubscription? _socketSubscription;
  bool _isDisposed = false;
  bool _isProcessingTurn = false;
  int? _myId;
  int? _opponentId;
  String? _presetRoomId;
  Map<String, dynamic>? _pendingGameOverData;

  // Getters
  BattleUIState get state => _state;
  Stream<BattleEvent> get eventStream => _animationManager.eventStream;
  Map<String, dynamic> get skillData => _skillData;

  BattleProvider() {
    _animationManager = BattleAnimationManager(skillData: _skillData);
    _loadSkillData();
  }

  // --- PUBLIC METHODS ---

  void setRoomId(String roomId) => _presetRoomId = roomId;

  void connect(int userId) {
    if (_state.isConnected || _isDisposed) return;
    
    _myId = userId;
    _updateStatus("서버 연결 중...");

    // 연결 상태 모니터링
    _socketService.setConnectionListener((isConnected) {
       _state = _state.copyWith(
          isConnected: isConnected,
          statusMessage: isConnected ? "연결됨!" : "연결 끊김. 재연결 시도 중..."
       );
       notifyListeners();
    });

    // 소켓 구독 (중복 방지)
    _socketSubscription?.cancel();
    _socketSubscription = _socketService.messageStream.listen(_handleMessage);

    final String roomId = _presetRoomId ?? "arena_1"; 
    
    _authService.getToken().then((token) {
        if (token != null && !_isDisposed) {
            final String url = "${AppConfig.battleSocketUrl}/$roomId/$_myId?token=$token";
            _socketService.connect(url);
        }
    });
  }

  void sendMove(int moveId) {
    if (!_state.isConnected || !_state.isMyTurn) return;
    
    _state = _state.copyWith(isMyTurn: false);
    notifyListeners();

    _socketService.sendMessage({
      "action": "select_move",
      "move_id": moveId
    });
  }

  @override
  void dispose() {
    _isDisposed = true; 
    _socketSubscription?.cancel();
    _socketService.disconnect();
    _socketService.dispose();
    _animationManager.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  // --- MESSAGE HANDLER ---

  void _handleMessage(dynamic message) async {
    if (_isDisposed || message is! String) return;
    
    try {
      final data = jsonDecode(message);
      final String type = data['type']?.toString() ?? "";

      switch (type) {
        case "JOIN":
          _addLog(data['message']?.toString() ?? "상대방이 입장했습니다.");
          break;
        case "BATTLE_START":
          _handleBattleStart(data);
          break;
        case "WAITING":
          _state = _state.copyWith(statusMessage: "상대의 선택을 기다리는 중...");
          notifyListeners();
          break;
        case "OPPONENT_SELECTING":
          _state = _state.copyWith(isOpponentThinking: true);
          notifyListeners();
          break;
        case "TURN_RESULT":
          _onTurnResultReceived(data);
          break;
        case "GAME_OVER":
          _onGameOverReceived(data);
          break;
        case "LEAVE":
          _addLog("상대방이 전장을 이탈했습니다.");
          _handleGameOver({'result': 'WIN', 'reward': {'reason': 'opponent_fled', 'exp_gained': 20}});
          break;
      }
    } catch (e) {
      debugPrint("⚠️ Battle Message Error: $e");
    }
  }

  // --- INTERNAL LOGIC ---

  void _handleGameOver(Map<String, dynamic> data) {
    String result = data['result']?.toString() ?? "LOSE";
    bool iWon = (result == "WIN");
    _state = _state.copyWith(statusMessage: iWon ? "Victory! 🏆" : "Defeat... 💀");
    notifyListeners();
    _animationManager.emitEvent(BattleEvent(
      type: iWon ? BattleEventType.victory : BattleEventType.defeat, 
      message: jsonEncode(data['reward'])
    ));
  }

  Future<void> _onTurnResultReceived(Map<String, dynamic> data) async {
    _state = _state.copyWith(isOpponentThinking: false);
    _isProcessingTurn = true;
    notifyListeners();

    await _animationManager.processTurnResult(
      data['results'], _myId!, _state.oppName, _opponentId, _addLog, _handleHpChange
    );

    _parseStateSync(data['player_states']);
    _isProcessingTurn = false;
    
    if (_pendingGameOverData != null) {
       _handleGameOver(_pendingGameOverData!);
       _pendingGameOverData = null;
    } else {
       _state = _state.copyWith(isMyTurn: true); 
       notifyListeners();
    }
  }

  void _onGameOverReceived(Map<String, dynamic> data) {
    if (_isProcessingTurn) _pendingGameOverData = data;
    else _handleGameOver(data);
  }

  void _handleHpChange(int target, int delta) {
    if (target == _myId) {
      _state = _state.copyWith(myHp: (_state.myHp + delta).clamp(0, _state.myMaxHp));
    } else {
      _state = _state.copyWith(oppHp: (_state.oppHp + delta).clamp(0, _state.oppMaxHp));
    }
    notifyListeners();
  }

  void _handleBattleStart(Map<String, dynamic> data) {
    final players = data['players'] as Map<String, dynamic>;
    players.forEach((key, value) {
      int uid = int.parse(key);
      if (uid != _myId) {
        _opponentId = uid;
        _state = _state.copyWith(
          oppName: value['name'], oppHp: value['hp'], oppMaxHp: value['max_hp'],
          oppPetType: value['pet_type'] ?? 'dog', oppSideUrl: value['side_url'],
        );
      } else {
        _state = _state.copyWith(
          myHp: value['hp'], myMaxHp: value['max_hp'], 
          mySkills: (value['skills'] as List).map((e) => e as Map<String, dynamic>).toList()
        );
      }
    });
    _state = _state.copyWith(
      oppId: data['opponent_id'],
      oppName: data['opponent_name'],
      statusMessage: "전투 시작!",
      isMyTurn: true
      );
    notifyListeners();
  }

  void _addLog(String msg) {
    List<String> newLogs = List.from(_state.logs)..insert(0, msg);
    if (newLogs.length > 50) newLogs.removeLast();
    _state = _state.copyWith(logs: newLogs);
    notifyListeners();
  }

  void _updateStatus(String msg) {
    _state = _state.copyWith(statusMessage: msg);
    notifyListeners();
  }

  Future<void> _loadSkillData() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/data/skills.json');
      _skillData.addAll(jsonDecode(jsonStr));
    } catch (e) { debugPrint("Skill Load Error: $e"); }
  }

  void _parseStateSync(dynamic playerStates) {
     if (playerStates == null) return;
     final pStates = playerStates as Map<String, dynamic>;
     pStates.forEach((uid, pState) {
        if (int.parse(uid) == _myId) {
           _state = _state.copyWith(myHp: pState['hp']);
        } else {
           _state = _state.copyWith(oppHp: pState['hp']);
        }
     });
  }
}