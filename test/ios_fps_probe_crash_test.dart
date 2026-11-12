// Regression: on a real iPhone 17 (iOS 27.2) queryNativeMaxFpsAt1080p opened
// the front camera with mandatory minFrameRate '55'. flutter_webrtc then set
// activeVideoMaxFrameDuration to an unsupported value inside a dispatch_sync,
// AVFoundation threw, and the app aborted (SIGABRT) at the start of every
// video call: qa_artifacts/phase3/iphone_crashlogs/Runner-2026-11-12-234134.ips
// (same signature in the published v1.5.0: Runner-2026-11-12-195811.ips).
// On iOS the front-camera probe must not open the camera.
import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/webrtc/camera_constraint_selector.dart';

class _RecordingMediaDevices {
  final calls = <Map<String, dynamic>>[];
  Future<dynamic> getUserMedia(Map<String, dynamic> c) async {
    calls.add(c);
    throw StateError('SIGABRT on real iPhone: unsupported frame duration');
  }
}

void main() {
  tearDown(CameraConstraintSelector.clearCacheForTesting);

  test('iOS front fps probe does not open the camera and returns 30', () async {
    CameraConstraintSelector.clearCacheForTesting();
    CameraConstraintSelector.isIOSOverrideForTesting = true;
    final md = _RecordingMediaDevices();
    final fps = await CameraConstraintSelector.queryNativeMaxFpsAt1080p(isFrontCamera: true, mediaDevices: md);
    expect(md.calls, isEmpty, reason: 'must not issue the 55-60 fps getUserMedia on iOS');
    expect(fps, 30);
  });
}
