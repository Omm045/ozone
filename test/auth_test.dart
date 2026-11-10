import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/auth/auth_service.dart';
import 'package:ozone/core/auth/auth_provider.dart';

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
  });
}
