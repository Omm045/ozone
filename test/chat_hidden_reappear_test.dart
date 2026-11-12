// Regression: a chat I deleted "for me" must reappear when the OTHER person
// sends a new message. Previously sendMessage only removed the sender from
// hiddenFor, so the peer's messages were silently invisible to me.
// Real-Firestore coverage: integration_test/qa/chat_real_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/database/chat_repository.dart';
import 'package:ozone/models/user_model.dart';

void main() {
  test('peer message un-hides a chat I deleted for me', () async {
    final me = UserModel(uid: 'uid_me', email: 'me@ozone.test', createdAt: DateTime.now());
    final peer = UserModel(uid: 'uid_peer', email: 'peer@ozone.test', createdAt: DateTime.now());
    final repo = MockChatRepository(initialUsers: [me, peer]);
    final chat = await repo.getOrCreateChat(peer, me);

    await repo.removeChat(chatId: chat.id, userUid: me.uid);
    expect((await repo.getChatsStream(me.uid).first).any((c) => c.id == chat.id), isFalse);
    expect((await repo.getChatsStream(peer.uid).first).any((c) => c.id == chat.id), isTrue);

    await repo.sendMessage(chatId: chat.id, text: 'hello?', currentUser: peer);
    expect((await repo.getChatsStream(me.uid).first).any((c) => c.id == chat.id), isTrue);
  });
}
