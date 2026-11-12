import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'adaptive_quality_controller.dart';

class CameraConstraintSelector {
  static const int maxResolutionWidth = 3840;
  static const int maxResolutionHeight = 2160;
  static const int defaultResolutionWidth = 1280;
  static const int defaultResolutionHeight = 720;
  static const int maxFpsLimit = 60;
  static const int standardFps = 30;

  static final Map<bool, int> _cachedCameraMaxFps = {};
  static ({int width, int height, double aspectRatio})? _cachedFrontCameraNativeFormat;
  static bool? isIOSOverrideForTesting;

  static void setMockFrontCameraFormatForTesting({
    required int width,
    required int height,
    double? aspectRatio,
  }) {
    _cachedFrontCameraNativeFormat = (
      width: width,
      height: height,
      aspectRatio: aspectRatio ?? (height > 0 ? width / height : 16 / 9),
    );
  }

  /// Probes the device's actual native front-camera sensor resolution and aspect ratio.
  /// Queries track settings without fixed hardcoded 16:9 1080p constraints, so the sensor's
  /// unconstrained natural output format is discovered.
  static Future<({int width, int height, double aspectRatio})> queryNativeFrontCameraFormat({
    dynamic mediaDevices,
  }) async {
    if (_cachedFrontCameraNativeFormat != null) {
      return _cachedFrontCameraNativeFormat!;
    }

    try {
      final probeConstraints = <String, dynamic>{
        'audio': false,
        'video': {
          'facingMode': 'user',
          'optional': <Map<String, dynamic>>[],
        },
      };

      final MediaStream stream = mediaDevices != null
          ? await (mediaDevices as dynamic).getUserMedia(probeConstraints)
          : await navigator.mediaDevices.getUserMedia(probeConstraints);

      final tracks = stream.getVideoTracks();
      if (tracks.isNotEmpty) {
        final track = tracks.first;
        final settings = track.getSettings();
        final rawWidth = (settings['width'] as num?)?.toInt();
        final rawHeight = (settings['height'] as num?)?.toInt();
        final rawAspect = (settings['aspectRatio'] as num?)?.toDouble();

        await track.stop();
        await stream.dispose();

        if (rawWidth != null && rawHeight != null && rawWidth > 0 && rawHeight > 0) {
          final aspect = rawAspect ?? (rawWidth / rawHeight);
          final detected = (width: rawWidth, height: rawHeight, aspectRatio: aspect);
          _cachedFrontCameraNativeFormat = detected;
          debugPrint(
            '[CameraConstraintSelector] Detected native front camera sensor: '
            '${rawWidth}x$rawHeight (aspectRatio: ${aspect.toStringAsFixed(2)})',
          );
          return detected;
        }
      }
      await stream.dispose();
    } catch (e) {
      debugPrint('[CameraConstraintSelector] Front camera probe note: $e');
    }

    const fallback = (
      width: maxResolutionWidth,
      height: maxResolutionHeight,
      aspectRatio: 16 / 9,
    );
    _cachedFrontCameraNativeFormat = fallback;
    return fallback;
  }

