import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/call_session.dart';
import '../../models/user_model.dart';
import 'ice_config_provider.dart';
import 'adaptive_quality_controller.dart';
import 'camera_constraint_selector.dart';
import 'quality_preferences.dart';

class WebRtcCallManager extends ChangeNotifier {
  final FirebaseFirestore? _customFirestore;
  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;
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

  bool _isCaller = false;
  bool _hasRemoteDescription = false;
  bool _hasGatheredHostCandidate = false;
  bool _isLocalNetworkDenied = false;
  final Set<String> _gatheredCandidateTypes = {};
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  final List<String> _sessionLogs = [];
  String? _connectedPair;

  bool _isMuted = false;
  bool _isVideoDisabled = false;
  bool _isFrontCamera = true;
  bool _isSpeakerphoneOn = false;

  Timer? _statsTimer;
  Timer? _connectionTimeoutTimer;
  Timer? _disconnectGraceTimer;
  static const Duration disconnectGracePeriod = Duration(seconds: 6);
  bool _isDisposed = false;
  StreamSubscription? _callDocSubscription;
  StreamSubscription? _candidatesSubscription;

  int _previousBytesSent = 0;
  double _previousTimestamp = 0;
  int _statsCounter = 0;

  WebRtcCallManager({
    FirebaseFirestore? firestore,
    IceConfigProvider? iceConfigProvider,
  })  : _customFirestore = firestore,
        _iceConfigProvider = iceConfigProvider ?? const DefaultIceConfigProvider(),
        qualityController = AdaptiveQualityController(
          initialTier: ResolutionTier.p1080,
          consecutiveGoodSamplesRequired: 5,
        ) {
    qualityController.onTierChanged = _onResolutionTierChanged;
  }

  CallStatus get status => _status;
  String? get failureReason => _failureReason;
  QualityIndicatorState get qualityState => _qualityState;
  CallSession? get currentSession => _currentSession;
  bool get isMuted => _isMuted;
  bool get isVideoDisabled => _isVideoDisabled;
  bool get isSpeakerphoneOn => _isSpeakerphoneOn;
  bool get isAudioOnly => _currentSession?.isAudioOnly ?? false;
  bool get isLocalNetworkDenied => _isLocalNetworkDenied;
  bool get hasGatheredHostCandidate => _hasGatheredHostCandidate;
  bool get isCaller => _isCaller;
  bool get hasRemoteDescription => _hasRemoteDescription;
  Set<String> get gatheredCandidateTypes => Set.unmodifiable(_gatheredCandidateTypes);
  List<String> get sessionLogs => List.unmodifiable(_sessionLogs);
  String? get connectedPair => _connectedPair;

  Future<void> toggleSpeakerphone() async {
    _isSpeakerphoneOn = !_isSpeakerphoneOn;
    try {
      await Helper.setSpeakerphoneOn(_isSpeakerphoneOn);
      _log('Speakerphone state updated: $_isSpeakerphoneOn');
    } catch (e) {
      _log('Speakerphone toggle note: $e');
    }
    notifyListeners();
  }

