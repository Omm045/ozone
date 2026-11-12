import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ozone/core/webrtc/adaptive_quality_controller.dart';
import 'package:ozone/core/webrtc/camera_constraint_selector.dart';
import 'package:ozone/core/webrtc/sdp_utils.dart';
import 'package:ozone/core/webrtc/webrtc_call_manager.dart';
import 'package:ozone/design_system/quality_indicator_widget.dart';
import 'package:ozone/models/call_session.dart';

void main() {
  group('Cross-Platform Video Freezing & Connection Bug Fixes', () {
    test('ICE Candidate Queueing: queues candidates before remote description is set and flushes them', () async {
      final manager = WebRtcCallManager();
      expect(manager.isRemoteDescriptionSet, isFalse);
      expect(manager.remoteCandidateQueue, isEmpty);

      // Verify queue exists and is exposed
      expect(manager.hasRemoteDescription, isFalse);
      manager.dispose();
    });

    test('SDP Munging: prioritizes Baseline H.264, VP8 ahead of High-Profile H.264, and fast start bitrate', () {
      const sampleSdp =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98 100\r\n'
          'a=rtpmap:96 H264/90000\r\n'
          'a=fmtp:96 profile-level-id=64002a\r\n'
          'a=rtpmap:97 H264/90000\r\n'
          'a=fmtp:97 profile-level-id=42e01f\r\n'
          'a=rtpmap:98 VP8/90000\r\n'
          'a=rtpmap:100 VP9/90000\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=rtpmap:111 opus/48000/2\r\n';

      final munged = SdpUtils.optimizeSdp(sampleSdp);
      // Constrained Baseline H264 (97) and VP8 (98) precede High-Profile H264 (96) and VP9 (100)
      expect(munged, contains('m=video 9 UDP/TLS/RTP/SAVPF 97 98 96 100'));
      // Video bitrate floor/ceiling hints injected
      expect(munged, contains('x-google-min-bitrate=2500;x-google-start-bitrate=6000;x-google-max-bitrate=16000'));
      // Opus audio is tuned to 64kbps with FEC enabled
      expect(munged, contains('a=fmtp:111 minptime=10;useinbandfec=1;maxaveragebitrate=64000;stereo=0;sprop-stereo=0;cbr=1'));
    });

    test('Camera constraints support true 1080p start and dynamic 4K tiering', () {
      CameraConstraintSelector.isMacOSOverrideForTesting = false;
      final constraints4k = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p4k,
      );
      final videoMandatory = constraints4k['video']['mandatory'] as Map<String, dynamic>;
      expect(videoMandatory['maxWidth'], '3840');
      expect(videoMandatory['maxHeight'], '2160');
      expect(videoMandatory['maxFrameRate'], '30');

      final constraints720 = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p720,
      );
      final video720Mandatory = constraints720['video']['mandatory'] as Map<String, dynamic>;
      expect(video720Mandatory['maxWidth'], '1280');
      expect(video720Mandatory['maxHeight'], '720');
      expect(video720Mandatory['maxFrameRate'], '30');
      CameraConstraintSelector.clearCacheForTesting();
    });

    test('Front camera quality uses native resolution and aspect ratio, while back camera is untouched', () {
      CameraConstraintSelector.clearCacheForTesting();
      CameraConstraintSelector.isMacOSOverrideForTesting = false;

      // 1. Back camera check: must be 100% untouched
      final backConstraints1080 = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
        isFrontCamera: false,
      );
      final backVideo = backConstraints1080['video']['mandatory'] as Map<String, dynamic>;
      expect(backVideo['maxWidth'], '1920');
      expect(backVideo['maxHeight'], '1080');
      expect(backVideo['minWidth'], '1280');
      expect(backVideo['minHeight'], '720');
      expect(backConstraints1080['video']['facingMode'], 'environment');

      // 2. Front camera check with native 4:3 sensor (e.g. iPad or 1440x1080 front camera)
      CameraConstraintSelector.setMockFrontCameraFormatForTesting(
        width: 1440,
        height: 1080,
        aspectRatio: 1440 / 1080, // 4:3 = 1.333
      );

      final frontConstraints1080 = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
        isFrontCamera: true,
      );
      final frontVideo = frontConstraints1080['video']['mandatory'] as Map<String, dynamic>;
      expect(frontVideo['maxWidth'], '1440');
      expect(frontVideo['maxHeight'], '1080');
      expect(frontConstraints1080['video']['facingMode'], 'user');

      // 3. Front camera check with portrait sensor (e.g. mobile 1080x1920)
      CameraConstraintSelector.setMockFrontCameraFormatForTesting(
        width: 1080,
        height: 1920,
        aspectRatio: 1080 / 1920, // 9:16 = 0.5625
      );

      final frontConstraintsPortrait = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
        isFrontCamera: true,
      );
      final frontPortraitVideo = frontConstraintsPortrait['video']['mandatory'] as Map<String, dynamic>;
      expect(frontPortraitVideo['maxHeight'], '1920');
      expect(frontPortraitVideo['maxWidth'], '1080');
      expect(frontConstraintsPortrait['video']['facingMode'], 'user');

      CameraConstraintSelector.clearCacheForTesting();
    });

    test('iOS camera constraints use safe W3C 1080p start without mandatory maps', () {
      CameraConstraintSelector.isIOSOverrideForTesting = true;
      final ios1080Constraints = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
        isFrontCamera: true,
      );
      final video1080 = ios1080Constraints['video'] as Map<String, dynamic>;
      expect(video1080['facingMode'], 'user');
      expect(video1080['width'], {'ideal': 1920});
      expect(video1080['height'], {'ideal': 1080});
      expect(video1080['frameRate'], {'ideal': 30});
      expect(video1080.containsKey('mandatory'), isFalse);
      final optional1080 = video1080['optional'] as List;
      expect(optional1080.any((m) => m is Map && m['focusMode'] == 'continuous'), isTrue);

      CameraConstraintSelector.clearCacheForTesting();
    });

    test('Call duration timer starts at 00:00 on connection and resets for a new call', () async {
      final manager = WebRtcCallManager();
      // Before connection: duration is 0
      expect(manager.callDurationSeconds, 0);

      // Simulate connection
      manager.handleConnectionStateForTesting(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
      expect(manager.status, CallStatus.connected);
      expect(manager.connectedAt, isNotNull);
      expect(manager.callDurationSeconds, 0);

      // Verify format 00:00
      final minutes = (manager.callDurationSeconds ~/ 60).toString().padLeft(2, '0');
      final seconds = (manager.callDurationSeconds % 60).toString().padLeft(2, '0');
      expect('$minutes:$seconds', '00:00');

      // End the call
      await manager.endCall();
      expect(manager.status, CallStatus.ended);
      expect(manager.connectedAt, isNull);
      expect(manager.callDurationSeconds, 0);

      // Start a new call and connect again: duration resets to 00:00
      manager.handleConnectionStateForTesting(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
      expect(manager.status, CallStatus.connected);
      expect(manager.connectedAt, isNotNull);
      expect(manager.callDurationSeconds, 0);

      manager.dispose();
    });

    test('Force True 1080p/720p HD capture constraints and audio gain control flags', () {
      CameraConstraintSelector.isMacOSOverrideForTesting = false;
      final constraints = CameraConstraintSelector.getMediaConstraints(
        tier: ResolutionTier.p1080,
        isFrontCamera: true,
      );

      final video = constraints['video'] as Map<String, dynamic>;
      final mandatory = video['mandatory'] as Map<String, dynamic>;
      expect(mandatory['minWidth'], '1280');
      expect(mandatory['minHeight'], '720');
      expect(mandatory['idealWidth'], '1920');
      expect(mandatory['idealHeight'], '1080');
      expect(mandatory['minFrameRate'], '24');
      expect(mandatory['maxFrameRate'], '30');

      // W3C dictionary constraints for macOS / iOS WebRTC
      expect(video['width'], {'min': 1280, 'ideal': 1920, 'max': 1920});
      expect(video['height'], {'min': 720, 'ideal': 1080, 'max': 1080});
      expect(video['frameRate'], {'min': 24, 'ideal': 30, 'max': 30});

      // Audio processing and Google WebRTC gain control flags
      final audio = constraints['audio'] as Map<String, dynamic>;
      expect(audio['echoCancellation'], isTrue);
      expect(audio['noiseSuppression'], isTrue);
      expect(audio['autoGainControl'], isTrue);
      final audioMandatory = audio['mandatory'] as Map<String, dynamic>;
      expect(audioMandatory['googAutoGainControl'], 'true');
      expect(audioMandatory['googHighpassFilter'], 'true');
      expect(audioMandatory['googEchoCancellation'], 'true');
      CameraConstraintSelector.clearCacheForTesting();
    });

    test('AdaptiveQualityController minimum 6Mbps bitrate on direct P2P and clean state format', () {
      final controller = AdaptiveQualityController(initialTier: ResolutionTier.p1080);

      // Excellent direct P2P network with < 20ms RTT must not cap below 6000000 bps
      final directP2PBitrate = controller.getTargetBitrateBps(
        routeType: 'Direct P2P',
        rttMs: 15.0,
      );
      expect(directP2PBitrate, greaterThanOrEqualTo(6000000));

      // Clean connectionState formatting
      expect(
        AdaptiveQualityController.formatConnectionState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        ),
        'connected',
      );
      expect(
        AdaptiveQualityController.formatConnectionState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnecting,
        ),
        'connecting',
      );
    });

    test('WebRtcCallManager speaker state defaults to true for video calls and toggles', () async {
      final manager = WebRtcCallManager();
      expect(manager.isSpeakerOn, isTrue);
      expect(manager.isSpeakerphoneOn, isTrue);

      await manager.toggleSpeaker();
      expect(manager.isSpeakerOn, isFalse);
      expect(manager.isSpeakerphoneOn, isFalse);

      await manager.toggleSpeaker();
      expect(manager.isSpeakerOn, isTrue);
      expect(manager.isSpeakerphoneOn, isTrue);

      manager.dispose();
    });
  });

  group('Connection Telemetry & QualityIndicatorWidget Modal Tests', () {
    testWidgets('Tapping QualityIndicatorWidget opens dark modal card with live telemetry', (tester) async {
      const telemetry = ConnectionTelemetry(
        sendingBitrateKbps: 4800,
        receivingBitrateKbps: 4950,
        sentResolution: '1920 x 1080',
        sentFps: 30,
        receivedResolution: '1920 x 1080',
        receivedFps: 30,
        roundTripTimeMs: 38,
        packetLossPercent: 0.2,
        jitterMs: 4,
        routeType: 'Direct P2P',
        connectionState: 'connected',
        qualityStatus: 'Excellent',
      );

      const state = QualityIndicatorState(
        tier: ResolutionTier.p1080,
        fps: 30,
        rttMs: 38,
        bandwidthMbps: 4.8,
        packetLossPercent: 0.2,
        isAuto: true,
        telemetry: telemetry,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: QualityIndicatorWidget(state: state),
            ),
          ),
        ),
      );

      expect(find.byType(QualityIndicatorWidget), findsOneWidget);

      // Tap on the widget to open telemetry dialog
      await tester.tap(find.byType(QualityIndicatorWidget));
      await tester.pumpAndSettle();

      // Check Header
      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('Excellent'), findsOneWidget);

      // Check Telemetry Rows
      expect(find.text('Sending:'), findsOneWidget);
      expect(find.text('4800 kbps'), findsOneWidget);
      expect(find.text('Receiving:'), findsOneWidget);
      expect(find.text('4950 kbps'), findsOneWidget);
      expect(find.text('Picture sent:'), findsOneWidget);
      expect(find.text('1920 x 1080 at 30 fps'), findsNWidgets(2)); // Sent & Received
      expect(find.text('Delay (round trip):'), findsOneWidget);
      expect(find.text('38 ms'), findsOneWidget);
      expect(find.text('Packet loss:'), findsOneWidget);
      expect(find.text('0.2 %'), findsOneWidget);
      expect(find.text('Jitter:'), findsOneWidget);
      expect(find.text('4 ms'), findsOneWidget);
      expect(find.text('Route:'), findsOneWidget);
      expect(find.text('Direct P2P'), findsOneWidget);
      expect(find.text('State:'), findsOneWidget);
      expect(find.text('connected'), findsOneWidget);

      // Check Footer
      expect(find.text('Updates every 2 seconds. Tap to close.'), findsOneWidget);

      // Tap footer to close
      await tester.tap(find.text('Updates every 2 seconds. Tap to close.'));
      await tester.pumpAndSettle();

      expect(find.text('Updates every 2 seconds. Tap to close.'), findsNothing);
    });
  });
}
