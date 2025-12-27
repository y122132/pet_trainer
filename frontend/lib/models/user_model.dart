// lib/models/user_model.dart

class UserModel {
  final int id;
  final String username;
  final String nickname;
  final int? characterId; // [New] 캐릭터 ID (없으면 null)
  final bool hasCharacter; // [New] 캐릭터 생성 여부
  final String? token; // JWT 토큰

  UserModel({
    required this.id,
    required this.username,
    required this.nickname,
    this.characterId,
    this.hasCharacter = false,
    this.token,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? json['user_id'] ?? 0,
      username: json['username'] ?? '',
      nickname: json['nickname'] ?? '',
      characterId: json['character_id'],
      hasCharacter: json['has_character'] ?? false,
      token: json['access_token'], // 로그인 성공 시 받아오는 토큰
    );
  }

  // 2. 객체를 다시 JSON으로 변환 (기기 로컬 저장 시 사용)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'nickname': nickname,
      'character_id': characterId,
      'has_character': hasCharacter,
      'access_token': token,
    };
  }
}