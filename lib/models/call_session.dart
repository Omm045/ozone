enum CallStatus {
  ringing,
  connecting,
  connected,
  ended,
  rejected,
  failed,
}

class CallSession {
  final String id;
  final String callerUid;
  final String callerEmail;
  final String calleeUid;
  final String calleeEmail;
  final CallStatus status;
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
    this.failureReason,
    this.offer,
    this.answer,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'callerUid': callerUid,
      'callerEmail': callerEmail,
      'calleeUid': calleeUid,
      'calleeEmail': calleeEmail,
      'status': status.name,
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
      failureReason: failureReason ?? this.failureReason,
      offer: offer ?? this.offer,
      answer: answer ?? this.answer,
      createdAt: createdAt,
    );
  }
}
