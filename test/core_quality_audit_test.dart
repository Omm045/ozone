import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ozone/core/webrtc/adaptive_quality_controller.dart';
import 'package:ozone/core/webrtc/camera_constraint_selector.dart';
import 'package:ozone/core/webrtc/quality_preferences.dart';
import 'package:ozone/core/webrtc/sdp_utils.dart';
import 'package:ozone/core/webrtc/webrtc_call_manager.dart';

void main() {
  group('Phase 3: Core 1080p/4K Video & Loudspeaker Audio Invariant Suite', () {
    setUp(() {
      CameraConstraintSelector.clearCacheForTesting();
    });

    tearDown(() {
      CameraConstraintSelector.clearCacheForTesting();
    });

    test('1.a Starting Quality Tier defaults to 1080p (1920x1080 @ 30fps) on all platforms', () {
      final defaultTier = QualityPreferences.getDefaultStartingTier();
      expect(defaultTier, ResolutionTier.p1080);
      expect(defaultTier.width, 1920);
      expect(defaultTier.height, 1080);
      expect(defaultTier.targetFps, 30);
      expect(defaultTier.targetBitrateBps, 8000000); // 8 Mbps
    });

    test('1.b iOS uses crash-safe native W3C ideal constraints (no mandatory or minWidth keys)', () {
      CameraConstraintSelector.isIOSOverrideForTesting = true;
      final iosConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
        isFrontCamera: true,
      );

      final video = iosConstraints['video'] as Map<String, dynamic>;
      expect(video['facingMode'], 'user');
      expect(video['width'], {'ideal': 1920});
      expect(video['height'], {'ideal': 1080});
      expect(video['frameRate'], {'ideal': 30});

      // Crucial: Must NOT contain mandatory map or minWidth/minHeight to avoid AVCaptureSession abort
      expect(video.containsKey('mandatory'), isFalse);
      expect(video.containsKey('minWidth'), isFalse);
      expect(video.containsKey('minHeight'), isFalse);

      final optional = video['optional'] as List;
      expect(optional.any((m) => m is Map && m['focusMode'] == 'continuous'), isTrue);
      expect(optional.any((m) => m is Map && m['exposureMode'] == 'continuous'), isTrue);
    });

    test('1.c macOS webcam capture is capped to native 1080p @ 30fps (preventing 4K->VGA fallback)', () {
      CameraConstraintSelector.isMacOSOverrideForTesting = true;
      final macConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
        isFrontCamera: true,
      );

      final video = macConstraints['video'] as Map<String, dynamic>;
      // String ideals: the Darwin capturer ignores numeric ideals (it then
      // selected 640x480 @ 0 fps on a real MacBook Air; QA audit).
      expect(video['width'], {'ideal': '1920', 'max': 1920});
      expect(video['height'], {'ideal': '1080', 'max': 1080});
      expect(video['frameRate'], {'ideal': '30', 'max': 30});
      expect(video.containsKey('mandatory'), isFalse);
    });

    test('1.d Android Camera2 constraints pass Full HD with mandatory keys and fallback', () {
      CameraConstraintSelector.isAndroidOverrideForTesting = true;
      final androidConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
        isFrontCamera: true,
      );

      final video = androidConstraints['video'] as Map<String, dynamic>;
      expect(video['facingMode'], 'user');
      expect(video['width'], {'ideal': 1920, 'max': 1920});
      expect(video['height'], {'ideal': 1080, 'max': 1080});
      expect(video.containsKey('mandatory'), isTrue);

      final mandatory = video['mandatory'] as Map<String, dynamic>;
      expect(mandatory['minWidth'], '1280');
      expect(mandatory['minHeight'], '720');
      expect(mandatory['maxWidth'], '1920');
      expect(mandatory['maxHeight'], '1080');
      expect(mandatory['minFrameRate'], '24');
      expect(mandatory['maxFrameRate'], '30');

      // Graceful 720p fallback helper
      final fallback = CameraConstraintSelector.get720pFallbackConstraints(isFrontCamera: true);
      final fbVideo = fallback['video'] as Map<String, dynamic>;
      expect(fbVideo['width'], {'ideal': 1280, 'max': 1920});
      expect(fbVideo['height'], {'ideal': 720, 'max': 1080});
    });

    test('1.e RTCRtpSender encoding parameters enforce scaleResolutionDownBy == 1.0 and 2.5 Mbps floor', () {
      for (final tier in ResolutionTier.values) {
        expect(
          tier.scaleResolutionDownBy,
          1.0,
          reason: 'Tier ${tier.name} must never downscale resolution',
        );
      }

      // 1080p encoding parameters
      final p1080Params = CameraConstraintSelector.getEncodingParameters(ResolutionTier.p1080);
      expect(p1080Params['minBitrate'], 2500000); // 2.5 Mbps floor
      expect(p1080Params['maxBitrate'], 8000000); // 8 Mbps target
      expect(p1080Params['scaleResolutionDownBy'], 1.0);
      expect(p1080Params['maxFramerate'], 30);

      // 4K encoding parameters
      final p4kParams = CameraConstraintSelector.getEncodingParameters(ResolutionTier.p4k);
      expect(p4kParams['minBitrate'], 2500000);
      expect(p4kParams['maxBitrate'], 16000000); // 16 Mbps for 4K
      expect(p4kParams['scaleResolutionDownBy'], 1.0);

      // Adaptive controller bitrate scaling
      final controller = AdaptiveQualityController(initialTier: ResolutionTier.p1080);
      expect(controller.getTargetBitrateBps(routeType: 'Direct P2P'), 8000000);
      controller.setManualTier(ResolutionTier.p4k);
      expect(controller.getTargetBitrateBps(routeType: 'Direct P2P'), 16000000);
    });

    test('1.f ConnectionTelemetry and raw enum string formats cleanly as lowercase connected', () {
      expect(
        AdaptiveQualityController.formatConnectionState('RTCPeerConnectionStateConnected'),
        'connected',
      );
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
      expect(
        AdaptiveQualityController.formatConnectionState(
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
        ),
        'disconnected',
      );

      const telemetry = ConnectionTelemetry(
        connectionState: 'connected',
        routeType: 'Direct P2P',
      );
      expect(telemetry.connectionState, 'connected');
      expect(telemetry.routeType, 'Direct P2P');
    });

    test('2.a SDP optimization prioritizes Constrained Baseline H.264 & VP8 ahead of 640032 and tunes Opus', () {
      const sdpWithHighAndBaseline =
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

      final optimized = SdpUtils.optimizeSdp(sdpWithHighAndBaseline);

      // Baseline H.264 (97) and VP8 (98) must appear BEFORE High-Profile (96) and VP9 (100)
      expect(optimized, contains('m=video 9 UDP/TLS/RTP/SAVPF 97 98 96 100'));

      // Instant frame 1 bitrate hints injected
      expect(optimized, contains('x-google-min-bitrate=2500;x-google-start-bitrate=6000;x-google-max-bitrate=16000'));

      // Opus tuned to 64 kbps, FEC enabled, mono CBR
      expect(
        optimized,
        contains('a=fmtp:111 minptime=10;useinbandfec=1;maxaveragebitrate=64000;stereo=0;sprop-stereo=0;cbr=1'),
      );
    });

    test('2.b WebRtcCallManager defaults to loudspeaker On and cleanly resets state', () async {
      final manager = WebRtcCallManager();
      expect(manager.isSpeakerOn, isTrue);
      expect(manager.isSpeakerphoneOn, isTrue);

      // Toggle speaker
      await manager.toggleSpeaker();
      expect(manager.isSpeakerOn, isFalse);

      await manager.toggleSpeaker();
      expect(manager.isSpeakerOn, isTrue);

      // Verify clean reset on hangup
      await manager.endCall();
      expect(manager.isRemoteDescriptionSet, isFalse);
      expect(manager.remoteCandidateQueue, isEmpty);
      expect(manager.connectedAt, isNull);
      expect(manager.gatheredCandidateTypes, isEmpty);

      manager.dispose();
    });
  });
}
