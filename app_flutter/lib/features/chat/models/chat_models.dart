import 'dart:convert';
import 'dart:typed_data';

/// O SQLite grava `datetime('now')` em UTC, sem sufixo. Interpretar esse
/// texto como horário local deslocava conversas de dia perto da meia-noite.
DateTime? parseBackendDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  var value = raw.trim().replaceFirst(' ', 'T');
  final hasZone = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(value);
  if (!hasZone) value = '${value}Z';
  return DateTime.tryParse(value)?.toLocal();
}

class ChatSource {
  const ChatSource({required this.title, required this.url, this.snippet = ''});

  final String title;
  final String url;
  final String snippet;

  factory ChatSource.fromJson(Map<String, dynamic> json) => ChatSource(
    title: (json['title'] as String? ?? '').trim(),
    url: (json['url'] as String? ?? '').trim(),
    snippet: (json['snippet'] as String? ?? '').trim(),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    if (snippet.isNotEmpty) 'snippet': snippet,
  };

  static List<ChatSource> parseList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => ChatSource.fromJson(Map<String, dynamic>.from(item)))
        .where((source) => source.url.isNotEmpty || source.title.isNotEmpty)
        .toList();
  }
}

class ChatAttachment {
  const ChatAttachment({
    this.id,
    required this.filename,
    required this.mime,
    required this.size,
    required this.kind,
    this.bytes,
    this.extractedText,
    this.createdAt,
  });

  final int? id;
  final String filename;
  final String mime;
  final int size;
  final String kind;
  final Uint8List? bytes;
  final String? extractedText;
  final DateTime? createdAt;

  bool get isImage => kind == 'image' || mime.startsWith('image/');
  bool get isText => kind == 'text';
  bool get isPending => id == null;

  String get extension {
    final index = filename.lastIndexOf('.');
    if (index <= 0 || index == filename.length - 1) return '';
    return filename.substring(index + 1).toUpperCase();
  }

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
    id: (json['id'] as num?)?.toInt(),
    filename: (json['filename'] as String? ?? 'arquivo').trim(),
    mime: (json['mime'] as String? ?? 'application/octet-stream').trim(),
    size: (json['size'] as num?)?.toInt() ?? 0,
    kind: (json['kind'] as String? ?? 'file').trim(),
    extractedText: json['extracted_text'] as String?,
    createdAt: parseBackendDate(json['created_at'] as String?),
  );

  static List<ChatAttachment> fromJsonList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => ChatAttachment.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'filename': filename,
    'mime': mime,
    'size': size,
    'kind': kind,
  };

  ChatAttachment copyWith({
    int? id,
    String? filename,
    String? mime,
    int? size,
    String? kind,
    Uint8List? bytes,
    String? extractedText,
    DateTime? createdAt,
  }) => ChatAttachment(
    id: id ?? this.id,
    filename: filename ?? this.filename,
    mime: mime ?? this.mime,
    size: size ?? this.size,
    kind: kind ?? this.kind,
    bytes: bytes ?? this.bytes,
    extractedText: extractedText ?? this.extractedText,
    createdAt: createdAt ?? this.createdAt,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.sources = const [],
    this.attachments = const [],
    this.createdAt,
  });

  final String role;
  final String content;
  final List<ChatSource> sources;
  final List<ChatAttachment> attachments;
  final DateTime? createdAt;

  bool get isUser => role == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    var sources = ChatSource.parseList(json['sources']);
    if (sources.isEmpty && json['sources_json'] is String) {
      try {
        sources = ChatSource.parseList(jsonDecode(json['sources_json'] as String));
      } catch (_) {
        sources = const [];
      }
    }
    var attachments = <ChatAttachment>[];
    final rawAttachments = json['attachments'];
    if (rawAttachments is List) {
      attachments = rawAttachments
          .whereType<Map>()
          .map((item) => ChatAttachment.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } else if (json['attachments_json'] is String) {
      try {
        attachments = ChatAttachment.fromJsonList(
          jsonDecode(json['attachments_json'] as String),
        );
      } catch (_) {
        attachments = [];
      }
    }
    return ChatMessage(
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      sources: sources,
      attachments: attachments,
      createdAt: parseBackendDate(json['created_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (sources.isNotEmpty)
      'sources': sources.map((item) => item.toJson()).toList(),
    if (attachments.isNotEmpty)
      'attachments': attachments.map((item) => item.toJson()).toList(),
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}
