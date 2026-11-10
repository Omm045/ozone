import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../models/chat_model.dart';
import '../../models/chat_message.dart';

abstract class ChatRepository {
  Future<UserModel?> lookupUserByEmail(String email);
  Future<ChatModel> getOrCreateChat(UserModel targetUser, UserModel currentUser);
  Future<ChatModel> createInviteChat(String email, UserModel currentUser);
  Stream<List<ChatModel>> getChatsStream(String userUid);
  Stream<List<ChatMessage>> getMessagesStream(String chatId);
  Future<ChatMessage> sendMessage({
    required String chatId,
    required String text,
    required UserModel currentUser,
  });
  Future<void> markDelivered(String chatId, String messageId);
  Future<void> markRead(String chatId, String messageId);
}

class FirestoreChatRepository implements ChatRepository {
  final FirebaseFirestore _firestore;

  FirestoreChatRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<UserModel?> lookupUserByEmail(String email) async {
    final normalized = email.toLowerCase().trim();
    final query = await _firestore
        .collection('users')
        .where('email', isEqualTo: normalized)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    return UserModel.fromMap(doc.data(), doc.id);
  }

  @override
  Future<ChatModel> getOrCreateChat(
    UserModel targetUser,
    UserModel currentUser,
  ) async {
    if (targetUser.uid == currentUser.uid) {
      throw Exception('Cannot start a chat with yourself');
    }

    final chatId = ChatModel.deterministicChatId(currentUser.uid, targetUser.uid);
    final chatDoc = _firestore.collection('chats').doc(chatId);
    final snapshot = await chatDoc.get();

    if (snapshot.exists && snapshot.data() != null) {
      return ChatModel.fromMap(snapshot.data()!, snapshot.id);
    }

    final newChat = ChatModel(
      id: chatId,
      participantUids: [currentUser.uid, targetUser.uid],
      participantEmails: [currentUser.email, targetUser.email],
      updatedAt: DateTime.now(),
    );

    await chatDoc.set(newChat.toMap());
    return newChat;
  }

  @override
  Future<ChatModel> createInviteChat(String email, UserModel currentUser) async {
    final normalized = email.toLowerCase().trim();
    if (normalized == currentUser.email.toLowerCase().trim()) {
      throw Exception('Cannot invite your own email');
    }

    final sanitized = normalized.replaceAll('@', '_').replaceAll('.', '_');
    final chatId = 'invite_${currentUser.uid}_$sanitized';
    final chatDoc = _firestore.collection('chats').doc(chatId);
    final snapshot = await chatDoc.get();

    if (snapshot.exists && snapshot.data() != null) {
      return ChatModel.fromMap(snapshot.data()!, snapshot.id);
    }

    final inviteChat = ChatModel(
      id: chatId,
      participantUids: [currentUser.uid, 'pending_invite'],
      participantEmails: [currentUser.email, normalized],
      updatedAt: DateTime.now(),
    );

    await chatDoc.set(inviteChat.toMap());
    return inviteChat;
  }

  @override
  Stream<List<ChatModel>> getChatsStream(String userUid) {
    return _firestore
        .collection('chats')
        .where('participantUids', arrayContains: userUid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatMessage.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  @override
  Future<ChatMessage> sendMessage({
    required String chatId,
    required String text,
    required UserModel currentUser,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw Exception('Message cannot be empty');
    }

    final messageRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc();

    final message = ChatMessage(
      id: messageRef.id,
      chatId: chatId,
      senderUid: currentUser.uid,
      senderEmail: currentUser.email,
      text: trimmed,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toMap());
    batch.update(_firestore.collection('chats').doc(chatId), {
      'lastMessageText': trimmed,
      'lastMessageTimestamp': message.timestamp.toIso8601String(),
      'updatedAt': message.timestamp.toIso8601String(),
    });

    await batch.commit();
    return message;
  }

  @override
  Future<void> markDelivered(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'status': MessageStatus.delivered.name});
  }

  @override
  Future<void> markRead(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'status': MessageStatus.read.name});
  }
}

class MockChatRepository implements ChatRepository {
  final Map<String, UserModel> _users = {};
  final Map<String, ChatModel> _chats = {};
  final Map<String, List<ChatMessage>> _messages = {};
  final _chatsController = StreamController<List<ChatModel>>.broadcast();
  final Map<String, StreamController<List<ChatMessage>>> _messageControllers = {};

