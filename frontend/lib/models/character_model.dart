// --- 데이터 모델 클래스 ---

// 스탯 정보 모델
class Stat {
  int strength;      // 근력 (빨간색)
  int intelligence;  // 지능 (파란색)
  int agility;       // 민첩 (구 Stamina) (초록색)
  int defense;       // 방어력
  int luck;          // 운
  int happiness;     // 행복도 (핑크색)
  int health;        // 현재 체력
  int exp;           // 현재 경험치
  int level;         // 레벨
  int unused_points; // 미사용 스탯 포인트 (분배 가능)

  Stat({
    required this.strength,
    required this.intelligence,
    required this.agility,
    required this.defense,
    required this.luck,
    required this.happiness,
    required this.health,
    this.exp = 0,
    this.level = 1,
    this.unused_points = 0,
  });

  // JSON 파싱 (서버 -> 앱)
  factory Stat.fromJson(Map<String, dynamic> json) {
    return Stat(
      strength: json['strength'] ?? 0,
      intelligence: json['intelligence'] ?? 0,
      agility: json['agility'] ?? 0,
      defense: json['defense'] ?? 10, // Def default
      luck: json['luck'] ?? 5,        // Luck default
      happiness: json['happiness'] ?? 0,
      health: json['health'] ?? 100,
      exp: json['exp'] ?? 0,
      level: json['level'] ?? 1,
      unused_points: json['unused_points'] ?? 0,
    );
  }
}

// 캐릭터 정보 모델
class Character {
  final int id;
  final int userId;
  final String name;
  final String petType; // 반려동물 종류 (dog, cat 등) - [New]
  final List<int> learnedSkills; // 습득한 기술 ID 목록 - [New]
  List<int> equippedSkills;
  final Stat? stat; // 연관된 스탯 객체
  final String? imagePath;

  // New image URLs
  final String? frontUrl;
  final String? backUrl;
  final String? sideUrl;
  final String? faceUrl;

  Character({
    required this.id,
    required this.userId,
    required this.name,
    required this.equippedSkills,
    this.petType = 'dog', // 기본값
    this.learnedSkills = const [],
    this.stat,
    this.imagePath,
    this.frontUrl = "",
    this.backUrl = "",
    this.sideUrl = "",
    this.faceUrl = "",
  });

  // JSON 파싱 (서버 -> 앱)
  factory Character.fromJson(Map<String, dynamic> json) {
    return Character(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      name: json['name'] ?? 'Unknown',
      petType: json['pet_type'] ?? 'dog', // 서버 데이터 반영
      learnedSkills: List<int>.from(json['learned_skills'] ?? [5]),
      equippedSkills: List<int>.from(json['equipped_skills'] ?? [5]),
      stat: (json['stats'] ?? json['stat']) != null ? Stat.fromJson(json['stats'] ?? json['stat']) : null,
      imagePath: json['image_path'],
      frontUrl: json['front_url'] ?? "",
      backUrl: json['back_url'] ?? "",
      sideUrl: json['side_url'] ?? "",
      faceUrl: json['face_url'] ?? "",
    );
  }
}
