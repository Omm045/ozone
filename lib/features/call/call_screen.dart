import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../models/user_model.dart';
import '../../models/call_session.dart';
import '../../core/webrtc/webrtc_call_manager.dart';
import '../../design_system/ozone_theme.dart';
import '../../design_system/quality_indicator_widget.dart';

class CallScreen extends StatefulWidget {
  final UserModel caller;
  final UserModel callee;
  final bool isIncoming;
  final CallSession? incomingSession;

  const CallScreen({
    super.key,
    required this.caller,
    required this.callee,
    this.isIncoming = false,
    this.incomingSession,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final WebRtcCallManager _callManager;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _callManager = WebRtcCallManager();
    _initCall();
  }

  Future<void> _initCall() async {
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
      );
    }
  }

  @override
  void dispose() {
    _callManager.dispose();
    super.dispose();
  }

  Widget _buildControlButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
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
          const SizedBox(width: 14),

          // Camera Switch
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            tooltip: 'Switch Camera',
            onPressed: () => _callManager.switchCamera(),
          ),
          const SizedBox(width: 14),

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
          const SizedBox(width: 20),

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
    return Container(
      color: Colors.black.withValues(alpha: 0.9),
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
                Icons.portable_wifi_off_rounded,
                color: OzoneTheme.ruby,
                size: 44,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Call Failed',
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
            const SizedBox(height: 8),
            const Text(
              '(v1 operates in STUN-only P2P mode. Direct connection could not be established behind symmetric NAT/firewall).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white38,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: OzoneTheme.surfaceCard),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final otherEmail = widget.isIncoming ? widget.caller.email : widget.callee.email;

    return ListenableBuilder(
      listenable: _callManager,
      builder: (context, _) {
        final isConnected = _callManager.status == CallStatus.connected;
        final isFailed = _callManager.status == CallStatus.failed;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // 1. Remote Video (Full Screen)
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
                                : 'Connecting direct peer-to-peer...',
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

              // 2. Local Video (Picture-in-Picture)
              if (_isInitialized && !_callManager.isVideoDisabled)
                Positioned(
                  top: 50,
                  right: 16,
                  width: 110,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24, width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.black54,
                      ),
                      child: RTCVideoView(
                        _callManager.localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),

              // 3. Live On-Screen Quality Indicator (Top Left)
              if (isConnected)
                Positioned(
                  top: 50,
                  left: 16,
                  child: QualityIndicatorWidget(state: _callManager.qualityState),
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
                        "Couldn't connect — this may be due to one of your networks.",
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
