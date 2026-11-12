// Regression: on a real iPhone (callee, audio call) ICE went checking ->
// failed within 1 ms and the call was failed immediately, although the same
// pair connected in 367 ms on retry (qa_artifacts/phase3/m2i_audio_full_2 vs
// _3). With the negotiation timeout running, a pre-connect 'failed' must not
// end the call; the timeout still fails it if ICE never recovers.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ozone/core/webrtc/webrtc_call_manager.dart';
import 'package:ozone/models/call_session.dart';

void main() {
  test('transient pre-connect ICE failed waits for the negotiation timeout', () {
    fakeAsync((async) {
      final m = WebRtcCallManager();
      m.setStatusForTesting(CallStatus.connecting);
      m.startConnectionTimeoutForTesting(const Duration(seconds: 15));
      m.handleIceConnectionStateForTesting(RTCIceConnectionState.RTCIceConnectionStateFailed);
      expect(m.status, CallStatus.connecting);
      m.handleIceConnectionStateForTesting(RTCIceConnectionState.RTCIceConnectionStateConnected);
      expect(m.status, CallStatus.connected);
      m.dispose();
    });
  });

  test('pre-connect ICE failed that never recovers fails at the timeout', () {
    fakeAsync((async) {
      final m = WebRtcCallManager();
      m.setStatusForTesting(CallStatus.connecting);
      m.startConnectionTimeoutForTesting(const Duration(seconds: 15));
      m.handleIceConnectionStateForTesting(RTCIceConnectionState.RTCIceConnectionStateFailed);
      async.elapse(const Duration(seconds: 16));
      expect(m.status, CallStatus.failed);
      m.dispose();
    });
  });
}
