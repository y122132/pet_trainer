class GuestbookEntry {
  final int id;
  final String content;
  final bool isSecret;
  final int authorId;
  final String authorNickname;
  final String? authorPetType;
  final String createdAt;

  GuestbookEntry({
    required this.id,
    required this.content,
    required this.isSecret,
    required this.authorId,
    required this.authorNickname,
    this.authorPetType,
    required this.createdAt,
  });

  // [수정] 서버에서 오는 중첩된 author 객체를 올바르게 파싱하도록 수정
  factory GuestbookEntry.fromJson(Map<String, dynamic> json) {
    final authorData = json['author'] as Map<String, dynamic>?;

    return GuestbookEntry(
      id: json['id'],
      content: json['content'],
      isSecret: json['is_secret'] ?? false,
      authorId: json['author_id'],
      authorNickname: authorData?['nickname'] ?? '익명',
      authorPetType: authorData?['pet_type'],
      createdAt: json['created_at'],
    );
  }
}
