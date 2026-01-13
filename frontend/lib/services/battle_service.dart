import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart';

class BattleService {
  final String baseUrl = AppConfig.baseUrl;
  final AuthService _authService = AuthService();

  Future<Map<String, String>> _getHeaders() async {
    final token = await AuthService().getToken();
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    };
  }

  Future<String?> sendInvite(int friendId) async {
    final token = await _authService.getToken();
    if (token == null) return null;

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/battle/invite?friend_id=$friendId'),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json"
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['room_id'];
      } else {
        print("Invite failed: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Error sending invite: $e");
      return null;
    }
  }

  
  Future<bool> updateEquippedSkills(List<int> skillIds) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/characters/me/equip-skills'),
        headers: headers,
        body: jsonEncode({'skill_ids': skillIds}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Update Skill Error: $e");
      return false;
    }
  }
}
