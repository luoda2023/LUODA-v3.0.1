import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';

void main() {
  test('contact card encodes and round-trips peerId/name/platform', () {
    const card = DirectChatContact(
      peerId: 'ACCT-7788',
      name: '张三',
      platform: 'Windows',
    );
    final encoded = card.encode();
    expect(encoded, '[contact]ACCT-7788|张三|Windows');

    final parsed = DirectChatContact.tryParse(encoded);
    expect(parsed, isNotNull);
    expect(parsed!.peerId, 'ACCT-7788');
    expect(parsed.name, '张三');
    expect(parsed.platform, 'Windows');
  });

  test('contact card omits empty name/platform fields', () {
    const card = DirectChatContact(peerId: 'ACCT-7788');
    final encoded = card.encode();
    expect(encoded, '[contact]ACCT-7788');

    final parsed = DirectChatContact.tryParse(encoded);
    expect(parsed, isNotNull);
    expect(parsed!.peerId, 'ACCT-7788');
    expect(parsed.name, '');
    expect(parsed.platform, '');
  });

  test('contact card round-trips a numeric peerId with a spaced name', () {
    const card = DirectChatContact(
      peerId: '423727',
      name: '张三 经理',
      platform: 'iPhone',
    );
    final parsed = DirectChatContact.tryParse(card.encode());
    expect(parsed, isNotNull);
    expect(parsed!.peerId, '423727');
    expect(parsed.name, '张三 经理');
    expect(parsed.platform, 'iPhone');
  });

  test('tryParse rejects non-card text and empty peerId', () {
    expect(DirectChatContact.tryParse('你好'), isNull);
    expect(DirectChatContact.tryParse('[contact]'), isNull);
    expect(DirectChatContact.tryParse('[contact]  '), isNull);
    expect(DirectChatContact.tryParse(''), isNull);
  });

  test('leading/trailing whitespace is trimmed', () {
    final parsed = DirectChatContact.tryParse(
      '  [contact] ACCT-7788 | 王五 | macOS  ',
    );
    expect(parsed, isNotNull);
    expect(parsed!.peerId, 'ACCT-7788');
    expect(parsed.name, '王五');
    expect(parsed.platform, 'macOS');
  });
}
