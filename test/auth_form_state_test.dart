// Regression: during sign-in/up RootGate replaced AuthScreen with a spinner,
// destroying its state; after an error the form fell back to Sign In mode
// with the typed email/password cleared. Found on the real macOS app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ozone/core/auth/auth_provider.dart';
import 'package:ozone/core/auth/auth_service.dart';
import 'package:ozone/core/database/chat_repository.dart';
import 'package:ozone/main.dart';
import 'package:ozone/models/user_model.dart';

/// Real Firebase has network latency, so the loading frame renders; mirror it.
class _SlowAuth extends MockAuthService {
  _SlowAuth({super.chatRepository});
  @override
  Future<UserModel> signUp({required String email, required String password}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.signUp(email: email, password: password);
  }
}

void main() {
  testWidgets('sign-up error keeps Sign Up mode and the typed email', (t) async {
    final repo = MockChatRepository();
    final auth = OzoneAuthProvider(authService: _SlowAuth(chatRepository: repo));
    await t.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<OzoneAuthProvider>.value(value: auth),
      Provider<ChatRepository>.value(value: repo),
    ], child: const OzoneApp()));
    await t.pumpAndSettle();

    await t.tap(find.text("Don't have an account? Sign Up"));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'not-an-email');
    await t.enterText(find.byType(TextField).at(1), 'StrongPassw0rd!');
    await t.tap(find.widgetWithText(ElevatedButton, 'Sign Up'));
    await t.pumpAndSettle();

    expect(find.textContaining('Invalid email address'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign Up'), findsOneWidget,
        reason: 'form must stay in Sign Up mode after an error');
    expect(find.text('not-an-email'), findsOneWidget, reason: 'typed email must be kept');
  });
}
