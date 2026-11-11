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

  const ConversationScreen({
    super.key,
    required this.chat,
    required this.chatRepository,
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
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: OzoneTheme.surfaceCard,
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
    // 1. Try email lookup
    var targetUser = await widget.chatRepository.lookupUserByEmail(targetEmail);

    // 2. Fall back to existing chat's known participant UID if user profile document lookup was delayed
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
        return const Icon(Icons.access_time, size: 12, color: Colors.white38);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 12, color: Colors.white54);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 13, color: Colors.white70);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 13, color: OzoneTheme.cyan);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<OzoneAuthProvider>();
    final currentUser = auth.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final otherEmail = widget.chat.otherUserEmail(currentUser.email);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          otherEmail,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_rounded, color: OzoneTheme.cyan, size: 22),
            tooltip: 'Start Audio Call',
            onPressed: () => _startCall(currentUser, otherEmail, callType: CallType.audio),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: OzoneTheme.cyan, size: 26),
            tooltip: 'Start Video Call (1080p -> 4K)',
            onPressed: () => _startCall(currentUser, otherEmail, callType: CallType.video),
          ),
        ],
      ),
      body: Column(
        children: [
          // Message Thread Stream
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: widget.chatRepository.getMessagesStream(widget.chat.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline,
                          color: OzoneTheme.textSecondary,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Say hello to $otherEmail',
                          style: const TextStyle(color: OzoneTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderUid == currentUser.uid;

                    // Automatically mark incoming messages as read
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
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12, width: 0.8),
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
                            horizontal: 14,
                            vertical: 10,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? OzoneTheme.cyan.withValues(alpha: 0.2)
                                : OzoneTheme.surfaceCard,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isMe ? 16 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 16),
                            ),
                            border: Border.all(
                              color: isMe
                                  ? OzoneTheme.cyan.withValues(alpha: 0.5)
                                  : Colors.white10,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                msg.text,
                                style: const TextStyle(
                                  color: OzoneTheme.textPrimary,
                                  fontSize: 15,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    DateFormat.jm().format(msg.timestamp),
                                    style: const TextStyle(
                                      color: OzoneTheme.textSecondary,
                                      fontSize: 10,
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

          // Message Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: OzoneTheme.surface,
              border: Border(top: BorderSide(color: Colors.white10, width: 1)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: OzoneTheme.cyan),
                    tooltip: 'Send',
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
