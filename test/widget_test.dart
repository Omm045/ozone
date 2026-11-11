import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ozone/core/auth/auth_service.dart';
import 'package:ozone/core/auth/auth_provider.dart';
import 'package:ozone/core/database/chat_repository.dart';
import 'package:ozone/models/user_model.dart';
import 'package:ozone/main.dart';

void main() {
  testWidgets('OzoneApp renders AuthScreen when unauthenticated', (WidgetTester tester) async {
    final mockAuth = MockAuthService();
    final mockRepo = MockChatRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => OzoneAuthProvider(authService: mockAuth),
          ),
          Provider<ChatRepository>.value(value: mockRepo),
        ],
        child: const OzoneApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('OZONE'), findsOneWidget);
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('Chat list displays existing conversation on fresh sign-in without Connect-by-Email', (WidgetTester tester) async {
    final alice = UserModel(
      uid: 'uid_alice',
      email: 'alice@ozone.test',
      isEmailVerified: true,
      createdAt: DateTime.now(),
    );
    final bob = UserModel(
      uid: 'uid_bob',
      email: 'bob@ozone.test',
      isEmailVerified: true,
      createdAt: DateTime.now(),
    );

    final mockRepo = MockChatRepository(initialUsers: [alice, bob]);
    // Create an existing chat between Alice and Bob
    await mockRepo.getOrCreateChat(bob, alice);

    // Simulate fresh sign-in / app launch with Alice authenticated
    final mockAuth = MockAuthService(
      initialUser: alice,
      chatRepository: mockRepo,
    );

    final authProvider = OzoneAuthProvider(authService: mockAuth);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<OzoneAuthProvider>.value(value: authProvider),
          Provider<ChatRepository>.value(value: mockRepo),
        ],
        child: const OzoneApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Bob appears directly in Alice's chat list on launch
    expect(find.text('bob@ozone.test'), findsOneWidget);
    // Verify empty state "No conversations yet" is NOT shown
    expect(find.text('No conversations yet'), findsNothing);

    // Tapping the conversation opens the conversation view with messaging and calling
    await tester.tap(find.text('bob@ozone.test'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
  });
}
