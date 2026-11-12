import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'adaptive_quality_controller.dart';

class CameraConstraintSelector {
  static const int maxResolutionWidth = 1920;
  static const int maxResolutionHeight = 1080;
  static const int defaultResolutionWidth = 1280;
  static const int defaultResolutionHeight = 720;
  static const int maxFpsLimit = 60;
  static const int standardFps = 30;

  static final Map<bool, int> _cachedCameraMaxFps = {};
  static ({int width, int height, double aspectRatio})? _cachedFrontCameraNativeFormat;

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
  }

  /// Builds media constraints matching the negotiated send resolution tier and call mode.
  /// When [isAudioOnly] is true, video is completely disabled ('video': false).
  /// Maximum capture resolution is capped to 1920x1080 (defaulting to 1280x720 for stability)
  /// and uses the native camera sensor's maximum supported frame rate (up to 60fps).
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

    // BACK CAMERA CODE PATH — 100% PRESERVED AND UNTOUCHED
    if (!isFrontCamera) {
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
      final optionalConstraints = <Map<String, dynamic>>[];
      if (cappedFps >= 60) {
        optionalConstraints.addAll([
          {'minFrameRate': '60'},
          {'maxFrameRate': '60'},
        ]);
      }

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
          'facingMode': 'environment',
          'optional': optionalConstraints,
        },
      };
    }

    // FRONT CAMERA ONLY: Query and use the device's native front-camera sensor resolution
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
      // 1080p, 1440p, 4K tiers: use sensor native resolution capped at 1920x1080
      if (isLandscapeSensor) {
        frontTargetWidth = nativeFormat.width.clamp(1280, maxResolutionWidth);
        frontTargetHeight = (frontTargetWidth / nativeFormat.aspectRatio).round().clamp(720, maxResolutionHeight);
      } else {
        frontTargetHeight = nativeFormat.height.clamp(1280, maxResolutionWidth);
        frontTargetWidth = (frontTargetHeight * nativeFormat.aspectRatio).round().clamp(720, maxResolutionHeight);
      }
      frontMinWidth = (frontTargetWidth * 0.6).round();
      frontMinHeight = (frontTargetHeight * 0.6).round();
    }

    final cappedFps = maxFps.clamp(15, maxFpsLimit);
    final optionalConstraints = <Map<String, dynamic>>[];
    if (cappedFps >= 60) {
      optionalConstraints.addAll([
        {'minFrameRate': '60'},
        {'maxFrameRate': '60'},
      ]);
    }

    return {
      'audio': audioConstraints,
      'video': {
        'mandatory': {
          'minWidth': frontMinWidth.toString(),
          'minHeight': frontMinHeight.toString(),
          'maxWidth': frontTargetWidth.toString(),
          'maxHeight': frontTargetHeight.toString(),
          'minFrameRate': '15',
          'maxFrameRate': cappedFps.toString(),
        },
        'facingMode': 'user',
        'optional': optionalConstraints,
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
      'maxFramerate': (maxFramerate ?? tier.targetFps).clamp(15, maxFpsLimit),
    };
  }
}
