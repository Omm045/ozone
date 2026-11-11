import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/auth/auth_provider.dart';
import 'package:ozone/core/auth/auth_service.dart';
import 'package:ozone/core/database/chat_repository.dart';
import 'package:ozone/core/webrtc/camera_constraint_selector.dart';
import 'package:ozone/core/webrtc/quality_preferences.dart';
import 'package:ozone/core/webrtc/adaptive_quality_controller.dart';
import 'package:ozone/core/utils/update_checker.dart';
import 'package:ozone/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 8: Permanent Account Deletion Tests', () {
    late MockChatRepository chatRepository;
    late MockAuthService authService;
    late UserModel alice;
    late UserModel bob;

    setUp(() {
      alice = UserModel(
        uid: 'uid_alice',
        email: 'alice@ozone.test',
        displayName: 'Alice',
        isEmailVerified: true,
        createdAt: DateTime.now(),
      );

      bob = UserModel(
        uid: 'uid_bob',
        email: 'bob@ozone.test',
        displayName: 'Bob',
        isEmailVerified: true,
        createdAt: DateTime.now(),
      );

      chatRepository = MockChatRepository(initialUsers: [alice, bob]);
      authService = MockAuthService(
        initialUser: alice,
        chatRepository: chatRepository,
      );
    });

    test('Account deletion removes user from participantUids and adds to hiddenFor, preserving chat for peer', () async {
      // 1. Create a chat between Alice and Bob
      final chat = await chatRepository.getOrCreateChat(bob, alice);
      expect(chat.participantUids, containsAll(['uid_alice', 'uid_bob']));

      // 2. Send messages
      await chatRepository.sendMessage(
        chatId: chat.id,
        text: 'Hello Bob!',
        currentUser: alice,
      );
      await chatRepository.sendMessage(
        chatId: chat.id,
        text: 'Hi Alice!',
        currentUser: bob,
      );

      // Verify both see the chat initially
      final aliceInitialChats = await chatRepository.getChatsStream(alice.uid).first;
      expect(aliceInitialChats.length, 1);
      expect(aliceInitialChats.first.id, chat.id);

      final bobInitialChats = await chatRepository.getChatsStream(bob.uid).first;
      expect(bobInitialChats.length, 1);
      expect(bobInitialChats.first.id, chat.id);

      // 3. Alice deletes her account
      await chatRepository.deleteUserData(alice.uid);

      // 4. Verify Alice's profile is deleted
      final lookupAlice = await chatRepository.lookupUserByEmail(alice.email);
      expect(lookupAlice, isNull);

      // 5. Verify Alice's chat list no longer shows the chat
      final alicePostDeletionChats = await chatRepository.getChatsStream(alice.uid).first;
      expect(alicePostDeletionChats, isEmpty);

      // 6. Verify Bob STILL HAS the chat with all message history intact
      final bobPostDeletionChats = await chatRepository.getChatsStream(bob.uid).first;
      expect(bobPostDeletionChats.length, 1);
      expect(bobPostDeletionChats.first.id, chat.id);

      final bobMessages = await chatRepository.getMessagesStream(chat.id).first;
      expect(bobMessages.length, 2);
      expect(bobMessages[0].text, 'Hello Bob!');
      expect(bobMessages[1].text, 'Hi Alice!');
    });

    test('OzoneAuthProvider deleteAccount signs out and cleans state', () async {
      final authProvider = OzoneAuthProvider(authService: authService);
      expect(authProvider.currentUser?.uid, alice.uid);
      expect(authProvider.isAuthenticated, isTrue);

      final success = await authProvider.deleteAccount(chatRepository: chatRepository);
      expect(success, isTrue);
      expect(authProvider.currentUser, isNull);
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.status, AuthStatus.unauthenticated);
    });
  });

  group('Part 6 & 7: Settings & Version Check Tests', () {
    test('QualityPreferences persists tier and Auto mode correctly', () async {
      SharedPreferences.setMockInitialValues({});

      // Initial preference is Auto (null)
      var saved = await QualityPreferences.getSavedPreference();
      expect(saved, isNull);

      // Save 1080p
      await QualityPreferences.savePreference(ResolutionTier.p1080);
      saved = await QualityPreferences.getSavedPreference();
      expect(saved, ResolutionTier.p1080);

      // Save 4K
      await QualityPreferences.savePreference(ResolutionTier.p4k);
      saved = await QualityPreferences.getSavedPreference();
      expect(saved, ResolutionTier.p4k);

      // Reset to Auto
      await QualityPreferences.savePreference(null);
      saved = await QualityPreferences.getSavedPreference();
      expect(saved, isNull);
    });

    test('Semver version comparison logic correctly detects updates', () {
      // Basic updates
      expect(UpdateChecker.isVersionNewer('v1.0.1', '1.0.0'), isTrue);
      expect(UpdateChecker.isVersionNewer('1.1.0', '1.0.9'), isTrue);
      expect(UpdateChecker.isVersionNewer('2.0.0', '1.9.9'), isTrue);

      // Same version
      expect(UpdateChecker.isVersionNewer('v1.0.0', '1.0.0'), isFalse);
      expect(UpdateChecker.isVersionNewer('1.0.0', '1.0.0'), isFalse);

      // Older version
      expect(UpdateChecker.isVersionNewer('0.9.0', '1.0.0'), isFalse);
      expect(UpdateChecker.isVersionNewer('1.0.0', '1.0.1'), isFalse);

      // Build numbers ignored
      expect(UpdateChecker.isVersionNewer('v1.0.0+2', '1.0.0+1'), isFalse);
      expect(UpdateChecker.isVersionNewer('v1.0.1+1', '1.0.0+99'), isTrue);
    });
  });

  group('Part 5: Native Max FPS Probe & Constraint Tests', () {
    test('CameraConstraintSelector fallback to 30fps on failure', () async {
      // Querying without camera hardware in test environment safely returns 30fps standard baseline
      final fps = await CameraConstraintSelector.queryNativeMaxFpsAt1080p(isFrontCamera: true);
      expect(fps, 30);
    });

    test('CameraConstraintSelector getEncodingParameters scales bitrate properly', () {
      final p1080Params = CameraConstraintSelector.getEncodingParameters(ResolutionTier.p1080);
      expect(p1080Params['maxBitrate'], 5500000);
      expect(p1080Params['scaleResolutionDownBy'], 1.0);

      final p720Params = CameraConstraintSelector.getEncodingParameters(ResolutionTier.p720);
      expect(p720Params['maxBitrate'], 2500000);
      expect(p720Params['scaleResolutionDownBy'], 1.5);

      final p4kParams = CameraConstraintSelector.getEncodingParameters(ResolutionTier.p4k);
      expect(p4kParams['maxBitrate'], 20000000);
      expect(p4kParams['scaleResolutionDownBy'], 1.0);
    });
  });
}
