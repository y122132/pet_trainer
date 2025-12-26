// lib/services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  // 백엔드 기본 URL (환경에 따라 수정)
  static const String baseUrl = 'http://localhost:8000/api/v1/auth';

  // 로그인 기능
  Future<Map<String, dynamic>?> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body); // {access_token, token_type, user_id} 반환
      } else {
        print("Login Failed: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Error during login: $e");
      return null;
    }
  }

  // 회원가입 기능
  Future<bool> register(String username, String password, String nickname) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
          "nickname": nickname,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Error during register: $e");
      return false;
    }
  }
}