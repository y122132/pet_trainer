import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:pet_trainer_frontend/models/character.dart';
import 'package:pet_trainer_frontend/models/pet_config.dart';

import 'package:pet_trainer_frontend/config.dart';

class CharProvider with ChangeNotifier {
  // 캐릭터 상태 데이터 (Private 변수)
  Character? _character;
  Character? get character => _character;

  // --- 편의를 위한 Getters (UI에서 접근하기 쉽게) ---
  int get strength => _character?.stat?.strength ?? 0;
  int get intelligence => _character?.stat?.intelligence ?? 0;
  int get stamina => _character?.stat?.stamina ?? 0;
  int get happiness => _character?.stat?.happiness ?? 0;
  int get health => _character?.stat?.health ?? 0;
  int get maxHealth => 100; // 최대 체력 (임시)
  int get currentExp => _character?.stat?.exp ?? 0;
  int get maxExp => 100; // 최대 경험치 (임시)
  int get level => _character?.stat?.level ?? 1;
  String get imagePath => _character?.imageUrl ?? 'assets/images/characters/char_default.png';
  double get expPercentage => (currentExp / maxExp).clamp(0.0, 1.0); // 경험치 바(Bar)용 퍼센트

  // 스탯 맵 반환 (UI 차트용)
  Map<String, int> get statsMap => {
    "STR": strength,
    "INT": intelligence,
    "DEX": stamina,
    "HAP": happiness
  };
  
  // 현재 진행 중인 미션/메시지
  String _statusMessage = "시작하려면 버튼을 누르세요!";
  String get statusMessage => _statusMessage;
  
  // 백엔드 주소 (Config 파일에서 로드)
  final String _baseUrl = AppConfig.baseUrl; // 예: http://192.168.1.5:8000

  // --- 펫 관련 설정 (강아지/고양이 등) ---
  String _currentPetType = "dog";         // 기본값: 강아지
  PetConfig _petConfig = PET_CONFIGS["dog"]!; // 기본 설정

  String get currentPetType => _currentPetType;
  PetConfig get petConfig => _petConfig;

  // 펫 종류 변경 메서드 (설정 변경 시 호출)
  void setPetType(String type) {
    if (PET_CONFIGS.containsKey(type)) {
      _currentPetType = type;
      _petConfig = PET_CONFIGS[type]!;
      print("[Provider] 펫 변경: $_currentPetType (${_petConfig.name})");
      notifyListeners();
    }
  }

  // --- 스탯 관리 로직 ---
  
  // 사용되지 않은 스탯 포인트 (훈련 보상으로 획득)
  int _unusedStatPoints = 0;
  int get unusedStatPoints => _unusedStatPoints;

  /// 스탯 포인트 추가 (보너스 등)
  void addUnusedPoints(int points) {
    _unusedStatPoints += points;
    notifyListeners();
  }

  /// 특정 스탯에 포인트 할당 (분배)
  /// [statType]: 스탯 종류 ('strength', 'intelligence', 등)
  /// [amount]: 할당할 양 (기본 1)
  void allocateStatSpecific(String statType, [int amount = 1]) {
    if (_character == null || _character!.stat == null) return;
    if (_unusedStatPoints < amount) return; // 포인트 부족 시 중단

    switch (statType) {
      case 'strength':
        _character!.stat!.strength += amount;
        break;
      case 'intelligence':
        _character!.stat!.intelligence += amount;
        break;
      case 'stamina':
        _character!.stat!.stamina += amount;
        break;
      case 'happiness':
        _character!.stat!.happiness += amount;
        break;
      case 'health':
        _character!.stat!.health += amount;
        break;
    }
    _unusedStatPoints -= amount;
    
    // 이미지 갱신 등
    _updateImage();
    
    // 서버 동기화 (비동기)
    syncStatToBackend(); 
    
    notifyListeners();
  }

  /// 보상 획득 로직 (AI 분석 결과 반영)
  /// [baseReward]: 기본 스탯 증가량 {stat_type, value}
  /// [bonusPoints]: 추가 할당 가능한 포인트 (사용자 분배용)
  void gainReward(Map<String, dynamic> baseReward, int bonusPoints) {
    if (_character == null || _character!.stat == null) return;
    
    // 1. 기본 보상 즉시 적용 (자동 성장)
    String statType = baseReward['stat_type'] ?? 'strength';
    int value = baseReward['value'] ?? 0;
    
    if (value > 0) {
      switch (statType) {
        case 'strength': _character!.stat!.strength += value; break;
        case 'intelligence': _character!.stat!.intelligence += value; break;
        case 'stamina': _character!.stat!.stamina += value; break;
        case 'happiness': _character!.stat!.happiness += value; break;
        case 'health': _character!.stat!.health += value; break;
      }
    }
    
    // 2. 보너스 포인트 적립 (즉시 분배가 아니라 저장해둠)
    if (bonusPoints > 0) {
      _unusedStatPoints += bonusPoints;
    }
    
    // 3. 경험치 추가 및 레벨업 로직 (예시)
    _character!.stat!.exp += 15;
    if (_character!.stat!.exp >= 100) {
      _character!.stat!.level += 1;
      _character!.stat!.exp = 0;
      _unusedStatPoints += 5; // 레벨업 보너스
      _statusMessage = "레벨업! 🎉 (포인트 +5)";
    }
    
    _balanceStats();
    _updateImage();
    syncStatToBackend();
    
    notifyListeners();
  }
  
