import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/database/chat_repository.dart';
import '../../models/chat_model.dart';
import '../../design_system/ozone_theme.dart';
import 'connect_by_email_dialog.dart';
import '../conversation/conversation_screen.dart';

class ChatListScreen extends StatelessWidget {
  final ChatRepository chatRepository;

  const ChatListScreen({super.key, required this.chatRepository});

  void _openChat(BuildContext context, ChatModel chat) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          chat: chat,
          chatRepository: chatRepository,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteChat(
    BuildContext context,
    ChatModel chat,
    String currentUserUid,
    String currentUserEmail,
  ) async {
    final otherEmail = chat.otherUserEmail(currentUserEmail);
    final isInvite = chat.isPendingInvite;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: OzoneTheme.surfaceCard,
          title: Text(
            isInvite ? 'Delete Invite?' : 'Remove Conversation?',
            style: const TextStyle(color: OzoneTheme.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: Text(
            isInvite
                ? 'Remove pending invite for $otherEmail? This invite entry will be deleted.'
                : 'Remove chat with $otherEmail from your list? Message history will be retained for the other participant.',
            style: const TextStyle(color: OzoneTheme.textSecondary, fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              key: const Key('cancelDeleteChatBtn'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: OzoneTheme.textSecondary)),
            ),
            TextButton(
              key: const Key('confirmDeleteChatBtn'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                isInvite ? 'Delete' : 'Remove',
                style: const TextStyle(color: OzoneTheme.ruby, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await chatRepository.removeChat(chatId: chat.id, userUid: currentUserUid);
    }
  }

  void _showConnectDialog(BuildContext context) {
    final auth = context.read<OzoneAuthProvider>();
    final currentUser = auth.currentUser;
    if (currentUser == null) return;

    showDialog(
      context: context,
      builder: (_) => ConnectByEmailDialog(
        currentUser: currentUser,
        chatRepository: chatRepository,
        onChatSelected: (chat) => _openChat(context, chat),
      ),
    );
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_rounded, color: OzoneTheme.cyan, size: 22),
            const SizedBox(width: 8),
            Text(
              'OZONE',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<List<ChatModel>>(
        stream: chatRepository.getChatsStream(currentUser.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('[ChatListScreen] Error loading chats: ${snapshot.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: OzoneTheme.ruby, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load chats: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: OzoneTheme.ruby, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data ?? [];

          if (chats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: OzoneTheme.surfaceCard,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: OzoneTheme.cyan.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: OzoneTheme.cyan,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No conversations yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: OzoneTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Connect with someone by entering their email address to start chatting or video calling.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: OzoneTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _showConnectDialog(context),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Connect by Email'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: chats.length,
            separatorBuilder: (_, _) => const Divider(
              color: Colors.white10,
              height: 1,
              indent: 72,
            ),
            itemBuilder: (context, index) {
              final chat = chats[index];
              final otherEmail = chat.otherUserEmail(currentUser.email);
              final isInvite = chat.isPendingInvite;

              return GestureDetector(
                onSecondaryTap: () => _confirmDeleteChat(
                  context,
                  chat,
                  currentUser.uid,
                  currentUser.email,
                ),
                child: ListTile(
                  key: Key('chat_item_${chat.id}'),
                  leading: CircleAvatar(
                    backgroundColor: OzoneTheme.surfaceCard,
                    child: Text(
                      otherEmail.isNotEmpty ? otherEmail[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: isInvite ? OzoneTheme.amber : OzoneTheme.cyan,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    otherEmail,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: OzoneTheme.textPrimary,
                    ),
                  ),
                  subtitle: isInvite
                      ? Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: OzoneTheme.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: OzoneTheme.amber.withValues(alpha: 0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: const Text(
                                'INVITE PENDING',
                                style: TextStyle(
                                  color: OzoneTheme.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Waiting for registration',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: OzoneTheme.textSecondary, fontSize: 12),
                              ),
                            ),
                          ],
                        )
                      : Text(
                          chat.lastMessageText ?? 'Tap to chat or call',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: OzoneTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (chat.lastMessageTimestamp != null && !isInvite)
                        Text(
                          DateFormat.jm().format(chat.lastMessageTimestamp!),
                          style: const TextStyle(
                            color: OzoneTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      if (isInvite)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: OzoneTheme.textSecondary),
                          tooltip: 'Delete Invite',
                          onPressed: () => _confirmDeleteChat(
                            context,
                            chat,
                            currentUser.uid,
                            currentUser.email,
                          ),
                        ),
                    ],
                  ),
                  onTap: () => _openChat(context, chat),
                  onLongPress: () => _confirmDeleteChat(
                    context,
                    chat,
                    currentUser.uid,
                    currentUser.email,
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: OzoneTheme.cyan,
        foregroundColor: Colors.black,
        tooltip: 'Connect by Email',
        onPressed: () => _showConnectDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
