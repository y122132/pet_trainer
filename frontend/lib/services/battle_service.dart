import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pet_trainer_frontend/api_config.dart';
import 'package:pet_trainer_frontend/services/auth_service.dart';

class BattleService {
  final AuthService _authService = AuthService();

  // 친구에게 배틀 초대장 발송
  // Returns: room_id String if successful, null otherwise
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
}
