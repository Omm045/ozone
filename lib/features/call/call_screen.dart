import 'dart:async';
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
  Offset? _pipOffset;
  Timer? _durationTimer;
  int _callDurationSeconds = 0;
  bool _timerStarted = false;

  @override
  void initState() {
    super.initState();
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
          // Mute Microphone
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

          // Speakerphone Toggle
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

          // Diagnostics Inspector
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: OzoneTheme.cyan, size: 24),
            tooltip: 'Call Diagnostics',
            onPressed: () => _showDiagnosticsSheet(context),
          ),
          const SizedBox(width: 20),

          // End Call Button
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

  Widget _buildControlButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mute Button
          IconButton(
            icon: Icon(
              _callManager.isMuted ? Icons.mic_off : Icons.mic,
              color: _callManager.isMuted ? OzoneTheme.ruby : Colors.white,
            ),
            tooltip: _callManager.isMuted ? 'Unmute' : 'Mute',
            onPressed: () => _callManager.toggleMute(),
          ),
          const SizedBox(width: 8),

          // Camera Switch
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            tooltip: 'Switch Camera',
            onPressed: () => _callManager.switchCamera(),
          ),
          const SizedBox(width: 8),

          // Toggle Video
          IconButton(
            icon: Icon(
              _callManager.isVideoDisabled
                  ? Icons.videocam_off
                  : Icons.videocam,
              color: _callManager.isVideoDisabled
                  ? OzoneTheme.ruby
                  : Colors.white,
            ),
            tooltip: _callManager.isVideoDisabled ? 'Turn Camera On' : 'Turn Camera Off',
            onPressed: () => _callManager.toggleVideo(),
          ),
          const SizedBox(width: 8),

          // Quality Selector
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Colors.white),
            tooltip: 'Video Quality',
            onPressed: () => _showQualitySelectorSheet(context),
          ),
          const SizedBox(width: 8),

          // Diagnostics Inspector
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: OzoneTheme.cyan),
            tooltip: 'Call Diagnostics',
            onPressed: () => _showDiagnosticsSheet(context),
          ),
          const SizedBox(width: 14),

          // End Call Button
          FloatingActionButton(
            heroTag: 'endCallBtn',
            backgroundColor: OzoneTheme.ruby,
            foregroundColor: Colors.white,
            elevation: 0,
            mini: true,
            tooltip: 'End Call',
            onPressed: () async {
              await _callManager.endCall();
              if (mounted) Navigator.of(context).pop();
            },
            child: const Icon(Icons.call_end),
          ),
        ],
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
                    _buildDiagRow('Remote Description Set', _callManager.hasRemoteDescription ? 'Yes' : 'No'),
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
    const pipHeight = 160.0;
    _pipOffset ??= Offset(screenSize.width - pipWidth - 16, 50);

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
              // 1. Remote Video (Primary Full Screen View)
              if (isConnected && _isInitialized)
                Positioned.fill(
                  child: RTCVideoView(
                    _callManager.remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                )
              else
                // Connecting / Ringing Placeholder
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
                            otherEmail,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: OzoneTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _callManager.status == CallStatus.ringing
                                ? 'Ringing... (Baseline 1080p 30fps)'
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

              // 2. Local Video (Small Draggable Picture-in-Picture Box)
              if (_isInitialized && !_callManager.isVideoDisabled)
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: OzoneTheme.cyan.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.black54,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: RTCVideoView(
                          _callManager.localRenderer,
                          mirror: true,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  ),
                ),

              // 3. Live On-Screen Quality Indicator (Top Left)
              if (isConnected)
                Positioned(
                  top: 50,
                  left: 16,
                  child: GestureDetector(
                    onTap: () => _showQualitySelectorSheet(context),
                    child: QualityIndicatorWidget(state: _callManager.qualityState),
                  ),
                ),

              // 4. In-Call Bottom Controls
              if (!isFailed)
                Positioned(
                  bottom: 36,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildControlButtons()),
                ),

              // 5. Connection Failure Overlay
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

  void _showQualitySelectorSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: OzoneTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final currentManualTier = _callManager.qualityController.manualTier;
        final isAuto = _callManager.qualityController.isAuto;

        Widget buildOption({
          required String title,
          required String subtitle,
          required bool isSelected,
          required VoidCallback onTap,
        }) {
          return ListTile(
            title: Text(
              title,
              style: TextStyle(
                color: isSelected ? OzoneTheme.cyan : OzoneTheme.textPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(
                color: OzoneTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            trailing: isSelected
                ? const Icon(Icons.check_circle_rounded, color: OzoneTheme.cyan)
                : const Icon(Icons.circle_outlined, color: Colors.white24),
            onTap: () {
              Navigator.of(ctx).pop();
              onTap();
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, color: OzoneTheme.cyan, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Video Quality',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: OzoneTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12),
                buildOption(
                  title: 'Auto (recommended)',
                  subtitle: 'Adapts automatically based on network bandwidth',
                  isSelected: isAuto,
                  onTap: () => _callManager.setQualityPreference(null),
                ),
                buildOption(
                  title: '1080p',
                  subtitle: 'Full HD • 30 fps (3.5 Mbps)',
                  isSelected: !isAuto && currentManualTier == ResolutionTier.p1080,
                  onTap: () => _callManager.setQualityPreference(ResolutionTier.p1080),
                ),
                buildOption(
                  title: '1440p',
                  subtitle: 'Quad HD • 30 fps (7.0 Mbps)',
                  isSelected: !isAuto && currentManualTier == ResolutionTier.p1440,
                  onTap: () => _callManager.setQualityPreference(ResolutionTier.p1440),
                ),
                buildOption(
                  title: '4K',
                  subtitle: 'Ultra HD • 30 fps (15.0 Mbps)',
                  isSelected: !isAuto && currentManualTier == ResolutionTier.p4k,
                  onTap: () => _callManager.setQualityPreference(ResolutionTier.p4k),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
