import 'dart:io';
import 'package:flutter/foundation.dart';
import 'adaptive_quality_controller.dart';

class CameraConstraintSelector {
  /// Builds media constraints matching the negotiated send resolution tier and call mode.
  /// When [isAudioOnly] is true, video is completely disabled ('video': false).
  static Map<String, dynamic> getMediaConstraintsForTier(
    ResolutionTier tier, {
    bool isFrontCamera = true,
    bool isAudioOnly = false,
    int maxFps = 30,
  }) {
    final audioConstraints = _getAudioConstraints();

    if (isAudioOnly) {
      return {
        'audio': audioConstraints,
        'video': false,
      };
    }

    return {
      'audio': audioConstraints,
      'video': {
        'mandatory': {
          'minWidth': tier.width.toString(),
          'minHeight': tier.height.toString(),
          'minFrameRate': '30',
        },
        'facingMode': isFrontCamera ? 'user' : 'environment',
        'optional': [
          {'maxFrameRate': maxFps.toString()},
        ],
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
    return {
      'maxBitrate': tier.targetBitrateBps,
      'scaleResolutionDownBy': tier.scaleResolutionDownBy,
      'maxFramerate': maxFramerate ?? tier.targetFps,
    };
  }
}
