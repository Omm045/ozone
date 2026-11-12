import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../models/user_model.dart';
import '../database/chat_repository.dart';

abstract class AuthService {
  UserModel? get currentUser;
  Stream<UserModel?> get authStateChanges;
  Future<UserModel> signUp({required String email, required String password});
  Future<UserModel> signIn({required String email, required String password});
  Future<UserModel> signInWithGoogle();
  Future<void> sendPasswordResetEmail({required String email});
  Future<void> sendEmailVerification();
  Future<bool> checkEmailVerification();
  Future<void> signOut();
  Future<void> deleteAccount({
    String? password,
    required ChatRepository chatRepository,
  });
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
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(userModel.toMap(), SetOptions(merge: true));
    } catch (e, stackTrace) {
      debugPrint(
        '[FirebaseAuthService] Warning: Failed to persist user profile in /users/${user.uid} during signUp: $e\n$stackTrace',
      );
    }

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
    final userModel = UserModel(
      uid: user.uid,
      email: normalizedEmail,
      displayName: user.displayName ?? normalizedEmail.split('@').first,
      isEmailVerified: user.emailVerified,
      createdAt: user.metadata.creationTime ?? DateTime.now(),
    );

    // Self-healing: Ensure the Firestore profile document exists on every sign-in,
    // even if it failed or was skipped at sign-up time (e.g. Firestore was unavailable).
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(userModel.toMap(), SetOptions(merge: true));
    } catch (e, stackTrace) {
      debugPrint(
        '[FirebaseAuthService] Warning: Failed to upsert user profile in /users/${user.uid} during signIn: $e\n$stackTrace',
      );
    }

    return userModel;
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google Sign-In was cancelled.');
    }

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);
    final user = userCredential.user!;
    final normalizedEmail = (user.email ?? googleUser.email).toLowerCase().trim();

    final userModel = UserModel(
      uid: user.uid,
      email: normalizedEmail,
      displayName: user.displayName ?? googleUser.displayName ?? normalizedEmail.split('@').first,
      isEmailVerified: user.emailVerified,
      createdAt: user.metadata.creationTime ?? DateTime.now(),
    );

    // Self-healing: Ensure Firestore profile document exists in /users/{uid}
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(userModel.toMap(), SetOptions(merge: true));
    } catch (e, stackTrace) {
      debugPrint(
        '[FirebaseAuthService] Warning: Failed to upsert user profile in /users/${user.uid} during signInWithGoogle: $e\n$stackTrace',
      );
    }

    return userModel;
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    final normalizedEmail = email.toLowerCase().trim();
    if (normalizedEmail.isEmpty) {
      throw Exception('Email address cannot be empty.');
    }
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: normalizedEmail);
    } on FirebaseAuthException {
      // Intentionally suppress specific auth exception to prevent user enumeration
    }
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
      try {
        await _firestore.collection('users').doc(user.uid).set({
          'isEmailVerified': true,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint(
          '[FirebaseAuthService] Warning: Failed to update isEmailVerified in /users/${user.uid}: $e',
        );
      }
    }

    return verified;
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  @override
  Future<void> deleteAccount({
    String? password,
    required ChatRepository chatRepository,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('No user is currently signed in.');
    }

    final uid = user.uid;

    // 1. Delete user data and clean up participant lists in Firestore
    await chatRepository.deleteUserData(uid);

    // 2. Delete Firebase Auth user (with re-auth handling if required)
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (password != null && user.email != null) {
          final cred = EmailAuthProvider.credential(
            email: user.email!,
            password: password,
          );
          await user.reauthenticateWithCredential(cred);
          await user.delete();
        } else {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    // 3. Final sign out
    await _firebaseAuth.signOut();
  }
}

class MockAuthService implements AuthService {
  UserModel? _currentUser;
  final Map<String, ({String password, UserModel user})> _users = {};
  bool _verificationSent = false;
  String? _lastPasswordResetEmail;
  String? get lastPasswordResetEmail => _lastPasswordResetEmail;
  final ChatRepository? chatRepository;

  MockAuthService({
    UserModel? initialUser,
    this.chatRepository,
  }) {
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
    final repo = chatRepository;
    if (repo is MockChatRepository) {
      repo.registerUser(user);
    }
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
    final repo = chatRepository;
    if (repo is MockChatRepository) {
      repo.registerUser(entry.user);
    }
    return entry.user;
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    final user = UserModel(
      uid: 'mock_google_uid_${DateTime.now().millisecondsSinceEpoch}',
      email: 'google_user@ozone.test',
      displayName: 'GoogleUser',
      isEmailVerified: true,
      createdAt: DateTime.now(),
    );
    _currentUser = user;
    final repo = chatRepository;
    if (repo is MockChatRepository) {
      repo.registerUser(user);
    }
    return user;
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    final normalized = email.toLowerCase().trim();
    if (normalized.isEmpty || !normalized.contains('@')) {
      throw Exception('Invalid email address format.');
    }
    _lastPasswordResetEmail = normalized;
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

  @override
  Future<void> deleteAccount({
    String? password,
    required ChatRepository chatRepository,
  }) async {
    if (_currentUser == null) {
      throw Exception('No user is currently signed in.');
    }
    final uid = _currentUser!.uid;
    final email = _currentUser!.email;

    await chatRepository.deleteUserData(uid);
    _users.remove(email);
    _currentUser = null;
    _verificationSent = false;
  }
}