  // 간단한 경험치 획득 (테스트용)
  void gainExp(int amount) {
    if (_character != null && _character!.stat != null) {
      _character!.stat!.exp += amount;
      if (_character!.stat!.exp >= 100) {
        _character!.stat!.level += 1;
        _character!.stat!.exp -= 100;
        _statusMessage = "레벨 업!!";
      }
      _updateImage();
      notifyListeners();
    }
  }

  // 상태 메시지 업데이트
  void updateStatusMessage(String msg) {
    _statusMessage = msg;
    notifyListeners();
  }

  // --- 서버 통신 (API) ---

  // 데이터 로드 (서버에서 캐릭터 정보 가져오기)
  // [id]: 캐릭터 ID (기본값 1)
  Future<void> fetchCharacter([int id = 1]) async {
    try {
      // API 호출: GET /v1/characters/{id}
      final response = await http.get(Uri.parse('$_baseUrl/v1/characters/$id'));
      if (response.statusCode == 200) {
        if (response.bodyBytes.isEmpty) {
           throw Exception("Empty response body");
        }
        // 한글 깨짐 방지를 위해 utf8.decode 사용
        final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        
        // 데이터 무결성 체크
        if (data.isEmpty) {
           throw Exception("Empty JSON data");
        }
        
        _character = Character.fromJson(data);
        
        // [New] 서버에서 가져온 펫 종류 적용 (동기화)
        // 기존에는 하드코딩된 'dog'만 사용했으나, 이제는 DB 정보를 따름
        _currentPetType = _character!.petType;
        if (PET_CONFIGS.containsKey(_currentPetType)) {
          _petConfig = PET_CONFIGS[_currentPetType]!;
        } else {
          // 예외 처리: 모르는 펫 타입이면 기본값 유지
          print("Unknown pet type: $_currentPetType, using default.");
        }
        
        // 서버의 'unused_points' 정보를 로컬 변수와 동기화
        if (_character!.stat != null) {
            _unusedStatPoints = _character!.stat!.unused_points;
        }
        
        _updateImage();
        notifyListeners();
      } else {
        print("fetchCharacter failed: ${response.statusCode}");
        _statusMessage = "서버 오류: ${response.statusCode}";
        notifyListeners();
      }
    } catch (e) {
      print("fetchCharacter error: $e");
      _statusMessage = "서버 연결 실패 혹은 데이터 오류";
      notifyListeners();
    }
  }

  // 서버로 현재 스탯 상태 동기화 (저장)
  Future<void> syncStatToBackend() async {
    if (_character == null) return;
    try {
      // API 호출: PUT /v1/characters/{id}/stats
      await http.put(
        Uri.parse('$_baseUrl/v1/characters/${_character!.id}/stats'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "strength": _character!.stat!.strength,
          "intelligence": _character!.stat!.intelligence,
          "stamina": _character!.stat!.stamina,
          "happiness": _character!.stat!.happiness,
          "health": _character!.stat!.health,
          "exp": _character!.stat!.exp,
          "level": _character!.stat!.level,
          "unused_points": _unusedStatPoints
        })
      );
    } catch (e) {
      print("sync error: $e");
    }
  }

  // 밸런스 조정 (최대값/최소값 제한 등 안전장치)
  void _balanceStats() {
    // 예시: 행복도가 100을 넘지 않도록 제한
    if (_character!.stat!.happiness > 100) _character!.stat!.happiness = 100;
  }

  // 스탯에 따라 이미지/표정 변경 로직
  void _updateImage() {
    if (_character == null) return;
    
    // 단순 예시: 행복도에 따라 이미지 경로 변경
    int happy = _character!.stat!.happiness;
    if (happy > 80) {
      _character!.imageUrl = "assets/images/characters/char_happy.png"; 
    } else if (happy < 30) {
      _character!.imageUrl = "assets/images/characters/char_sad.png";
    } else {
      _character!.imageUrl = "assets/images/characters/char_default.png";
    }
  }
}
