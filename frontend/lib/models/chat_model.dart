class ChatMessage {
  final int fromUserId;   // 보낸 사람 ID
  final String message;    // 메시지 내용
  final DateTime timestamp; // 수신 시간 (UI 표시용)

  ChatMessage({
    required this.fromUserId,
    required this.message,
    required this.timestamp,
  });

  // 백엔드 chat.py의 payload {"from_user_id": 1, "message": "..."} 를 파싱
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      fromUserId: json['from_user_id'] ?? 0,
      message: json['message'] ?? '',
      timestamp: DateTime.now(), // 실시간 수신 시점의 시간 저장
    );
  }
}