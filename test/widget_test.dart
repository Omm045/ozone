import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ozone/core/auth/auth_service.dart';
import 'package:ozone/core/auth/auth_provider.dart';
import 'package:ozone/core/database/chat_repository.dart';
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
}
