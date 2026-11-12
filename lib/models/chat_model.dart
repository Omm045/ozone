class ChatModel {
  final String id;
  final List<String> participantUids;
  final List<String> participantEmails;
  final String? lastMessageText;
  final DateTime? lastMessageTimestamp;
  final DateTime updatedAt;
  final List<String> hiddenFor;

  const ChatModel({
    required this.id,
    required this.participantUids,
    required this.participantEmails,
    this.lastMessageText,
    this.lastMessageTimestamp,
    required this.updatedAt,
    this.hiddenFor = const [],
  });

  bool isHiddenFor(String uid) {
    final cleanUid = uid.trim();
    return hiddenFor.any((h) => h.trim() == cleanUid);
  }

  bool get isPendingInvite =>
      id.startsWith('invite_') || participantUids.contains('pending_invite');

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

  String otherUserUid(String currentUserUid) {
    return participantUids.firstWhere(
      (uid) => uid != currentUserUid && uid != 'pending_invite',
      orElse: () => '',
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
      'hiddenFor': hiddenFor,
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
      hiddenFor: List<String>.from(map['hiddenFor'] as List? ?? []),
    );
  }

  ChatModel copyWith({
    String? id,
    List<String>? participantUids,
    List<String>? participantEmails,
    String? lastMessageText,
    DateTime? lastMessageTimestamp,
    DateTime? updatedAt,
    List<String>? hiddenFor,
  }) {
    return ChatModel(
      id: id ?? this.id,
      participantUids: participantUids ?? this.participantUids,
      participantEmails: participantEmails ?? this.participantEmails,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageTimestamp: lastMessageTimestamp ?? this.lastMessageTimestamp,
      updatedAt: updatedAt ?? this.updatedAt,
      hiddenFor: hiddenFor ?? this.hiddenFor,
    );
  }
}
