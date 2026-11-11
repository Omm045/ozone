import 'dart:io';
import 'package:flutter/foundation.dart';
import 'adaptive_quality_controller.dart';

class CameraConstraintSelector {
  static const int maxResolutionWidth = 1920;
  static const int maxResolutionHeight = 1080;
  static const int defaultResolutionWidth = 1280;
  static const int defaultResolutionHeight = 720;
  static const int maxFpsLimit = 30;

  /// Builds media constraints matching the negotiated send resolution tier and call mode.
  /// When [isAudioOnly] is true, video is completely disabled ('video': false).
  /// Maximum capture resolution is capped to 1920x1080 at 30fps (defaulting to 1280x720 at 30fps for stability)
  /// and removes 4K capture constraints that overload Android MediaCodec and macOS ScreenCaptureKit.
  static Map<String, dynamic> getMediaConstraintsForTier(
    ResolutionTier tier, {
    bool isFrontCamera = true,
    bool isAudioOnly = false,
    int maxFps = maxFpsLimit,
  }) {
    final audioConstraints = _getAudioConstraints();

    if (isAudioOnly) {
      return {
        'audio': audioConstraints,
        'video': false,
      };
    }

    final int targetWidth;
    final int targetHeight;

    if (tier == ResolutionTier.p720) {
      targetWidth = defaultResolutionWidth;
      targetHeight = defaultResolutionHeight;
    } else {
      // Capped to 1920x1080 for 1080p, 1440p, and 4K tiers to protect hardware encoders
      targetWidth = maxResolutionWidth;
      targetHeight = maxResolutionHeight;
    }

    final cappedFps = maxFps.clamp(15, maxFpsLimit);

    return {
      'audio': audioConstraints,
      'video': {
        'mandatory': {
          'minWidth': defaultResolutionWidth.toString(),
          'minHeight': defaultResolutionHeight.toString(),
          'maxWidth': targetWidth.toString(),
          'maxHeight': targetHeight.toString(),
          'minFrameRate': '15',
          'maxFrameRate': cappedFps.toString(),
        },
        'facingMode': isFrontCamera ? 'user' : 'environment',
        'optional': <Map<String, dynamic>>[],
      },
    };
  }

  /// Optimized audio constraints tuned per platform.
  /// On macOS, disabling aggressive WebRTC software noiseSuppression and highpass filter
  /// prevents built-in MacBook mic input from being over-attenuated into near-silence.
  static dynamic _getAudioConstraints() {
    if (kIsWeb) {
      return {
        'echoCancellation': true,
        'autoGainControl': true,
        'noiseSuppression': true,
      };
    }

    if (Platform.isMacOS) {
      return {
        'mandatory': {
          'googEchoCancellation': 'true',
          'googAutoGainControl': 'true',
          'googNoiseSuppression': 'false', // Prevent signal crushing on macOS mic
          'googHighpassFilter': 'false', // Retain natural voice frequencies
          'googTypingNoiseDetection': 'false',
          'googAudioMirroring': 'false',
        },
        'optional': <Map<String, dynamic>>[],
      };
    }

    return {
      'mandatory': {
        'googEchoCancellation': 'true',
        'googAutoGainControl': 'true',
        'googNoiseSuppression': 'true',
        'googHighpassFilter': 'true',
      },
      'optional': <Map<String, dynamic>>[],
    };
  }

  /// Parameters to set on RTCRtpSender via setParameters()
  static Map<String, dynamic> getEncodingParameters(
    ResolutionTier tier, {
    int? maxFramerate,
  }) {
    final bitrate = tier == ResolutionTier.p720 ? 2500000 : 5000000;
    return {
      'maxBitrate': bitrate,
      'scaleResolutionDownBy': tier.scaleResolutionDownBy,
      'maxFramerate': (maxFramerate ?? tier.targetFps).clamp(15, maxFpsLimit),
    };
  }
}
