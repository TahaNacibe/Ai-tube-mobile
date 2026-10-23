class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.sources = const [],
    this.images = const [],
  });

  final String role;
  final String content;
  final List<Map<String, dynamic>> sources;
  final List<Map<String, dynamic>> images;

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'sources': sources,
    'images': images,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: json['role'] as String? ?? 'assistant',
    content: json['content'] as String? ?? '',
    sources: _objectList(json['sources']),
    images: _objectList(json['images']),
  );
}

class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  String title;
  int updatedAt;
  final List<ChatMessage> messages;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt,
    'messages': messages.map((message) => message.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? 'New conversation',
    updatedAt: json['updatedAt'] as int? ?? 0,
    messages: (json['messages'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList(),
  );
}

List<Map<String, dynamic>> _objectList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().toList();
}
