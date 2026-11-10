class ChatModel {
  final String id;
  final List<String> participantUids;
  final List<String> participantEmails;
  final String? lastMessageText;
  final DateTime? lastMessageTimestamp;
  final DateTime updatedAt;

  const ChatModel({
    required this.id,
    required this.participantUids,
    required this.participantEmails,
    this.lastMessageText,
    this.lastMessageTimestamp,
    required this.updatedAt,
  });

  static String deterministicChatId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  String otherUserEmail(String currentUserEmail) {
    final normalized = currentUserEmail.toLowerCase().trim();
    return participantEmails.firstWhere(
      (email) => email.toLowerCase().trim() != normalized,
      orElse: () => participantEmails.isNotEmpty ? participantEmails.first : 'User',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'participantUids': participantUids,
      'participantEmails': participantEmails.map((e) => e.toLowerCase().trim()).toList(),
      'lastMessageText': lastMessageText,
      'lastMessageTimestamp': lastMessageTimestamp?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ChatModel.fromMap(Map<String, dynamic> map, String id) {
    return ChatModel(
      id: id,
      participantUids: List<String>.from(map['participantUids'] as List? ?? []),
      participantEmails: List<String>.from(map['participantEmails'] as List? ?? []),
      lastMessageText: map['lastMessageText'] as String?,
      lastMessageTimestamp: map['lastMessageTimestamp'] != null
          ? DateTime.tryParse(map['lastMessageTimestamp'] as String)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
