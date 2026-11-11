import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../models/user_model.dart';
import '../../models/call_session.dart';
import '../../core/webrtc/webrtc_call_manager.dart';
import '../../core/webrtc/adaptive_quality_controller.dart';
import '../../design_system/ozone_theme.dart';
import '../../design_system/quality_indicator_widget.dart';

class CallScreen extends StatefulWidget {
  final UserModel caller;
  final UserModel callee;
  final bool isIncoming;
  final CallSession? incomingSession;
  final WebRtcCallManager? callManager;
  final CallType callType;

  const CallScreen({
    super.key,
    required this.caller,
    required this.callee,
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
    // Default to Contain on desktop (macOS/Windows/Linux) and Cover on mobile
    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    _isCover = !isDesktop;

    _callManager = widget.callManager ?? WebRtcCallManager();
    _callManager.addListener(_onCallManagerChanged);
    _initCall();
  }

  void _onCallManagerChanged() {
    if (_callManager.status == CallStatus.connected && !_timerStarted) {
      _timerStarted = true;
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _callDurationSeconds++;
          });
        }
      });
    } else if (_callManager.status != CallStatus.connected && _timerStarted) {
      _durationTimer?.cancel();
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _peerDisplayName {
    final email = widget.isIncoming ? widget.caller.email : widget.callee.email;
    final prefix = email.split('@').first;
    if (prefix.isNotEmpty) {
      return prefix[0].toUpperCase() + prefix.substring(1);
    }
    return email;
  }

  Future<void> _initCall() async {
    await _callManager.loadSavedQualityPreference();
    await _callManager.initializeRenderers();
    if (mounted) {
      setState(() => _isInitialized = true);
    }

    if (widget.isIncoming && widget.incomingSession != null) {
      await _callManager.acceptIncomingCall(session: widget.incomingSession!);
    } else {
      await _callManager.startOutgoingCall(
        caller: widget.caller,
        callee: widget.callee,
        callType: widget.callType,
      );
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _callManager.removeListener(_onCallManagerChanged);
    _callManager.dispose();
    super.dispose();
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
          const SizedBox(width: 14),
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: OzoneTheme.cyan, size: 24),
            tooltip: 'Call Diagnostics',
            onPressed: () => _showDiagnosticsSheet(context),
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
                  boxShadow: [
                    BoxShadow(
                      color: OzoneTheme.cyan.withValues(alpha: 0.15),
                      blurRadius: 32,
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: _callManager.status == CallStatus.connected
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: _callManager.status == CallStatus.connected
                      ? OzoneTheme.emerald
                      : OzoneTheme.textSecondary,
                  letterSpacing: _callManager.status == CallStatus.connected ? 1.0 : 0.0,
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

  Widget _buildFloatingBottomControlBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF13151C).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white12, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Mute Mic
              IconButton(
                icon: Icon(
                  _callManager.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: _callManager.isMuted ? OzoneTheme.ruby : Colors.white,
                  size: 24,
                ),
                tooltip: _callManager.isMuted ? 'Unmute' : 'Mute',
                onPressed: () => _callManager.toggleMute(),
              ),
              const SizedBox(width: 8),

              // 2. Switch/Toggle Camera
              IconButton(
                icon: Icon(
                  _callManager.isVideoDisabled
                      ? Icons.videocam_off_rounded
                      : Icons.flip_camera_ios_rounded,
                  color: _callManager.isVideoDisabled ? OzoneTheme.ruby : Colors.white,
                  size: 24,
                ),
                tooltip: 'Switch Camera',
                onPressed: () => _callManager.switchCamera(),
              ),
              const SizedBox(width: 8),

              // 3. Screen Share
              IconButton(
                icon: Icon(
                  _callManager.isScreenSharing
                      ? Icons.stop_screen_share_rounded
                      : Icons.screen_share_rounded,
                  color: _callManager.isScreenSharing ? OzoneTheme.cyan : Colors.white,
                  size: 24,
                ),
                tooltip: _callManager.isScreenSharing ? 'Stop Screen Share' : 'Share Screen',
                onPressed: () => _callManager.toggleScreenShare(),
              ),
              const SizedBox(width: 8),

              // 4. Quality / Stats Button
              IconButton(
                icon: const Icon(
                  Icons.speed_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                tooltip: 'Connection Stats',
                onPressed: () => showConnectionStatsModal(
                  context,
                  _callManager.qualityState,
                  callManager: _callManager,
                ),
              ),
              const SizedBox(width: 12),

              // 5. Red Hangup Button
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
        ),
      ),
    );
  }

  Widget _buildScreenShareBanner() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        margin: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          color: const Color(0xFF13151C).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: OzoneTheme.cyan.withValues(alpha: 0.3), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: OzoneTheme.cyan.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.screen_share_rounded,
                color: OzoneTheme.cyan,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'You are sharing your screen',
              style: TextStyle(
                color: OzoneTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Other participants see your shared screen in real-time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: OzoneTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: OzoneTheme.ruby,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.stop_screen_share_rounded, size: 20),
              label: const Text(
                'Stop Sharing',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              onPressed: () => _callManager.stopScreenShare(),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildFailureOverlay(String reason) {
    final isPermissionError = reason.toLowerCase().contains('camera or microphone access');
    final isLocalNetDenied = _callManager.isLocalNetworkDenied;
    final isRejected = _callManager.status == CallStatus.rejected ||
        reason.toLowerCase().contains('declined');

    final IconData iconData;
    final String title;
    final String guidanceText;

    if (isRejected) {
      iconData = Icons.call_end_rounded;
      title = 'Call Declined';
      guidanceText = 'The recipient declined the call.';
    } else if (isPermissionError) {
      iconData = Icons.no_photography_rounded;
      title = 'Permissions Required';
      guidanceText =
          'Ozone requires access to your camera and microphone. Please open System Settings > Privacy & Security and enable permissions for Ozone.';
    } else if (isLocalNetDenied) {
      iconData = Icons.wifi_off_rounded;
      title = 'Local Network Permission Denied';
      guidanceText =
          'Direct local WiFi calling requires Local Network access. If this was denied, please enable Local Network access for Ozone in System Settings, or connect via an internet-reachable network.';
    } else {
      iconData = Icons.portable_wifi_off_rounded;
      title = 'Call Failed';
      guidanceText =
          'Could not establish a direct peer-to-peer connection. Verify both devices have an active internet connection.';
    }

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
              child: Icon(
                iconData,
                color: OzoneTheme.ruby,
                size: 42,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
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
            const SizedBox(height: 12),
            Text(
              guidanceText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white54,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OzoneTheme.cyan,
                    side: const BorderSide(color: OzoneTheme.cyan),
                  ),
                  icon: const Icon(Icons.analytics_outlined, size: 18),
                  label: const Text('Diagnostics'),
                  onPressed: () => _showDiagnosticsSheet(context),
                ),
                const SizedBox(width: 16),
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
          ],
        ),
      ),
    );
  }

  void _showDiagnosticsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: OzoneTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.analytics_outlined, color: OzoneTheme.cyan, size: 22),
                        const SizedBox(width: 10),
                        const Text(
                          'Call Diagnostics & ICE Pipeline',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: OzoneTheme.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12),
                    _buildDiagRow('Call Status', _callManager.status.name.toUpperCase()),
                    _buildDiagRow('Role', _callManager.isCaller ? 'Caller' : 'Callee'),
                    _buildDiagRow(
                      'Local Network Status',
                      _callManager.isLocalNetworkDenied ? 'Denied / No Host Candidate' : 'Allowed / Active',
                      color: _callManager.isLocalNetworkDenied ? OzoneTheme.ruby : OzoneTheme.emerald,
                    ),
                    _buildDiagRow(
                      'Gathered Candidates',
                      _callManager.gatheredCandidateTypes.isEmpty
                          ? 'None'
                          : _callManager.gatheredCandidateTypes.join(', '),
                    ),
                    _buildDiagRow(
                      'Connected ICE Pair',
                      _callManager.connectedPair ?? 'None / Negotiating',
                      color: _callManager.connectedPair != null ? OzoneTheme.emerald : Colors.white70,
                    ),
                    _buildDiagRow('Remote Description Set', _callManager.isRemoteDescriptionSet ? 'Yes' : 'No'),
                    const SizedBox(height: 16),
                    const Text(
                      'Event Timeline & Signaling Log',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: OzoneTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: _callManager.sessionLogs.isEmpty
                          ? const Text(
                              'No logs recorded yet.',
                              style: TextStyle(color: Colors.white38, fontSize: 12),
                            )
                          : SelectableText(
                              _callManager.sessionLogs.join('\n'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Colors.white70,
                                height: 1.4,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDiagRow(String label, String value, {Color color = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(color: OzoneTheme.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final otherEmail = widget.isIncoming ? widget.caller.email : widget.callee.email;
    final screenSize = MediaQuery.of(context).size;
    const pipWidth = 110.0;
    const pipHeight = 155.0;
    _pipOffset ??= Offset(screenSize.width - pipWidth - 16, 68);

    return ListenableBuilder(
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
                _buildAudioCallView(otherEmail),
                if (isFailed)
                  Positioned.fill(
                    child: _buildFailureOverlay(
                      _callManager.failureReason ??
                          "Could not establish a direct peer-to-peer connection. Verify both devices have an active internet connection.",
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
              // 1. Full-screen remote video (double-tap to toggle Cover/Contain)
              if (isConnected && _isInitialized)
                Positioned.fill(
                  child: _callManager.isScreenSharing
                      ? _buildScreenShareBanner()
                      : GestureDetector(
                          onDoubleTap: () {
                            setState(() {
                              _isCover = !_isCover;
                            });
                          },
                          child: RTCVideoView(
                            _callManager.remoteRenderer,
                            objectFit: _isCover
                                ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                                : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                          ),
                        ),
                )
              else
                // Ringing / Connecting placeholder
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
                              otherEmail.isNotEmpty ? otherEmail[0].toUpperCase() : '?',
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
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: OzoneTheme.cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 2. Draggable Floating PiP Card (mirrored local camera view)
              if (_isInitialized)
                Positioned(
                  left: _pipOffset!.dx,
                  top: _pipOffset!.dy,
                  width: pipWidth,
                  height: pipHeight,
                  child: GestureDetector(
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
                            : RTCVideoView(
                                _callManager.localRenderer,
                                mirror: true,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                              ),
                      ),
                    ),
                  ),
                ),

              // 3. Top Center Overlay (Display Name + Lock Icon + Live Call Duration MM:SS)
              if (isConnected) _buildTopCenterOverlay(),

              // 4. Top Right Overlay (Sleek Green Signal-Bar Quality Indicator)
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

              // 5. Bottom Floating Pill Control Bar (Mute, Camera, Screen Share, Quality/Stats, Hangup)
              if (!isFailed)
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildFloatingBottomControlBar()),
                ),

              // 6. Connection Failure Overlay
              if (isFailed)
                Positioned.fill(
                  child: _buildFailureOverlay(
                    _callManager.failureReason ??
                        "Could not establish a direct peer-to-peer connection. Verify both devices have an active internet connection.",
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
