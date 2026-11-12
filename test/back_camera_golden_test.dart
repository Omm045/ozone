// Back-camera constraint golden snapshot.
//
// The back camera is confirmed correct on real devices and must never change.
// This test snapshots every constraint map the selector can produce for the
// back camera (isFrontCamera: false) on iOS, Android, macOS and the generic
// path, for every tier and the FPS values the call manager can pass.
//
// The golden file is test/goldens/back_camera_constraints.json. It must only
// be regenerated with explicit owner approval:
//   flutter test test/back_camera_golden_test.dart \
//     --dart-define=UPDATE_BACK_CAMERA_GOLDEN=true
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/webrtc/adaptive_quality_controller.dart';
import 'package:ozone/core/webrtc/camera_constraint_selector.dart';

const _goldenPath = 'test/goldens/back_camera_constraints.json';
const _update = bool.fromEnvironment('UPDATE_BACK_CAMERA_GOLDEN');

void _setPlatform(String platform) {
  CameraConstraintSelector.clearCacheForTesting();
  CameraConstraintSelector.isIOSOverrideForTesting = platform == 'ios';
  CameraConstraintSelector.isAndroidOverrideForTesting = platform == 'android';
  CameraConstraintSelector.isMacOSOverrideForTesting = platform == 'macos';
}

Map<String, dynamic> _snapshot() {
  final out = <String, dynamic>{};
  for (final platform in ['ios', 'android', 'macos', 'generic']) {
    _setPlatform(platform);
    for (final tier in ResolutionTier.values) {
      for (final fps in [30, 60]) {
        out['$platform/${tier.name}/fps$fps'] =
            CameraConstraintSelector.getMediaConstraintsForTier(
          tier,
          isFrontCamera: false,
          maxFps: fps,
        );
      }
    }
    out['$platform/720pFallback'] =
        CameraConstraintSelector.get720pFallbackConstraints(isFrontCamera: false);
    out['$platform/4kUpgrade'] =
        CameraConstraintSelector.get4KUpgradeConstraints(isFrontCamera: false);
    out['$platform/1080p'] =
        CameraConstraintSelector.get1080pConstraints(isFrontCamera: false);
  }
  CameraConstraintSelector.clearCacheForTesting();
  // Round-trip through JSON so the comparison is structural and stable.
  return jsonDecode(jsonEncode(out)) as Map<String, dynamic>;
}

void main() {
  test('back-camera constraint maps match the golden snapshot exactly', () {
    final actual = _snapshot();
    final file = File(_goldenPath);
    if (_update) {
      file.createSync(recursive: true);
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(actual));
    }
    expect(file.existsSync(), isTrue, reason: 'missing $_goldenPath');
    final golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(actual.keys.toSet(), golden.keys.toSet());
    for (final key in golden.keys) {
      expect(actual[key], golden[key], reason: 'back-camera constraints changed for $key');
    }
  });
}
