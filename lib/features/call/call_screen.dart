import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../models/user_model.dart';
import '../../models/call_session.dart';
import '../../core/webrtc/webrtc_call_manager.dart';
import '../../design_system/ozone_theme.dart';
import '../../design_system/quality_indicator_widget.dart';

class CallScreen extends StatefulWidget {
  final UserModel? caller;
  final UserModel? callee;
  final bool isIncoming;
  final CallSession? incomingSession;
  final WebRtcCallManager? callManager;
  final CallType callType;

  const CallScreen({
    super.key,
    this.caller,
    this.callee,
    this.isIncoming = false,
    this.incomingSession,
    this.callManager,
    this.callType = CallType.video,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final WebRtcCallManager _callManager;

  bool _isInitialized = false;
  late bool _isCover;
  Offset? _pipOffset;
  Timer? _durationTimer;
  int _callDurationSeconds = 0;
  bool _timerStarted = false;

  @override
  void initState() {
    super.initState();
    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    _isCover = !isDesktop;

    _callManager = widget.callManager ?? WebRtcCallManager();
    _callManager.addListener(_onCallManagerChanged);
    if (_callManager.status == CallStatus.connected) {
      _startDurationTimer();
    }
    _init1on1Call();
  }

  void _onCallManagerChanged() {
    if (_callManager.status == CallStatus.connected) {
      if (!_timerStarted) {
        _startDurationTimer();
      }
    } else {
      if (_timerStarted) {
        _stopDurationTimer();
      }
    }
  }

  void _startDurationTimer() {
    _timerStarted = true;
    _callDurationSeconds = _callManager.callDurationSeconds;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _callDurationSeconds = _callManager.callDurationSeconds;
        });
      }
    });
  }

  void _stopDurationTimer() {
    _timerStarted = false;
    _durationTimer?.cancel();
    _durationTimer = null;
    if (mounted) {
      setState(() {
        _callDurationSeconds = 0;
      });
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _peerDisplayName {
    final email = widget.isIncoming
        ? (widget.caller?.email ?? 'Caller')
        : (widget.callee?.email ?? 'Recipient');
    final prefix = email.split('@').first;
    if (prefix.isNotEmpty) {
      return prefix[0].toUpperCase() + prefix.substring(1);
    }
    return email;
  }

  Future<void> _init1on1Call() async {
    await _callManager.loadSavedQualityPreference();
    await _callManager.initializeRenderers();
    if (mounted) {
      setState(() => _isInitialized = true);
    }

    if (widget.isIncoming && widget.incomingSession != null) {
      await _callManager.acceptIncomingCall(session: widget.incomingSession!);
    } else if (_callManager.status != CallStatus.connected && widget.caller != null && widget.callee != null) {
      await _callManager.startOutgoingCall(
        caller: widget.caller!,
        callee: widget.callee!,
        callType: widget.callType,
      );
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _callManager.removeListener(_onCallManagerChanged);
    if (widget.callManager == null) {
      _callManager.dispose();
    }
    super.dispose();
  }

  Widget _buildTopCenterOverlay() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white12, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _peerDisplayName,
                style: const TextStyle(
                  color: OzoneTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.lock_rounded,
                color: OzoneTheme.cyan,
                size: 14,
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_callDurationSeconds),
                style: const TextStyle(
                  color: OzoneTheme.emerald,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomControlBar() {
    final isMuted = _callManager.isMuted;
    final isCameraOff = _callManager.isVideoDisabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF13151C).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white12, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: isMuted ? OzoneTheme.ruby : Colors.white,
              size: 24,
            ),
            tooltip: isMuted ? 'Unmute' : 'Mute',
            onPressed: () => _callManager.toggleMute(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              isCameraOff ? Icons.videocam_off_rounded : Icons.flip_camera_ios_rounded,
              color: isCameraOff ? OzoneTheme.ruby : Colors.white,
              size: 24,
            ),
            tooltip: 'Switch Camera',
            onPressed: () => _callManager.switchCamera(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(
              Icons.speed_rounded,
              color: Colors.white,
              size: 24,
            ),
            tooltip: 'Connection Stats',
            onPressed: () {
              showConnectionStatsModal(
                context,
                _callManager.qualityState,
                callManager: _callManager,
              );
            },
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'endVideoCallBtn',
            backgroundColor: OzoneTheme.ruby,
            foregroundColor: Colors.white,
            elevation: 0,
            mini: true,
            tooltip: 'End Call',
            onPressed: () async {
              await _callManager.endCall();
              if (mounted) Navigator.of(context).pop();
            },
            child: const Icon(Icons.call_end_rounded, size: 22),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const pipWidth = 110.0;
    const pipHeight = 155.0;
    final defaultOffset = _pipOffset ?? Offset(screenSize.width - pipWidth - 16, 68);
    final maxX = (screenSize.width - pipWidth - 8.0).clamp(8.0, double.infinity);
    final maxY = (screenSize.height - pipHeight - 110.0).clamp(40.0, double.infinity);
    _pipOffset = Offset(
      defaultOffset.dx.clamp(8.0, maxX),
      defaultOffset.dy.clamp(40.0, maxY),
    );

    final Widget content = ListenableBuilder(
      listenable: _callManager,
      builder: (context, _) {
        final isConnected = _callManager.status == CallStatus.connected;
        final isFailed = _callManager.status == CallStatus.failed ||
            _callManager.status == CallStatus.rejected;
        final isAudioMode = widget.callType == CallType.audio ||
            _callManager.isAudioOnly ||
            (widget.incomingSession?.isAudioOnly ?? false);

        if (isAudioMode) {
          return Scaffold(
            backgroundColor: OzoneTheme.background,
            body: Stack(
              children: [
                _buildAudioCallView(_peerDisplayName),
                if (isFailed)
                  Positioned.fill(
                    child: _buildFailureOverlay(
                      _callManager.failureReason ??
                          "Could not establish a direct peer-to-peer connection.",
                    ),
                  ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (isConnected && _isInitialized)
                Positioned.fill(
                  child: GestureDetector(
                    onDoubleTap: () {
                      setState(() {
                        _isCover = !_isCover;
                      });
                    },
                    child: RepaintBoundary(
                      child: RTCVideoView(
                        _callManager.remoteRenderer,
                        objectFit: _isCover
                            ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                            : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      ),
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: Container(
                    color: OzoneTheme.background,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: OzoneTheme.surfaceCard,
                            child: Text(
                              _peerDisplayName.isNotEmpty ? _peerDisplayName[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: OzoneTheme.cyan,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _peerDisplayName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: OzoneTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _callManager.status == CallStatus.ringing
                                ? 'Ringing...'
                                : 'Connecting peer-to-peer...',
                            style: const TextStyle(
                              fontSize: 14,
                              color: OzoneTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: OzoneTheme.cyan,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Draggable PiP Card
              if (_isInitialized)
                Positioned(
                  left: _pipOffset!.dx,
                  top: _pipOffset!.dy,
                  width: pipWidth,
                  height: pipHeight,
                  child: GestureDetector(
                    key: const ValueKey('pip_draggable_1on1'),
                    onPanUpdate: (details) {
                      setState(() {
                        final newX = (_pipOffset!.dx + details.delta.dx)
                            .clamp(8.0, screenSize.width - pipWidth - 8.0);
                        final newY = (_pipOffset!.dy + details.delta.dy)
                            .clamp(40.0, screenSize.height - pipHeight - 110.0);
                        _pipOffset = Offset(newX, newY);
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: OzoneTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white24,
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: _callManager.isVideoDisabled
                            ? const Center(
                                child: Icon(
                                  Icons.videocam_off_rounded,
                                  color: Colors.white38,
                                  size: 32,
                                ),
                              )
                            : RepaintBoundary(
                                child: RTCVideoView(
                                  _callManager.localRenderer,
                                  mirror: true,
                                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),

              if (isConnected)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, right: 16),
                      child: QualityIndicatorWidget(
                        state: _callManager.qualityState,
                        callManager: _callManager,
                        onTap: () => showConnectionStatsModal(
                          context,
                          _callManager.qualityState,
                          callManager: _callManager,
                        ),
                      ),
                    ),
                  ),
                ),

              if (isConnected) _buildTopCenterOverlay(),

              if (!isFailed)
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildFloatingBottomControlBar()),
                ),

              if (isFailed)
                Positioned.fill(
                  child: _buildFailureOverlay(
                    _callManager.failureReason ??
                        "Could not establish a direct peer-to-peer connection.",
                  ),
                ),
            ],
          ),
        );
      },
    );

    return RepaintBoundary(child: content);
  }

  Widget _buildAudioControlButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: OzoneTheme.surfaceCard.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _callManager.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: _callManager.isMuted ? OzoneTheme.ruby : OzoneTheme.textPrimary,
              size: 26,
            ),
            tooltip: _callManager.isMuted ? 'Unmute' : 'Mute',
            onPressed: () => _callManager.toggleMute(),
          ),
          const SizedBox(width: 14),
          IconButton(
            icon: Icon(
              _callManager.isSpeakerphoneOn
                  ? Icons.volume_up_rounded
                  : Icons.volume_down_rounded,
              color: _callManager.isSpeakerphoneOn ? OzoneTheme.cyan : OzoneTheme.textPrimary,
              size: 26,
            ),
            tooltip: _callManager.isSpeakerphoneOn ? 'Speakerphone: On' : 'Speakerphone: Off',
            onPressed: () => _callManager.toggleSpeakerphone(),
          ),
          const SizedBox(width: 20),
          FloatingActionButton(
            heroTag: 'endAudioCallBtn',
            backgroundColor: OzoneTheme.ruby,
            foregroundColor: Colors.white,
            elevation: 0,
            mini: true,
            tooltip: 'End Call',
            onPressed: () async {
              await _callManager.endCall();
              if (mounted) Navigator.of(context).pop();
            },
            child: const Icon(Icons.call_end_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioCallView(String otherEmail) {
    return Positioned.fill(
      child: Container(
        color: OzoneTheme.background,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OzoneTheme.surfaceCard,
                  border: Border.all(
                    color: OzoneTheme.cyan.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    otherEmail.isNotEmpty ? otherEmail[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.bold,
                      color: OzoneTheme.cyan,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                otherEmail,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: OzoneTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _callManager.status == CallStatus.connected
                    ? _formatDuration(_callDurationSeconds)
                    : (_callManager.status == CallStatus.ringing
                        ? 'Ringing...'
                        : 'Connecting audio...'),
                style: const TextStyle(
                  fontSize: 16,
                  color: OzoneTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 48.0),
                child: _buildAudioControlButtons(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFailureOverlay(String reason) {
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: OzoneTheme.ruby.withValues(alpha: 0.2),
                border: Border.all(color: OzoneTheme.ruby, width: 2),
              ),
              child: const Icon(
                Icons.call_end_rounded,
                color: OzoneTheme.ruby,
                size: 42,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Call Ended',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: OzoneTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: OzoneTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: OzoneTheme.surfaceCard,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
