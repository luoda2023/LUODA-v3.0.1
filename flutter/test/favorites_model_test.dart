import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/favorites_model.dart';

ChatUser _user(String id, String name) => ChatUser(id: id, firstName: name);

ChatMessage _textMessage({String peerId = 'peer-1', String text = 'hello world'}) {
  return ChatMessage(
    text: text,
    createdAt: DateTime.now(),
    user: _user(peerId, 'Peer One'),
    customProperties: <String, dynamic>{'ldesk_kind': 'text', 'ldesk_id': 'm1'},
  );
}

ChatMessage _imageMessage() {
  return ChatMessage(
    text: '',
    createdAt: DateTime.now(),
    user: _user('peer-1', 'Peer One'),
    customProperties: <String, dynamic>{
      'ldesk_kind': 'file',
      'ldesk_id': 'm2',
      'ldesk_file_name': 'photo.png',
      'ldesk_local_path': 'C:/tmp/photo.png',
      'ldesk_file_size': 2048,
    },
  );
}

ChatMessage _fileMessage() {
  return ChatMessage(
    text: '',
    createdAt: DateTime.now(),
    user: _user('peer-1', 'Peer One'),
    customProperties: <String, dynamic>{
      'ldesk_kind': 'file',
      'ldesk_id': 'm3',
      'ldesk_file_name': 'report.pdf',
      'ldesk_local_path': 'C:/tmp/report.pdf',
      'ldesk_file_size': 102400,
    },
  );
}

ChatMessage _locationMessage() {
  return ChatMessage(
    text: '[location]31.230416,121.473701|上海迪士尼乐园|上海市浦东新区川沙新镇',
    createdAt: DateTime.now(),
    user: _user('peer-1', 'Peer One'),
    customProperties: <String, dynamic>{'ldesk_kind': 'text', 'ldesk_id': 'm4'},
  );
}

ChatMessage _voiceMessage() {
  return ChatMessage(
    text: '',
    createdAt: DateTime.now(),
    user: _user('peer-1', 'Peer One'),
    customProperties: <String, dynamic>{
      'ldesk_kind': 'voice',
      'ldesk_id': 'm5',
      'ldesk_file_name': 'voice_1.amr',
      'ldesk_local_path': 'C:/tmp/voice_1.amr',
    },
  );
}