  MockChatRepository({List<UserModel>? initialUsers}) {
    if (initialUsers != null) {
      for (final u in initialUsers) {
        _users[u.email.toLowerCase().trim()] = u;
      }
    }
  }

  void registerUser(UserModel user) {
    _users[user.email.toLowerCase().trim()] = user;
  }

  @override
  Future<UserModel?> lookupUserByEmail(String email) async {
    final normalized = email.toLowerCase().trim();
    return _users[normalized];
  }

  @override
  Future<ChatModel> getOrCreateChat(UserModel targetUser, UserModel currentUser) async {
    if (targetUser.uid == currentUser.uid) {
      throw Exception('Cannot start a chat with yourself');
    }

    final chatId = ChatModel.deterministicChatId(currentUser.uid, targetUser.uid);
    if (_chats.containsKey(chatId)) {
      return _chats[chatId]!;
    }

    final chat = ChatModel(
      id: chatId,
      participantUids: [currentUser.uid, targetUser.uid],
      participantEmails: [currentUser.email, targetUser.email],
      updatedAt: DateTime.now(),
    );
    _chats[chatId] = chat;
    _messages[chatId] = [];
    _emitChats(currentUser.uid);
    return chat;
  }

  @override
  Future<ChatModel> createInviteChat(String email, UserModel currentUser) async {
    final normalized = email.toLowerCase().trim();
    if (normalized == currentUser.email.toLowerCase().trim()) {
      throw Exception('Cannot invite your own email');
    }

    final sanitized = normalized.replaceAll('@', '_').replaceAll('.', '_');
    final chatId = 'invite_${currentUser.uid}_$sanitized';
    if (_chats.containsKey(chatId)) {
      return _chats[chatId]!;
    }

    final invite = ChatModel(
      id: chatId,
      participantUids: [currentUser.uid, 'pending_invite'],
      participantEmails: [currentUser.email, normalized],
      updatedAt: DateTime.now(),
    );
    _chats[chatId] = invite;
    _messages[chatId] = [];
    _emitChats(currentUser.uid);
    return invite;
  }

  @override
  Stream<List<ChatModel>> getChatsStream(String userUid) async* {
    final initial = _chats.values
        .where((c) => c.participantUids.contains(userUid))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    yield initial;
    yield* _chatsController.stream.map(
      (list) => list.where((c) => c.participantUids.contains(userUid)).toList(),
    );
  }

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) async* {
    yield List<ChatMessage>.from(_messages[chatId] ?? []);
    final controller = _messageControllers.putIfAbsent(
      chatId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
    yield* controller.stream;
  }

  @override
  Future<ChatMessage> sendMessage({
    required String chatId,
    required String text,
    required UserModel currentUser,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw Exception('Message cannot be empty');
    }

    final message = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      chatId: chatId,
      senderUid: currentUser.uid,
      senderEmail: currentUser.email,
      text: trimmed,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
    );

    final list = _messages.putIfAbsent(chatId, () => []);
    list.add(message);

    final existingChat = _chats[chatId];
    if (existingChat != null) {
      _chats[chatId] = ChatModel(
        id: existingChat.id,
        participantUids: existingChat.participantUids,
        participantEmails: existingChat.participantEmails,
        lastMessageText: trimmed,
        lastMessageTimestamp: message.timestamp,
        updatedAt: message.timestamp,
      );
      _emitChats(currentUser.uid);
    }

    _emitMessages(chatId);
    return message;
  }

  @override
  Future<void> markDelivered(String chatId, String messageId) async {
    final list = _messages[chatId];
    if (list != null) {
      final index = list.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        list[index] = list[index].copyWith(status: MessageStatus.delivered);
        _emitMessages(chatId);
      }
    }
  }

  @override
  Future<void> markRead(String chatId, String messageId) async {
    final list = _messages[chatId];
    if (list != null) {
      final index = list.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        list[index] = list[index].copyWith(status: MessageStatus.read);
        _emitMessages(chatId);
      }
    }
  }

  void _emitChats(String userUid) {
    final userChats = _chats.values
        .filterUser(userUid)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (!_chatsController.isClosed) {
      _chatsController.add(userChats);
    }
  }

  void _emitMessages(String chatId) {
    final msgs = _messages[chatId] ?? [];
    final controller = _messageControllers[chatId];
    if (controller != null && !controller.isClosed) {
      controller.add(List.from(msgs));
    }
  }
}

extension _ChatFilter on Iterable<ChatModel> {
  Iterable<ChatModel> filterUser(String uid) {
    return where((c) => c.participantUids.contains(uid));
  }
}
