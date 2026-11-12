import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/database/chat_repository.dart';
import '../../models/call_session.dart';
import '../../models/user_model.dart';
import '../../design_system/ozone_theme.dart';
import '../../core/webrtc/webrtc_call_manager.dart';
import 'call_screen.dart';
import '../../main.dart';

class IncomingCallOverlayManager extends StatefulWidget {
  final Widget child;

  const IncomingCallOverlayManager({super.key, required this.child});

  @override
  State<IncomingCallOverlayManager> createState() =>
      _IncomingCallOverlayManagerState();
}

class _IncomingCallOverlayManagerState
    extends State<IncomingCallOverlayManager> {
  StreamSubscription<CallSession?>? _callSub;
  String? _subscribedUid;
  CallSession? _currentIncomingCall;
  bool _isHandlingAction = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<OzoneAuthProvider>();
    final chatRepository = context.read<ChatRepository>();
    final user = auth.currentUser;

    if (auth.status != AuthStatus.authenticated || user == null) {
      _callSub?.cancel();
      _callSub = null;
      _subscribedUid = null;
      if (_currentIncomingCall != null) {
        setState(() => _currentIncomingCall = null);
      }
    } else if (_subscribedUid != user.uid) {
      _callSub?.cancel();
      _subscribedUid = user.uid;
      _callSub = chatRepository.getIncomingCallsStream(user.uid).listen((session) {
        if (mounted) {
          // Ignore any stale incoming call document older than 45 seconds to prevent crash loops
          if (session != null &&
              DateTime.now().difference(session.createdAt).inSeconds > 45) {
            if (_currentIncomingCall != null) {
              setState(() => _currentIncomingCall = null);
            }
            return;
          }
          setState(() {
            _currentIncomingCall = session;
          });
        }
      });
    }
  }

  Future<void> _acceptCall(CallSession session, UserModel currentUser) async {
    if (_isHandlingAction) return;
    _isHandlingAction = true;

    final callerUser = UserModel(
      uid: session.callerUid,
      email: session.callerEmail,
      createdAt: session.createdAt,
    );

    // Immediately dismiss the overlay UI to prevent duplicate accept events
    setState(() => _currentIncomingCall = null);

    try {
      // Delay Navigator.push until initializeRenderers() has completed
      final callManager = context.read<WebRtcCallManager>();
      await callManager.initializeRenderers();

      await OzoneApp.navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            caller: callerUser,
            callee: currentUser,
            isIncoming: true,
            incomingSession: session,
            callType: session.callType,
          ),
        ),
      );
    } finally {
      _isHandlingAction = false;
    }
  }

  Future<void> _declineCall(CallSession session) async {
    if (_isHandlingAction) return;
    _isHandlingAction = true;

    final chatRepository = context.read<ChatRepository>();
    setState(() => _currentIncomingCall = null);
    try {
      await chatRepository.declineCall(session.id);
    } finally {
      _isHandlingAction = false;
    }
  }

  @override
  void dispose() {
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<OzoneAuthProvider>();
    final currentUser = auth.currentUser;

    return Stack(
      children: [
        widget.child,
        if (_currentIncomingCall != null && currentUser != null)
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: IncomingCallView(
                session: _currentIncomingCall!,
                onAccept: () => _acceptCall(_currentIncomingCall!, currentUser),
                onDecline: () => _declineCall(_currentIncomingCall!),
              ),
            ),
          ),
      ],
    );
  }
}

class IncomingCallView extends StatelessWidget {
  final CallSession session;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallView({
    super.key,
    required this.session,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final callerEmail = session.callerEmail;
    final initial = callerEmail.isNotEmpty ? callerEmail[0].toUpperCase() : '?';

    return Container(
      color: Colors.black.withValues(alpha: 0.94),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Header Label
            Padding(
              padding: const EdgeInsets.only(top: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    session.isAudioOnly ? Icons.phone_in_talk_rounded : Icons.videocam_rounded,
                    color: OzoneTheme.cyan,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    session.isAudioOnly ? 'INCOMING AUDIO CALL' : 'INCOMING VIDEO CALL',
                    style: const TextStyle(
                      color: OzoneTheme.cyan,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
            ),

            // Middle: Avatar & Caller Info
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OzoneTheme.surfaceCard,
                    border: Border.all(
                      color: OzoneTheme.cyan.withValues(alpha: 0.5),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: OzoneTheme.cyan.withValues(alpha: 0.2),
                        blurRadius: 28,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: OzoneTheme.cyan,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  callerEmail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: OzoneTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  session.isAudioOnly
                      ? 'Ozone Voice Call • Ringing...'
                      : 'Ozone HD Video Call • Ringing...',
                  style: const TextStyle(
                    fontSize: 14,
                    color: OzoneTheme.textSecondary,
                  ),
                ),
              ],
            ),

            // Bottom: Accept & Decline Actions
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline Button
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        key: const Key('declineCallBtn'),
                        heroTag: 'declineCallBtn',
                        backgroundColor: OzoneTheme.ruby,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        onPressed: onDecline,
                        child: const Icon(Icons.call_end_rounded, size: 30),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Decline',
                        style: TextStyle(
                          color: OzoneTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  // Accept Button
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        key: const Key('acceptCallBtn'),
                        heroTag: 'acceptCallBtn',
                        backgroundColor: OzoneTheme.emerald,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        onPressed: onAccept,
                        child: Icon(
                          session.isAudioOnly ? Icons.phone_rounded : Icons.videocam_rounded,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Accept',
                        style: TextStyle(
                          color: OzoneTheme.emerald,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