  void _log(String message) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final entry = '[$timeStr] $message';
    _sessionLogs.add(entry);
    debugPrint('[WebRtcCallManager] $message');
  }

  Future<void> initializeRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> loadSavedQualityPreference() async {
    final savedTier = await QualityPreferences.getSavedPreference();
    qualityController.setManualTier(savedTier);
    if (savedTier != null) {
      _applyEncodingParameters(savedTier);
    }
    _qualityState = qualityController.getCurrentIndicatorState();
    notifyListeners();
  }

  Future<void> setQualityPreference(ResolutionTier? tier) async {
    qualityController.setManualTier(tier);
    await QualityPreferences.savePreference(tier);
    if (tier != null) {
      _applyEncodingParameters(tier);
    } else {
      _applyEncodingParameters(qualityController.currentTier);
    }
    _qualityState = qualityController.getCurrentIndicatorState();
    notifyListeners();
  }

  static String extractCandidateType(String? candidateStr) {
    if (candidateStr == null || candidateStr.isEmpty) return 'unknown';
    final parts = candidateStr.split(' ');
    final typIndex = parts.indexOf('typ');
    if (typIndex != -1 && typIndex + 1 < parts.length) {
      return parts[typIndex + 1];
    }
    return 'unknown';
  }

  Future<void> _probeLocalNetwork() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send([0], InternetAddress('224.0.0.251'), 5353);
      socket.close();
      _log('Probed local network multicast to trigger OS permissions prompt if needed.');
    } catch (e) {
      _log('Local network socket probe note: $e');
    }
  }

  /// Deterministic tie-breaker for simultaneous call glare (when both users call each other).
  /// If myUid > peerUid, my call takes precedence (do not yield).
  /// If myUid < peerUid, peer call takes precedence (yield outgoing, accept incoming).
  static bool shouldYieldGlare({required String myUid, required String peerUid}) {
    return myUid.compareTo(peerUid) > 0;
  }

  Future<void> startOutgoingCall({
    required UserModel caller,
    required UserModel callee,
    CallType callType = CallType.video,
  }) async {
    // Teardown any lingering prior session before initiating new call
    if (_currentSession != null) {
      _endCallInternal(status: CallStatus.ended);
    }

    _isCaller = true;
    _status = CallStatus.ringing;
    _failureReason = null;
    _hasGatheredHostCandidate = false;
    _isLocalNetworkDenied = false;
    _gatheredCandidateTypes.clear();
    _pendingRemoteCandidates.clear();
    _hasRemoteDescription = false;
    _sessionLogs.clear();
    _connectedPair = null;
    _log('Starting outgoing ${callType.name} call to ${callee.email}');
    notifyListeners();

    final callDoc = _firestore.collection('calls').doc();
    _currentSession = CallSession(
      id: callDoc.id,
      callerUid: caller.uid,
      callerEmail: caller.email,
      calleeUid: callee.uid,
      calleeEmail: callee.email,
      status: CallStatus.ringing,
      callType: callType,
      createdAt: DateTime.now(),
    );

    try {
      await _setupMediaAndPeerConnection(isAudioOnly: callType == CallType.audio);
    } catch (e) {
      _onMediaSetupFailed(e);
      return;
    }

    // Create SDP Offer
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': callType == CallType.audio ? 0 : 1,
    });
    await _peerConnection!.setLocalDescription(offer);

    // Save Call Doc with Offer in Firestore
    await callDoc.set({
      ..._currentSession!.toMap(),
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });
    _log('Created offer and stored in Firestore call doc ${callDoc.id}');

    // Start ringing timeout waiting for callee to answer
    _startRingingTimeoutTimer();

    // Listen for Answer
    _callDocSubscription = callDoc.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;

      final session = CallSession.fromMap(data, snapshot.id);
      if (session.status == CallStatus.rejected) {
        _log('Call was declined by recipient.');
        _endCallInternal(status: CallStatus.rejected, reason: 'Call declined by recipient.');
        return;
      }
      if (session.status == CallStatus.ended) {
        _log('Call was ended by remote party.');
        _endCallInternal(status: CallStatus.ended);
        return;
      }

      if (_peerConnection != null &&
          session.answer != null &&
          !_hasRemoteDescription &&
          _status != CallStatus.connected) {
        _log('Received answer from callee.');
        try {
          final answer = RTCSessionDescription(
            session.answer!['sdp'] as String,
            session.answer!['type'] as String,
          );
          await _peerConnection!.setRemoteDescription(answer);
          _hasRemoteDescription = true;
          _status = CallStatus.connecting;
          _log('Set remote description from answer; starting negotiation timeout timer.');
          notifyListeners();
          // Callee answered: cancel ringing timer and start 15s negotiation timer
          _startConnectionTimeoutTimer(reason: 'ICE negotiation after answer');
          await _drainPendingCandidates();
        } catch (e) {
          _log('Error setting remote description from answer: $e');
          _onConnectionFailed(reason: 'Failed to negotiate connection: $e');
        }
      }
    });

    // Listen for Callee ICE Candidates
    _listenForRemoteCandidates(callDoc.id, isCaller: true);
  }

  Future<void> acceptIncomingCall({required CallSession session}) async {
    // Teardown any lingering prior session before accepting new call
    if (_currentSession != null && _currentSession!.id != session.id) {
      _endCallInternal(status: CallStatus.ended);
    }

    _isCaller = false;
    _currentSession = session;
    _status = CallStatus.connecting;
    _failureReason = null;
    _hasGatheredHostCandidate = false;
    _isLocalNetworkDenied = false;
    _gatheredCandidateTypes.clear();
    _pendingRemoteCandidates.clear();
    _hasRemoteDescription = false;
    _sessionLogs.clear();
    _connectedPair = null;
    _log('Accepting incoming ${session.isAudioOnly ? "audio" : "video"} call ${session.id} from ${session.callerEmail}');
    notifyListeners();

    try {
      await _setupMediaAndPeerConnection(isAudioOnly: session.isAudioOnly);
    } catch (e) {
      _onMediaSetupFailed(e);
      return;
    }

    final callDoc = _firestore.collection('calls').doc(session.id);

    // Set Remote Description from Offer
    if (session.offer != null) {
      try {
        final offer = RTCSessionDescription(
          session.offer!['sdp'] as String,
          session.offer!['type'] as String,
        );
        await _peerConnection!.setRemoteDescription(offer);
        _hasRemoteDescription = true;
        _log('Set remote description from offer.');
        await _drainPendingCandidates();
      } catch (e) {
        _log('Error setting remote description from offer: $e');
        _onConnectionFailed(reason: 'Failed to negotiate connection: $e');
        return;
      }
    }

    // Create SDP Answer
    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': session.isAudioOnly ? 0 : 1,
    });
    await _peerConnection!.setLocalDescription(answer);

    // Update Call Doc in Firestore
    await callDoc.update({
      'status': CallStatus.connecting.name,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });

    _startConnectionTimeoutTimer(reason: 'callee ICE negotiation');

    // Listen for caller terminating call while connecting
    _callDocSubscription = callDoc.snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;
      final current = CallSession.fromMap(data, snapshot.id);
      if (current.status == CallStatus.ended || current.status == CallStatus.rejected) {
        _log('Remote caller terminated call.');
        _endCallInternal(status: current.status);
      }
    });

    // Listen for Caller ICE Candidates
    _listenForRemoteCandidates(session.id, isCaller: false);
  }

  void _onMediaSetupFailed(Object error) {
    _status = CallStatus.failed;
    final errStr = error.toString().toLowerCase();
    if (errStr.contains('permission') ||
        errStr.contains('notallowed') ||
        errStr.contains('denied') ||
        errStr.contains('security')) {
      _failureReason =
          'Camera or Microphone access was denied. Please grant Camera and Microphone permissions in Settings to make calls.';
    } else {
      _failureReason = 'Failed to access camera or microphone: $error';
    }
    _log('Media setup failed: $_failureReason');
    notifyListeners();

    if (_currentSession != null) {
      _firestore.collection('calls').doc(_currentSession!.id).update({
        'status': CallStatus.failed.name,
        'failureReason': _failureReason,
      }).catchError((_) {});
    }
  }

  Future<void> _drainPendingCandidates() async {
    if (_peerConnection == null || _pendingRemoteCandidates.isEmpty) return;
    _log('Draining ${_pendingRemoteCandidates.length} buffered remote candidates...');
    final candidatesToDrain = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in candidatesToDrain) {
      try {
        final cType = extractCandidateType(candidate.candidate);
        await _peerConnection!.addCandidate(candidate);
        _log('Applied buffered remote candidate: [type=$cType]');
      } catch (e) {
        _log('Error applying buffered candidate: $e');
      }
    }
  }

  Future<void> _setupMediaAndPeerConnection({bool isAudioOnly = false}) async {
    // 0. Probe local network to trigger iOS/macOS Local Network permission prompt if needed
    await _probeLocalNetwork();

    // Enumerate audio devices and log for diagnostic visibility (e.g. Mac mic device checks)
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
      _log(
        'Detected ${audioInputs.length} audio input device(s): '
        '${audioInputs.map((d) => "${d.label.isEmpty ? "Default Audio Input" : d.label} (${d.deviceId})").join(', ')}',
      );
    } catch (e) {
      _log('Device enumeration note: $e');
    }

    // 1. Get User Media starting at 1080p baseline or audio-only
    final mediaConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
      qualityController.currentTier,
      isFrontCamera: _isFrontCamera,
      isAudioOnly: isAudioOnly,
      maxFps: qualityController.currentTargetFps,
    );

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (!isAudioOnly) {
      localRenderer.srcObject = _localStream;
    }

    final audioTracks = _localStream!.getAudioTracks();
    final videoTracks = _localStream!.getVideoTracks();

    // Ensure audio tracks are unmuted and gain is full level (fixes macOS hardware attenuation)
    try {
      await Helper.setMicrophoneMuted(false);
    } catch (_) {}

    for (final audioTrack in audioTracks) {
      audioTrack.enabled = !_isMuted;
      try {
        await Helper.setVolume(1.0, audioTrack);
      } catch (_) {}
    }

    // Detect 60fps support if camera supports it
    if (videoTracks.isNotEmpty) {
      try {
        final settings = videoTracks.first.getSettings();
        final reportedFps = settings['frameRate'];
        if (reportedFps is num && reportedFps >= 50) {
          qualityController.deviceSupports60Fps = true;
          _log('Camera supports high framerate capture (${reportedFps}fps). 60fps enabled for high tiers.');
        }
      } catch (_) {}
    }

    _log(
      'Acquired local stream: ${audioTracks.length} audio track(s) (enabled: ${audioTracks.map((t) => t.enabled).toList()}), '
      '${videoTracks.length} video track(s) (enabled: ${videoTracks.map((t) => t.enabled).toList()})',
    );

    // 2. Build PeerConnection with STUN-only iceServers
    final rtcConfig = await _iceConfigProvider.getIceServers(callId: _currentSession?.id);
    final iceServersCount = (rtcConfig['iceServers'] as List?)?.length ?? 0;
    _log('Configuring RTCPeerConnection with $iceServersCount ICE server group(s).');
    _peerConnection = await createPeerConnection(rtcConfig);

    // 3. Add tracks to PeerConnection
    for (final track in _localStream!.getTracks()) {
      final sender = await _peerConnection!.addTrack(track, _localStream!);
      _log('Added track to RTCPeerConnection: id=${track.id}, kind=${track.kind}, enabled=${track.enabled}');
      if (track.kind == 'video') {
        _videoSender = sender;
        _applyEncodingParameters(qualityController.currentTier);
      }
    }

    // 4. Handle Remote Track
    _peerConnection!.onTrack = (event) {
      _log('Received remote track: kind=${event.track.kind}, streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        if (!isAudioOnly) {
          remoteRenderer.srcObject = event.streams[0];
        }
        if (event.track.kind == 'video' || isAudioOnly) {
          _handleConnectionRecovered();
          _onConnected();
        }
        notifyListeners();
      }
    };

    // 5. Handle ICE Candidates
    _peerConnection!.onIceCandidate = (candidate) {
      if (_currentSession == null) return;
      final candStr = candidate.candidate ?? '';
      final candidateType = extractCandidateType(candStr);
      _gatheredCandidateTypes.add(candidateType);
      if (candidateType == 'host') {
        _hasGatheredHostCandidate = true;
      }
      _log('Gathered local ICE candidate: [type=$candidateType] $candStr');

      final collection = _isCaller ? 'callerCandidates' : 'calleeCandidates';

      unawaited(() async {
        try {
          await _firestore
              .collection('calls')
              .doc(_currentSession!.id)
              .collection(collection)
              .add({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        } catch (e) {
          _log('Error uploading candidate to Firestore: $e');
        }
      }());
    };

    // 6. Handle Connection State
    _peerConnection!.onIceConnectionState = (state) {
      _log('ICE Connection State changed: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _handleConnectionRecovered();
        _onConnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _handleConnectionLostWithGracePeriod(reason: 'ICE connection state disconnected');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _log(
          'ICE Connection failed. Gathered types: $_gatheredCandidateTypes, hasHost: $_hasGatheredHostCandidate',
        );
        _handleConnectionLostWithGracePeriod(reason: 'ICE connection state failed');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _endCallInternal(status: CallStatus.ended);
      }
    };

    _peerConnection!.onConnectionState = (state) {
      _log('Peer Connection State changed: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _handleConnectionRecovered();
        _onConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _handleConnectionLostWithGracePeriod(reason: 'Peer connection state $state');
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
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && _peerConnection != null) {
            // Guard against stale candidates from mismatched or previously ended calls
            if (_currentSession == null || _currentSession!.id != callId) {
              _log('Ignoring stale ICE candidate from call $callId (active: ${_currentSession?.id})');
              continue;
            }

            final candStr = data['candidate'] as String? ?? '';
            final candidateType = extractCandidateType(candStr);
            final candidate = RTCIceCandidate(
              data['candidate'] as String,
              data['sdpMid'] as String?,
              data['sdpMLineIndex'] as int?,
            );

            if (!_hasRemoteDescription) {
              _pendingRemoteCandidates.add(candidate);
              _log('Buffered remote ICE candidate before remote description: [type=$candidateType] $candStr');
            } else {
              try {
                await _peerConnection!.addCandidate(candidate);
                _log('Applied remote ICE candidate: [type=$candidateType] $candStr');
              } catch (e) {
                _log('Error applying remote candidate: $e');
              }
            }
          }
        }
      }
    });
  }

  void _onConnected() {
    if (_status == CallStatus.connected) return;
    _log('Call successfully established and connected.');
    _connectionTimeoutTimer?.cancel();
    _status = CallStatus.connected;
    _startStatsPolling();
    _logConnectedCandidatePair();
    notifyListeners();
  }

  void _startRingingTimeoutTimer() {
    _connectionTimeoutTimer?.cancel();
    _log('Started ringing timeout timer (30s) waiting for callee to answer.');
    _connectionTimeoutTimer = Timer(const Duration(seconds: 30), () {
      _log('Ringing timeout timer fired after 30s! Current status: $_status');
      if (_status == CallStatus.ringing) {
        _log('Call ringing timed out — recipient did not answer within 30 seconds.');
        _onRingingTimeout();
      }
    });
  }

  void _onRingingTimeout() {
    _status = CallStatus.failed;
    _failureReason = 'No answer — recipient did not respond in time.';
    _log('Call failed: $_failureReason');
    notifyListeners();

    if (_currentSession != null) {
      final id = _currentSession!.id;
      _firestore.collection('calls').doc(id).update({
        'status': CallStatus.failed.name,
        'failureReason': _failureReason,
      }).catchError((_) {});
      _cleanupCallSignaling(id);
    }
  }

  void _startConnectionTimeoutTimer({
    Duration duration = const Duration(seconds: 15),
    String reason = 'ICE negotiation',
  }) {
    _connectionTimeoutTimer?.cancel();
    _log('Started connection timeout timer (${duration.inSeconds}s, reason: $reason).');
    _connectionTimeoutTimer = Timer(duration, () {
      _log('Connection timeout timer fired after ${duration.inSeconds}s! Current status: $_status');
      if (_status != CallStatus.connected && _status != CallStatus.ended) {
        _log('Connection timed out after ${duration.inSeconds}s.');
        _onConnectionFailed();
      }
    });
  }

  void _onConnectionFailed({String? reason}) {
    _connectionTimeoutTimer?.cancel();
    _status = CallStatus.failed;
    if (reason != null) {
      _failureReason = reason;
    } else if (!_hasGatheredHostCandidate) {
      _isLocalNetworkDenied = true;
      _failureReason =
          "Local network access was not permitted. Calls may be limited to networks with internet-reachable connectivity.";
    } else {
      _isLocalNetworkDenied = false;
      _failureReason =
          "Could not establish a direct peer-to-peer connection. Verify both devices have an active internet connection.";
    }
    _log(
      'Connection failed: $_failureReason (isLocalNetworkDenied=$_isLocalNetworkDenied, gatheredTypes=$_gatheredCandidateTypes)',
    );
    notifyListeners();

    if (_currentSession != null) {
      final id = _currentSession!.id;
      _firestore.collection('calls').doc(id).update({
        'status': CallStatus.failed.name,
        'failureReason': _failureReason,
      }).catchError((_) {});
      _cleanupCallSignaling(id);
    }
  }

  Future<void> _cleanupCallSignaling(String callId) async {
    try {
      final callerCandDocs = await _firestore
          .collection('calls')
          .doc(callId)
          .collection('callerCandidates')
          .get();
      for (final doc in callerCandDocs.docs) {
        await doc.reference.delete().catchError((_) {});
      }
      final calleeCandDocs = await _firestore
          .collection('calls')
          .doc(callId)
          .collection('calleeCandidates')
          .get();
      for (final doc in calleeCandDocs.docs) {
        await doc.reference.delete().catchError((_) {});
      }
      _log('Cleaned up signaling candidates for call $callId');
    } catch (e) {
      _log('Note: Error during signaling candidate cleanup: $e');
    }
  }

  Future<void> _logConnectedCandidatePair() async {
    if (_peerConnection == null) return;
    try {
      final reports = await _peerConnection!.getStats();
      for (final report in reports) {
        if (report.type == 'candidate-pair' &&
            (report.values['state'] == 'succeeded' || report.values['nominated'] == true)) {
          final localType = report.values['localCandidateType'] ??
              report.values['candidateType'] ??
              'unknown';
          final remoteType = report.values['remoteCandidateType'] ?? 'unknown';
          _connectedPair = 'local=$localType, remote=$remoteType';
          _log('Connected via ICE candidate pair: $_connectedPair');
        }
      }
    } catch (e) {
      _log('Candidate pair logging note: $e');
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _measureStats();
    });
  }

  Future<void> _measureStats() async {
    if (_isDisposed || _peerConnection == null || _status != CallStatus.connected) return;

    try {
      final reports = await _peerConnection!.getStats();
      double availableBandwidth = qualityController.currentTier.targetBitrateBps.toDouble();
      double rtt = 45.0;
      double packetLoss = 0.0;
      int fps = 30;

      _statsCounter++;
      dynamic outboundAudioLevel;
      dynamic inboundAudioLevel;

      for (final report in reports) {
        final values = report.values;
        if ((report.type == 'media-source' || report.type == 'outbound-rtp') &&
            values['kind'] == 'audio') {
          outboundAudioLevel ??= values['audioLevel'] ?? values['totalAudioEnergy'];
        } else if (report.type == 'inbound-rtp' && values['kind'] == 'audio') {
          inboundAudioLevel ??= values['audioLevel'] ?? values['totalAudioEnergy'];
        }

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

      if (_isDisposed || _status != CallStatus.connected) return;

      if (_statsCounter % 5 == 0 &&
          (outboundAudioLevel != null || inboundAudioLevel != null)) {
        _log('Audio Stats: outboundLevel=$outboundAudioLevel, inboundLevel=$inboundAudioLevel');
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
          encoding.maxFramerate = qualityController.currentTargetFps;
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

  bool get isDisconnectGracePeriodActive =>
      _disconnectGraceTimer != null && _disconnectGraceTimer!.isActive;

  void _handleConnectionLostWithGracePeriod({required String reason}) {
    if (_status != CallStatus.connected) {
      if (_status != CallStatus.failed &&
          _status != CallStatus.ended &&
          _status != CallStatus.rejected) {
        _onConnectionFailed();
      }
      return;
    }

    if (_disconnectGraceTimer != null && _disconnectGraceTimer!.isActive) {
      _log('Already within disconnection grace period. ($reason)');
      return;
    }

    _log('Transient connection interruption ($reason). Starting 6s grace period for WebRTC recovery...');
    _disconnectGraceTimer = Timer(disconnectGracePeriod, () {
      _log('Disconnection grace period (6s) expired without reconnection. Declaring network lost.');
      _disconnectGraceTimer = null;
      if (_status == CallStatus.connected) {
        _onNetworkLost();
      }
    });
  }

  void _handleConnectionRecovered() {
    if (_disconnectGraceTimer != null) {
      _log('Connection recovered to connected/completed within grace period! Cancelling grace timer.');
      _disconnectGraceTimer?.cancel();
      _disconnectGraceTimer = null;
    }
  }

  @visibleForTesting
  void handleConnectionStateForTesting(RTCPeerConnectionState state) {
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      _handleConnectionRecovered();
      _onConnected();
    } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      _handleConnectionLostWithGracePeriod(reason: 'Peer connection state $state');
    }
  }

  @visibleForTesting
  void handleIceConnectionStateForTesting(RTCIceConnectionState state) {
    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      _handleConnectionRecovered();
      _onConnected();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      _handleConnectionLostWithGracePeriod(reason: 'ICE connection state disconnected');
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      _handleConnectionLostWithGracePeriod(reason: 'ICE connection state failed');
    }
  }

  @visibleForTesting
  void setStatusForTesting(CallStatus newStatus) {
    _status = newStatus;
  }

  @visibleForTesting
  void expireGracePeriodForTesting() {
    if (_disconnectGraceTimer != null && _disconnectGraceTimer!.isActive) {
      _disconnectGraceTimer?.cancel();
      _disconnectGraceTimer = null;
      if (_status == CallStatus.connected) {
        _onNetworkLost();
      }
    }
  }

  void _onNetworkLost() {
    _log('Network connection dropped mid-call.');
    _status = CallStatus.failed;
    _failureReason = 'Connection lost — network interrupted mid-call.';
    notifyListeners();

    if (_currentSession != null) {
      final id = _currentSession!.id;
      _firestore.collection('calls').doc(id).update({
        'status': CallStatus.failed.name,
        'failureReason': _failureReason,
      }).catchError((_) {});
      _cleanupCallSignaling(id);
    }
    _endCallInternal(status: CallStatus.failed, reason: _failureReason);
  }

  Future<void> rejectCall({required CallSession session}) async {
    _status = CallStatus.rejected;
    _failureReason = 'Call declined.';
    _log('Call was declined by user.');
    notifyListeners();

    await _firestore.collection('calls').doc(session.id).update({
      'status': CallStatus.rejected.name,
      'failureReason': 'Call declined by recipient.',
    }).catchError((_) {});

    await _cleanupCallSignaling(session.id);
    _endCallInternal(status: CallStatus.rejected, reason: 'Call declined by recipient.');
  }

  Future<void> endCall() async {
    final sessionId = _currentSession?.id;
    if (_currentSession != null) {
      await _firestore.collection('calls').doc(_currentSession!.id).update({
        'status': CallStatus.ended.name,
      }).catchError((_) {});
    }
    if (sessionId != null) {
      await _cleanupCallSignaling(sessionId);
    }
    _endCallInternal(status: CallStatus.ended);
  }

  void _endCallInternal({required CallStatus status, String? reason}) {
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    _statsTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _callDocSubscription?.cancel();
    _candidatesSubscription?.cancel();

    _pendingRemoteCandidates.clear();
    _hasRemoteDescription = false;

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;

    _peerConnection?.close();
    _peerConnection?.dispose();
    _peerConnection = null;

    try {
      if (localRenderer.srcObject != null) {
        localRenderer.srcObject = null;
      }
    } catch (_) {}
    try {
      if (remoteRenderer.srcObject != null) {
        remoteRenderer.srcObject = null;
      }
    } catch (_) {}

    _status = status;
    if (reason != null) {
      _failureReason = reason;
    } else if (status == CallStatus.rejected) {
      _failureReason = 'Call declined by recipient.';
    } else if (status == CallStatus.ended) {
      _failureReason = null;
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    _statsTimer?.cancel();
    _endCallInternal(status: CallStatus.ended);
    try {
      localRenderer.dispose();
    } catch (_) {}
    try {
      remoteRenderer.dispose();
    } catch (_) {}
    super.dispose();
  }
}
