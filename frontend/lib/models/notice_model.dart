class NoticeModel {
  final int id;
  final String title;
  final String content;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoticeModel({
    required this.id,
    required this.title,
    required this.content,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NoticeModel.fromJson(Map<String, dynamic> json) {
    return NoticeModel(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      isActive: json['is_active'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}
