class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final bool isEmailVerified;
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.isEmailVerified = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email.toLowerCase().trim(),
      'displayName': displayName.isEmpty
          ? (email.split('@').first)
          : displayName,
      'isEmailVerified': isEmailVerified,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    final email = (map['email'] as String? ?? '').toLowerCase().trim();
    return UserModel(
      uid: uid,
      email: email,
      displayName: (map['displayName'] as String?)?.isNotEmpty == true
          ? map['displayName'] as String
          : (email.split('@').first),
      isEmailVerified: map['isEmailVerified'] as bool? ?? false,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  UserModel copyWith({
    String? displayName,
    bool? isEmailVerified,
  }) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      createdAt: createdAt,
    );
  }
}
