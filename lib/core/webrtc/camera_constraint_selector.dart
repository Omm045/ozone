import 'adaptive_quality_controller.dart';

class CameraConstraintSelector {
  /// Builds media constraints matching the negotiated send resolution tier.
  /// Prevents capturing 4K and downscaling when running at 1080p or 720p.
  static Map<String, dynamic> getMediaConstraintsForTier(
    ResolutionTier tier, {
    bool isFrontCamera = true,
  }) {
    return {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': tier.width.toString(),
          'minHeight': tier.height.toString(),
          'minFrameRate': '30',
        },
        'facingMode': isFrontCamera ? 'user' : 'environment',
        'optional': [],
      },
    };
  }

  /// Parameters to set on RTCRtpSender via setParameters()
  static Map<String, dynamic> getEncodingParameters(ResolutionTier tier) {
    return {
      'maxBitrate': tier.targetBitrateBps,
      'scaleResolutionDownBy': tier.scaleResolutionDownBy,
      'maxFramerate': tier.targetFps,
    };
  }
}
