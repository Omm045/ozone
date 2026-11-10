import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../models/chat_model.dart';
import '../../core/database/chat_repository.dart';
import '../../design_system/ozone_theme.dart';

class ConnectByEmailDialog extends StatefulWidget {
  final UserModel currentUser;
  final ChatRepository chatRepository;
  final void Function(ChatModel chat) onChatSelected;

  const ConnectByEmailDialog({
    super.key,
    required this.currentUser,
    required this.chatRepository,
    required this.onChatSelected,
  });

  @override
  State<ConnectByEmailDialog> createState() => _ConnectByEmailDialogState();
}

class _ConnectByEmailDialogState extends State<ConnectByEmailDialog> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    if (email.toLowerCase() == widget.currentUser.email.toLowerCase()) {
      setState(() {
        _errorMessage = 'You cannot connect with your own email.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final targetUser = await widget.chatRepository.lookupUserByEmail(email);

      if (targetUser != null) {
        // User is registered -> get or create chat thread
        final chat = await widget.chatRepository.getOrCreateChat(
          targetUser,
          widget.currentUser,
        );
        if (mounted) {
          Navigator.of(context).pop();
          widget.onChatSelected(chat);
        }
      } else {
        // User is not yet registered -> create invite thread
        final inviteChat = await widget.chatRepository.createInviteChat(
          email,
          widget.currentUser,
        );
        if (mounted) {
          Navigator.of(context).pop();
          widget.onChatSelected(inviteChat);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OzoneTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.person_add_alt_1, color: OzoneTheme.cyan),
          SizedBox(width: 10),
          Text(
            'Connect by Email',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: OzoneTheme.textPrimary,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Enter the email address of the person you want to chat or call with:',
            style: TextStyle(
              fontSize: 13,
              color: OzoneTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'user@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            onSubmitted: (_) => _handleConnect(),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(color: OzoneTheme.ruby, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: OzoneTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleConnect,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }
}
