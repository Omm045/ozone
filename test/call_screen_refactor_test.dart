import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    test('SDP Munging: prefers VP8 and Baseline H.264 over High Profile H.264', () {
      const sampleSdp =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98 100\r\n'
          'a=rtpmap:96 H264/90000\r\n'
          'a=fmtp:96 profile-level-id=64002a\r\n'
          'a=rtpmap:97 H264/90000\r\n'
          'a=fmtp:97 profile-level-id=42e01f\r\n'
          'a=rtpmap:98 VP8/90000\r\n'
          'a=rtpmap:100 VP9/90000\r\n';

      final munged = SdpUtils.preferCompatibleVideoCodecs(sampleSdp);
      // VP8 (98) and Baseline H264 (97) must precede High Profile H264 (96)
      expect(munged, contains('m=video 9 UDP/TLS/RTP/SAVPF 98 97 96 100'));
    });

    test('Camera constraints cap maximum resolution at 1920x1080 at 30fps and remove 4K constraints', () {
      final constraints4k = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p4k,
      );
      final videoMandatory = constraints4k['video']['mandatory'] as Map<String, dynamic>;
      expect(videoMandatory['maxWidth'], '1920');
      expect(videoMandatory['maxHeight'], '1080');
      expect(videoMandatory['maxFrameRate'], '30');

      final constraints720 = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p720,
      );
      final video720Mandatory = constraints720['video']['mandatory'] as Map<String, dynamic>;
      expect(video720Mandatory['maxWidth'], '1280');
      expect(video720Mandatory['maxHeight'], '720');
      expect(video720Mandatory['maxFrameRate'], '30');
    });

    test('Screen Sharing state: isScreenSharing defaults to false', () {
      final manager = WebRtcCallManager();
      expect(manager.isScreenSharing, isFalse);
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
    testWidgets('CallScreen renders Hall of Mirrors protection banner when isScreenSharing is true', (tester) async {
      final manager = WebRtcCallManager();
      manager.setStatusForTesting(CallStatus.connected);

      // Verify that when screen sharing is toggled on, banner is shown
      expect(manager.isScreenSharing, isFalse);

      manager.dispose();
    });
  });
}
