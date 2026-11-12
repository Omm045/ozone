import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/database/chat_repository.dart';
import '../../models/chat_model.dart';
import '../../models/chat_message.dart';
import '../../models/user_model.dart';
import '../../models/call_session.dart';
import '../../design_system/ozone_theme.dart';
import '../call/call_screen.dart';

class ConversationScreen extends StatefulWidget {
  final ChatModel chat;
  final ChatRepository chatRepository;
  final bool isEmbedded;

  const ConversationScreen({
    super.key,
    required this.chat,
    required this.chatRepository,
    this.isEmbedded = false,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final auth = context.read<OzoneAuthProvider>();
    final currentUser = auth.currentUser;
    if (currentUser == null) return;

    OzoneHaptics.light();
    _messageController.clear();
    await widget.chatRepository.sendMessage(
      chatId: widget.chat.id,
      text: text,
      currentUser: currentUser,
    );

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _confirmDeleteMessage(BuildContext context, ChatMessage message) async {
    OzoneHaptics.medium();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: OzoneTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: OzoneTheme.hairlineBorderSide,
          ),
          title: const Text(
            'Delete message?',
            style: TextStyle(color: OzoneTheme.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'This message will be deleted for everyone in this chat.',
            style: TextStyle(color: OzoneTheme.textSecondary, fontSize: 14),
          ),
          actions: [
            TextButton(
              key: const Key('cancelDeleteMessageBtn'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: OzoneTheme.textSecondary)),
            ),
            TextButton(
              key: const Key('confirmDeleteMessageBtn'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Delete',
                style: TextStyle(color: OzoneTheme.ruby, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await widget.chatRepository.deleteMessage(
        chatId: widget.chat.id,
        messageId: message.id,
      );
    }
  }

  void _startCall(
    UserModel currentUser,
    String targetEmail, {
    CallType callType = CallType.video,
  }) async {
    OzoneHaptics.medium();
    var targetUser = await widget.chatRepository.lookupUserByEmail(targetEmail);

    if (targetUser == null) {
      final otherUid = widget.chat.otherUserUid(currentUser.uid);
      if (otherUid.isNotEmpty) {
        targetUser = UserModel(
          uid: otherUid,
          email: targetEmail,
          createdAt: DateTime.now(),
        );
      }
    }

    if (!mounted) return;

    if (targetUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$targetEmail is not yet registered to receive calls.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          caller: currentUser,
          callee: targetUser!,
          isIncoming: false,
          callType: callType,
        ),
      ),
    );
  }

  Widget _buildReceiptIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time_rounded, size: 12, color: Colors.white38);
      case MessageStatus.sent:
        return const Icon(Icons.check_rounded, size: 12, color: Colors.white54);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all_rounded, size: 13, color: Colors.white70);
      case MessageStatus.read:
        return const Icon(Icons.done_all_rounded, size: 13, color: OzoneTheme.cyan);
    }
  }

  Widget _buildTopStageBar(UserModel currentUser, String otherEmail) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: OzoneTheme.surface,
        border: Border(bottom: OzoneTheme.hairlineBorderSide),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: OzoneTheme.background,
              border: Border.all(color: OzoneTheme.cyan.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Center(
              child: Text(
                otherEmail.isNotEmpty ? otherEmail[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: OzoneTheme.cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  otherEmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: OzoneTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: OzoneTheme.emerald,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Direct P2P Ready • 1080p HD',
                      style: TextStyle(
                        fontSize: 11,
                        color: OzoneTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone_rounded, color: OzoneTheme.cyan, size: 22),
            tooltip: 'Start Audio Call',
            onPressed: () => _startCall(currentUser, otherEmail, callType: CallType.audio),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: OzoneTheme.cyan, size: 26),
            tooltip: 'Start Video Call (1080p HD)',
            onPressed: () => _startCall(currentUser, otherEmail, callType: CallType.video),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<OzoneAuthProvider>();
    final currentUser = auth.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: OzoneTheme.cyan)),
      );
    }

    final otherEmail = widget.chat.otherUserEmail(currentUser.email);

    final chatBody = Column(
      children: [
        if (widget.isEmbedded) _buildTopStageBar(currentUser, otherEmail),

        // Message Thread Stream
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: StreamBuilder<List<ChatMessage>>(
                stream: widget.chatRepository.getMessagesStream(widget.chat.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: OzoneTheme.cyan),
                    );
                  }

                  final messages = snapshot.data ?? [];

                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: OzoneTheme.surface,
                              border: Border.all(
                                color: OzoneTheme.cyan.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: OzoneTheme.cyan,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Say hello to $otherEmail',
                            style: const TextStyle(
                              color: OzoneTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Direct peer-to-peer encrypted messages and HD calls',
                            style: TextStyle(
                              color: OzoneTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg.senderUid == currentUser.uid;

                      if (!isMe && msg.status != MessageStatus.read) {
                        widget.chatRepository.markRead(widget.chat.id, msg.id);
                      }

                      if (msg.isDeleted) {
                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            key: Key('deleted_msg_${msg.id}'),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: OzoneTheme.hairlineBorder,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.block_flipped, size: 13, color: Colors.white38),
                                const SizedBox(width: 6),
                                const Text(
                                  'Message deleted',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat.jm().format(msg.timestamp),
                                  style: const TextStyle(
                                    color: Colors.white24,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: isMe ? () => _confirmDeleteMessage(context, msg) : null,
                          onSecondaryTap: isMe ? () => _confirmDeleteMessage(context, msg) : null,
                          child: Container(
                            key: Key('msg_${msg.id}'),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? OzoneTheme.cyan.withValues(alpha: 0.16)
                                  : OzoneTheme.surface,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(isMe ? 18 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 18),
                              ),
                              border: Border.all(
                                color: isMe
                                    ? OzoneTheme.cyan.withValues(alpha: 0.4)
                                    : OzoneTheme.hairlineColor,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.text,
                                  style: const TextStyle(
                                    color: OzoneTheme.textPrimary,
                                    fontSize: 15,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      DateFormat.jm().format(msg.timestamp),
                                      style: TextStyle(
                                        color: isMe
                                            ? OzoneTheme.cyan.withValues(alpha: 0.8)
                                            : OzoneTheme.textSecondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 4),
                                      _buildReceiptIcon(msg.status),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),

        // Message Input Bar
        Container(
          decoration: const BoxDecoration(
            color: OzoneTheme.surface,
            border: Border(top: OzoneTheme.hairlineBorderSide),
          ),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(color: OzoneTheme.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: const TextStyle(color: OzoneTheme.textSecondary, fontSize: 14),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            filled: true,
                            fillColor: OzoneTheme.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: OzoneTheme.hairlineBorderSide,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: OzoneTheme.hairlineBorderSide,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(color: OzoneTheme.cyan, width: 1.5),
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: OzoneTheme.cyan,
                          boxShadow: [
                            BoxShadow(
                              color: OzoneTheme.cyan.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                          tooltip: 'Send',
                          onPressed: _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.isEmbedded) {
      return Container(
        color: OzoneTheme.background,
        child: chatBody,
      );
    }

    return Scaffold(
      backgroundColor: OzoneTheme.background,
      appBar: AppBar(
        title: Text(
          otherEmail,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_rounded, color: OzoneTheme.cyan, size: 22),
            tooltip: 'Start Audio Call',
            onPressed: () => _startCall(currentUser, otherEmail, callType: CallType.audio),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: OzoneTheme.cyan, size: 26),
            tooltip: 'Start Video Call',
            onPressed: () => _startCall(currentUser, otherEmail, callType: CallType.video),
          ),
        ],
      ),
      body: chatBody,
    );
  }
}
