class Stat {
  int strength;
  int intelligence;
  int stamina;
  int happiness;
  int health;
  int exp;
  int level;
  int unused_points;

  Stat({
    required this.strength,
    required this.intelligence,
    required this.stamina,
    required this.happiness,
    required this.health,
    this.exp = 0,
    this.level = 1,
    this.unused_points = 0,
  });

  factory Stat.fromJson(Map<String, dynamic> json) {
    return Stat(
      strength: json['strength'] ?? 0,
      intelligence: json['intelligence'] ?? 0,
      stamina: json['stamina'] ?? 0,
      happiness: json['happiness'] ?? 0,
      health: json['health'] ?? 100,
      exp: json['exp'] ?? 0,
      level: json['level'] ?? 1,
      unused_points: json['unused_points'] ?? 0,
    );
  }
}

class Character {
  final int id;
  final int userId;
  final String name;
  String imageUrl;
  final Stat? stat;

  Character({
    required this.id,
    required this.userId,
    required this.name,
    this.imageUrl = 'assets/images/characters/char_default.png', 
    this.stat,
  });

  factory Character.fromJson(Map<String, dynamic> json) {
    return Character(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      name: json['name'] ?? 'Unknown',
      imageUrl: json['image_url'] ?? 'assets/images/characters/char_default.png',
      stat: (json['stats'] ?? json['stat']) != null ? Stat.fromJson(json['stats'] ?? json['stat']) : null,
    );
  }
}
