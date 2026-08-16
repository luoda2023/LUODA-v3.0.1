import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';

void main() {
  test('parses a full add-friend QR payload', () {
    final parsed = DirectPairingStore.parseFriendPayload(
      'luoda://friend?v=1&id=423727&name=%E5%BC%A0%E4%B8%89&acct=423727',
    );
    expect(parsed, isNotNull);
    expect(parsed!.peerId, '423727');
    expect(parsed.name, '张三');
    expect(parsed.accountId, '423727');
  });

  test('parses a bare-ID friend QR without name/account', () {
    final parsed =
        DirectPairingStore.parseFriendPayload('luoda://friend?v=1&id=ACCT-7788');
    expect(parsed, isNotNull);
    expect(parsed!.peerId, 'ACCT-7788');
    expect(parsed.name, '');
    expect(parsed.accountId, '');
  });

  test('rejects non-friend schemes and hosts', () {
    expect(DirectPairingStore.parseFriendPayload('luoda://pair?id=1'), isNull);
    expect(DirectPairingStore.parseFriendPayload('https://example.com'), isNull);
    expect(DirectPairingStore.parseFriendPayload('随便一串文字'), isNull);
    expect(DirectPairingStore.parseFriendPayload(''), isNull);
  });

  test('rejects a friend payload with an empty ID', () {
    expect(
      DirectPairingStore.parseFriendPayload('luoda://friend?v=1&name=x'),
      isNull,
    );
    expect(
      DirectPairingStore.parseFriendPayload('luoda://friend?id=   '),
      isNull,
    );
  });

  test('trims whitespace in every field', () {
    final parsed = DirectPairingStore.parseFriendPayload(
      '  luoda://friend?id= 814012 &name= 李四 &acct= 814012  ',
    );
    expect(parsed, isNotNull);
    expect(parsed!.peerId, '814012');
    expect(parsed.name, '李四');
    expect(parsed.accountId, '814012');
  });
}
