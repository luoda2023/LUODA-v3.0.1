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
  });
}
