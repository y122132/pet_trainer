// Event types for Animation Triggers
enum BattleEventType {
  attack,
  hit,
  damage,
  heal,
  miss,
  crit,
  victory,
  defeat,
  shake, // Camera shake
}

// Payload for events
class BattleEvent {
  final BattleEventType type;
  final int? actorId; // Who acted?
  final int? targetId; // Who was targeted?
  final int? value; // Damage/Heal amount
  final String? message; 

  BattleEvent({required this.type, this.actorId, this.targetId, this.value, this.message});
}

// Full State for the View to render
class BattleUIState {
  final int myHp;
  final int myMaxHp;
  final int oppHp;
  final int oppMaxHp;
  final String oppName;
  final String oppPetType;
  final bool isMyTurn;
  final bool isConnected;
  final String statusMessage;
  final List<String> logs;
  final List<Map<String, dynamic>> mySkills;
  final List<String> myStatuses;
  final List<String> oppStatuses;
  // UI related flags
  final bool isOpponentThinking;

  BattleUIState({
    this.myHp = 100,
    this.myMaxHp = 100,
    this.oppHp = 100,
    this.oppMaxHp = 100,
    this.oppName = "Opponent",
    this.oppPetType = "dog",
    this.isMyTurn = false,
    this.isConnected = false,
    this.statusMessage = "Connecting...",
    this.logs = const [],
    this.mySkills = const [],
    this.myStatuses = const [],
    this.oppStatuses = const [],
    this.isOpponentThinking = false,
  });

  // CopyWith for immutable updates
  BattleUIState copyWith({
    int? myHp, int? myMaxHp, int? oppHp, int? oppMaxHp,
    String? oppName, String? oppPetType,
    bool? isMyTurn, bool? isConnected, String? statusMessage,
    List<String>? logs, List<Map<String, dynamic>>? mySkills,
    List<String>? myStatuses, List<String>? oppStatuses,
    bool? isOpponentThinking,
  }) {
    return BattleUIState(
      myHp: myHp ?? this.myHp,
      myMaxHp: myMaxHp ?? this.myMaxHp,
      oppHp: oppHp ?? this.oppHp,
      oppMaxHp: oppMaxHp ?? this.oppMaxHp,
      oppName: oppName ?? this.oppName,
      oppPetType: oppPetType ?? this.oppPetType,
      isMyTurn: isMyTurn ?? this.isMyTurn,
      isConnected: isConnected ?? this.isConnected,
      statusMessage: statusMessage ?? this.statusMessage,
      logs: logs ?? this.logs,
      mySkills: mySkills ?? this.mySkills,
      myStatuses: myStatuses ?? this.myStatuses,
      oppStatuses: oppStatuses ?? this.oppStatuses,
      isOpponentThinking: isOpponentThinking ?? this.isOpponentThinking,
    );
  }
}
