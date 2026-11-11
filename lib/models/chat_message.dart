enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
}

class ChatMessage {
  final String id;
  final String chatId;
  final String senderUid;
  final String senderEmail;
  final String text;
  final DateTime timestamp;
  final MessageStatus status;
  final bool isDeleted;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderUid,
    required this.senderEmail,
    required this.text,
    required this.timestamp,
    this.status = MessageStatus.sent,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chatId': chatId,
      'senderUid': senderUid,
      'senderEmail': senderEmail,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'isDeleted': isDeleted,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map, String id) {
    return ChatMessage(
      id: id,
      chatId: map['chatId'] as String? ?? '',
      senderUid: map['senderUid'] as String? ?? '',
      senderEmail: map['senderEmail'] as String? ?? '',
      text: map['text'] as String? ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      status: MessageStatus.values.firstWhere(
        (s) => s.name == (map['status'] as String? ?? 'sent'),
        orElse: () => MessageStatus.sent,
      ),
      isDeleted: map['isDeleted'] as bool? ?? false,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderUid,
    String? senderEmail,
    String? text,
    DateTime? timestamp,
    MessageStatus? status,
    bool? isDeleted,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderUid: senderUid ?? this.senderUid,
      senderEmail: senderEmail ?? this.senderEmail,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
