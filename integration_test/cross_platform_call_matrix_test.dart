import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ozone/core/webrtc/adaptive_quality_controller.dart';
import 'package:ozone/core/webrtc/camera_constraint_selector.dart';
import 'package:ozone/core/webrtc/sdp_utils.dart';
import 'package:ozone/core/webrtc/webrtc_call_manager.dart';
import 'package:ozone/design_system/ozone_theme.dart';
import 'package:ozone/features/call/call_screen.dart';
import 'package:ozone/models/call_session.dart';
import 'package:ozone/models/user_model.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Cross-Platform Bidirectional 1:1 Call Matrix Tests', () {
    final now = DateTime.now();

    final macUser = UserModel(uid: 'mac_uid', email: 'mac@ozone.test', createdAt: now);
    final iosUser1 = UserModel(uid: 'ios1_uid', email: 'ios1@ozone.test', createdAt: now);
    final iosUser2 = UserModel(uid: 'ios2_uid', email: 'ios2@ozone.test', createdAt: now);
    final androidUser1 = UserModel(uid: 'android1_uid', email: 'android1@ozone.test', createdAt: now);
    final androidUser2 = UserModel(uid: 'android2_uid', email: 'android2@ozone.test', createdAt: now);

    setUp(() {
      CameraConstraintSelector.clearCacheForTesting();
    });

    tearDown(() {
      CameraConstraintSelector.clearCacheForTesting();
    });

    Future<void> runBilateralCallTest({
      required WidgetTester tester,
      required String pairName,
      required UserModel caller,
      required UserModel callee,
      required bool callerIsMac,
      required bool callerIsIOS,
      required bool callerIsAndroid,
      required bool calleeIsMac,
      required bool calleeIsIOS,
      required bool calleeIsAndroid,
    }) async {
      // 1. Verify Caller Constraints
      CameraConstraintSelector.clearCacheForTesting();
      if (callerIsMac) CameraConstraintSelector.isMacOSOverrideForTesting = true;
      if (callerIsIOS) CameraConstraintSelector.isIOSOverrideForTesting = true;
      if (callerIsAndroid) CameraConstraintSelector.isAndroidOverrideForTesting = true;

      final callerConstraints = CameraConstraintSelector.getMediaConstraintsForTier(ResolutionTier.p1080);
      final callerVideo = callerConstraints['video'] as Map<String, dynamic>;
      expect(callerVideo['width'], isNotNull);
      expect(callerVideo['height'], isNotNull);
      if (callerIsIOS || callerIsMac) {
        expect(callerVideo.containsKey('mandatory'), isFalse, reason: '$pairName caller must not have mandatory map');
      }

      // 2. Verify Callee Constraints
      CameraConstraintSelector.clearCacheForTesting();
      if (calleeIsMac) CameraConstraintSelector.isMacOSOverrideForTesting = true;
      if (calleeIsIOS) CameraConstraintSelector.isIOSOverrideForTesting = true;
      if (calleeIsAndroid) CameraConstraintSelector.isAndroidOverrideForTesting = true;

      final calleeConstraints = CameraConstraintSelector.getMediaConstraintsForTier(ResolutionTier.p1080);
      final calleeVideo = calleeConstraints['video'] as Map<String, dynamic>;
      expect(calleeVideo['width'], isNotNull);
      expect(calleeVideo['height'], isNotNull);

      // 3. Simulated SDP Offer/Answer Exchange
      const rawOfferSdp =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98 100\r\n'
          'a=rtpmap:96 H264/90000\r\n'
          'a=fmtp:96 profile-level-id=640032\r\n'
          'a=rtpmap:97 H264/90000\r\n'
          'a=fmtp:97 profile-level-id=42e01f\r\n'
          'a=rtpmap:98 VP8/90000\r\n'
          'a=rtpmap:100 VP9/90000\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=rtpmap:111 opus/48000/2\r\n';

      final mungedOffer = SdpUtils.optimizeSdp(rawOfferSdp);
      // Constrained-Baseline H.264 (97) + VP8 (98) must precede High-Profile (96) and VP9 (100)
      expect(mungedOffer, contains('m=video 9 UDP/TLS/RTP/SAVPF 97 98 96 100'));
      expect(mungedOffer, contains('x-google-min-bitrate=2500;x-google-start-bitrate=6000;x-google-max-bitrate=16000'));
      expect(mungedOffer, contains('a=fmtp:111 minptime=10;useinbandfec=1;maxaveragebitrate=64000;stereo=0;sprop-stereo=0;cbr=1'));

      // 4. Mount CallScreen UI and test live interactive widgets
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
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Top bar caller pill & non-overlapping badge
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('${caller.email.split('@').first[0].toUpperCase()}${caller.email.split('@').first.substring(1)}'), findsWidgets);

      // Verify Controls: Mute, Camera, Speaker
      expect(manager.isSpeakerOn, isTrue, reason: '$pairName: Loudspeaker must default to ON');
      manager.toggleMute();
      expect(manager.isMuted, isTrue);
      manager.toggleMute();
      expect(manager.isMuted, isFalse);

      await manager.toggleSpeaker();
      expect(manager.isSpeakerOn, isFalse);
      await manager.toggleSpeaker();
      expect(manager.isSpeakerOn, isTrue);

      // Verify Telemetry formatting
      final telemetry = manager.latestTelemetry;
      expect(telemetry.connectionState, 'connected');
      expect(telemetry.routeType, 'Direct P2P');

      // Verify Instant Hangup (< 100ms)
      final stopwatch = Stopwatch()..start();
      await manager.endCall();
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(100), reason: '$pairName: Hangup must complete within 100ms');

      // Verify State Reset
      expect(manager.status, CallStatus.ended);
      expect(manager.isRemoteDescriptionSet, isFalse);
      expect(manager.remoteCandidateQueue, isEmpty);

      manager.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }

    testWidgets('Pair 1: Mac <-> iOS (Bidirectional: Mac->iOS and iOS->Mac)', (tester) async {
      // 1.1 Mac caller -> iOS callee
      await runBilateralCallTest(
        tester: tester,
        pairName: 'Mac -> iOS',
        caller: macUser,
        callee: iosUser1,
        callerIsMac: true,
        callerIsIOS: false,
        callerIsAndroid: false,
        calleeIsMac: false,
        calleeIsIOS: true,
        calleeIsAndroid: false,
      );

      // 1.2 iOS caller -> Mac callee
      await runBilateralCallTest(
        tester: tester,
        pairName: 'iOS -> Mac',
        caller: iosUser1,
        callee: macUser,
        callerIsMac: false,
        callerIsIOS: true,
        callerIsAndroid: false,
        calleeIsMac: true,
        calleeIsIOS: false,
        calleeIsAndroid: false,
      );
    });

    testWidgets('Pair 2: iOS <-> Android (Bidirectional: iOS->Android and Android->iOS)', (tester) async {
      // 2.1 iOS caller -> Android callee
      await runBilateralCallTest(
        tester: tester,
        pairName: 'iOS -> Android',
        caller: iosUser1,
        callee: androidUser1,
        callerIsMac: false,
        callerIsIOS: true,
        callerIsAndroid: false,
        calleeIsMac: false,
        calleeIsIOS: false,
        calleeIsAndroid: true,
      );

      // 2.2 Android caller -> iOS callee
      await runBilateralCallTest(
        tester: tester,
        pairName: 'Android -> iOS',
        caller: androidUser1,
        callee: iosUser1,
        callerIsMac: false,
        callerIsIOS: false,
        callerIsAndroid: true,
        calleeIsMac: false,
        calleeIsIOS: true,
        calleeIsAndroid: false,
      );
    });

    testWidgets('Pair 3: iOS <-> iOS (Bidirectional: Simulator 1 <-> Simulator 2 / iPhone)', (tester) async {
      // 3.1 iOS Device 1 -> iOS Device 2
      await runBilateralCallTest(
        tester: tester,
        pairName: 'iOS 1 -> iOS 2',
        caller: iosUser1,
        callee: iosUser2,
        callerIsMac: false,
        callerIsIOS: true,
        callerIsAndroid: false,
        calleeIsMac: false,
        calleeIsIOS: true,
        calleeIsAndroid: false,
      );

      // 3.2 iOS Device 2 -> iOS Device 1
      await runBilateralCallTest(
        tester: tester,
        pairName: 'iOS 2 -> iOS 1',
        caller: iosUser2,
        callee: iosUser1,
        callerIsMac: false,
        callerIsIOS: true,
        callerIsAndroid: false,
        calleeIsMac: false,
        calleeIsIOS: true,
        calleeIsAndroid: false,
      );
    });

    testWidgets('Pair 4: Android <-> Android (Bidirectional: Emulator 1 <-> Emulator 2)', (tester) async {
      // 4.1 Android 1 -> Android 2
      await runBilateralCallTest(
        tester: tester,
        pairName: 'Android 1 -> Android 2',
        caller: androidUser1,
        callee: androidUser2,
        callerIsMac: false,
        callerIsIOS: false,
        callerIsAndroid: true,
        calleeIsMac: false,
        calleeIsIOS: false,
        calleeIsAndroid: true,
      );

      // 4.2 Android 2 -> Android 1
      await runBilateralCallTest(
        tester: tester,
        pairName: 'Android 2 -> Android 1',
        caller: androidUser2,
        callee: androidUser1,
        callerIsMac: false,
        callerIsIOS: false,
        callerIsAndroid: true,
        calleeIsMac: false,
        calleeIsIOS: false,
        calleeIsAndroid: true,
      );
    });

    testWidgets('Pair 5: Mac <-> Android (Bidirectional: Mac->Android and Android->Mac)', (tester) async {
      // 5.1 Mac caller -> Android callee
      await runBilateralCallTest(
        tester: tester,
        pairName: 'Mac -> Android',
        caller: macUser,
        callee: androidUser1,
        callerIsMac: true,
        callerIsIOS: false,
        callerIsAndroid: false,
        calleeIsMac: false,
        calleeIsIOS: false,
        calleeIsAndroid: true,
      );

      // 5.2 Android caller -> Mac callee
      await runBilateralCallTest(
        tester: tester,
        pairName: 'Android -> Mac',
        caller: androidUser1,
        callee: macUser,
        callerIsMac: false,
        callerIsIOS: false,
        callerIsAndroid: true,
        calleeIsMac: true,
        calleeIsIOS: false,
        calleeIsAndroid: false,
      );
    });

    test('6. Pairwise glare determinism across platforms', () {
      final peers = [macUser, iosUser1, androidUser1, iosUser2];

      // Verify deterministic glare resolution across every distinct pair
      for (int i = 0; i < peers.length; i++) {
        for (int j = i + 1; j < peers.length; j++) {
          final peerA = peers[i];
          final peerB = peers[j];

          final aYields = WebRtcCallManager.shouldYieldGlare(myUid: peerA.uid, peerUid: peerB.uid);
          final bYields = WebRtcCallManager.shouldYieldGlare(myUid: peerB.uid, peerUid: peerA.uid);

          // Exactly one party must yield, ensuring zero collisions
          expect(aYields != bYields, isTrue, reason: 'Glare between ${peerA.email} and ${peerB.email} must resolve deterministically');
        }
      }
    });
  });
}
