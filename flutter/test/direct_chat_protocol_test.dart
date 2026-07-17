import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';
import 'package:luoda_flutter/models/viewer_session_model.dart';

void main() {
  test('direct chat message envelope preserves identity and unicode', () {
    final record = DirectChatRecord(
      id: 'message-1',
      conversationId: 'peer-1',
      originDeviceId: 'device-1',
      originSequence: 7,
      direction: DirectChatDirection.outgoing,
      kind: DirectChatKind.text,
      text: 'hello \u4f60\u597d',
      senderId: 'sender-1',
      senderName: 'LDesk',
      senderAvatar: '',
      sentAt: DateTime.utc(2026, 7, 17, 8, 30),
      delivery: DirectChatDelivery.queued,
    );

    final encoded = DirectChatEnvelope.message(record).encode();
    final decoded = DirectChatEnvelope.decode(encoded);
    final restored = DirectChatRecord.fromJson(decoded!.data);

    expect(decoded.type, 'message');
    expect(restored.id, record.id);
    expect(restored.originSequence, 7);
    expect(restored.text, 'hello \u4f60\u597d');
    expect(restored.delivery, DirectChatDelivery.queued);
  });

  test('legacy and malformed payloads remain outside the control protocol', () {
    expect(DirectChatEnvelope.decode('ordinary chat text'), isNull);
    expect(
        DirectChatEnvelope.decode('${DirectChatEnvelope.prefix}bad'), isNull);
  });

  test('file record keeps transfer metadata for cross-device history', () {
    final record = DirectChatRecord.fromJson(<String, dynamic>{
      'id': 'file-1',
      'conversation_id': 'peer-2',
      'origin_device_id': 'device-2',
      'origin_sequence': 9,
      'direction': 'outgoing',
      'kind': 'file',
      'text': 'sent file',
      'sender_id': 'sender-2',
      'sender_name': 'PC',
      'sender_avatar': '',
      'sent_at': '2026-07-17T08:30:00Z',
      'delivery': 'delivered',
      'file_name': 'report.pdf',
      'file_size': 4096,
      'file_sha256': 'abc123',
    });

    expect(record.kind, DirectChatKind.file);
    expect(record.fileName, 'report.pdf');
    expect(record.fileSize, 4096);
    expect(record.delivery, DirectChatDelivery.delivered);
  });

  test('paired target carries a WAN fallback for off-LAN connections', () {
    final pairing = DirectPairing(
      peerId: 'peer-3',
      displayName: 'PC',
      lanEndpoint: '192.168.1.8:21118',
      publicEndpoint: '203.0.113.8:21118',
      fingerprint: List<String>.filled(64, 'a').join(),
      updatedAt: DateTime.utc(2026, 7, 17),
    );

    expect(pairing.connectionTarget, contains('192.168.1.8:21118'));
    expect(
      pairing.connectionTarget,
      contains('fallback=203.0.113.8:21118'),
    );
  });

  test('viewer control events stay out of ordinary direct chat', () {
    final model = ViewerSessionModel();

    expect(model.handleWireMessage('ordinary chat text'), isFalse);
    expect(
      model.handleWireMessage('INVITE_TOKEN:ABC123:sid-1:123:true'),
      isTrue,
    );
    expect(model.inviteTokenPayload, 'ABC123:sid-1:123:true');

    expect(
      model.handleWireMessage('VIEWER_LIST:8:4096:1:v1|Alice|false|123'),
      isTrue,
    );
    expect(model.viewerListPayload, '8:4096:1:v1|Alice|false|123');

    expect(
      model.handleWireMessage('BROADCAST_CHAT:v1:Alice:124:hello'),
      isTrue,
    );
    expect(model.broadcastChatPayloads, <String>['v1:Alice:124:hello']);
    expect(model.handleWireMessage('KICK_VIEWER:v1:host_kick'), isTrue);
    expect(model.lastControlPayload, 'KICK_VIEWER:v1:host_kick');

    model.dispose();
  });
}
