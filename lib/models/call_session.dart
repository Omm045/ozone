enum CallStatus {
  ringing,
  connecting,
  connected,
  ended,
  rejected,
  failed,
}

enum CallType {
  video,
  audio,
}

class CallSession {
  final String id;
  final String callerUid;
  final String callerEmail;
  final String calleeUid;
  final String calleeEmail;
  final CallStatus status;
  final CallType callType;
  final String? failureReason;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final DateTime createdAt;

  const CallSession({
    required this.id,
    required this.callerUid,
    required this.callerEmail,
    required this.calleeUid,
    required this.calleeEmail,
    this.status = CallStatus.ringing,
    this.callType = CallType.video,
    this.failureReason,
    this.offer,
    this.answer,
    required this.createdAt,
  });

  bool get isAudioOnly => callType == CallType.audio;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'callerUid': callerUid,
      'callerEmail': callerEmail,
      'calleeUid': calleeUid,
      'calleeEmail': calleeEmail,
      'status': status.name,
      'callType': callType.name,
      'failureReason': failureReason,
      'offer': offer,
      'answer': answer,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CallSession.fromMap(Map<String, dynamic> map, String id) {
    return CallSession(
      id: id,
      callerUid: map['callerUid'] as String? ?? '',
      callerEmail: map['callerEmail'] as String? ?? '',
      calleeUid: map['calleeUid'] as String? ?? '',
      calleeEmail: map['calleeEmail'] as String? ?? '',
      status: CallStatus.values.firstWhere(
        (s) => s.name == (map['status'] as String? ?? 'ringing'),
        orElse: () => CallStatus.ringing,
      ),
      callType: CallType.values.firstWhere(
        (t) => t.name == (map['callType'] as String? ?? 'video'),
        orElse: () => CallType.video,
      ),
      failureReason: map['failureReason'] as String?,
      offer: map['offer'] as Map<String, dynamic>?,
      answer: map['answer'] as Map<String, dynamic>?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  CallSession copyWith({
    CallStatus? status,
    CallType? callType,
    String? failureReason,
    Map<String, dynamic>? offer,
    Map<String, dynamic>? answer,
  }) {
    return CallSession(
      id: id,
      callerUid: callerUid,
      callerEmail: callerEmail,
      calleeUid: calleeUid,
      calleeEmail: calleeEmail,
      status: status ?? this.status,
      callType: callType ?? this.callType,
      failureReason: failureReason ?? this.failureReason,
      offer: offer ?? this.offer,
      answer: answer ?? this.answer,
      createdAt: createdAt,
    );
  }
}
