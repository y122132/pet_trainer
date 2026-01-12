class GuestbookEntry {
  final int id;
  final String content;
  final int authorId;
  final String authorNickname;
  final String? authorPetType;
  final String createdAt;

  GuestbookEntry({
    required this.id,
    required this.content,
    required this.authorId,
    required this.authorNickname,
    this.authorPetType,
    required this.createdAt,
  });

  factory GuestbookEntry.fromJson(Map<String, dynamic> json) {
    return GuestbookEntry(
      id: json['id'],
      content: json['content'],
      authorId: json['author_id'],
      authorNickname: json['author_nickname'] ?? '익명',
      authorPetType: json['author_pet_type'] ?? 'dog',
      createdAt: json['created_at'],
    );
  }
}