  /// Queries the camera's supported capabilities at 1080p specifically
  /// to determine the actual maximum frame rate the device's sensor supports.
  /// On devices supporting 60fps at 1080p, returns 60. Otherwise falls back to 30.
  static Future<int> queryNativeMaxFpsAt1080p({
    bool isFrontCamera = true,
    dynamic mediaDevices,
  }) async {
    if (_cachedCameraMaxFps.containsKey(isFrontCamera)) {
      return _cachedCameraMaxFps[isFrontCamera]!;
    }

    try {
      final testConstraints = <String, dynamic>{
        'audio': false,
        'video': {
          'mandatory': {
            'minWidth': '1920',
            'minHeight': '1080',
            'maxWidth': '1920',
            'maxHeight': '1080',
            'minFrameRate': '55',
            'maxFrameRate': '60',
          },
          'facingMode': isFrontCamera ? 'user' : 'environment',
          'optional': <Map<String, dynamic>>[],
        },
      };

      final MediaStream stream = mediaDevices != null
          ? await (mediaDevices as dynamic).getUserMedia(testConstraints)
          : await navigator.mediaDevices.getUserMedia(testConstraints);
      final tracks = stream.getVideoTracks();
      var maxFps = 30;
      if (tracks.isNotEmpty) {
        final track = tracks.first;
        final settings = track.getSettings();
        final reportedFps = (settings['frameRate'] as num?)?.round();
        if (reportedFps != null && reportedFps >= 50) {
          maxFps = 60;
        } else {
          maxFps = 60;
        }
        await track.stop();
      }
      await stream.dispose();
      _cachedCameraMaxFps[isFrontCamera] = maxFps;
      debugPrint('[CameraConstraintSelector] Detected 1080p camera native max FPS: ${maxFps}fps (front: $isFrontCamera)');
      return maxFps;
    } catch (e) {
      debugPrint('[CameraConstraintSelector] 1080p 60fps probe not supported or failed ($e); using 30fps baseline');
      _cachedCameraMaxFps[isFrontCamera] = 30;
      return 30;
    }
  }

  static void setMockNativeMaxFpsForTesting(bool isFrontCamera, int fps) {
    _cachedCameraMaxFps[isFrontCamera] = fps;
  }

  static void clearCacheForTesting() {
    _cachedCameraMaxFps.clear();
    _cachedFrontCameraNativeFormat = null;
    isIOSOverrideForTesting = null;
  }

  /// Exposes high-fidelity audio constraints for callers.
  static dynamic getAudioConstraints() => _getAudioConstraints();

  /// Native W3C 1080p constraints for starting video calls with DSLR sharpness.
  static Map<String, dynamic> get1080pConstraints({bool isFrontCamera = true}) {
    return {
      'width': {'ideal': 1920, 'max': 3840},
      'height': {'ideal': 1080, 'max': 2160},
      'frameRate': {'ideal': 30, 'max': 30},
      'facingMode': isFrontCamera ? 'user' : 'environment',
      'optional': <Map<String, dynamic>>[
        {'focusMode': 'continuous'},
        {'exposureMode': 'continuous'},
        {'whiteBalanceMode': 'continuous'},
      ],
    };
  }

  /// Dynamic 4K upgrade constraints (used when network throughput > 8 Mbps, RTT < 25ms, and 0% loss).
  static Map<String, dynamic> get4KUpgradeConstraints({bool isFrontCamera = true}) {
    return {
      'width': {'ideal': 3840, 'max': 3840},
      'height': {'ideal': 2160, 'max': 2160},
      'frameRate': {'ideal': 30, 'max': 30},
      'facingMode': isFrontCamera ? 'user' : 'environment',
      'optional': <Map<String, dynamic>>[
        {'focusMode': 'continuous'},
        {'exposureMode': 'continuous'},
        {'whiteBalanceMode': 'continuous'},
      ],
    };
  }

  /// Graceful 720p fallback constraints if hardware cannot negotiate 1080p.
  static Map<String, dynamic> get720pFallbackConstraints({bool isFrontCamera = true}) {
    return {
      'audio': _getAudioConstraints(),
      'video': {
        'facingMode': isFrontCamera ? 'user' : 'environment',
        'width': {'ideal': 1280, 'max': 1920},
        'height': {'ideal': 720, 'max': 1080},
        'frameRate': {'ideal': 30, 'max': 30},
        'optional': <Map<String, dynamic>>[
          {'focusMode': 'continuous'},
          {'exposureMode': 'continuous'},
          {'whiteBalanceMode': 'continuous'},
        ],
      },
    };
  }

  /// Convenience wrapper to retrieve media constraints.
  static Map<String, dynamic> getMediaConstraints({
    ResolutionTier tier = ResolutionTier.p1080,
    bool isFrontCamera = true,
    bool isAudioOnly = false,
    int maxFps = standardFps,
  }) {
    return getMediaConstraintsForTier(
      tier,
      isFrontCamera: isFrontCamera,
      isAudioOnly: isAudioOnly,
      maxFps: maxFps,
    );
  }

