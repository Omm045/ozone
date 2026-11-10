import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/call_session.dart';
import '../../models/user_model.dart';
import 'ice_config_provider.dart';
import 'adaptive_quality_controller.dart';
import 'camera_constraint_selector.dart';

class WebRtcCallManager extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  final IceConfigProvider _iceConfigProvider;
  final AdaptiveQualityController qualityController;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RTCRtpSender? _videoSender;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  CallSession? _currentSession;
  CallStatus _status = CallStatus.connecting;
  String? _failureReason;
  QualityIndicatorState _qualityState = const QualityIndicatorState();

  bool _isMuted = false;
  bool _isVideoDisabled = false;
  bool _isFrontCamera = true;

  Timer? _statsTimer;
  Timer? _connectionTimeoutTimer;
  StreamSubscription? _callDocSubscription;
  StreamSubscription? _candidatesSubscription;

  int _previousBytesSent = 0;
  double _previousTimestamp = 0;

  WebRtcCallManager({
    FirebaseFirestore? firestore,
    IceConfigProvider? iceConfigProvider,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _iceConfigProvider = iceConfigProvider ?? const DefaultIceConfigProvider(),
        qualityController = AdaptiveQualityController(initialTier: ResolutionTier.p1080) {
    qualityController.onTierChanged = _onResolutionTierChanged;
  }

  CallStatus get status => _status;
  String? get failureReason => _failureReason;
  QualityIndicatorState get qualityState => _qualityState;
  CallSession? get currentSession => _currentSession;
  bool get isMuted => _isMuted;
  bool get isVideoDisabled => _isVideoDisabled;

  Future<void> initializeRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> startOutgoingCall({
    required UserModel caller,
    required UserModel callee,
  }) async {
    _status = CallStatus.ringing;
    _failureReason = null;
    notifyListeners();

    final callDoc = _firestore.collection('calls').doc();
    _currentSession = CallSession(
      id: callDoc.id,
      callerUid: caller.uid,
      callerEmail: caller.email,
      calleeUid: callee.uid,
      calleeEmail: callee.email,
      status: CallStatus.ringing,
      createdAt: DateTime.now(),
    );

    await _setupMediaAndPeerConnection();

    // Create SDP Offer
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });
    await _peerConnection!.setLocalDescription(offer);

    // Save Call Doc with Offer in Firestore
    await callDoc.set({
      ..._currentSession!.toMap(),
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });

    _startConnectionTimeoutTimer();

    // Listen for Answer
    _callDocSubscription = callDoc.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;

      final session = CallSession.fromMap(data, snapshot.id);
      if (session.status == CallStatus.ended || session.status == CallStatus.rejected) {
        _endCallInternal(status: session.status);
        return;
      }

      if (_peerConnection != null &&
          session.answer != null &&
          _status != CallStatus.connected) {
        final answer = RTCSessionDescription(
          session.answer!['sdp'] as String,
          session.answer!['type'] as String,
        );
        await _peerConnection!.setRemoteDescription(answer);
      }
    });

    // Listen for Callee ICE Candidates
    _listenForRemoteCandidates(callDoc.id, isCaller: true);
  }

  Future<void> acceptIncomingCall({required CallSession session}) async {
    _currentSession = session;
    _status = CallStatus.connecting;
    _failureReason = null;
    notifyListeners();

    await _setupMediaAndPeerConnection();

    final callDoc = _firestore.collection('calls').doc(session.id);

    // Set Remote Description from Offer
    if (session.offer != null) {
      final offer = RTCSessionDescription(
        session.offer!['sdp'] as String,
        session.offer!['type'] as String,
      );
      await _peerConnection!.setRemoteDescription(offer);
    }

    // Create SDP Answer
    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });
    await _peerConnection!.setLocalDescription(answer);

    // Update Call Doc in Firestore
    await callDoc.update({
      'status': CallStatus.connecting.name,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });

    _startConnectionTimeoutTimer();

    // Listen for Caller ICE Candidates
    _listenForRemoteCandidates(session.id, isCaller: false);
  }

  Future<void> _setupMediaAndPeerConnection() async {
    // 1. Get User Media starting at 1080p baseline
    final mediaConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
      qualityController.currentTier,
      isFrontCamera: _isFrontCamera,
    );

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localRenderer.srcObject = _localStream;

    // 2. Build PeerConnection with STUN-only iceServers
    final rtcConfig = _iceConfigProvider.getIceServers();
    _peerConnection = await createPeerConnection(rtcConfig);

    // 3. Add tracks to PeerConnection
    for (final track in _localStream!.getTracks()) {
      final sender = await _peerConnection!.addTrack(track, _localStream!);
      if (track.kind == 'video') {
        _videoSender = sender;
        _applyEncodingParameters(qualityController.currentTier);
      }
    }

    // 4. Handle Remote Track
    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        notifyListeners();
      }
    };

    // 5. Handle ICE Candidates
    _peerConnection!.onIceCandidate = (candidate) {
      if (_currentSession == null) return;
      final collection = _currentSession!.callerUid == _firestore.app.name
          ? 'callerCandidates'
          : 'calleeCandidates';

      _firestore
          .collection('calls')
          .doc(_currentSession!.id)
          .collection(collection)
          .add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // 6. Handle Connection State
    _peerConnection!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _connectionTimeoutTimer?.cancel();
        _status = CallStatus.connected;
        _startStatsPolling();
        notifyListeners();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _onConnectionFailed();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _endCallInternal(status: CallStatus.ended);
      }
    };
  }

  void _listenForRemoteCandidates(String callId, {required bool isCaller}) {
    final remoteCollection = isCaller ? 'calleeCandidates' : 'callerCandidates';
    _candidatesSubscription = _firestore
        .collection('calls')
        .doc(callId)
        .collection(remoteCollection)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && _peerConnection != null) {
            final candidate = RTCIceCandidate(
              data['candidate'] as String,
              data['sdpMid'] as String?,
              data['sdpMLineIndex'] as int?,
            );
            _peerConnection!.addCandidate(candidate);
          }
        }
      }
    });
  }

  void _startConnectionTimeoutTimer() {
    _connectionTimeoutTimer?.cancel();
    // 15 seconds connection timeout for direct STUN-only P2P
    _connectionTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (_status != CallStatus.connected && _status != CallStatus.ended) {
        _onConnectionFailed();
      }
    });
  }

  void _onConnectionFailed() {
    _connectionTimeoutTimer?.cancel();
    _status = CallStatus.failed;
    _failureReason = "Couldn't connect — this may be due to one of your networks.";
    notifyListeners();

    if (_currentSession != null) {
      _firestore.collection('calls').doc(_currentSession!.id).update({
        'status': CallStatus.failed.name,
        'failureReason': _failureReason,
      }).catchError((_) {});
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _measureStats();
    });
  }

  Future<void> _measureStats() async {
    if (_peerConnection == null || _status != CallStatus.connected) return;

    try {
      final reports = await _peerConnection!.getStats();
      double availableBandwidth = qualityController.currentTier.targetBitrateBps.toDouble();
      double rtt = 45.0;
      double packetLoss = 0.0;
      int fps = 30;

      for (final report in reports) {
        final values = report.values;
        if (report.type == 'outbound-rtp' && values['kind'] == 'video') {
          final bytes = int.tryParse(values['bytesSent']?.toString() ?? '0') ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
          if (_previousTimestamp > 0 && now > _previousTimestamp && bytes >= _previousBytesSent) {
            final diffBytes = bytes - _previousBytesSent;
            final diffTime = now - _previousTimestamp;
            availableBandwidth = (diffBytes * 8.0) / diffTime;
          }
          _previousBytesSent = bytes;
          _previousTimestamp = now;

          final statFps = int.tryParse(values['framesPerSecond']?.toString() ?? '0');
          if (statFps != null && statFps > 0) fps = statFps;
        } else if (report.type == 'remote-inbound-rtp') {
          final roundTrip = double.tryParse(values['roundTripTime']?.toString() ?? '0');
          if (roundTrip != null && roundTrip > 0) rtt = roundTrip * 1000.0;
          final lostFrac = double.tryParse(values['fractionLost']?.toString() ?? '0');
          if (lostFrac != null) packetLoss = lostFrac;
        } else if (report.type == 'candidate-pair' && values['state'] == 'succeeded') {
          final curRtt = double.tryParse(values['currentRoundTripTime']?.toString() ?? '0');
          if (curRtt != null && curRtt > 0) rtt = curRtt * 1000.0;
          final bitrate = double.tryParse(values['availableOutgoingBitrate']?.toString() ?? '0');
          if (bitrate != null && bitrate > 0) availableBandwidth = bitrate;
        }
      }

      final sample = NetworkStatsSample(
        availableBandwidthBps: availableBandwidth,
        roundTripTimeMs: rtt,
        packetLossRate: packetLoss,
        currentFps: fps,
      );

      qualityController.processSample(sample);
      _qualityState = qualityController.getCurrentIndicatorState();
      notifyListeners();
    } catch (_) {}
  }

  void _onResolutionTierChanged(ResolutionTier newTier) {
    _applyEncodingParameters(newTier);
    _qualityState = qualityController.getCurrentIndicatorState();
    notifyListeners();
  }

  void _applyEncodingParameters(ResolutionTier tier) {
    if (_videoSender == null) return;
    try {
      final parameters = _videoSender!.parameters;
      final encodings = parameters.encodings;
      if (encodings != null && encodings.isNotEmpty) {
        for (final encoding in encodings) {
          encoding.maxBitrate = tier.targetBitrateBps;
          encoding.maxFramerate = tier.targetFps;
          encoding.scaleResolutionDownBy = tier.scaleResolutionDownBy;
        }
        _videoSender!.setParameters(parameters);
      }
    } catch (_) {}
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
    notifyListeners();
  }

  void toggleVideo() {
    _isVideoDisabled = !_isVideoDisabled;
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = !_isVideoDisabled;
    });
    notifyListeners();
  }

  Future<void> switchCamera() async {
    _isFrontCamera = !_isFrontCamera;
    final videoTrack = _localStream?.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      await Helper.switchCamera(videoTrack);
      notifyListeners();
    }
  }

  Future<void> endCall() async {
    if (_currentSession != null) {
      await _firestore.collection('calls').doc(_currentSession!.id).update({
        'status': CallStatus.ended.name,
      }).catchError((_) {});
    }
    _endCallInternal(status: CallStatus.ended);
  }

  void _endCallInternal({required CallStatus status}) {
    _statsTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _callDocSubscription?.cancel();
    _candidatesSubscription?.cancel();

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;

    _peerConnection?.close();
    _peerConnection?.dispose();
    _peerConnection = null;

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _endCallInternal(status: CallStatus.ended);
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}
