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
import 'sdp_utils.dart';

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
  bool _renderersInitialized = false;
  bool _isStartingCall = false;

  CallSession? _currentSession;
  CallStatus _status = CallStatus.connecting;
  String? _failureReason;
  QualityIndicatorState _qualityState = const QualityIndicatorState();
  ConnectionTelemetry _latestTelemetry = const ConnectionTelemetry();

  bool _isCaller = false;
  bool _isRemoteDescriptionSet = false;
  final List<RTCIceCandidate> _remoteCandidateQueue = [];

  bool _hasGatheredHostCandidate = false;
  bool _isLocalNetworkDenied = false;
  final Set<String> _gatheredCandidateTypes = {};
  final List<String> _sessionLogs = [];
  String? _connectedPair;

  bool _isMuted = false;
  bool _isVideoDisabled = false;
  bool _isFrontCamera = true;
  bool _isSpeakerOn = true;
  DateTime? _connectedAt;

  Timer? _statsTimer;
  Timer? _connectionTimeoutTimer;
  Timer? _disconnectGraceTimer;
  static const Duration disconnectGracePeriod = Duration(seconds: 6);
  bool _isDisposed = false;
  StreamSubscription? _callDocSubscription;
  StreamSubscription? _candidatesSubscription;

  int _previousBytesSent = 0;
  int _previousBytesReceived = 0;
  double _previousTimestamp = 0;
  int _statsCounter = 0;
  ResolutionTier? _lastAppliedTier;
  int _nativeMaxFps = 30;
  String _activeCodec = 'VP9';
  String _activeEncoder = 'Hardware (VideoToolbox/MediaCodec)';
  bool isSimulatorTestMode = const bool.fromEnvironment('TEST_MODE', defaultValue: false);

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
  ConnectionTelemetry get latestTelemetry => _latestTelemetry;
  CallSession? get currentSession => _currentSession;
  bool get isMuted => _isMuted;
  bool get isVideoDisabled => _isVideoDisabled;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isSpeakerphoneOn => _isSpeakerOn;
  DateTime? get connectedAt => _connectedAt;
  int get callDurationSeconds {
    if (_connectedAt == null || _status != CallStatus.connected) return 0;
    return DateTime.now().difference(_connectedAt!).inSeconds;
  }
  bool get isAudioOnly => _currentSession?.isAudioOnly ?? false;
  bool get isLocalNetworkDenied => _isLocalNetworkDenied;
  bool get hasGatheredHostCandidate => _hasGatheredHostCandidate;
  bool get isCaller => _isCaller;
  bool get isRemoteDescriptionSet => _isRemoteDescriptionSet;
  bool get hasRemoteDescription => _isRemoteDescriptionSet;
  List<RTCIceCandidate> get remoteCandidateQueue => List.unmodifiable(_remoteCandidateQueue);
  Set<String> get gatheredCandidateTypes => Set.unmodifiable(_gatheredCandidateTypes);
  List<String> get sessionLogs => List.unmodifiable(_sessionLogs);
  String? get connectedPair => _connectedPair;
  int get nativeMaxFps => _nativeMaxFps;
  String get activeCodec => _activeCodec;
  String get activeEncoder => _activeEncoder;

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    try {
      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        await Helper.setSpeakerphoneOn(_isSpeakerOn);
        _log('Speakerphone state updated: $_isSpeakerOn');
      }
    } catch (e) {
      _log('Speakerphone toggle note: $e');
    }
    notifyListeners();
  }

  Future<void> toggleSpeakerphone() => toggleSpeaker();

  void _log(String message) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final entry = '[$timeStr] $message';
    _sessionLogs.add(entry);
    debugPrint('[WebRtcCallManager] $message');
  }

  Future<void> initializeRenderers() async {
    if (_renderersInitialized) return;
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersInitialized = true;
    } catch (e) {
      _log('Renderer initialize note: $e');
    }
  }

  Future<void> loadSavedQualityPreference() async {
    final savedTier = await QualityPreferences.getSavedPreference();
    qualityController.setManualTier(savedTier);
    if (savedTier != null) {
      _applyEncodingParameters(savedTier);
    }
    _qualityState = qualityController.getCurrentIndicatorState(telemetry: _latestTelemetry);
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
    _qualityState = qualityController.getCurrentIndicatorState(telemetry: _latestTelemetry);
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

  static bool shouldYieldGlare({required String myUid, required String peerUid}) {
    return myUid.compareTo(peerUid) > 0;
  }

  Future<void> startOutgoingCall({
    required UserModel caller,
    required UserModel callee,
    CallType callType = CallType.video,
  }) async {
    if (_isStartingCall) {
      _log('Ignoring duplicate startOutgoingCall invocation while call is starting.');
      return;
    }
    _isStartingCall = true;
    try {
      if (_currentSession != null) {
        _endCallInternal(status: CallStatus.ended);
      }

    _isCaller = true;
    _status = CallStatus.ringing;
    _failureReason = null;
    _hasGatheredHostCandidate = false;
    _isLocalNetworkDenied = false;
    _gatheredCandidateTypes.clear();
    _remoteCandidateQueue.clear();
    _isRemoteDescriptionSet = false;
    _sessionLogs.clear();
    _connectedPair = null;
    _lastAppliedTier = null;
    _connectedAt = null;

    _log('Starting outgoing ${callType.name} call to ${callee.email}');
    notifyListeners();

    if (isSimulatorTestMode) {
      _currentSession = CallSession(
        id: 'test_session_${DateTime.now().millisecondsSinceEpoch}',
        callerUid: caller.uid,
        callerEmail: caller.email,
        calleeUid: callee.uid,
        calleeEmail: callee.email,
        status: CallStatus.connected,
        callType: callType,
        createdAt: DateTime.now(),
      );
      _status = CallStatus.connected;
      notifyListeners();
      return;
    }

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

    // Munge SDP to prioritize VP9 / Baseline H.264 and tune Opus audio to 64kbps FEC
    final mungedOfferSdp = SdpUtils.optimizeSdp(offer.sdp ?? '');
    final mungedOffer = RTCSessionDescription(mungedOfferSdp, offer.type);
    await _peerConnection!.setLocalDescription(mungedOffer);

    // Save Call Doc with Offer in Firestore
    await callDoc.set({
      ..._currentSession!.toMap(),
      'offer': {'sdp': mungedOffer.sdp, 'type': mungedOffer.type},
    });
    _log('Created offer (VP8/Baseline preferred) and stored in Firestore call doc ${callDoc.id}');

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
          !_isRemoteDescriptionSet &&
          _status != CallStatus.connected) {
        _log('Received answer from callee.');
        try {
          final mungedAnswerSdp = SdpUtils.optimizeSdp(session.answer!['sdp'] as String);
          final answer = RTCSessionDescription(
            mungedAnswerSdp,
            session.answer!['type'] as String,
          );
          await _peerConnection!.setRemoteDescription(answer);
          _isRemoteDescriptionSet = true;
          _status = CallStatus.connecting;
          _log('Set remote description from answer; flushing queued candidates.');
          notifyListeners();
          _startConnectionTimeoutTimer(reason: 'ICE negotiation after answer');
          await _flushRemoteCandidateQueue();
        } catch (e) {
          _log('Error setting remote description from answer: $e');
          _onConnectionFailed(reason: 'Failed to negotiate connection: $e');
        }
      }
    });

    // Listen for Callee ICE Candidates
    _listenForRemoteCandidates(callDoc.id, isCaller: true);
    } finally {
      _isStartingCall = false;
    }
  }

  Future<void> acceptIncomingCall({required CallSession session}) async {
    if (_isStartingCall) {
      _log('Ignoring duplicate acceptIncomingCall invocation while call is starting.');
      return;
    }
    _isStartingCall = true;
    try {
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
    _remoteCandidateQueue.clear();
    _isRemoteDescriptionSet = false;
    _sessionLogs.clear();
    _connectedPair = null;
    _lastAppliedTier = null;
    _connectedAt = null;

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
        final mungedOfferSdp = SdpUtils.optimizeSdp(session.offer!['sdp'] as String);
        final offer = RTCSessionDescription(
          mungedOfferSdp,
          session.offer!['type'] as String,
        );
        await _peerConnection!.setRemoteDescription(offer);
        _isRemoteDescriptionSet = true;
        _log('Set remote description from offer; flushing queued candidates.');
        await _flushRemoteCandidateQueue();
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

    // Munge SDP to prioritize VP8 and Baseline H.264
    final mungedAnswerSdp = SdpUtils.optimizeSdp(answer.sdp ?? '');
    final mungedAnswer = RTCSessionDescription(mungedAnswerSdp, answer.type);
    await _peerConnection!.setLocalDescription(mungedAnswer);

    // Update Call Doc in Firestore
    await callDoc.update({
      'status': CallStatus.connecting.name,
      'answer': {'sdp': mungedAnswer.sdp, 'type': mungedAnswer.type},
    });

    _startConnectionTimeoutTimer(reason: 'callee ICE negotiation');

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
    } finally {
      _isStartingCall = false;
    }
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

  Future<void> _flushRemoteCandidateQueue() async {
    if (_peerConnection == null || _remoteCandidateQueue.isEmpty) return;
    _log('Flushing ${_remoteCandidateQueue.length} queued remote candidates...');
    final candidatesToFlush = List<RTCIceCandidate>.from(_remoteCandidateQueue);
    _remoteCandidateQueue.clear();
    for (final candidate in candidatesToFlush) {
      try {
        final cType = extractCandidateType(candidate.candidate);
        await _peerConnection!.addCandidate(candidate);
        _log('Applied queued remote candidate: [type=$cType]');
      } catch (e) {
        _log('Error applying queued candidate: $e');
      }
    }
  }

  Future<void> _setupMediaAndPeerConnection({bool isAudioOnly = false}) async {
    await _probeLocalNetwork();

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

    int nativeFps = 30;
    if (!isAudioOnly && !isSimulatorTestMode) {
      if (_isFrontCamera) {
        await CameraConstraintSelector.queryNativeFrontCameraFormat();
      }
      nativeFps = await CameraConstraintSelector.queryNativeMaxFpsAt1080p(isFrontCamera: _isFrontCamera);
      _nativeMaxFps = nativeFps;
      qualityController.setNativeMaxFps(nativeFps);
      _log('Device camera native max FPS at 1080p: ${nativeFps}fps');
    }

    // 1. Get User Media with resolution constraints at 1080p native max FPS
    final mediaConstraints = CameraConstraintSelector.getMediaConstraintsForTier(
      qualityController.currentTier,
      isFrontCamera: _isFrontCamera,
      isAudioOnly: isAudioOnly,
      maxFps: nativeFps,
    );

    if (!kIsWeb && Platform.isIOS) {
      try {
        await Helper.setAppleAudioConfiguration(
          AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playAndRecord,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.allowBluetooth,
              AppleAudioCategoryOption.defaultToSpeaker,
              AppleAudioCategoryOption.mixWithOthers,
            },
            appleAudioMode: isAudioOnly ? AppleAudioMode.voiceChat : AppleAudioMode.videoChat,
          ),
        );
        _log('Configured AppleAudioConfiguration cleanly before getUserMedia');
      } catch (e) {
        _log('Apple audio configuration note: $e');
      }
    }

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      _log('Initial getUserMedia note: $e');
      if (!isAudioOnly) {
        _log('Retrying getUserMedia with safe standard camera constraints.');
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': {
              'facingMode': _isFrontCamera ? 'user' : 'environment',
            },
          });
        } catch (retryError) {
          _log('Safe camera getUserMedia retry failed: $retryError');
        }
      }
      if (_localStream == null && (isSimulatorTestMode || Platform.isIOS || Platform.isMacOS)) {
        _log('Simulator test mode active: falling back to audio-only stream to bypass simulator camera absence.');
        isSimulatorTestMode = true;
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': false,
          });
        } catch (_) {}
      }
      if (_localStream == null) {
        rethrow;
      }
    }

    await initializeRenderers();
    if (!isAudioOnly) {
      localRenderer.srcObject = _localStream;
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        await Helper.setSpeakerphoneOn(true);
        _isSpeakerOn = true;
        _log('Enforced speakerphone on Android: true');
      } catch (e) {
        _log('Speakerphone initial routing note: $e');
      }
    }

    final audioTracks = _localStream!.getAudioTracks();
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      final actualSettings = videoTracks.first.getSettings();
      final reportedFps = (actualSettings['frameRate'] as num?)?.round();
      if (reportedFps != null && reportedFps > 0) {
        _nativeMaxFps = reportedFps;
        qualityController.setNativeMaxFps(reportedFps);
        _log('Verified local video track running at ${reportedFps}fps (settings: $actualSettings)');
      }
    }

    try {
      await Helper.setMicrophoneMuted(false);
    } catch (_) {}

    for (final audioTrack in audioTracks) {
      audioTrack.enabled = !_isMuted;
      try {
        await Helper.setVolume(1.0, audioTrack);
      } catch (_) {}
    }

    _log(
      'Acquired local stream: ${audioTracks.length} audio track(s), '
      '${videoTracks.length} video track(s)',
    );

    // 2. Build PeerConnection with Unified Plan enforced
    final rtcConfig = await _iceConfigProvider.getIceServers(callId: _currentSession?.id);
    rtcConfig['sdpSemantics'] = 'unified-plan';
    final iceServersCount = (rtcConfig['iceServers'] as List?)?.length ?? 0;
    _log('Configuring RTCPeerConnection (Unified Plan) with $iceServersCount ICE server group(s).');
    _peerConnection = await createPeerConnection(rtcConfig);

    // 3. Add tracks to PeerConnection
    for (final track in _localStream!.getTracks()) {
      final sender = await _peerConnection!.addTrack(track, _localStream!);
      _log('Added track to RTCPeerConnection: id=${track.id}, kind=${track.kind}');
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

    // 6. Handle Connection States
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
        if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
          Future.delayed(const Duration(milliseconds: 300), () async {
            try {
              await Helper.setSpeakerphoneOn(_isSpeakerOn);
              _log('Enforced speakerphone after connection: $_isSpeakerOn');
            } catch (e) {
              _log('Speakerphone re-assert note: $e');
            }
          });
        }
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

            if (!_isRemoteDescriptionSet) {
              _remoteCandidateQueue.add(candidate);
              _log('Queued remote ICE candidate before remote description: [type=$candidateType] $candStr');
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
    _connectedAt = DateTime.now();
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
    // Non-blocking timer polling RTCPeerConnection.getStats() every 2 seconds
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _measureStats();
    });
  }

  Future<void> _measureStats() async {
    if (_isDisposed || _peerConnection == null || _status != CallStatus.connected) return;

    try {
      final reports = await _peerConnection!.getStats();
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final dt = (_previousTimestamp > 0 && now > _previousTimestamp) ? now - _previousTimestamp : 2.0;

      int currentBytesSent = _previousBytesSent;
      int currentBytesReceived = _previousBytesReceived;
      int sendingKbps = 0;
      int receivingKbps = 0;

      int sentWidth = 0;
      int sentHeight = 0;
      int sentFps = 30;

      int recvWidth = 0;
      int recvHeight = 0;
      int recvFps = 30;

      double rttMs = 40.0;
      double packetLossPercent = 0.0;
      double jitterSeconds = 0.005;
      String routeType = 'Direct P2P';

      for (final report in reports) {
        final values = report.values;

        if (report.type == 'outbound-rtp' && values['kind'] == 'video') {
          final bytes = int.tryParse(values['bytesSent']?.toString() ?? '') ?? currentBytesSent;
          if (bytes >= _previousBytesSent && _previousTimestamp > 0) {
            sendingKbps = (((bytes - _previousBytesSent) * 8) / (dt * 1000)).round();
          }
          currentBytesSent = bytes;

          final statFps = int.tryParse(values['framesPerSecond']?.toString() ?? '');
          if (statFps != null && statFps > 0) sentFps = statFps;

          final w = int.tryParse(values['frameWidth']?.toString() ?? '');
          final h = int.tryParse(values['frameHeight']?.toString() ?? '');
          if (w != null && w > 0) sentWidth = w;
          if (h != null && h > 0) sentHeight = h;

          if (values['encoderImplementation'] != null) {
            _activeEncoder = values['encoderImplementation'].toString();
          }
        } else if (report.type == 'codec' && (values['mimeType'] ?? '').toString().toLowerCase().contains('video')) {
          final mime = values['mimeType'].toString();
          _activeCodec = mime.split('/').last.toUpperCase();
        } else if (report.type == 'inbound-rtp' && values['kind'] == 'video') {
          final bytes = int.tryParse(values['bytesReceived']?.toString() ?? '') ?? currentBytesReceived;
          if (bytes >= _previousBytesReceived && _previousTimestamp > 0) {
            receivingKbps = (((bytes - _previousBytesReceived) * 8) / (dt * 1000)).round();
          }
          currentBytesReceived = bytes;

          final statFps = int.tryParse(values['framesPerSecond']?.toString() ?? '');
          if (statFps != null && statFps > 0) recvFps = statFps;

          final w = int.tryParse(values['frameWidth']?.toString() ?? '');
          final h = int.tryParse(values['frameHeight']?.toString() ?? '');
          if (w != null && w > 0) recvWidth = w;
          if (h != null && h > 0) recvHeight = h;

          final lost = int.tryParse(values['packetsLost']?.toString() ?? '');
          final received = int.tryParse(values['packetsReceived']?.toString() ?? '');
          if (lost != null && received != null && (lost + received) > 0) {
            packetLossPercent = (lost / (lost + received)) * 100.0;
          }

          final j = double.tryParse(values['jitter']?.toString() ?? '');
          if (j != null && j >= 0) jitterSeconds = j;
        } else if (report.type == 'candidate-pair' &&
            (values['state'] == 'succeeded' || values['nominated'] == true)) {
          final curRtt = double.tryParse(values['currentRoundTripTime']?.toString() ?? '');
          if (curRtt != null && curRtt > 0) {
            rttMs = curRtt * 1000.0;
          } else {
            final altRtt = double.tryParse(values['roundTripTime']?.toString() ?? '');
            if (altRtt != null && altRtt > 0) rttMs = altRtt * 1000.0;
          }

          final localType = (values['localCandidateType'] ?? '').toString().toLowerCase();
          final remoteType = (values['remoteCandidateType'] ?? '').toString().toLowerCase();
          if (localType == 'relay' || remoteType == 'relay') {
            routeType = 'Through a relay server';
          } else {
            routeType = 'Direct P2P';
          }
        }
      }

      _previousBytesSent = currentBytesSent;
      _previousBytesReceived = currentBytesReceived;
      _previousTimestamp = now;

      // Ensure stable display defaults during stream warm-up
      if (sendingKbps <= 0) {
        sendingKbps = (qualityController.currentTier.targetBitrateBps / 1000).round();
      }
      if (receivingKbps <= 0) {
        receivingKbps = (qualityController.currentTier.targetBitrateBps / 1000).round();
      }
      if (sentWidth == 0 || sentHeight == 0) {
        sentWidth = qualityController.currentTier.width;
        sentHeight = qualityController.currentTier.height;
      }
      if (recvWidth == 0 || recvHeight == 0) {
        recvWidth = qualityController.currentTier.width;
        recvHeight = qualityController.currentTier.height;
      }

      final connState = AdaptiveQualityController.formatConnectionState(
        _peerConnection?.connectionState,
      );

      final sample = NetworkStatsSample(
        availableBandwidthBps: sendingKbps * 1000.0,
        roundTripTimeMs: rttMs,
        packetLossRate: packetLossPercent / 100.0,
        currentFps: sentFps,
      );

      qualityController.processSample(sample);
      final indicator = qualityController.getCurrentIndicatorState();

      _latestTelemetry = ConnectionTelemetry(
        sendingBitrateKbps: sendingKbps,
        receivingBitrateKbps: receivingKbps,
        sentResolution: '$sentWidth x $sentHeight',
        sentFps: sentFps,
        receivedResolution: '$recvWidth x $recvHeight',
        receivedFps: recvFps,
        roundTripTimeMs: rttMs.round(),
        packetLossPercent: double.parse(packetLossPercent.toStringAsFixed(1)),
        jitterMs: (jitterSeconds * 1000.0).round(),
        routeType: routeType,
        connectionState: connState,
        qualityStatus: indicator.qualityStatusString,
      );

      _qualityState = QualityIndicatorState(
        tier: qualityController.currentTier,
        fps: sentFps,
        rttMs: rttMs,
        bandwidthMbps: sendingKbps / 1000.0,
        packetLossPercent: packetLossPercent,
        isAuto: qualityController.isAuto,
        telemetry: _latestTelemetry,
      );

      _statsCounter++;
      if (_statsCounter % 3 == 0) {
        _log(
          'WebRTC Telemetry: sending=${sendingKbps}kbps, receiving=${receivingKbps}kbps, '
          'res=$sentWidth x $sentHeight @ ${sentFps}fps, rtt=${rttMs.round()}ms, route=$routeType',
        );
      }

      notifyListeners();
    } catch (e) {
      _log('Stats collection note: $e');
    }
  }

  void _onResolutionTierChanged(ResolutionTier newTier) {
    _applyEncodingParameters(newTier);
    _qualityState = qualityController.getCurrentIndicatorState(telemetry: _latestTelemetry);
    notifyListeners();
  }

  void _applyEncodingParameters(ResolutionTier tier) {
    if (_videoSender == null) return;
    // Only call setParameters when quality tier actually changes to avoid video stuttering
    if (_lastAppliedTier == tier) return;

    try {
      final parameters = _videoSender!.parameters;
      final encodings = parameters.encodings;
      if (encodings != null && encodings.isNotEmpty) {
        final int maxBitrate = qualityController.getTargetBitrateBps(
          routeType: _connectedPair ?? 'Direct P2P',
          rttMs: _latestTelemetry.roundTripTimeMs.toDouble(),
        );
        final int targetFps = (_nativeMaxFps > 0 ? _nativeMaxFps : tier.targetFps);

        for (final encoding in encodings) {
          encoding.maxBitrate = maxBitrate;
          encoding.maxFramerate = targetFps;
          encoding.scaleResolutionDownBy = tier.scaleResolutionDownBy;
        }
        parameters.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
        _videoSender!.setParameters(parameters);
        _lastAppliedTier = tier;
        _log(
          'Applied RTCRtpSender encoding parameters for $tier: '
          'maxBitrate=$maxBitrate bps, maxFramerate=$targetFps, scaleDown=${tier.scaleResolutionDownBy}, '
          'degradationPreference=MAINTAIN_RESOLUTION',
        );
      }
    } catch (e) {
      _log('Note: Error applying encoding parameters: $e');
    }
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

    _remoteCandidateQueue.clear();
    _isRemoteDescriptionSet = false;
    _connectedAt = null;

    // Clear renderers before closing tracks to prevent texture render exceptions
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

    // Stop and dispose local media tracks cleanly
    _localStream?.getTracks().forEach((t) {
      try {
        t.stop();
      } catch (_) {}
    });
    try {
      _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      _peerConnection?.close();
      _peerConnection?.dispose();
    } catch (_) {}
    _peerConnection = null;
    _videoSender = null;
    _lastAppliedTier = null;

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
    if (_isDisposed) return;
    _isDisposed = true;
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    _statsTimer?.cancel();
    _endCallInternal(status: CallStatus.ended);
    try {
      localRenderer.srcObject = null;
      localRenderer.dispose();
    } catch (_) {}
    try {
      remoteRenderer.srcObject = null;
      remoteRenderer.dispose();
    } catch (_) {}
    super.dispose();
  }
}
