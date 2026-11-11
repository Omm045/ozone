import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../models/chat_model.dart';
import '../../models/chat_message.dart';
import '../../models/call_session.dart';

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
  Future<void> deleteMessage({required String chatId, required String messageId});
  Future<void> removeChat({required String chatId, required String userUid});
  Stream<CallSession?> getIncomingCallsStream(String userUid);
  Future<void> declineCall(String callId);
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

    if (query.docs.isEmpty) {
      // No document found matching this email in /users.
      // This means no matching profile document exists in the /users collection.
      debugPrint(
        '[FirestoreChatRepository] lookupUserByEmail: No user document found in /users for email: "$normalized". '
        'This means no matching document exists in /users.',
      );
      return null;
    }
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
        .snapshots()
        .map((snapshot) {
      final chats = snapshot.docs
          .map((doc) => ChatModel.fromMap(doc.data(), doc.id))
          .where((chat) => !chat.isHiddenFor(userUid))
          .toList();
      chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return chats;
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

  @override
  Future<void> deleteMessage({required String chatId, required String messageId}) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'isDeleted': true,
      'text': '',
    });
  }

  @override
  Future<void> removeChat({required String chatId, required String userUid}) async {
    final docRef = _firestore.collection('chats').doc(chatId);
    final snapshot = await docRef.get();
    if (!snapshot.exists || snapshot.data() == null) return;

    final chat = ChatModel.fromMap(snapshot.data()!, snapshot.id);
    if (chat.isPendingInvite) {
      // Pending/unregistered invite: delete the entire chat document
      await docRef.delete();
    } else {
      // Real contact chat: hide only for this user
      await docRef.update({
        'hiddenFor': FieldValue.arrayUnion([userUid]),
      });
    }
  }

  @override
  Stream<CallSession?> getIncomingCallsStream(String userUid) {
    return _firestore
        .collection('calls')
        .where('calleeUid', isEqualTo: userUid)
        .where('status', isEqualTo: CallStatus.ringing.name)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final sessions = snapshot.docs
          .map((doc) => CallSession.fromMap(doc.data(), doc.id))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final latest = sessions.firstOrNull;
      if (latest != null) {
        if (DateTime.now().difference(latest.createdAt).inSeconds > 45) {
          return null;
        }
      }
      return latest;
    });
  }

  @override
  Future<void> declineCall(String callId) async {
    await _firestore.collection('calls').doc(callId).update({
      'status': CallStatus.rejected.name,
      'failureReason': 'Call declined by recipient.',
    }).catchError((_) {});
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
    final user = _users[normalized];
    if (user == null) {
      // Diagnostic: No user document found matching this email.
      // This means no matching document exists in /users.
      debugPrint(
        '[MockChatRepository] lookupUserByEmail: No user found for email: "$normalized". '
        'This means no matching document exists in /users.',
      );
    }
    return user;
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
    _emitChats();
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
    _emitChats();
    return invite;
  }

  @override
  Stream<List<ChatModel>> getChatsStream(String userUid) async* {
    final initial = _chats.values
        .where((c) => c.participantUids.contains(userUid) && !c.isHiddenFor(userUid))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    yield initial;
    yield* _chatsController.stream.map(
      (list) => list
          .where((c) => c.participantUids.contains(userUid) && !c.isHiddenFor(userUid))
          .toList(),
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

  int _messageCounter = 0;

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
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}_${++_messageCounter}',
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
      _emitChats();
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

  @override
  Future<void> deleteMessage({required String chatId, required String messageId}) async {
    final list = _messages[chatId];
    if (list != null) {
      final index = list.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        list[index] = list[index].copyWith(
          isDeleted: true,
          text: '',
        );
        _emitMessages(chatId);
      }
    }
  }

  @override
  Future<void> removeChat({required String chatId, required String userUid}) async {
    final chat = _chats[chatId];
    if (chat == null) return;
    if (chat.isPendingInvite) {
      _chats.remove(chatId);
      _messages.remove(chatId);
    } else {
      final updatedHidden = Set<String>.from(chat.hiddenFor)..add(userUid);
      _chats[chatId] = chat.copyWith(hiddenFor: updatedHidden.toList());
    }
    _emitChats();
  }

  final _incomingCallsController = StreamController<CallSession?>.broadcast(sync: true);
  CallSession? _activeIncomingCall;

  @override
  Stream<CallSession?> getIncomingCallsStream(String userUid) {
    late final StreamController<CallSession?> controller;
    StreamSubscription<CallSession?>? sub;

    controller = StreamController<CallSession?>.broadcast(
      sync: true,
      onListen: () {
        if (_activeIncomingCall != null &&
            _activeIncomingCall!.calleeUid == userUid &&
            _activeIncomingCall!.status == CallStatus.ringing) {
          scheduleMicrotask(() {
            if (!controller.isClosed) {
              controller.add(_activeIncomingCall);
            }
          });
        }
        sub = _incomingCallsController.stream.listen((session) {
          if (!controller.isClosed) {
            if (session != null &&
                session.calleeUid == userUid &&
                session.status == CallStatus.ringing) {
              controller.add(session);
            } else {
              controller.add(null);
            }
          }
        });
      },
      onCancel: () {
        sub?.cancel();
      },
    );

    return controller.stream;
  }

  void simulateIncomingCall(CallSession session) {
    _activeIncomingCall = session;
    _incomingCallsController.add(session);
  }

  void clearIncomingCall() {
    _activeIncomingCall = null;
    _incomingCallsController.add(null);
  }

  @override
  Future<void> declineCall(String callId) async {
    if (_activeIncomingCall != null && _activeIncomingCall!.id == callId) {
      _activeIncomingCall = CallSession(
        id: _activeIncomingCall!.id,
        callerUid: _activeIncomingCall!.callerUid,
        callerEmail: _activeIncomingCall!.callerEmail,
        calleeUid: _activeIncomingCall!.calleeUid,
        calleeEmail: _activeIncomingCall!.calleeEmail,
        status: CallStatus.rejected,
        failureReason: 'Call declined by recipient.',
        createdAt: _activeIncomingCall!.createdAt,
      );
      _incomingCallsController.add(null);
    }
  }

  void _emitChats() {
    final allChats = _chats.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (!_chatsController.isClosed) {
      _chatsController.add(allChats);
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
