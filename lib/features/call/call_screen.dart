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

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late final WebRtcCallManager _callManager;

  bool _isInitialized = false;
  late bool _isCover;
  bool _isLocalMain = false; // Double-tap swaps local/remote feeds
  bool _showControls = true; // Auto-hiding HUD controls
  Timer? _autoHideTimer;
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
    _resetAutoHideTimer();
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

  void _resetAutoHideTimer() {
    _autoHideTimer?.cancel();
    // In automated integration tests, do not auto-hide controls to allow deterministic finder assertions
    const isTestMode = bool.fromEnvironment('TEST_MODE', defaultValue: false);
    if (isTestMode) return;

    _autoHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControlsVisibility() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _resetAutoHideTimer();
    }
  }

  void _swapFeeds() {
    OzoneHaptics.selection();
    setState(() {
      _isLocalMain = !_isLocalMain;
    });
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
    } else if (_callManager.status != CallStatus.connected &&
        widget.caller != null &&
        widget.callee != null) {
      await _callManager.startOutgoingCall(
        caller: widget.caller!,
        callee: widget.callee!,
        callType: widget.callType,
      );
    }
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _durationTimer?.cancel();
    _callManager.removeListener(_onCallManagerChanged);
    if (widget.callManager == null) {
      _callManager.dispose();
    }
    super.dispose();
  }

  void _handleEndCall() {
    OzoneHaptics.medium();
    if (mounted) {
      Navigator.of(context).pop();
    }
    unawaited(_callManager.endCall());
  }

  Widget _buildTopBarOverlay() {
    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 240),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: OzoneTheme.surface.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(24),
                      border: OzoneTheme.hairlineBorder,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _peerDisplayName,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              color: OzoneTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.lock_rounded,
                          color: OzoneTheme.cyan,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              QualityIndicatorWidget(
                state: _callManager.qualityState,
                callManager: _callManager,
                durationText: _formatDuration(_callDurationSeconds),
                onTap: () {
                  _resetAutoHideTimer();
                  showConnectionStatsModal(
                    context,
                    _callManager.qualityState,
                    callManager: _callManager,
                  );
                },
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

    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 240),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: OzoneTheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(34),
          border: OzoneTheme.hairlineBorder,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 6),
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
              onPressed: () {
                _resetAutoHideTimer();
                OzoneHaptics.light();
                _callManager.toggleMute();
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                isCameraOff ? Icons.videocam_off_rounded : Icons.flip_camera_ios_rounded,
                color: isCameraOff ? OzoneTheme.ruby : Colors.white,
                size: 24,
              ),
              tooltip: 'Switch Camera',
              onPressed: () {
                _resetAutoHideTimer();
                OzoneHaptics.light();
                _callManager.switchCamera();
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                _callManager.isSpeakerOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_rounded,
                color: _callManager.isSpeakerOn ? OzoneTheme.cyan : Colors.white,
                size: 24,
              ),
              tooltip: _callManager.isSpeakerOn ? 'Speaker: On' : 'Speaker: Off',
              onPressed: () {
                _resetAutoHideTimer();
                OzoneHaptics.light();
                _callManager.toggleSpeaker();
              },
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
                _resetAutoHideTimer();
                OzoneHaptics.light();
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
              onPressed: _handleEndCall,
              child: const Icon(Icons.call_end_rounded, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    const pipWidth = 114.0;
    const pipHeight = 160.0;
    final defaultOffset = _pipOffset ?? Offset(screenSize.width - pipWidth - 16, 74);
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

        // Determine main vs PiP feeds according to swap state
        final mainRenderer = _isLocalMain ? _callManager.localRenderer : _callManager.remoteRenderer;
        final pipRenderer = _isLocalMain ? _callManager.remoteRenderer : _callManager.localRenderer;
        final isPipLocal = !_isLocalMain;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Cinema Full-Bleed Video Canvas with Pinch-to-Zoom
              if (isConnected && _isInitialized)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _toggleControlsVisibility,
                    onDoubleTap: _swapFeeds,
                    child: RepaintBoundary(
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 4.0,
                        clipBehavior: Clip.none,
                        child: RTCVideoView(
                          mainRenderer,
                          mirror: _isLocalMain,
                          objectFit: _isCover
                              ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                              : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                        ),
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
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: OzoneTheme.surface,
                              border: Border.all(
                                color: OzoneTheme.cyan.withValues(alpha: 0.5),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: OzoneTheme.cyan.withValues(alpha: 0.2),
                                  blurRadius: 28,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _peerDisplayName.isNotEmpty ? _peerDisplayName[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  color: OzoneTheme.cyan,
                                  fontSize: 42,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
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
                                : 'Connecting peer-to-peer (1080p)...',
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

              // Smooth Draggable Local PiP Preview with Double-Tap Swap
              if (_isInitialized)
                Positioned(
                  left: _pipOffset!.dx,
                  top: _pipOffset!.dy,
                  width: pipWidth,
                  height: pipHeight,
                  child: GestureDetector(
                    key: const ValueKey('pip_draggable_1on1'),
                    onTap: _swapFeeds,
                    onDoubleTap: _swapFeeds,
                    onPanUpdate: (details) {
                      setState(() {
                        final newX = (_pipOffset!.dx + details.delta.dx)
                            .clamp(8.0, screenSize.width - pipWidth - 8.0);
                        final newY = (_pipOffset!.dy + details.delta.dy)
                            .clamp(40.0, screenSize.height - pipHeight - 110.0);
                        _pipOffset = Offset(newX, newY);
                      });
                    },
                    onPanEnd: (_) {
                      // Spring snap to nearest edge
                      final midX = screenSize.width / 2;
                      final targetX = (_pipOffset!.dx < midX) ? 14.0 : (screenSize.width - pipWidth - 14.0);
                      setState(() {
                        _pipOffset = Offset(targetX, _pipOffset!.dy);
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: OzoneTheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: OzoneTheme.cyan.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: (isPipLocal && _callManager.isVideoDisabled)
                            ? const Center(
                                child: Icon(
                                  Icons.videocam_off_rounded,
                                  color: Colors.white38,
                                  size: 32,
                                ),
                              )
                            : RepaintBoundary(
                                child: RTCVideoView(
                                  pipRenderer,
                                  mirror: isPipLocal,
                                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),

              if (isConnected) _buildTopBarOverlay(),

              if (!isFailed)
                Positioned(
                  bottom: 34,
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
        color: OzoneTheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(36),
        border: OzoneTheme.hairlineBorder,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
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
            onPressed: () {
              OzoneHaptics.light();
              _callManager.toggleMute();
            },
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
            onPressed: () {
              OzoneHaptics.light();
              _callManager.toggleSpeakerphone();
            },
          ),
          const SizedBox(width: 20),
          FloatingActionButton(
            heroTag: 'endAudioCallBtn',
            backgroundColor: OzoneTheme.ruby,
            foregroundColor: Colors.white,
            elevation: 0,
            mini: true,
            tooltip: 'End Call',
            onPressed: _handleEndCall,
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
                  color: OzoneTheme.surface,
                  border: Border.all(
                    color: OzoneTheme.cyan.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: OzoneTheme.cyan.withValues(alpha: 0.15),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                  ],
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
                backgroundColor: OzoneTheme.surface,
                foregroundColor: Colors.white,
                side: OzoneTheme.hairlineBorderSide,
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
