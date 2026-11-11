import 'package:cloud_firestore/cloud_firestore.dart';

class ConferenceParticipant {
  final String userId;
  final String displayName;
  final bool isMuted;
  final bool isCameraOff;
  final bool isScreenSharing;
  final DateTime joinedAt;

  const ConferenceParticipant({
    required this.userId,
    required this.displayName,
    this.isMuted = false,
    this.isCameraOff = false,
    this.isScreenSharing = false,
    required this.joinedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'displayName': displayName,
      'isMuted': isMuted,
      'isCameraOff': isCameraOff,
      'isScreenSharing': isScreenSharing,
      'joinedAt': Timestamp.fromDate(joinedAt),
    };
  }

  factory ConferenceParticipant.fromMap(Map<String, dynamic> map) {
    DateTime parseTime(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return ConferenceParticipant(
      userId: map['userId'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'Guest',
      isMuted: map['isMuted'] as bool? ?? false,
      isCameraOff: map['isCameraOff'] as bool? ?? false,
      isScreenSharing: map['isScreenSharing'] as bool? ?? false,
      joinedAt: parseTime(map['joinedAt']),
    );
  }

  ConferenceParticipant copyWith({
    String? userId,
    String? displayName,
    bool? isMuted,
    bool? isCameraOff,
    bool? isScreenSharing,
    DateTime? joinedAt,
  }) {
    return ConferenceParticipant(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      isMuted: isMuted ?? this.isMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }
}

class ConferenceRoom {
  final String id;
  final String name;
  final String hostUid;
  final Map<String, ConferenceParticipant> participants;
  final DateTime createdAt;
  final bool isActive;

  const ConferenceRoom({
    required this.id,
    required this.name,
    required this.hostUid,
    this.participants = const {},
    required this.createdAt,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'hostUid': hostUid,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'participants': participants.map((key, value) => MapEntry(key, value.toMap())),
    };
  }

  factory ConferenceRoom.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseTime(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    final rawParticipants = map['participants'] as Map<dynamic, dynamic>? ?? {};
    final parsedParticipants = <String, ConferenceParticipant>{};
    rawParticipants.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        parsedParticipants[key.toString()] = ConferenceParticipant.fromMap(value);
      } else if (value is Map) {
        parsedParticipants[key.toString()] =
            ConferenceParticipant.fromMap(Map<String, dynamic>.from(value));
      }
    });

    return ConferenceRoom(
      id: id,
      name: map['name'] as String? ?? 'Ozone Room',
      hostUid: map['hostUid'] as String? ?? '',
      participants: parsedParticipants,
      createdAt: parseTime(map['createdAt']),
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}
