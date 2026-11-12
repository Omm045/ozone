// Regression: tapping Accept on the incoming-call overlay must open the call
// screen. Before the fix, the overlay called context.read<WebRtcCallManager>()
// which no ancestor provides, throwing ProviderNotFoundException after the
// overlay had already been dismissed, so incoming calls could never be
// accepted (shipped in v1.5.0).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ozone/core/auth/auth_provider.dart';
import 'package:ozone/core/auth/auth_service.dart';
import 'package:ozone/core/database/chat_repository.dart';
import 'package:ozone/features/call/call_screen.dart';
import 'package:ozone/main.dart';
import 'package:ozone/models/call_session.dart';
import 'package:ozone/models/user_model.dart';

void main() {
  testWidgets('tapping Accept opens CallScreen using the production provider tree',
      (tester) async {
    final alice = UserModel(
        uid: 'uid_alice', email: 'alice@ozone.test', isEmailVerified: true, createdAt: DateTime.now());
    final bob = UserModel(
        uid: 'uid_bob', email: 'bob@ozone.test', isEmailVerified: true, createdAt: DateTime.now());
    final repo = MockChatRepository(initialUsers: [alice, bob]);
    final auth = OzoneAuthProvider(
        authService: MockAuthService(initialUser: bob, chatRepository: repo));

    // Exactly the providers main.dart registers: no WebRtcCallManager.
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<OzoneAuthProvider>.value(value: auth),
        Provider<ChatRepository>.value(value: repo),
      ],
      child: const OzoneApp(),
    ));
    await tester.pumpAndSettle();

    repo.simulateIncomingCall(CallSession(
      id: 'call_accept_regression',
      callerUid: alice.uid,
      callerEmail: alice.email,
      calleeUid: bob.uid,
      calleeEmail: bob.email,
      callType: CallType.audio,
      createdAt: DateTime.now(),
    ));
    await tester.pump();
    expect(find.byKey(const Key('acceptCallBtn')), findsOneWidget);

    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = errors.add;
    Object? zoneError;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('acceptCallBtn')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }).catchError((Object e) {
      zoneError = e;
    });
    await tester.pump(const Duration(milliseconds: 400));
    FlutterError.onError = prev;

    final providerErrors = [
      ...errors.map((e) => e.exception),
      ?zoneError,
      if (tester.takeException() case final Object e) e,
    ].whereType<ProviderNotFoundException>();
    expect(providerErrors, isEmpty);
    expect(find.byType(CallScreen, skipOffstage: false), findsOneWidget,
        reason: 'Accept must navigate to the call screen');

    // Tear down without running the real call pipeline further.
    await tester.pumpWidget(const SizedBox());
    // Drain errors from the real WebRTC/Firestore pipeline, which is
    // unavailable in a unit test; only the navigation is under test here.
    tester.takeException();
  });
}
