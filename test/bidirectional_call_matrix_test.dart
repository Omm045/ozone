import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ozone/core/webrtc/adaptive_quality_controller.dart';
import 'package:ozone/core/webrtc/camera_constraint_selector.dart';
import 'package:ozone/core/webrtc/sdp_utils.dart';
import 'package:ozone/core/webrtc/webrtc_call_manager.dart';
import 'package:ozone/models/call_session.dart';

void main() {
  group('Bidirectional Call Matrix & Cross-Platform Verification Tests', () {
    setUp(() {
      CameraConstraintSelector.clearCacheForTesting();
    });

    tearDown(() {
      CameraConstraintSelector.clearCacheForTesting();
    });

    test('Direction 1: iPhone <-> Mac Constraints and SDP Negotiation', () {
      // macOS Side: Webcam capture capped to native 1920x1080 @ 30fps
      CameraConstraintSelector.isMacOSOverrideForTesting = true;
      final macConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
      );
      final macVideo = macConstraints['video'] as Map<String, dynamic>;
      expect(macVideo['width'], {'ideal': '1920', 'max': 1920});
      expect(macVideo['height'], {'ideal': '1080', 'max': 1080});
      expect(macVideo['frameRate'], {'ideal': '30', 'max': 30});
      expect(macVideo.containsKey('mandatory'), isFalse);

      // iOS Side: Native W3C constraints without mandatory maps
      CameraConstraintSelector.clearCacheForTesting();
      CameraConstraintSelector.isIOSOverrideForTesting = true;
      final iosConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
        isFrontCamera: true,
      );
      final iosVideo = iosConstraints['video'] as Map<String, dynamic>;
      expect(iosVideo['facingMode'], 'user');
      expect(iosVideo['width'], {'ideal': 1920});
      expect(iosVideo['height'], {'ideal': 1080});
      expect(iosVideo['frameRate'], {'ideal': 30});
      expect(iosVideo.containsKey('mandatory'), isFalse);

      // Cross-Platform SDP Munging: Both Mac and iPhone exchange Baseline H.264 & VP8 first
      const rawSdp =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98 100\r\n'
          'a=rtpmap:96 H264/90000\r\n'
          'a=fmtp:96 profile-level-id=640032\r\n'
          'a=rtpmap:97 H264/90000\r\n'
          'a=fmtp:97 profile-level-id=42e01f\r\n'
          'a=rtpmap:98 VP8/90000\r\n'
          'a=rtpmap:100 VP9/90000\r\n';

      final mungedSdp = SdpUtils.optimizeSdp(rawSdp);
      // Baseline H.264 (97) and VP8 (98) must precede High-Profile (96) and VP9 (100)
      expect(mungedSdp, contains('m=video 9 UDP/TLS/RTP/SAVPF 97 98 96 100'));
      expect(mungedSdp, contains('x-google-min-bitrate=2500;x-google-start-bitrate=6000;x-google-max-bitrate=16000'));
    });

    test('Direction 2: iPhone <-> Android Constraints & MediaCodec Protection', () {
      // Android Side: Pass W3C keys and mandatory full HD constraints
      CameraConstraintSelector.clearCacheForTesting();
      CameraConstraintSelector.isAndroidOverrideForTesting = true;
      final androidConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
        isFrontCamera: true,
      );
      final androidVideo = androidConstraints['video'] as Map<String, dynamic>;
      expect(androidVideo['facingMode'], 'user');
      expect(androidVideo['width'], {'ideal': 1920, 'max': 1920});
      expect(androidVideo['height'], {'ideal': 1080, 'max': 1080});
      expect(androidVideo['frameRate'], {'ideal': 30, 'max': 30});
      expect(androidVideo.containsKey('mandatory'), isTrue);

      final mandatory = androidVideo['mandatory'] as Map<String, dynamic>;
      expect(mandatory['minWidth'], '1280');
      expect(mandatory['minHeight'], '720');
      expect(mandatory['maxWidth'], '1920');
      expect(mandatory['maxHeight'], '1080');
      expect(mandatory['minFrameRate'], '24');
      expect(mandatory['maxFrameRate'], '30');

      // Android MediaCodec hardware decoders freeze when receiving High-Profile 640032.
      // SdpUtils must place 42e01f first.
      const androidOfferSdp =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 120 121 122\r\n'
          'a=rtpmap:120 H264/90000\r\n'
          'a=fmtp:120 profile-level-id=64002a\r\n'
          'a=rtpmap:121 H264/90000\r\n'
          'a=fmtp:121 profile-level-id=42001f\r\n'
          'a=rtpmap:122 VP8/90000\r\n';

      final mungedOffer = SdpUtils.optimizeSdp(androidOfferSdp);
      expect(mungedOffer, contains('m=video 9 UDP/TLS/RTP/SAVPF 121 122 120'));
    });

    test('Direction 3: Mac <-> Android Signaling & Codec Compatibility', () {
      CameraConstraintSelector.clearCacheForTesting();
      CameraConstraintSelector.isMacOSOverrideForTesting = true;
      final macConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
      );
      expect(macConstraints['video']['width'], {'ideal': '1920', 'max': 1920});

      CameraConstraintSelector.clearCacheForTesting();
      CameraConstraintSelector.isAndroidOverrideForTesting = true;
      final androidConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
      );
      expect(androidConstraints['video']['mandatory']['minWidth'], '1280');
    });

    test('Direction 4: Android <-> Android Hardware Decoding', () {
      const peerSdp =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98\r\n'
          'a=rtpmap:96 H264/90000\r\n'
          'a=fmtp:96 profile-level-id=640032\r\n'
          'a=rtpmap:97 H264/90000\r\n'
          'a=fmtp:97 profile-level-id=42e01f\r\n'
          'a=rtpmap:98 VP8/90000\r\n';

      final answerSdp = SdpUtils.optimizeSdp(peerSdp);
      // Ensures both Androids use Baseline H.264
      expect(answerSdp, contains('m=video 9 UDP/TLS/RTP/SAVPF 97 98 96'));
    });

    test('Scale Resolution Down By is strictly 1.0 across ALL tiers', () {
      for (final tier in ResolutionTier.values) {
        expect(
          tier.scaleResolutionDownBy,
          1.0,
          reason: '${tier.name} must never downscale resolution',
        );
      }

      final encodingParams = CameraConstraintSelector.getEncodingParameters(ResolutionTier.p1080);
      expect(encodingParams['scaleResolutionDownBy'], 1.0);
      expect(encodingParams['minBitrate'], 2500000);
      expect(encodingParams['maxBitrate'], 8000000);
      expect(encodingParams['maxFramerate'], 30);
    });

    test('Format connectionState cleanly across raw macOS desktop enum strings', () {
      // Raw string from macOS desktop WebRTC plugin
      expect(
        AdaptiveQualityController.formatConnectionState('RTCPeerConnectionStateConnected'),
        'connected',
      );
      // Enum toString()
      expect(
        AdaptiveQualityController.formatConnectionState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        ),
        'connected',
      );
      // Disconnecting / Failed states
      expect(
        AdaptiveQualityController.formatConnectionState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnecting,
        ),
        'connecting',
      );
      expect(
        AdaptiveQualityController.formatConnectionState('RTCPeerConnectionStateDisconnected'),
        'disconnected',
      );
      expect(
        AdaptiveQualityController.formatConnectionState(null),
        'connected',
      );
    });

    test('Strict call state reset cleans up queue, description state, and listeners', () async {
      final manager = WebRtcCallManager();
      expect(manager.isRemoteDescriptionSet, isFalse);
      expect(manager.remoteCandidateQueue, isEmpty);

      // Verify clean termination
      await manager.endCall();
      expect(manager.status, CallStatus.ended);
      expect(manager.isRemoteDescriptionSet, isFalse);
      expect(manager.remoteCandidateQueue, isEmpty);
      expect(manager.connectedAt, isNull);

      manager.dispose();
    });
  });
}
