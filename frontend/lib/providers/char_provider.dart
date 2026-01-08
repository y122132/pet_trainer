import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart'; 
import 'package:pet_trainer_frontend/models/pet_config.dart';
import 'package:pet_trainer_frontend/models/character_model.dart';

import 'package:pet_trainer_frontend/api_config.dart';

import 'package:pet_trainer_frontend/services/auth_service.dart';
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

  Map<String, int> get statsMap => {
    "STR": strength,
    "INT": intelligence,
    "AGI": agility,
    "DEF": defense,
    "LUK": luck
  };
  
  String _statusMessage = "시작하려면 버튼을 누르세요!";
  String get statusMessage => _statusMessage;

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  final String _baseUrl = AppConfig.baseUrl; // 예: http://192.168.1.5:8000

  String _currentPetType = "dog";         // 기본값: 강아지
  PetConfig _petConfig = PET_CONFIGS["dog"]!; // 기본 설정

  String get currentPetType => _currentPetType;
  PetConfig get petConfig => _petConfig;

  void setTemporaryImages(Map<String, XFile?> images) {
    tempFrontImage = images['Front'];
    tempBackImage = images['Back'];
    tempSideImage = images['Side'];
    tempFaceImage = images['Face'];
    notifyListeners();
  }

  void setPetType(String type) {
    if (PET_CONFIGS.containsKey(type)) {
      _currentPetType = type;
      _petConfig = PET_CONFIGS[type]!;
      print("[Provider] 펫 변경: $_currentPetType (${_petConfig.name})");
      notifyListeners();
    }
  }

  int _unusedStatPoints = 0;
  int get unusedStatPoints => _unusedStatPoints;

  void addUnusedPoints(int points) {
    _unusedStatPoints += points;
    notifyListeners();
  }

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
    
    syncStatToBackend(); 
    
    notifyListeners();
  }
  void resetStats() {
    if (_character == null || _character!.stat == null) return;
    
    int refundPoints = 0;
    
    refundPoints += _character!.stat!.strength;      // Base 0
    refundPoints += _character!.stat!.intelligence;  // Base 0
    refundPoints += _character!.stat!.agility;       // Base 0
    
    if (_character!.stat!.defense > 10) {
      refundPoints += (_character!.stat!.defense - 10);
    }
    
    if (_character!.stat!.luck > 5) {
      refundPoints += (_character!.stat!.luck - 5);
    }
    
    _unusedStatPoints += refundPoints;
    
    _character!.stat!.strength = 0;
    _character!.stat!.intelligence = 0;
    _character!.stat!.agility = 0;
    _character!.stat!.defense = 10;
    _character!.stat!.luck = 5;
    
    print("[Provider] 스탯 초기화 완료. 환불된 포인트: $refundPoints, 총 보유 포인트: $_unusedStatPoints");
    
    // 4. 서버 동기화 & UI 갱신
    syncStatToBackend();
    notifyListeners();
  }

  void gainReward(Map<String, dynamic> baseReward, int bonusPoints) {
    if (_character == null || _character!.stat == null) return;
    
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
    
    if (bonusPoints > 0) {
      _unusedStatPoints += bonusPoints;
    }
    
    gainExp(15);
    
    _balanceStats();
    syncStatToBackend();
    
    notifyListeners();
  }
  
  void gainExp(int amount) {
    if (_character != null && _character!.stat != null) {
      _character!.stat!.exp += amount;
      _checkLevelUp();
      notifyListeners();
    }
  }

  void updateExperience(int newExp, int newLevel) {
    if (_character == null || _character!.stat == null) return;

    _character!.stat!.exp = newExp;
    _character!.stat!.level = newLevel;
    
    int currentMaxExp = newLevel * 100;
    notifyListeners();
  }

  void _checkLevelUp() {
    bool leveledUp = false;
    int earnedPoints = 0;

    while (_character!.stat!.exp >= maxExp) {
      _character!.stat!.exp -= maxExp;
      _character!.stat!.level += 1;
      _unusedStatPoints += 4; // 레벨업 보상: 4포인트
      earnedPoints += 4;
      leveledUp = true;
    }

    if (leveledUp) {
      _statusMessage = "레벨업! 🎉 (포인트 +$earnedPoints)";
      print("[Provider] 레벨업 완료! 현재 레벨: ${_character!.stat!.level}, 남은 경험치: ${_character!.stat!.exp}");
    }
  }

  void updateStatusMessage(String msg) {
    if (msg.isEmpty) return;
    
    _statusMessage = msg;
    notifyListeners();
  }

  Future<void> fetchCharacter([int id = 1]) async {

    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('${AppConfig.charactersUrl}/$id'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        if (response.bodyBytes.isEmpty) {
           throw Exception("Empty response body");
        }
        final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        
        if (data.isEmpty) {
           throw Exception("Empty JSON data");
        }
        
        _character = Character.fromJson(data);
        
        _currentPetType = _character!.petType;
        if (PET_CONFIGS.containsKey(_currentPetType)) {
          _petConfig = PET_CONFIGS[_currentPetType]!;
        } else {
          print("Unknown pet type: $_currentPetType, using default.");
        }
        
        if (_character!.stat != null) {
            _unusedStatPoints = _character!.stat!.unused_points;
        }

        tempFrontImage = null;
        tempBackImage = null;
        tempSideImage = null;
        tempFaceImage = null;
        
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
    }
  }

  //  강제 레벨업 요청 (테스트용)
  Future<void> manualLevelUp() async {
    if (_character == null) return;
    try {
      final token = await AuthService().getToken();
      final response = await http.post(
        Uri.parse('${AppConfig.charactersUrl}/${_character!.id}/level-up'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        print("[Provider] Manual Level-up Success");
        await fetchCharacter(_character!.id);
        _statusMessage = "레벨업 성공! 🎉";
        notifyListeners();
      } else {
        print("manualLevelUp failed: ${response.statusCode}");
      }
    } catch (e) {
      print("manualLevelUp error: $e");
    }
  }

  // 서버로 현재 스탯 상태 동기화 (저장)
  Future<void> syncStatToBackend() async {
    if (_character == null || _character!.stat == null) return;

    final int charId = _character!.id;
    final stat = _character!.stat!;
    final bodyData = {
      "strength": stat.strength,
      "intelligence": stat.intelligence,
      "agility": stat.agility,
      "defense": stat.defense,
      "luck": stat.luck,
      "happiness": stat.happiness,
      "health": stat.health,
      "exp": stat.exp,
      "level": stat.level,
      "unused_points": _unusedStatPoints
    };

    try {
      final token = await AuthService().getToken();
      await http.put(
        Uri.parse('${AppConfig.charactersUrl}/$charId/stats'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode(bodyData)
      );
    } catch (e) {
      print("sync error: $e");
    }
  }

  void _balanceStats() {
    if (_character!.stat!.happiness > 100) _character!.stat!.happiness = 100;
  }

  Future<bool> createCharacterWithImages(String name, Map<String, XFile?> images) async {
    _isLoading = true;
    _statusMessage = "캐릭터 생성 중 (사진 전송)...";
    notifyListeners();

    try {
      final token = await AuthService().getToken();
      if (token == null) throw Exception("로그인이 필요합니다.");

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
              var bytes = await entry.value!.readAsBytes();
              String newFilename = '${entry.key.toLowerCase()}.png'; // 예: 'front.png'

              var pic = http.MultipartFile.fromBytes(
                  fieldName, 
                  bytes,
                  filename: newFilename // 표준화된 영문 파일명 사용
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
          
          await const FlutterSecureStorage().write(key: 'character_id', value: newCharId.toString());
          
          setTemporaryImages(images);
          
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
  void clearData() {
    _character = null;
    _unusedStatPoints = 0;
    notifyListeners();
  }

  // [New] 단일 캐릭터 이미지 업데이트 메서드
  Future<bool> updateCharacterImage(int charId, String imageKey, XFile newImageFile) async {
    _isLoading = true;
    _statusMessage = "이미지 업데이트 중...";
    notifyListeners();

    try {
      final token = await AuthService().getToken();
      if (token == null) throw Exception("로그인이 필요합니다.");

      var uri = Uri.parse("${AppConfig.baseUrl}/characters/$charId/image/$imageKey");
      var request = http.MultipartRequest("PUT", uri);
      
      request.headers.addAll({
        "Authorization": "Bearer $token",
      });

      // 파일 추가
      var bytes = await newImageFile.readAsBytes();
      var pic = http.MultipartFile.fromBytes(
          "image_file", // This must match the backend endpoint's File(...) parameter name
          bytes,
          filename: 'update.png', // Standardized filename
      );
      request.files.add(pic);

      print("[Provider] Sending single image update request for char $charId, key $imageKey...");
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print("[Provider] Image update Success: ${data['image_url']}");
          _isLoading = false;
          _statusMessage = "이미지 업데이트 성공!";
          notifyListeners();
          return true;
      } else {
          final errorParams = jsonDecode(response.body);
          throw Exception(errorParams['detail'] ?? "이미지 업데이트 실패 (${response.statusCode})");
      }

    } catch (e) {
      print("[Provider] Image update Error: $e");
      _statusMessage = "이미지 업데이트 오류: $e";
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