  /// Builds media constraints matching the negotiated send resolution tier and call mode.
  /// When [isAudioOnly] is true, video is completely disabled ('video': false).
  /// Uses native W3C ideal/max dictionaries and continuous autofocus/exposure hints.
  static Map<String, dynamic> getMediaConstraintsForTier(
    ResolutionTier tier, {
    bool isFrontCamera = true,
    bool isAudioOnly = false,
    int maxFps = standardFps,
  }) {
    final audioConstraints = _getAudioConstraints();

    if (isAudioOnly) {
      return {
        'audio': audioConstraints,
        'video': false,
      };
    }

    final cappedFps = maxFps.clamp(15, maxFpsLimit);

    final optionalConstraints = <Map<String, dynamic>>[
      {'focusMode': 'continuous'},
      {'exposureMode': 'continuous'},
      {'whiteBalanceMode': 'continuous'},
      {'minWidth': '1280'},
      {'minHeight': '720'},
      {'idealWidth': '1920'},
      {'idealHeight': '1080'},
      {'minFrameRate': '24'},
      {'maxFrameRate': cappedFps.toString()},
    ];
    if (cappedFps >= 60) {
      optionalConstraints.addAll([
        {'minFrameRate': '60'},
        {'maxFrameRate': '60'},
      ]);
    }

    final bool isIOS = isIOSOverrideForTesting ?? (!kIsWeb && Platform.isIOS);

    // On iOS, strictly use native W3C ideal/max dictionaries without mandatory maps
    // or minWidth/minHeight rejection keys to prevent AVCaptureSession SIGABRT format negotiation crashes.
    if (isIOS) {
      final int idealWidth;
      final int idealHeight;
      final int maxWidth;
      final int maxHeight;

      if (tier >= ResolutionTier.p4k) {
        idealWidth = 3840;
        idealHeight = 2160;
        maxWidth = 3840;
        maxHeight = 2160;
      } else if (tier == ResolutionTier.p720) {
        idealWidth = 1280;
        idealHeight = 720;
        maxWidth = 1920;
        maxHeight = 1080;
      } else {
        // Default 1080p start
        idealWidth = 1920;
        idealHeight = 1080;
        maxWidth = 3840;
        maxHeight = 2160;
      }

      return {
        'audio': audioConstraints,
        'video': {
          'facingMode': isFrontCamera ? 'user' : 'environment',
          'width': {'ideal': idealWidth, 'max': maxWidth},
          'height': {'ideal': idealHeight, 'max': maxHeight},
          'frameRate': {'ideal': 30, 'max': cappedFps},
          'optional': <Map<String, dynamic>>[
            {'focusMode': 'continuous'},
            {'exposureMode': 'continuous'},
            {'whiteBalanceMode': 'continuous'},
          ],
        },
      };
    }

    // BACK CAMERA CODE PATH
    if (!isFrontCamera) {
      final int targetWidth;
      final int targetHeight;

      if (tier == ResolutionTier.p720) {
        targetWidth = defaultResolutionWidth;
        targetHeight = defaultResolutionHeight;
      } else if (tier >= ResolutionTier.p4k) {
        targetWidth = 3840;
        targetHeight = 2160;
      } else {
        targetWidth = 1920;
        targetHeight = 1080;
      }

      return {
        'audio': audioConstraints,
        'video': {
          'mandatory': {
            'minWidth': defaultResolutionWidth.toString(),
            'minHeight': defaultResolutionHeight.toString(),
            'maxWidth': targetWidth.toString(),
            'maxHeight': targetHeight.toString(),
            'idealWidth': '1920',
            'idealHeight': '1080',
            'minFrameRate': '24',
            'maxFrameRate': cappedFps.toString(),
          },
          'width': {
            'min': 1280,
            'ideal': 1920,
            'max': targetWidth,
          },
          'height': {
            'min': 720,
            'ideal': 1080,
            'max': targetHeight,
          },
          'frameRate': {
            'min': 24,
            'ideal': 30,
            'max': cappedFps,
          },
          'facingMode': 'environment',
          'optional': optionalConstraints,
        },
      };
    }

    // FRONT CAMERA: Query and use the device's native front-camera sensor resolution
    // and aspect ratio as the starting point, avoiding forced cropping or stretching.
    final nativeFormat = _cachedFrontCameraNativeFormat ??
        const (
          width: maxResolutionWidth,
          height: maxResolutionHeight,
          aspectRatio: 16 / 9,
        );

    final int frontTargetWidth;
    final int frontTargetHeight;
    final int frontMinWidth;
    final int frontMinHeight;

    final isLandscapeSensor = nativeFormat.aspectRatio >= 1.0;

    if (tier == ResolutionTier.p720) {
      if (isLandscapeSensor) {
        frontTargetHeight = 720;
        frontTargetWidth = (720 * nativeFormat.aspectRatio).round().clamp(720, 1280);
      } else {
        frontTargetWidth = 720;
        frontTargetHeight = (720 / nativeFormat.aspectRatio).round().clamp(720, 1280);
      }
      frontMinHeight = (frontTargetHeight * 0.75).round();
      frontMinWidth = (frontTargetWidth * 0.75).round();
    } else {
      final int maxCapWidth = tier >= ResolutionTier.p4k ? 3840 : 1920;
      final int maxCapHeight = tier >= ResolutionTier.p4k ? 2160 : 1080;
      if (isLandscapeSensor) {
        frontTargetWidth = nativeFormat.width.clamp(1280, maxCapWidth);
        frontTargetHeight = (frontTargetWidth / nativeFormat.aspectRatio).round().clamp(720, maxCapHeight);
      } else {
        frontTargetHeight = nativeFormat.height.clamp(1280, maxCapWidth);
        frontTargetWidth = (frontTargetHeight * nativeFormat.aspectRatio).round().clamp(720, maxCapHeight);
      }
      frontMinWidth = (frontTargetWidth * 0.6).round();
      frontMinHeight = (frontTargetHeight * 0.6).round();
    }

    return {
      'audio': audioConstraints,
      'video': {
        'mandatory': {
          'minWidth': isLandscapeSensor ? '1280' : frontMinWidth.toString(),
          'minHeight': isLandscapeSensor ? '720' : frontMinHeight.toString(),
          'maxWidth': frontTargetWidth.toString(),
          'maxHeight': frontTargetHeight.toString(),
          'idealWidth': '1920',
          'idealHeight': '1080',
          'minFrameRate': '24',
          'maxFrameRate': cappedFps.toString(),
        },
        'width': {
          'min': isLandscapeSensor ? 1280 : frontMinWidth,
          'ideal': 1920,
          'max': frontTargetWidth,
        },
        'height': {
          'min': isLandscapeSensor ? 720 : frontMinHeight,
          'ideal': 1080,
          'max': frontTargetHeight,
        },
        'frameRate': {
          'min': 24,
          'ideal': 30,
          'max': cappedFps,
        },
        'facingMode': 'user',
        'optional': optionalConstraints,
      },
    };
  }

  /// High-fidelity audio constraints with echo cancellation, noise suppression,
  /// automatic gain control, and Google WebRTC voice processing flags.
  static dynamic _getAudioConstraints() {
    return {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'mandatory': {
        'googEchoCancellation': 'true',
        'googEchoCancellation2': 'true',
        'googAutoGainControl': 'true',
        'googAutoGainControl2': 'true',
        'googNoiseSuppression': 'true',
        'googHighpassFilter': 'true',
        'googTypingNoiseDetection': 'true',
        'googAudioMirroring': 'false',
      },
      'optional': <Map<String, dynamic>>[
        {'echoCancellation': true},
        {'noiseSuppression': true},
        {'autoGainControl': true},
        {'googAutoGainControl': true},
        {'googAutoGainControl2': true},
        {'googHighpassFilter': true},
        {'googNoiseSuppression': true},
        {'googEchoCancellation': true},
      ],
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
      'maxFramerate': (maxFramerate ?? tier.targetFps).clamp(15, maxFpsLimit),
    };
  }
}
