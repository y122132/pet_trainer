import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart'; // Import XFile
import 'package:pet_trainer_frontend/models/character_model.dart';
import 'package:pet_trainer_frontend/models/pet_config.dart';

import 'package:pet_trainer_frontend/api_config.dart';

import 'package:pet_trainer_frontend/services/auth_service.dart'; // [추가] AuthService 임포트
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CharProvider with ChangeNotifier {
  // 캐릭터 상태 데이터 (Private 변수)
  Character? _character;
  Character? get character => _character;

  // Temporary images for newly registered character
  XFile? tempFrontImage;
  XFile? tempBackImage;
  XFile? tempSideImage;
  XFile? tempFaceImage;

  // --- 편의를 위한 Getters (UI에서 접근하기 쉽게) ---
  int get strength => _character?.stat?.strength ?? 0;
  int get intelligence => _character?.stat?.intelligence ?? 0;
  int get agility => _character?.stat?.agility ?? 0;
  int get defense => _character?.stat?.defense ?? 0;
  int get luck => _character?.stat?.luck ?? 0;
  int get happiness => _character?.stat?.happiness ?? 0;
  int get health => _character?.stat?.health ?? 0;
  int get maxHealth => 100; // 최대 체력 (임시)
  int get currentExp => _character?.stat?.exp ?? 0;
  int get maxExp => 100; // 최대 경험치 (임시)
  int get level => _character?.stat?.level ?? 1;
  double get expPercentage => (currentExp / maxExp).clamp(0.0, 1.0); // 경험치 바(Bar)용 퍼센트

  // 스탯 맵 반환 (UI 차트용)
  Map<String, int> get statsMap => {
    "STR": strength,
    "INT": intelligence,
    "AGI": agility,
    "DEF": defense,
    "LUK": luck
  };
  
  // 현재 진행 중인 미션/메시지
  String _statusMessage = "시작하려면 버튼을 누르세요!";
  String get statusMessage => _statusMessage;

  // 로딩 상태
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  // 백엔드 주소 (Config 파일에서 로드)
  final String _baseUrl = AppConfig.baseUrl; // 예: http://192.168.1.5:8000

  // --- 펫 관련 설정 (강아지/고양이 등) ---
  String _currentPetType = "dog";         // 기본값: 강아지
  PetConfig _petConfig = PET_CONFIGS["dog"]!; // 기본 설정

  String get currentPetType => _currentPetType;
  PetConfig get petConfig => _petConfig;

  // Method to set the temporary images
  void setTemporaryImages(Map<String, XFile?> images) {
    tempFrontImage = images['Front'];
    tempBackImage = images['Back'];
    tempSideImage = images['Side'];
    tempFaceImage = images['Face'];
    notifyListeners();
  }

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
      case 'agility':
        _character!.stat!.agility += amount;
        break;
      case 'defense':
        _character!.stat!.defense += amount;
        break;
      case 'luck':
        _character!.stat!.luck += amount;
        break;
      case 'happiness':
        _character!.stat!.happiness += amount;
        break;
      case 'health':
        _character!.stat!.health += amount;
        break;
    }
    _unusedStatPoints -= amount;
    
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
        case 'agility': _character!.stat!.agility += value; break;
        case 'defense': _character!.stat!.defense += value; break;
        case 'luck': _character!.stat!.luck += value; break;
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
      notifyListeners();
    }
  }

  // 상태 메시지 업데이트 (캐릭터 대사 전용)
  void updateStatusMessage(String msg) {
    // 빈 문자열이나 null이 들어오면 무시 (기존 메시지 유지)
    if (msg.isEmpty) return;
    
    _statusMessage = msg;
    notifyListeners();
  }

  // --- 서버 통신 (API) ---

  // 데이터 로드 (서버에서 캐릭터 정보 가져오기)
  Future<void> fetchCharacter([int id = 1]) async {
    // Clear temporary images on any server fetch
    tempFrontImage = null;
    tempBackImage = null;
    tempSideImage = null;
    tempFaceImage = null;

    try {
      final token = await AuthService().getToken();
      // API 호출: GET /v1/characters/{id}
      final response = await http.get(
        Uri.parse('${AppConfig.charactersUrl}/$id'),
        headers: {
          "Authorization": "Bearer $token", // [추가] 인증 헤더
          "Content-Type": "application/json",
        },
      );

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
        _currentPetType = _character!.petType;
        if (PET_CONFIGS.containsKey(_currentPetType)) {
          _petConfig = PET_CONFIGS[_currentPetType]!;
        } else {
          print("Unknown pet type: $_currentPetType, using default.");
        }
        
        // 서버의 'unused_points' 정보를 로컬 변수와 동기화
        if (_character!.stat != null) {
            _unusedStatPoints = _character!.stat!.unused_points;
        }
        
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

  // [New] 내 캐릭터 정보 가져오기 (저장된 ID 기반)
  Future<void> fetchMyCharacter() async {
    final charIdStr = await AuthService().getCharacterId();
    if (charIdStr != null) {
      final charId = int.tryParse(charIdStr);
      if (charId != null) {
        print("[Provider] 내 캐릭터(ID: $charId) 불러오기 시작");
        await fetchCharacter(charId);
      } else {
         print("[Provider] 저장된 캐릭터 ID가 유효하지 않음.");
      }
    } else {
      print("[Provider] 저장된 캐릭터 ID가 없음. 로그인 필요?");
      // 테스트용: 기본값 1번 시도 (삭제 가능)
      // await fetchCharacter(1);
    }
  }

  // 서버로 현재 스탯 상태 동기화 (저장)
  Future<void> syncStatToBackend() async {
    if (_character == null) return;
    try {
      // [추가] 기기에 저장된 JWT 토큰 가져오기
      final token = await AuthService().getToken();
      // API 호출: PUT /v1/characters/{id}/stats
      await http.put(
        Uri.parse('${AppConfig.charactersUrl}/${_character!.id}/stats'),
        headers: {
          "Authorization": "Bearer $token", // [추가] 인증 헤더
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "strength": _character!.stat!.strength,
          "intelligence": _character!.stat!.intelligence,
          "agility": _character!.stat!.agility,
          "defense": _character!.stat!.defense,
          "luck": _character!.stat!.luck,
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

  // [New] 캐릭터 생성 및 이미지 업로드 통합 메서드 (Atomic)
  Future<bool> createCharacterWithImages(String name, Map<String, XFile?> images) async {
    _isLoading = true;
    _statusMessage = "캐릭터 생성 중 (사진 전송)...";
    notifyListeners();

    try {
      final token = await AuthService().getToken();
      if (token == null) throw Exception("로그인이 필요합니다.");

      // [Atomic Creation] 한번에 요청
      var uri = Uri.parse("${AppConfig.baseUrl}/characters/compose");
      var request = http.MultipartRequest("POST", uri);
      
      request.headers.addAll({
        "Authorization": "Bearer $token",
      });
      
      request.fields['name'] = name;
      request.fields['pet_type'] = "dog"; // 기본값

      // 파일 추가
      for (var entry in images.entries) {
          if (entry.value != null) {
              String fieldName = "${entry.key.toLowerCase()}_image";
              // XFile -> Byte Stream (Cross-platform safe)
              // fromPath는 dart:io에 의존하므로 웹/일부 환경에서 에러 발생
              // readAsBytes()는 모든 플랫폼에서 안전함
              var bytes = await entry.value!.readAsBytes();
              var pic = http.MultipartFile.fromBytes(
                  fieldName, 
                  bytes,
                  filename: entry.value!.name
              );
              request.files.add(pic);
          } else {
             throw Exception("${entry.key} 사진이 누락되었습니다.");
          }
      }

      print("[Provider] Sending atomic creation request...");
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          final newCharId = data['id'];
          
          print("[Provider] Creation Success: ID $newCharId");
          
          // ID 저장
          await const FlutterSecureStorage().write(key: 'character_id', value: newCharId.toString());
          
          // 로컬 상태 업데이트 (화면 즉시 반영용)
          setTemporaryImages(images);
          
          // 캐릭터 정보 새로고침
          await fetchCharacter(newCharId);
          
          _isLoading = false;
          return true;
      } else {
          final errorParams = jsonDecode(response.body);
          throw Exception(errorParams['detail'] ?? "생성 실패 (${response.statusCode})");
      }

    } catch (e) {
      print("[Provider] Creation Error: $e");
      _statusMessage = "생성 오류: $e";
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
