import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/models/user_model.dart';

class AuthService {
  // 보안 저장소 인스턴스 생성
  final _storage = const FlutterSecureStorage();

  // 1. 로그인 기능: 성공 시 토큰을 기기에 저장함
  Future<UserModel?> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.loginUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final user = UserModel.fromJson(responseData);

        // [핵심] 로그인 성공 시 토큰과 유저 ID를 기기에 저장
        if (user.token != null) {
          await _storage.write(key: 'jwt_token', value: user.token);
          await _storage.write(key: 'user_id', value: user.id.toString());
          if (user.characterId != null) {
             await _storage.write(key: 'character_id', value: user.characterId.toString());
          }
          print("[AUTH] 토큰 및 캐릭터 ID 저장 완료");
        }

        return user;
      } else {
        print("Login Failed: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Error during login: $e");
      return null;
    }
  }

  // 2. 회원가입 기능
  // 2. 회원가입 기능: 성공 여부와 메시지를 함께 반환
  Future<Map<String, dynamic>> register(String username, String password, String nickname) async {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.registerUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
          "nickname": nickname,
        }),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {"success": true, "message": "회원가입 성공"};
      } else {
        final errorData = jsonDecode(response.body);
        return {
          "success": false, 
          "message": errorData['detail'] ?? '알 수 없는 오류'
        };
      }
    } catch (e) {
      print("Error during register: $e");
      return {"success": false, "message": "서버 연결 실패. (${AppConfig.serverIp})"};
    }
  }

  // 3. 유틸리티 기능: 저장된 토큰 가져오기 (자동 로그인/API 헤더용)
  Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  Future<String?> getCharacterId() async {
    return await _storage.read(key: 'character_id');
  }

  Future<String?> getUserId() async {
    return await _storage.read(key: 'user_id');
  }

  // 4. 유틸리티 기능: 로그아웃 (저장된 정보 삭제)
  Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'user_id');
    await _storage.delete(key: 'character_id');
  }
}