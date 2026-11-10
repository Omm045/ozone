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
              final isInvite = chat.participantUids.contains('pending_invite');

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: OzoneTheme.surfaceCard,
                  child: Text(
                    otherEmail.isNotEmpty ? otherEmail[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: OzoneTheme.cyan,
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
                subtitle: Text(
                  isInvite
                      ? 'Invite pending (unregistered email)'
                      : (chat.lastMessageText ?? 'Tap to chat or call'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isInvite
                        ? OzoneTheme.amber
                        : OzoneTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                trailing: chat.lastMessageTimestamp != null
                    ? Text(
                        DateFormat.jm().format(chat.lastMessageTimestamp!),
                        style: const TextStyle(
                          color: OzoneTheme.textSecondary,
                          fontSize: 12,
                        ),
                      )
                    : null,
                onTap: () => _openChat(context, chat),
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
