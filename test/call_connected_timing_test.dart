// Regression: a remote track arrives when the remote description is applied,
// before ICE connects. It used to mark the call "connected" (starting the
// duration timer early). Measured on Mac<->Android: the callee showed
// connected 1331 ms and the caller 658 ms before ICE connected
// (qa_artifacts/phase3/m2a_video_full_1). Only ICE/PC connected may do it.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ozone/core/webrtc/webrtc_call_manager.dart';
import 'package:ozone/models/call_session.dart';

class _FakeStream extends Fake implements MediaStream {}

void main() {
  test('remote track does not mark the call connected; ICE connected does', () {
    final m = WebRtcCallManager();
    m.setStatusForTesting(CallStatus.connecting);
    m.handleRemoteTrackForTesting(_FakeStream(), isAudioOnly: true);
    expect(m.status, CallStatus.connecting);
    expect(m.connectedAt, isNull);
    expect(m.callDurationSeconds, 0);

    m.handleIceConnectionStateForTesting(RTCIceConnectionState.RTCIceConnectionStateConnected);
    expect(m.status, CallStatus.connected);
    expect(m.connectedAt, isNotNull);
    m.dispose();
  });
}
