import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/database/chat_repository.dart';
import 'package:ozone/models/user_model.dart';
import 'package:ozone/models/chat_model.dart';

void main() {
  group('Connect by Email & Chat Repository Tests', () {
    test('Lookup registered user by email succeeds', () async {
      final userBob = UserModel(
        uid: 'uid_bob',
        email: 'bob@ozone.test',
        displayName: 'Bob',
        isEmailVerified: true,
        createdAt: DateTime.now(),
      );

      final repo = MockChatRepository(initialUsers: [userBob]);

      final found = await repo.lookupUserByEmail('bob@ozone.test');
      expect(found, isNotNull);
      expect(found?.uid, 'uid_bob');

      // Case-insensitive check
      final foundUpper = await repo.lookupUserByEmail('BOB@OZONE.TEST');
      expect(foundUpper, isNotNull);
      expect(foundUpper?.email, 'bob@ozone.test');

      // Unregistered user check
      final notFound = await repo.lookupUserByEmail('unregistered@ozone.test');
      expect(notFound, isNull);
    });

    test('getOrCreateChat creates deterministic 1:1 chat thread', () async {
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
      final expectedId = ChatModel.deterministicChatId(alice.uid, bob.uid);
      expect(chat.id, expectedId);
      expect(chat.participantUids, containsAll(['uid_alice', 'uid_bob']));
      expect(chat.participantEmails, containsAll(['alice@ozone.test', 'bob@ozone.test']));

      // Fetching again returns existing thread
      final existing = await repo.getOrCreateChat(bob, alice);
      expect(existing.id, chat.id);
    });

    test('Cannot start a chat with yourself', () async {
      final alice = UserModel(
        uid: 'uid_alice',
        email: 'alice@ozone.test',
        createdAt: DateTime.now(),
      );
      final repo = MockChatRepository(initialUsers: [alice]);

      expect(
        () async => await repo.getOrCreateChat(alice, alice),
        throwsA(isA<Exception>()),
      );
    });

    test('createInviteChat creates pending thread for unregistered email', () async {
      final alice = UserModel(
        uid: 'uid_alice',
        email: 'alice@ozone.test',
        createdAt: DateTime.now(),
      );
      final repo = MockChatRepository(initialUsers: [alice]);

      final inviteChat = await repo.createInviteChat('colleague@work.com', alice);
      expect(inviteChat.id, startsWith('invite_uid_alice_'));
      expect(inviteChat.participantEmails, contains('colleague@work.com'));
      expect(inviteChat.participantUids, contains('pending_invite'));
    });
  });
}
