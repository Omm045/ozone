// ignore_for_file: subtype_of_sealed_class, annotate_overrides

import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ozone/core/auth/auth_service.dart';
import 'package:ozone/core/auth/auth_provider.dart';
import 'package:ozone/core/database/chat_repository.dart';
import 'package:ozone/models/user_model.dart';

void main() {
  group('Auth Service & Provider Tests', () {
    test('Sign up creates unverified user and transitions to awaitingVerification', () async {
      final mockAuth = MockAuthService();
      final authProvider = OzoneAuthProvider(authService: mockAuth);

      expect(authProvider.status, AuthStatus.unauthenticated);

      final success = await authProvider.signUp(
        email: 'alex@ozone.test',
        password: 'securePassword123',
      );

      expect(success, isTrue);
      expect(authProvider.status, AuthStatus.awaitingVerification);
      expect(authProvider.currentUser?.email, 'alex@ozone.test');
      expect(authProvider.currentUser?.isEmailVerified, isFalse);
    });

    test('Email verification updates status to authenticated', () async {
      final mockAuth = MockAuthService();
      final authProvider = OzoneAuthProvider(authService: mockAuth);

      await authProvider.signUp(
        email: 'bob@ozone.test',
        password: 'securePassword123',
      );
      expect(authProvider.isAwaitingVerification, isTrue);

      final verified = await authProvider.checkEmailVerification();
      expect(verified, isTrue);
      expect(authProvider.status, AuthStatus.authenticated);
      expect(authProvider.currentUser?.isEmailVerified, isTrue);
    });

    test('Weak password (< 6 chars) fails and sets error status', () async {
      final mockAuth = MockAuthService();
      final authProvider = OzoneAuthProvider(authService: mockAuth);

      final success = await authProvider.signUp(
        email: 'charlie@ozone.test',
        password: '123',
      );

      expect(success, isFalse);
      expect(authProvider.status, AuthStatus.error);
      expect(authProvider.errorMessage, contains('at least 6 characters'));
    });

    test('Sign in with wrong password fails', () async {
      final mockAuth = MockAuthService();
      final authProvider = OzoneAuthProvider(authService: mockAuth);

      await authProvider.signUp(
        email: 'david@ozone.test',
        password: 'correctPassword',
      );
      await authProvider.signOut();
      expect(authProvider.status, AuthStatus.unauthenticated);

      final success = await authProvider.signIn(
        email: 'david@ozone.test',
        password: 'wrongPassword',
      );
      expect(success, isFalse);
      expect(authProvider.status, AuthStatus.error);
      expect(authProvider.errorMessage, contains('Incorrect password'));
    });

    test('Sign out clears session and returns to unauthenticated', () async {
      final mockAuth = MockAuthService();
      final authProvider = OzoneAuthProvider(authService: mockAuth);

      await authProvider.signUp(
        email: 'eva@ozone.test',
        password: 'password123',
      );
      await authProvider.checkEmailVerification();
      expect(authProvider.isAuthenticated, isTrue);

      await authProvider.signOut();
      expect(authProvider.status, AuthStatus.unauthenticated);
      expect(authProvider.currentUser, isNull);
    });

    test(
      'Self-healing profile: missing Firestore document is created on signIn so lookupUserByEmail succeeds',
      () async {
        final fakeAuth = FakeFirebaseAuth();
        final fakeFirestore = FakeFirebaseFirestore();

        const userEmail = 'healed_user@ozone.test';
        const userUid = 'uid_healed_user_123';
        const password = 'password123';

        // 1. Simulate existing user with a valid Firebase Auth session
        // but NO corresponding /users/{uid} document in Firestore.
        fakeAuth.users[userEmail] = (
          password: password,
          user: FakeUser(
            uid: userUid,
            email: userEmail,
            displayName: 'Healed User',
            emailVerified: true,
          ),
        );

        final chatRepo = FirestoreChatRepository(firestore: fakeFirestore);

        // Before signIn: lookupUserByEmail fails because the profile document is missing
        final beforeSignIn = await chatRepo.lookupUserByEmail(userEmail);
        expect(beforeSignIn, isNull);

        // 2. Call signIn() on FirebaseAuthService
        final authService = FirebaseAuthService(
          firebaseAuth: fakeAuth,
          firestore: fakeFirestore,
        );
        final signedInUser = await authService.signIn(
          email: userEmail,
          password: password,
        );
        expect(signedInUser.uid, userUid);
        expect(signedInUser.email, userEmail);

        // 3. After signIn: lookupUserByEmail() succeeds because signIn self-healed the missing document
        final afterSignIn = await chatRepo.lookupUserByEmail(userEmail);
        expect(afterSignIn, isNotNull);
        expect(afterSignIn?.uid, userUid);
        expect(afterSignIn?.email, userEmail);
        expect(afterSignIn?.displayName, 'Healed User');
        expect(afterSignIn?.isEmailVerified, isTrue);
      },
    );

    test(
      'Self-healing profile in MockAuthService: missing user in MockChatRepository is registered on signIn',
      () async {
        final mockChatRepo = MockChatRepository();

        const email = 'mock_healed@ozone.test';
        const password = 'password123';

        // Sign up with an independent auth service so it is not in mockChatRepo
        final independentAuth = MockAuthService();
        await independentAuth.signUp(email: email, password: password);

        // Populate mockAuth credentials directly to simulate missing chat doc
        final entry = UserModel(
          uid: 'uid_mock_healed',
          email: email,
          createdAt: DateTime.now(),
        );
        final mockAuthWithUser = MockAuthService(
          initialUser: entry,
          chatRepository: mockChatRepo,
        );

        // Before signIn: user is not in mockChatRepo
        expect(await mockChatRepo.lookupUserByEmail(email), isNull);

        // signIn self-heals by registering user in mockChatRepo
        await mockAuthWithUser.signIn(email: email, password: password);

        // After signIn: user is found in mockChatRepo
        final found = await mockChatRepo.lookupUserByEmail(email);
        expect(found, isNotNull);
        expect(found?.email, email);
      },
    );

    test('sendPasswordResetEmail succeeds for valid email', () async {
      final mockAuth = MockAuthService();
      final authProvider = OzoneAuthProvider(authService: mockAuth);

      final result = await authProvider.sendPasswordResetEmail(email: 'user@ozone.test');
      expect(result, isTrue);
    });

    test('sendPasswordResetEmail fails for empty email', () async {
      final mockAuth = MockAuthService();
      final authProvider = OzoneAuthProvider(authService: mockAuth);

      final result = await authProvider.sendPasswordResetEmail(email: '');
      expect(result, isFalse);
      expect(authProvider.errorMessage, contains('Invalid email address format'));
    });

    test('signInWithGoogle signs in user and updates provider state', () async {
      final mockAuth = MockAuthService();
      final authProvider = OzoneAuthProvider(authService: mockAuth);

      final result = await authProvider.signInWithGoogle();
      expect(result, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.currentUser?.email, contains('google_user'));
    });
  });
}

