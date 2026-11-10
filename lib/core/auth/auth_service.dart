import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';

abstract class AuthService {
  UserModel? get currentUser;
  Stream<UserModel?> get authStateChanges;
  Future<UserModel> signUp({required String email, required String password});
  Future<UserModel> signIn({required String email, required String password});
  Future<void> sendEmailVerification();
  Future<bool> checkEmailVerification();
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  FirebaseAuthService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  UserModel? get currentUser {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
      isEmailVerified: user.emailVerified,
      createdAt: user.metadata.creationTime ?? DateTime.now(),
    );
  }

  @override
  Stream<UserModel?> get authStateChanges {
    return _firebaseAuth.authStateChanges().map((user) {
      if (user == null) return null;
      return UserModel(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? '',
        isEmailVerified: user.emailVerified,
        createdAt: user.metadata.creationTime ?? DateTime.now(),
      );
    });
  }

  @override
  Future<UserModel> signUp({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.toLowerCase().trim();
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );

    final user = credential.user!;
    final userModel = UserModel(
      uid: user.uid,
      email: normalizedEmail,
      displayName: normalizedEmail.split('@').first,
      isEmailVerified: false,
      createdAt: DateTime.now(),
    );

    // Persist user record in Firestore under /users/{uid}
    await _firestore
        .collection('users')
        .doc(user.uid)
        .set(userModel.toMap(), SetOptions(merge: true));

    // Send verification email
    await user.sendEmailVerification();

    return userModel;
  }

  @override
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.toLowerCase().trim();
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );

    final user = credential.user!;
    return UserModel(
      uid: user.uid,
      email: normalizedEmail,
      displayName: user.displayName ?? normalizedEmail.split('@').first,
      isEmailVerified: user.emailVerified,
      createdAt: user.metadata.creationTime ?? DateTime.now(),
    );
  }

  @override
  Future<void> sendEmailVerification() async {
    final user = _firebaseAuth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  @override
  Future<bool> checkEmailVerification() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    await user.reload();
    final updated = _firebaseAuth.currentUser;
    final verified = updated?.emailVerified ?? false;

    if (verified) {
      await _firestore.collection('users').doc(user.uid).update({
        'isEmailVerified': true,
      });
    }

    return verified;
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }
}

class MockAuthService implements AuthService {
  UserModel? _currentUser;
  final Map<String, ({String password, UserModel user})> _users = {};
  bool _verificationSent = false;

  MockAuthService({UserModel? initialUser}) {
    if (initialUser != null) {
      _users[initialUser.email.toLowerCase().trim()] = (
        password: 'password123',
        user: initialUser,
      );
      _currentUser = initialUser;
    }
  }

  @override
  UserModel? get currentUser => _currentUser;

  @override
  Stream<UserModel?> get authStateChanges => Stream.value(_currentUser);

  @override
  Future<UserModel> signUp({
    required String email,
    required String password,
  }) async {
    final normalized = email.toLowerCase().trim();
    if (!normalized.contains('@') || !normalized.contains('.')) {
      throw Exception('Invalid email address');
    }
    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }
    if (_users.containsKey(normalized)) {
      throw Exception('An account with this email already exists');
    }

    final user = UserModel(
      uid: 'mock_uid_${DateTime.now().millisecondsSinceEpoch}',
      email: normalized,
      displayName: normalized.split('@').first,
      isEmailVerified: false,
      createdAt: DateTime.now(),
    );

    _users[normalized] = (password: password, user: user);
    _currentUser = user;
    _verificationSent = true;
    return user;
  }

  @override
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final normalized = email.toLowerCase().trim();
    final entry = _users[normalized];
    if (entry == null) {
      throw Exception('No user found for $normalized');
    }
    if (entry.password != password) {
      throw Exception('Incorrect password');
    }

    _currentUser = entry.user;
    return entry.user;
  }

  @override
  Future<void> sendEmailVerification() async {
    _verificationSent = true;
  }

  @override
  Future<bool> checkEmailVerification() async {
    if (_currentUser == null) return false;
    if (_verificationSent) {
      _currentUser = _currentUser!.copyWith(isEmailVerified: true);
      final entry = _users[_currentUser!.email];
      if (entry != null) {
        _users[_currentUser!.email] = (password: entry.password, user: _currentUser!);
      }
      return true;
    }
    return _currentUser!.isEmailVerified;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _verificationSent = false;
  }
}
