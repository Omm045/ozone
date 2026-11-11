import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:ozone/core/auth/auth_provider.dart';
import 'package:ozone/core/auth/auth_service.dart';
import 'package:ozone/core/database/chat_repository.dart';
import 'package:ozone/core/webrtc/webrtc_call_manager.dart';
import 'package:ozone/core/webrtc/webrtc_mesh_conference_manager.dart';
import 'package:ozone/design_system/ozone_theme.dart';
import 'package:ozone/features/auth/auth_screen.dart';
import 'package:ozone/features/chats/connect_by_email_dialog.dart';
import 'package:ozone/features/conversation/conversation_screen.dart';
import 'package:ozone/features/call/call_screen.dart';
import 'package:ozone/models/call_session.dart';
import 'package:ozone/models/user_model.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Ozone Full App End-to-End Functionality Tests', () {
    testWidgets('Flow 1: Auth Screen & Navigation - Sign Up, Login UI, and Connect-By-Email Dialog', (tester) async {
      final authService = MockAuthService();
      final authProvider = OzoneAuthProvider(authService: authService);
      await tester.pumpWidget(
        MaterialApp(
          theme: OzoneTheme.darkTheme,
          home: ChangeNotifierProvider<OzoneAuthProvider>.value(
            value: authProvider,
            child: const AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title and input fields
      expect(find.text('OZONE'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2)); // Email and Password fields

      // Toggle to Sign Up mode
      final toggleButton = find.text('Don\'t have an account? Sign Up');
      if (toggleButton.evaluate().isNotEmpty) {
        await tester.tap(toggleButton);
        await tester.pumpAndSettle();
        expect(find.text('Create an account to start calling'), findsOneWidget);
      }

      // Test Connect-By-Email Dialog rendering
      final now = DateTime.now();
      final me = UserModel(uid: 'me_uid', email: 'me@ozone.test', createdAt: now);
      final repo = MockChatRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: OzoneTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: ctx,
                      builder: (_) => ConnectByEmailDialog(
                        currentUser: me,
                        chatRepository: repo,
                        onChatSelected: (_) {},
                      ),
                    );
                  },
                  child: const Text('Open Connect'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Connect by Email'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('Flow 2: Real-Time Messaging UI & Conversation Screen', (tester) async {
      final now = DateTime.now();
      final me = UserModel(uid: 'me_uid', email: 'me@ozone.test', createdAt: now);
      final peer = UserModel(uid: 'peer_uid', email: 'peer@ozone.test', createdAt: now);
      final repo = MockChatRepository(initialUsers: [me, peer]);
      final chat = await repo.getOrCreateChat(me, peer);

      final authService = MockAuthService(initialUser: me, chatRepository: repo);
      final authProvider = OzoneAuthProvider(authService: authService);

      await repo.sendMessage(
        chatId: chat.id,
        text: 'Hello from peer! Real-time check.',
        currentUser: peer,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: OzoneTheme.darkTheme,
          home: ChangeNotifierProvider<OzoneAuthProvider>.value(
            value: authProvider,
            child: ConversationScreen(
              chat: chat,
              chatRepository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('peer@ozone.test'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // Message input field

      // Type in text field
      await tester.enterText(find.byType(TextField), 'Test reply message');
      await tester.pump();
      expect(find.text('Test reply message'), findsOneWidget);
    });

    testWidgets('Flow 3: 1-on-1 Call Pipeline, Hall of Mirrors Protection & Telemetry Modal', (tester) async {
      final now = DateTime.now();
      final caller = UserModel(uid: 'caller_1', email: 'caller@ozone.test', createdAt: now);
      final callee = UserModel(uid: 'callee_2', email: 'callee@ozone.test', createdAt: now);

      final manager = WebRtcCallManager();
      manager.setStatusForTesting(CallStatus.connected);

      await tester.pumpWidget(
        MaterialApp(
          theme: OzoneTheme.darkTheme,
          home: CallScreen(
            caller: caller,
            callee: callee,
            callManager: manager,
            isIncoming: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top center display name and timer
      expect(find.text('Caller'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

      // Bottom floating control pill buttons
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.flip_camera_ios_rounded), findsOneWidget);
      expect(find.byIcon(Icons.screen_share_rounded), findsOneWidget);
      expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);

      // Mute / Unmute
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      expect(manager.isMuted, isTrue);

      await tester.tap(find.byIcon(Icons.mic_off_rounded));
      await tester.pump();
      expect(manager.isMuted, isFalse);

      // Open Telemetry Modal via Speed icon
      await tester.tap(find.byIcon(Icons.speed_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('Sending:'), findsOneWidget);
      expect(find.text('Receiving:'), findsOneWidget);
      expect(find.text('Updates every 2 seconds. Tap to close.'), findsOneWidget);

      // Tap footer to close modal
      await tester.tap(find.text('Updates every 2 seconds. Tap to close.'));
      await tester.pumpAndSettle();

      // Test Screen Share & Hall of Mirrors Protection
      await manager.startScreenShare();
      await tester.pump();

      if (manager.isScreenSharing) {
        expect(find.text('You are sharing your screen'), findsOneWidget);
        expect(find.text('Stop Sharing'), findsOneWidget);

        // Tap Stop Sharing
        await tester.tap(find.text('Stop Sharing'));
        await tester.pump();
        expect(manager.isScreenSharing, isFalse);
      }

      manager.dispose();
    });

    testWidgets('Flow 4: Multi-Peer Mesh Conference Room Grid & Room Code Sharing', (tester) async {
      final confManager = WebRtcMeshConferenceManager();
      confManager.addMockRemoteParticipantForTesting('peer_alpha', 'Alpha');
      confManager.addMockRemoteParticipantForTesting('peer_beta', 'Beta');

      await tester.pumpWidget(
        MaterialApp(
          theme: OzoneTheme.darkTheme,
          home: CallScreen(
            conferenceManager: confManager,
            roomId: 'conf_mesh_777',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // With 2 remote peers (3 total participants), it switches to the responsive multi-peer grid
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);

      // Share Room Code button in top bar
      expect(find.text('Share'), findsOneWidget);
      await tester.tap(find.text('Share'));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);

      confManager.dispose();
    });
  });
}