class FakeUserMetadata implements UserMetadata {
  @override
  final DateTime creationTime = DateTime.now();
  @override
  final DateTime lastSignInTime = DateTime.now();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUser implements User {
  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? displayName;
  @override
  final bool emailVerified;
  @override
  final UserMetadata metadata;

  FakeUser({
    required this.uid,
    this.email,
    this.displayName,
    this.emailVerified = true,
  }) : metadata = FakeUserMetadata();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUserCredential implements UserCredential {
  @override
  final User? user;

  FakeUserCredential(this.user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirebaseAuth implements FirebaseAuth {
  final Map<String, ({String password, FakeUser user})> users = {};
  FakeUser? _currentUser;

  @override
  User? get currentUser => _currentUser;

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final entry = users[email.toLowerCase().trim()];
    if (entry == null || entry.password != password) {
      throw FirebaseAuthException(code: 'user-not-found');
    }
    _currentUser = entry.user;
    return FakeUserCredential(entry.user);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQueryDocumentSnapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic> _data;

  FakeQueryDocumentSnapshot(this.id, this._data);

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  FakeQuerySnapshot(this.docs);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuery implements Query<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String collectionPath;
  final String? filterField;
  final Object? filterValue;
  final int? queryLimit;

  FakeQuery(
    this.firestore,
    this.collectionPath,
    this.filterField,
    this.filterValue, [
    this.queryLimit,
  ]);

  @override
  Query<Map<String, dynamic>> limit(int limit) {
    return FakeQuery(firestore, collectionPath, filterField, filterValue, limit);
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final col = firestore.collections[collectionPath] ?? {};
    var docs = col.entries.where((entry) {
      if (filterField != null) {
        return entry.value[filterField] == filterValue;
      }
      return true;
    }).map((entry) => FakeQueryDocumentSnapshot(entry.key, entry.value)).toList();

    if (queryLimit != null && docs.length > queryLimit!) {
      docs = docs.sublist(0, queryLimit!);
    }

    return FakeQuerySnapshot(docs);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String collectionPath;
  final String docId;

  FakeDocumentReference(this.firestore, this.collectionPath, this.docId);

  @override
  String get id => docId;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    final col = firestore.collections.putIfAbsent(collectionPath, () => {});
    if (options?.merge == true && col.containsKey(docId)) {
      col[docId] = {...col[docId]!, ...data};
    } else {
      col[docId] = Map<String, dynamic>.from(data);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCollectionReference implements CollectionReference<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String collectionPath;

  FakeCollectionReference(this.firestore, this.collectionPath);

  @override
  FakeDocumentReference doc([String? path]) {
    final docId = path ?? 'doc_${DateTime.now().millisecondsSinceEpoch}';
    return FakeDocumentReference(firestore, collectionPath, docId);
  }

  @override
  FakeQuery where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    return FakeQuery(firestore, collectionPath, field as String, isEqualTo);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirebaseFirestore implements FirebaseFirestore {
  final Map<String, Map<String, Map<String, dynamic>>> collections = {};

  @override
  FakeCollectionReference collection(String path) {
    return FakeCollectionReference(this, path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
