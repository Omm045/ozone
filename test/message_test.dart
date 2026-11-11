import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/database/chat_repository.dart';
import 'package:ozone/models/user_model.dart';
import 'package:ozone/models/chat_message.dart';

void main() {
  group('1:1 Messaging & Delivery/Read Receipts Tests', () {
    test('Send message and update delivery/read receipts', () async {
      final alice = UserModel(
        uid: 'uid_alice',
        email: 'alice@ozone.test',
        createdAt: DateTime.now(),
      );
      final bob = UserModel(
        uid: 'uid_bob',
        email: 'bob@ozone.test',
        createdAt: DateTime.now(),
      );

      final repo = MockChatRepository(initialUsers: [alice, bob]);
      final chat = await repo.getOrCreateChat(bob, alice);

      // 1. Send Message
      final sent = await repo.sendMessage(
        chatId: chat.id,
        text: 'Are you ready for the 1080p -> 4K call test?',
        currentUser: alice,
      );

      expect(sent.text, 'Are you ready for the 1080p -> 4K call test?');
      expect(sent.senderUid, alice.uid);
      expect(sent.status, MessageStatus.sent);

      // 2. Mark Delivered
      await repo.markDelivered(chat.id, sent.id);
      final streamMessagesAfterDelivered = await repo.getMessagesStream(chat.id).first;
      expect(streamMessagesAfterDelivered.first.status, MessageStatus.delivered);

      // 3. Mark Read
      await repo.markRead(chat.id, sent.id);
      final streamMessagesAfterRead = await repo.getMessagesStream(chat.id).first;
      expect(streamMessagesAfterRead.first.status, MessageStatus.read);
    });

    test('Reject empty or whitespace-only messages', () async {
      final alice = UserModel(
        uid: 'uid_alice',
        email: 'alice@ozone.test',
        createdAt: DateTime.now(),
      );
      final bob = UserModel(
        uid: 'uid_bob',
        email: 'bob@ozone.test',
        createdAt: DateTime.now(),
      );

      final repo = MockChatRepository(initialUsers: [alice, bob]);
      final chat = await repo.getOrCreateChat(bob, alice);

      expect(
        () async => await repo.sendMessage(
          chatId: chat.id,
          text: '   ',
          currentUser: alice,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Part 5 Fix: Soft delete message sets isDeleted true and clears text while preserving message sequence', () async {
      final alice = UserModel(
        uid: 'uid_alice',
        email: 'alice@ozone.test',
        createdAt: DateTime.now(),
      );
      final bob = UserModel(
        uid: 'uid_bob',
        email: 'bob@ozone.test',
        createdAt: DateTime.now(),
      );

      final repo = MockChatRepository(initialUsers: [alice, bob]);
      final chat = await repo.getOrCreateChat(bob, alice);

      // Alice sends two messages
      final msg1 = await repo.sendMessage(
        chatId: chat.id,
        text: 'First message to keep',
        currentUser: alice,
      );
      final msg2 = await repo.sendMessage(
        chatId: chat.id,
        text: 'Second message to delete',
        currentUser: alice,
      );

      var messages = await repo.getMessagesStream(chat.id).first;
      expect(messages.length, 2);
      expect(messages[1].isDeleted, isFalse);
      expect(messages[1].text, 'Second message to delete');

      // Alice deletes msg2
      await repo.deleteMessage(chatId: chat.id, messageId: msg2.id);

      messages = await repo.getMessagesStream(chat.id).first;
      expect(messages.length, 2);
      expect(messages[0].id, msg1.id);
      expect(messages[0].isDeleted, isFalse);
      expect(messages[0].text, 'First message to keep');

      expect(messages[1].id, msg2.id);
      expect(messages[1].isDeleted, isTrue);
      expect(messages[1].text, isEmpty);
      expect(messages[1].senderUid, alice.uid);
    });
  });
}
