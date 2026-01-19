// frontend/lib/providers/battle_provider.dart
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

  void setRoomId(String roomId) {
    _presetRoomId = roomId;
    // 🚩 [TRACK 1] 수동으로 방 번호를 설정할 때 기록
    debugPrint("📌 [BattleProvider] setRoomId 호출됨: $roomId");
  }

  void connect(int userId, {String? roomId}) {
    _myId = userId;
    final String? finalRoomId = roomId ?? _presetRoomId;

    debugPrint("🚀 [BattleProvider] connect 호출됨!");
    debugPrint("   - 인자로 받은 roomId: $roomId");
    debugPrint("   - 저장되어있던 _presetRoomId: $_presetRoomId");
    debugPrint("   - 최종 결정된 finalRoomId: $finalRoomId");
    
    _authService.getToken().then((token) {
      if (token != null && !_isDisposed) {
        final String url = "${AppConfig.battleSocketUrl}/$finalRoomId/$_myId?token=$token";
        debugPrint("🔗 [BattleProvider] 최종 접속 URL: $url");
        
        // 🔴 서버 메시지를 듣는 리스너가 누락되었을 수 있습니다.
        _socketSubscription?.cancel();
        _socketSubscription = _socketService.stream.listen(
          _handleMessage,
          onError: (err) => debugPrint("❌ [BattleProvider] 소켓 에러: $err"),
          onDone: () => debugPrint("🔌 [BattleProvider] 소켓 연결 종료"),
        );

        _socketService.connect(url);
      } else {
      debugPrint("❌ [BattleProvider] 토큰이 없거나 객체가 폐기되어 연결 불가");
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
    debugPrint("📩 [BattleProvider] 서버 메시지 수신: $message");
    
    try {
      final data = jsonDecode(message);
      final String type = data['type']?.toString() ?? "";

      switch (type) {
        case "MATCH_FOUND":
          final String newRoomId = data['room_id'];
          debugPrint("🎰 [MATCH_FOUND] 새 방 발견! ID: $newRoomId");
          _opponentId = data['opponent_id'];
          setRoomId(newRoomId); //  새 방 ID 고정
          _socketService.disconnect(); //  매칭 소켓 닫기
          connect(_myId!); // 새 방 ID로 배틀 소켓 재접속
          break;
        case "JOIN":
          _addLog(data['message']?.toString() ?? "상대방이 입장했습니다.");
          break;
        case "BATTLE_START":
          debugPrint("⚔️ [BATTLE_START] 배틀 데이터 수신 완료!");
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
    try {
      final players = data['players'] as Map<String, dynamic>;
      debugPrint("🏁 [BATTLE_START] 수신됨! 총 플레이어 수: ${players.length}");

      int? foundOppId;

      players.forEach((key, value) {
        final int uid = int.tryParse(key.toString()) ?? 0;
        final val = value as Map<String, dynamic>;

        if (uid != _myId) {
          foundOppId = uid;
          debugPrint("👤 상대방 정보 발견 (ID: $uid)");
          _state = _state.copyWith(
            oppId: uid,
            oppName: val['name'], 
            oppHp: val['hp'], 
            oppMaxHp: val['max_hp'],
            oppPetType: val['pet_type'], 
            oppSideUrl: val['side_url'] ?? "",
            oppFaceUrl: val['face_url'] ?? "",
            oppBackUrl: val['back_url'] ?? "",
            oppFrontUrl: val['front_url'] ?? "",
            oppFrontLeftUrl: val['front_left_url'] ?? "",
            oppFrontRightUrl: val['front_right_url'] ?? "",
            oppBackLeftUrl: val['back_left_url'] ?? "",
            oppBackRightUrl: val['back_right_url'] ?? "",
          );
        } else {
          debugPrint("👤 내 정보 동기화 중 (ID: $uid)");
          final List<dynamic> skillList = val['skills'] ?? [];
          final mappedSkills = skillList.map((e) => Map<String, dynamic>.from(e)).toList();

          _state = _state.copyWith(
            myHp: val['hp'],
            myMaxHp: val['max_hp'], 
            mySkills: mappedSkills,
          );
        }
      });

      _opponentId = foundOppId;

      // 🔴 [수정 포인트] 쉼표 추가 및 상태 확실히 변경
      _state = _state.copyWith(
        statusMessage: "전투 시작! 당신의 차례입니다.",
        isMyTurn: true,     // 👈 쉼표가 누락되었던 부분
        isConnected: true,  // 👈 소켓 연결 상태 확인
      );

      notifyListeners();
      debugPrint("✅ [UI 갱신 성공] 내 턴: ${_state.isMyTurn}, 스킬: ${_state.mySkills.length}개");
      
    } catch (e, stack) {
      debugPrint("🔥 [ERROR] _handleBattleStart 처리 실패: $e");
      debugPrint("📌 위치: $stack");
    }
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