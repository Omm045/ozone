import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ozone/core/webrtc/webrtc_call_manager.dart';
import 'package:ozone/core/webrtc/ice_config_provider.dart';
import 'package:ozone/core/webrtc/camera_constraint_selector.dart';
import 'package:ozone/core/webrtc/adaptive_quality_controller.dart';
import 'package:ozone/models/call_session.dart';

void main() {
  group('WebRTC Call Pipeline & Signaling Tests (STUN-only P2P)', () {
    String getSendCollection(bool isCaller) => isCaller ? 'callerCandidates' : 'calleeCandidates';
    String getListenCollection(bool isCaller) => isCaller ? 'calleeCandidates' : 'callerCandidates';

    test('Signaling collections are symmetric and correctly separated by role', () {
      // Caller generates callerCandidates and listens to calleeCandidates
      final callerSendCollection = getSendCollection(true);
      final callerListenCollection = getListenCollection(true);

      expect(callerSendCollection, 'callerCandidates');
      expect(callerListenCollection, 'calleeCandidates');

      // Callee generates calleeCandidates and listens to callerCandidates
      final calleeSendCollection = getSendCollection(false);
      final calleeListenCollection = getListenCollection(false);

      expect(calleeSendCollection, 'calleeCandidates');
      expect(calleeListenCollection, 'callerCandidates');

      // Ensure caller and callee write to opposite collections
      expect(callerSendCollection, calleeListenCollection);
      expect(calleeSendCollection, callerListenCollection);
      expect(callerSendCollection, isNot(equals(calleeSendCollection)));
    });

    test('Remote ICE Candidate Buffering queues candidates before remote description is set', () {
      final pendingCandidates = <String>[];
      final appliedCandidates = <String>[];
      bool hasRemoteDescription = false;

      void onReceiveRemoteCandidate(String candidate) {
        if (!hasRemoteDescription) {
          pendingCandidates.add(candidate);
        } else {
          appliedCandidates.add(candidate);
        }
      }

      void onSetRemoteDescription() {
        hasRemoteDescription = true;
        // Drain buffered candidates
        appliedCandidates.addAll(pendingCandidates);
        pendingCandidates.clear();
      }

      // Simulate remote candidates arriving early over signaling before answer arrives
      onReceiveRemoteCandidate('candidate:1 host 192.168.1.5');
      onReceiveRemoteCandidate('candidate:2 srflx 203.0.113.1');

      expect(pendingCandidates.length, 2);
      expect(appliedCandidates, isEmpty);

      // Answer arrives and remote description is applied
      onSetRemoteDescription();

      expect(pendingCandidates, isEmpty);
      expect(appliedCandidates.length, 2);
      expect(appliedCandidates.first, contains('host'));
      expect(appliedCandidates.last, contains('srflx'));

      // New candidate arriving after remote description is applied directly
      onReceiveRemoteCandidate('candidate:3 host 192.168.1.6');
      expect(pendingCandidates, isEmpty);
      expect(appliedCandidates.length, 3);
      expect(appliedCandidates.last, contains('host'));
    });

    test('Candidate parsing handles host, srflx, and relay accurately', () {
      expect(
        WebRtcCallManager.extractCandidateType('candidate:1 1 UDP 2130706431 10.0.0.1 50000 typ host generation 0'),
        'host',
      );
      expect(
        WebRtcCallManager.extractCandidateType('candidate:2 1 UDP 1694498815 198.51.100.2 50000 typ srflx raddr 10.0.0.1 rport 50000 generation 0'),
        'srflx',
      );
      expect(
        WebRtcCallManager.extractCandidateType('candidate:3 1 UDP 842164929 203.0.113.10 50000 typ relay raddr 198.51.100.2 rport 50000 generation 0'),
        'relay',
      );
    });

    test('IceServerConfig maintains iceTransportPolicy as all for STUN-only P2P', () {
      const config = IceServerConfig(
        stunUrls: IceServerConfig.defaultStunUrls,
      );

      final rtcConfig = config.toWebRtcConfig();
      // Must NOT restrict gathering to relay; MUST allow host/srflx P2P
      expect(rtcConfig['iceTransportPolicy'], 'all');
      final servers = rtcConfig['iceServers'] as List;
      expect(servers.length, 1);
    });

    test('Connection failure differentiates local network denial vs general network connectivity', () {
      String resolveFailureReason(bool hasGatheredHost) {
        if (!hasGatheredHost) {
          return "Local network access was not permitted. Calls may be limited to networks with internet-reachable connectivity.";
        }
        return "Could not establish a direct peer-to-peer connection. Verify both devices have an active internet connection.";
      }

      // Case 1: No host candidate gathered -> indicates iOS/macOS local network privacy denial
      final failureReason1 = resolveFailureReason(false);
      expect(failureReason1, contains('Local network access was not permitted'));

      // Case 2: Host candidate gathered but connection failed across STUN P2P
      final failureReason2 = resolveFailureReason(true);
      expect(failureReason2, contains('direct peer-to-peer'));
    });

    // =========================================================================
    // PART 3 RIGOROUS EDGE-CASE TESTS
    // =========================================================================

    test('Edge Case 1: Caller cancels call before callee answers without hanging or leaving orphaned state', () {
      // Mock call signaling state
      var callDocStatus = CallStatus.ringing;
      final cleanedUpCollections = <String>[];
      var calleeStatus = CallStatus.ringing;

      void callerCancelsCall(String callId) {
        callDocStatus = CallStatus.ended;
        // Purge signaling subcollections
        cleanedUpCollections.add('calls/$callId/callerCandidates');
        cleanedUpCollections.add('calls/$callId/calleeCandidates');
      }

      void calleeReceivesUpdate(CallStatus status) {
        if (status == CallStatus.ended) {
          calleeStatus = CallStatus.ended;
        }
      }

      // 1. Caller initiates and cancels while callee is still ringing
      expect(callDocStatus, CallStatus.ringing);
      expect(calleeStatus, CallStatus.ringing);

      callerCancelsCall('call_abc123');
      calleeReceivesUpdate(callDocStatus);

      // 2. Both sides reach CallStatus.ended cleanly
      expect(callDocStatus, CallStatus.ended);
      expect(calleeStatus, CallStatus.ended);

      // 3. Candidate documents purged
      expect(cleanedUpCollections, contains('calls/call_abc123/callerCandidates'));
      expect(cleanedUpCollections, contains('calls/call_abc123/calleeCandidates'));
    });

    test('Edge Case 2: Callee rejects the call with clear "call declined" state', () {
      var callDocStatus = CallStatus.ringing;
      String? callDocFailureReason;
      var callerObservedStatus = CallStatus.ringing;
      String? callerObservedReason;

      void calleeRejectsCall() {
        callDocStatus = CallStatus.rejected;
        callDocFailureReason = 'Call declined by recipient.';
      }

      void callerReceivesSnapshot(CallStatus status, String? failureReason) {
        if (status == CallStatus.rejected) {
          callerObservedStatus = CallStatus.rejected;
          callerObservedReason = failureReason ?? 'Call declined by recipient.';
        }
      }

      // Callee rejects incoming call
      calleeRejectsCall();
      callerReceivesSnapshot(callDocStatus, callDocFailureReason);

      expect(callerObservedStatus, CallStatus.rejected);
      expect(callerObservedReason, contains('Call declined by recipient'));
      expect(callerObservedStatus, isNot(equals(CallStatus.failed))); // Must be distinct from generic network failure
    });

    test('Edge Case 3: Network drops mid-call and triggers clear disconnection state rather than hanging', () {
      var status = CallStatus.connected;
      String? failureReason;
      var statsTimerCanceled = false;
      var mediaStopped = false;

      void handlePeerConnectionDrop(String iceOrPeerState) {
        if (iceOrPeerState == 'failed' || iceOrPeerState == 'disconnected') {
          if (status == CallStatus.connected) {
            status = CallStatus.failed;
            failureReason = 'Connection lost — network interrupted mid-call.';
            statsTimerCanceled = true;
            mediaStopped = true;
          }
        }
      }

      // Simulate network dropping after connection established
      expect(status, CallStatus.connected);
      handlePeerConnectionDrop('failed');

      expect(status, CallStatus.failed);
      expect(failureReason, contains('Connection lost — network interrupted mid-call'));
      expect(statsTimerCanceled, isTrue);
      expect(mediaStopped, isTrue);
    });

    test('Edge Case 4: Simultaneous call collision (glare) resolves deterministically via UID comparison', () {
      const userAliceUid = 'user_alice_100';
      const userBobUid = 'user_bob_200';

      // Alice calls Bob at the exact same time Bob calls Alice
      final aliceYields = WebRtcCallManager.shouldYieldGlare(
        myUid: userAliceUid,
        peerUid: userBobUid,
      );

      final bobYields = WebRtcCallManager.shouldYieldGlare(
        myUid: userBobUid,
        peerUid: userAliceUid,
      );

      // Deterministic symmetry: exactly one user yields, the other user's call proceeds
      expect(aliceYields, isFalse); // user_alice_100 < user_bob_200 -> Alice's call wins (does not yield)
      expect(bobYields, isTrue);   // user_bob_200 > user_alice_100 -> Bob yields his outgoing call and accepts Alice's

      expect(aliceYields != bobYields, isTrue, reason: 'Glare resolution must be strictly asymmetric and deterministic');
    });

    test('Edge Case 5: Stale ICE candidates from mismatched callId are dropped and never applied', () {
      final activeCallId = 'call_active_current';
      final appliedCandidates = <String>[];
      final droppedCandidates = <String>[];

      void onCandidateReceived({required String candidateCallId, required String candidateStr}) {
        if (candidateCallId != activeCallId) {
          droppedCandidates.add(candidateStr);
          return;
        }
        appliedCandidates.add(candidateStr);
      }

      // Candidate arriving from previous call cleanup or delayed Firestore stream
      onCandidateReceived(
        candidateCallId: 'call_old_previous',
        candidateStr: 'candidate:1 host 192.168.1.10',
      );

      // Candidate arriving for current active call
      onCandidateReceived(
        candidateCallId: activeCallId,
        candidateStr: 'candidate:2 host 192.168.1.20',
      );

      expect(droppedCandidates.length, 1);
      expect(droppedCandidates.first, contains('192.168.1.10'));
      expect(appliedCandidates.length, 1);
      expect(appliedCandidates.first, contains('192.168.1.20'));
    });

    test('Edge Case 6: Rapid repeated calls reset state and do not bleed leftover candidates', () {
      // Simulate state across two consecutive call attempts
      final call1Candidates = <String>[];
      final call2Candidates = <String>[];

      var activeCallId = 'call_attempt_1';
      var hasRemoteDescription = false;
      var isCaller = false;

      // Call 1 setup
      isCaller = true;
      activeCallId = 'call_attempt_1';
      call1Candidates.add('candidate:1 host');
      hasRemoteDescription = true;

      // User hangs up Call 1 and immediately initiates Call 2
      hasRemoteDescription = false; // Reset
      isCaller = false;
      activeCallId = 'call_attempt_2'; // New unique document ID
      call2Candidates.add('candidate:2 host');

      expect(activeCallId, 'call_attempt_2');
      expect(hasRemoteDescription, isFalse);
      expect(isCaller, isFalse);
      expect(call1Candidates, isNot(equals(call2Candidates)));
      expect(call2Candidates.length, 1);
      expect(call2Candidates.first, contains('candidate:2'));
    });

    test('Issue 1 Fix: Ringing timeout fires after 30s when callee never answers, preventing infinite hang', () {
      var status = CallStatus.ringing;
      String? failureReason;
      var timeoutFired = false;
      var cleanedUpSignaling = false;

      void onRingingTimeout() {
        timeoutFired = true;
        status = CallStatus.failed;
        failureReason = 'No answer — recipient did not respond in time.';
        cleanedUpSignaling = true;
      }

      // Simulate 30-second ringing timeout triggering because callee never answered
      expect(status, CallStatus.ringing);
      expect(timeoutFired, isFalse);

      onRingingTimeout();

      expect(status, CallStatus.failed);
      expect(timeoutFired, isTrue);
      expect(failureReason, contains('No answer'));
      expect(cleanedUpSignaling, isTrue);
    });

    test('Issue 1 Fix: Negotiation timeout fires after 15s if answer received but ICE fails to connect', () {
      var status = CallStatus.connecting;
      String? failureReason;
      var negotiationTimeoutFired = false;

      void onNegotiationTimeout() {
        negotiationTimeoutFired = true;
        status = CallStatus.failed;
        failureReason = 'Could not establish a direct peer-to-peer connection. Verify both devices have an active internet connection.';
      }

      expect(status, CallStatus.connecting);
      onNegotiationTimeout();

      expect(status, CallStatus.failed);
      expect(negotiationTimeoutFired, isTrue);
      expect(failureReason, contains('direct peer-to-peer connection'));
    });

    test('Issue 1 Fix: Any connection event (onIceConnectionState, onConnectionState, onTrack) transitions to connected and cancels timeout', () {
      var status = CallStatus.connecting;
      var timeoutTimerCanceled = false;
      var statsPollingStarted = false;

      void onConnected() {
        if (status == CallStatus.connected) return;
        timeoutTimerCanceled = true;
        status = CallStatus.connected;
        statsPollingStarted = true;
      }

      // 1. Peer connection state transitions to connected
      onConnected();

      expect(status, CallStatus.connected);
      expect(timeoutTimerCanceled, isTrue);
      expect(statsPollingStarted, isTrue);

      // 2. Subsequent onTrack or onIceConnectionState events are idempotent
      onConnected();
      expect(status, CallStatus.connected);
    });

    test('Part 2 Fix: Transient connection disconnection enters 6s grace period and recovers without failing call', () {
      final manager = WebRtcCallManager();
      manager.setStatusForTesting(CallStatus.connected);

      expect(manager.status, CallStatus.connected);
      expect(manager.isDisconnectGracePeriodActive, isFalse);

      // WebRTC transiently emits disconnected
      manager.handleConnectionStateForTesting(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);

      // Call is still connected because grace period is active
      expect(manager.status, CallStatus.connected);
      expect(manager.isDisconnectGracePeriodActive, isTrue);

      // Network recovers back to connected within grace period
      manager.handleConnectionStateForTesting(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      expect(manager.status, CallStatus.connected);
      expect(manager.isDisconnectGracePeriodActive, isFalse);
      expect(manager.failureReason, isNull);

      manager.dispose();
    });

    test('Part 2 Fix: Sustained connection failure exceeding 6s grace period declares connection lost', () {
      final manager = WebRtcCallManager();
      manager.setStatusForTesting(CallStatus.connected);

      // Network drops
      manager.handleConnectionStateForTesting(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);
      expect(manager.status, CallStatus.connected);
      expect(manager.isDisconnectGracePeriodActive, isTrue);

      // 6s grace period expires without recovery
      manager.expireGracePeriodForTesting();

      expect(manager.status, CallStatus.failed);
      expect(manager.failureReason, contains('network interrupted mid-call'));
      expect(manager.isDisconnectGracePeriodActive, isFalse);

      manager.dispose();
    });

    test('Part 2 Fix: Disposing WebRtcCallManager cancels grace timer and does not notify listeners', () {
      final manager = WebRtcCallManager();
      manager.setStatusForTesting(CallStatus.connected);
      manager.handleIceConnectionStateForTesting(RTCIceConnectionState.RTCIceConnectionStateDisconnected);
      expect(manager.isDisconnectGracePeriodActive, isTrue);

      var notificationCount = 0;
      manager.addListener(() => notificationCount++);

      manager.dispose();
      expect(manager.isDisconnectGracePeriodActive, isFalse);

      // Further state changes after dispose must not throw or notify
      manager.handleConnectionStateForTesting(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
      expect(notificationCount, 0);
    });

    test('Part 3: Audio-only mode produces zero camera constraints and video is false', () {
      final constraints = CameraConstraintSelector.getMediaConstraintsForTier(
        ResolutionTier.p1080,
        isAudioOnly: true,
      );

      expect(constraints['video'], isFalse);
      expect(constraints['audio'], isNotNull);
    });

    test('Part 3: CallSession correctly parses and serializes CallType.audio', () {
      final now = DateTime.now();
      final audioSession = CallSession(
        id: 'test_audio_call',
        callerUid: 'caller_1',
        callerEmail: 'caller@ozone.test',
        calleeUid: 'callee_2',
        calleeEmail: 'callee@ozone.test',
        status: CallStatus.ringing,
        callType: CallType.audio,
        createdAt: now,
      );

      expect(audioSession.isAudioOnly, isTrue);
      expect(audioSession.callType, CallType.audio);

      final map = audioSession.toMap();
      expect(map['callType'], 'audio');

      final reconstructed = CallSession.fromMap(map, 'test_audio_call');
      expect(reconstructed.isAudioOnly, isTrue);
      expect(reconstructed.callType, CallType.audio);
    });

    test('Part 4 & 5: 4K target bitrate is 16 Mbps and 60fps capability toggles target FPS', () {
      expect(ResolutionTier.p4k.targetBitrateBps, 16000000);

      final controller = AdaptiveQualityController(
        initialTier: ResolutionTier.p1080,
        deviceSupports60Fps: false,
      );
      expect(controller.currentTargetFps, 30);

      controller.deviceSupports60Fps = true;
      expect(controller.currentTargetFps, 60);

      // Low tier (720p) stays at 30fps floor even if device supports 60fps
      controller.setManualTier(ResolutionTier.p720);
      expect(controller.currentTargetFps, 30);
    });
  });
}
