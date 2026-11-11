import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ozone/core/auth/auth_service.dart';
import 'package:ozone/core/auth/auth_provider.dart';
import 'package:ozone/core/database/chat_repository.dart';
import 'package:ozone/models/user_model.dart';
import 'package:ozone/models/call_session.dart';
import 'package:ozone/main.dart';

void main() {
  group('App-Level Incoming Call Notification Tests', () {
    late UserModel alice;
    late UserModel bob;
    late MockChatRepository mockRepo;
    late MockAuthService mockAuth;
    late OzoneAuthProvider authProvider;

    setUp(() {
      alice = UserModel(
        uid: 'uid_alice',
        email: 'alice@ozone.test',
        isEmailVerified: true,
        createdAt: DateTime.now(),
      );
      bob = UserModel(
        uid: 'uid_bob',
        email: 'bob@ozone.test',
        isEmailVerified: true,
        createdAt: DateTime.now(),
      );

      mockRepo = MockChatRepository(initialUsers: [alice, bob]);
      mockAuth = MockAuthService(
        initialUser: bob,
        chatRepository: mockRepo,
      );
      authProvider = OzoneAuthProvider(authService: mockAuth);
    });

    testWidgets(
      'User on ChatListScreen sees incoming call UI appear immediately when a ringing call arrives',
      (WidgetTester tester) async {
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

        // 1. User Bob is on the chat list screen
        expect(find.text('OZONE'), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsOneWidget); // "Connect by Email" FAB
        expect(find.text('INCOMING VIDEO CALL'), findsNothing);

        // 2. Alice calls Bob: ringing call document is emitted for Bob's UID
        final incomingCall = CallSession(
          id: 'call_alice_to_bob_101',
          callerUid: alice.uid,
          callerEmail: alice.email,
          calleeUid: bob.uid,
          calleeEmail: bob.email,
          status: CallStatus.ringing,
          createdAt: DateTime.now(),
        );

        mockRepo.simulateIncomingCall(incomingCall);
        await tester.pump();

        // 3. Assert incoming call UI interrupts and is displayed directly over ChatListScreen
        expect(find.text('INCOMING VIDEO CALL'), findsOneWidget);
        expect(find.text('alice@ozone.test'), findsOneWidget);
        expect(find.text('Ozone HD Video Call • Ringing...'), findsOneWidget);
        expect(find.byKey(const Key('declineCallBtn')), findsOneWidget);
        expect(find.byKey(const Key('acceptCallBtn')), findsOneWidget);
      },
    );

    testWidgets(
      'Declining incoming call updates call status and dismisses the incoming call view',
      (WidgetTester tester) async {
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

        // Simulate incoming call
        final incomingCall = CallSession(
          id: 'call_alice_to_bob_102',
          callerUid: alice.uid,
          callerEmail: alice.email,
          calleeUid: bob.uid,
          calleeEmail: bob.email,
          status: CallStatus.ringing,
          createdAt: DateTime.now(),
        );

        mockRepo.simulateIncomingCall(incomingCall);
        await tester.pump();

        expect(find.text('INCOMING VIDEO CALL'), findsOneWidget);

        // Tap Decline button
        await tester.tap(find.byKey(const Key('declineCallBtn')));
        await tester.pumpAndSettle();

        // Incoming call view is dismissed
        expect(find.text('INCOMING VIDEO CALL'), findsNothing);

        // Bob remains on ChatListScreen
        expect(find.text('OZONE'), findsOneWidget);
      },
    );

    testWidgets(
      'Caller cancelling the call automatically dismisses the incoming call view on callee side',
      (WidgetTester tester) async {
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

        // Simulate incoming call
        final incomingCall = CallSession(
          id: 'call_alice_to_bob_103',
          callerUid: alice.uid,
          callerEmail: alice.email,
          calleeUid: bob.uid,
          calleeEmail: bob.email,
          status: CallStatus.ringing,
          createdAt: DateTime.now(),
        );

        mockRepo.simulateIncomingCall(incomingCall);
        await tester.pump();

        expect(find.text('INCOMING VIDEO CALL'), findsOneWidget);

        // Caller cancels (call document cleared/ended in stream)
        mockRepo.clearIncomingCall();
        await tester.pump();

        // Incoming call view automatically clears without user action
        expect(find.text('INCOMING VIDEO CALL'), findsNothing);
      },
    );

    testWidgets(
      'Signing out cancels incoming call subscription and clears active ringing state',
      (WidgetTester tester) async {
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

        // Simulate incoming call
        final incomingCall = CallSession(
          id: 'call_alice_to_bob_104',
          callerUid: alice.uid,
          callerEmail: alice.email,
          calleeUid: bob.uid,
          calleeEmail: bob.email,
          status: CallStatus.ringing,
          createdAt: DateTime.now(),
        );

        mockRepo.simulateIncomingCall(incomingCall);
        await tester.pump();

        expect(find.text('INCOMING VIDEO CALL'), findsOneWidget);

        // User signs out
        await authProvider.signOut();
        await tester.pumpAndSettle();

        // User is now on AuthScreen and incoming call view is gone
        expect(find.text('Sign in to your account'), findsOneWidget);
        expect(find.text('INCOMING VIDEO CALL'), findsNothing);
      },
    );

    testWidgets(
      'Incoming audio call reflects audio call type on overlay',
      (WidgetTester tester) async {
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

        final incomingAudioCall = CallSession(
          id: 'call_audio_alice_to_bob_105',
          callerUid: alice.uid,
          callerEmail: alice.email,
          calleeUid: bob.uid,
          calleeEmail: bob.email,
          status: CallStatus.ringing,
          callType: CallType.audio,
          createdAt: DateTime.now(),
        );

        mockRepo.simulateIncomingCall(incomingAudioCall);
        await tester.pump();

        expect(find.text('INCOMING AUDIO CALL'), findsOneWidget);
        expect(find.text('Ozone Voice Call • Ringing...'), findsOneWidget);
      },
    );
  });
}