void main() {
  group('FavoriteItem.fromMessage', () {
    test('text message becomes text favorite', () {
      final item = FavoriteItem.fromMessage(_textMessage());
      expect(item.type, FavoriteItemType.text);
      expect(item.title, 'hello world');
      expect(item.peerName, 'Peer One');
    });

    test('image file becomes image favorite', () {
      final item = FavoriteItem.fromMessage(_imageMessage());
      expect(item.type, FavoriteItemType.image);
      expect(item.localPath, 'C:/tmp/photo.png');
    });

    test('non-image file becomes file favorite with size subtitle', () {
      final item = FavoriteItem.fromMessage(_fileMessage());
      expect(item.type, FavoriteItemType.file);
      expect(item.subtitle, contains('KB'));
    });

    test('location text becomes location favorite with coordinates', () {
      final item = FavoriteItem.fromMessage(_locationMessage());
      expect(item.type, FavoriteItemType.location);
      expect(item.title, '上海迪士尼乐园');
      expect(item.extra['lat'], closeTo(31.230416, 0.0001));
      expect(item.extra['lng'], closeTo(121.473701, 0.0001));
    });

    test('voice message becomes voice favorite', () {
      final item = FavoriteItem.fromMessage(_voiceMessage());
      expect(item.type, FavoriteItemType.voice);
    });
  });

  group('FavoritesModel', () {
    test('toggle adds then removes a message favorite', () async {
      final model = FavoritesModel.instance;
      // 清理旧状态，保证断言独立。
      await model.removeAll(model.items.map((e) => e.id));

      final added = await model.toggleMessage(_textMessage());
      expect(added, isTrue);
      expect(model.isMessageFavorited(_textMessage()), isTrue);

      final removed = await model.toggleMessage(_textMessage());
      expect(removed, isFalse);
      expect(model.isMessageFavorited(_textMessage()), isFalse);
    });

    test('byType filters favorites correctly', () async {
      final model = FavoritesModel.instance;
      await model.removeAll(model.items.map((e) => e.id));

      await model.toggleMessage(_textMessage());
      await model.toggleMessage(_imageMessage());
      await model.toggleMessage(_locationMessage());

      expect(model.byType('image').length, 1);
      expect(model.byType('location').length, 1);
      expect(model.byType('text').length, 1);
      expect(model.byType('file').length, 0);
      expect(model.byType('all').length, 3);

      await model.removeAll(model.items.map((e) => e.id));
    });

    test('remove deletes a single favorite', () async {
      final model = FavoritesModel.instance;
      await model.removeAll(model.items.map((e) => e.id));
      await model.toggleMessage(_textMessage());
      final item = model.items.first;
      await model.remove(item.id);
      expect(model.items, isEmpty);
    });

    test('toggleChatHistory saves full conversation with timestamps',
        () async {
      final model = FavoritesModel.instance;
      await model.removeAll(model.items.map((e) => e.id));

      final now = DateTime(2026, 8, 15, 10, 30);
      final msgA = ChatMessage(
        text: '第一条消息',
        createdAt: now,
        user: _user('peer-1', 'Peer One'),
        customProperties: <String, dynamic>{
          'ldesk_kind': 'text',
          'ldesk_id': 'h1',
        },
      );
      final msgB = ChatMessage(
        text: '第二条消息',
        createdAt: now.add(const Duration(minutes: 2)),
        user: _user('peer-1', 'Peer One'),
        customProperties: <String, dynamic>{
          'ldesk_kind': 'text',
          'ldesk_id': 'h2',
        },
      );
      await model.toggleChatHistory(
        messages: <ChatMessage>[msgA, msgB],
        peerId: 'peer-1',
        peerName: 'Peer One',
        meId: 'me',
      );

      expect(model.items.length, 1);
      final item = model.items.first;
      expect(item.type, FavoriteItemType.forward);
      expect(item.chatMessages.length, 2);
      expect(item.chatMessages.first['text'], '第一条消息');
      expect(item.chatMessages.first['created_at'],
          now.millisecondsSinceEpoch);
      expect(item.chatMessages.last['created_at'],
          now.add(const Duration(minutes: 2)).millisecondsSinceEpoch);
      expect(item.chatMessages.first['is_me'], isFalse);

      // 重复收藏同一段聊天记录会取消。
      final again = await model.toggleChatHistory(
        messages: <ChatMessage>[msgA, msgB],
        peerId: 'peer-1',
        peerName: 'Peer One',
        meId: 'me',
      );
      expect(again, isFalse);
      expect(model.items, isEmpty);
    });

    test('forward favorite keeps forward items', () async {
      final model = FavoritesModel.instance;
      await model.removeAll(model.items.map((e) => e.id));

      final msg = ChatMessage(
        text: '聊天记录',
        createdAt: DateTime.now(),
        user: _user('peer-1', 'Peer One'),
        customProperties: <String, dynamic>{
          'ldesk_kind': 'forward',
          'ldesk_id': 'fwd-1',
          'ldesk_forward_title': '某会话的聊天记录',
          'ldesk_forward_items': <Map<String, dynamic>>[
            <String, dynamic>{
              'sender_name': '张三',
              'kind': 'text',
              'text': '第一条',
            },
            <String, dynamic>{
              'sender_name': '李四',
              'kind': 'file',
              'text': '文件',
              'file_name': 'a.pdf',
            },
          ],
        },
      );
      await model.toggleMessage(msg, peerName: 'Peer One');
      expect(model.items.length, 1);
      final item = model.items.first;
      expect(item.type, FavoriteItemType.forward);
      expect(item.forwardItems.length, 2);
      expect(item.forwardItems.first['text'], '第一条');
      expect(item.forwardItems.last['file_name'], 'a.pdf');
    });

    test('toggleChatHistory stores the chosen category label', () async {
      final model = FavoritesModel.instance;
      await model.removeAll(model.items.map((e) => e.id));

      final msg = ChatMessage(
        text: '一张图',
        createdAt: DateTime(2026, 8, 15, 11, 0),
        user: _user('peer-1', 'Peer One'),
        customProperties: <String, dynamic>{
          'ldesk_kind': 'text',
          'ldesk_id': 'c1',
        },
      );

      await model.toggleChatHistory(
        messages: <ChatMessage>[msg],
        peerId: 'peer-1',
        peerName: 'Peer One',
        meId: 'me',
        category: FavoriteItemType.image,
      );

      expect(model.items.length, 1);
      expect(model.items.first.type, FavoriteItemType.image);
      expect(model.items.first.chatMessages.length, 1);
      // 按分类过滤：命中 image，而不是默认的 forward。
      expect(model.byType(FavoriteItemType.image).length, 1);
      expect(model.byType(FavoriteItemType.forward), isEmpty);

      await model.removeAll(model.items.map((e) => e.id));
    });
  });
}
