import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';
import 'package:luoda_flutter/models/viewer_session_model.dart';

void main() {
  test('self target guard recognizes every local connection form', () {
    const ownId = '423727';
    const localAddresses = <String>['192.168.1.20', '198.51.100.44'];

    for (final target in <String>[
      '423 727',
      '423727/r',
      '423727@192.168.1.20:21118?key=test',
      'localhost:21118',
      '127.0.0.1:21118',
      '[::1]:21118',
      '0.0.0.0:21118',
      '192.168.1.20:21118',
      '198.51.100.44:21118',
    ]) {
      expect(
        DirectPairingStore.isSelfTargetValue(
          target,
          ownId: ownId,
          localAddresses: localAddresses,
        ),
        isTrue,
        reason: target,
      );
    }

    for (final target in <String>[
      '423728',
      '192.168.1.21:21118',
      '36.134.211.190:21118',
    ]) {
      expect(
        DirectPairingStore.isSelfTargetValue(
          target,
          ownId: ownId,
          localAddresses: localAddresses,
        ),
        isFalse,
        reason: target,
      );
    }
  });

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

  test('persisted chat text replaces malformed UTF-16 before rendering', () {
    final malformed = String.fromCharCodes(<int>[0xD800, 0x41, 0xDC00]);
    final record = DirectChatRecord.fromJson(<String, dynamic>{
      'id': 'message-invalid-utf16',
      'conversation_id': 'peer-invalid-utf16',
      'origin_device_id': 'device-invalid-utf16',
      'direction': 'incoming',
      'kind': 'text',
      'text': malformed,
      'sender_id': malformed,
      'sender_name': malformed,
      'sender_avatar': '',
      'sent_at': '2026-08-03T08:30:00Z',
      'delivery': 'delivered',
      'file_name': malformed,
      'reply_to_text': malformed,
    });

    expect(record.text, '\uFFFDA\uFFFD');
    expect(record.senderId, '\uFFFDA\uFFFD');
    expect(record.senderName, '\uFFFDA\uFFFD');
    expect(record.fileName, '\uFFFDA\uFFFD');
    expect(record.replyToText, '\uFFFDA\uFFFD');
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

  test('recalled and destroyed messages keep mutation state on the wire', () {
    final record = DirectChatRecord(
      id: 'mutation',
      conversationId: 'peer',
      originDeviceId: 'device',
      originSequence: 1,
      direction: DirectChatDirection.outgoing,
      kind: DirectChatKind.text,
      text: 'secret',
      senderId: 'sender',
      senderName: 'PC',
      senderAvatar: '',
      sentAt: DateTime.utc(2026, 7, 20),
      delivery: DirectChatDelivery.delivered,
    );
    final recalled = record.copyWith(
      originSequence: 2,
      disposition: DirectChatDisposition.recalled,
    );
    final restored = DirectChatRecord.fromJson(
      DirectChatEnvelope.decode(DirectChatEnvelope.message(recalled).encode())!
          .data,
    );
    expect(restored.disposition, DirectChatDisposition.recalled);
    expect(
      record.copyWith(disposition: DirectChatDisposition.destroyed).disposition,
      DirectChatDisposition.destroyed,
    );
  });

  test('self-destruct expiry survives direct message serialization', () {
    final expiresAt = DateTime.utc(2026, 7, 20, 12, 5);
    final record = DirectChatRecord(
      id: 'expiring-message',
      conversationId: 'peer',
      originDeviceId: 'device',
      originSequence: 3,
      direction: DirectChatDirection.outgoing,
      kind: DirectChatKind.text,
      text: 'temporary',
      senderId: 'sender',
      senderName: 'PC',
      senderAvatar: '',
      sentAt: DateTime.utc(2026, 7, 20, 12),
      delivery: DirectChatDelivery.sent,
      expiresAt: expiresAt,
    );

    final restored = DirectChatRecord.fromJson(
      DirectChatEnvelope.decode(DirectChatEnvelope.message(record).encode())!
          .data,
    );

    expect(restored.expiresAt, expiresAt);
    expect(restored.toJson()['expires_at'], expiresAt.toIso8601String());
  });

  test('voice record and chunk envelopes preserve playback metadata', () {
    final record = DirectChatRecord(
      id: 'voice-1',
      conversationId: 'peer-voice',
      originDeviceId: 'device-voice',
      originSequence: 10,
      direction: DirectChatDirection.outgoing,
      kind: DirectChatKind.voice,
      text: 'Voice message',
      senderId: 'sender-voice',
      senderName: 'Phone',
      senderAvatar: '',
      sentAt: DateTime.utc(2026, 7, 17, 9),
      delivery: DirectChatDelivery.sent,
      fileName: 'voice-1.wav',
      fileSize: 32000,
      fileSha256: List<String>.filled(64, 'a').join(),
      voiceDurationMs: 1800,
    );

    final restored = DirectChatRecord.fromJson(
      DirectChatEnvelope.decode(DirectChatEnvelope.message(record).encode())!
          .data,
    );
    expect(restored.kind, DirectChatKind.voice);
    expect(restored.voiceDurationMs, 1800);
    expect(restored.fileSize, 32000);

    final chunk = DirectChatEnvelope.decode(
      DirectChatEnvelope.voiceChunk(
        messageId: record.id,
        index: 1,
        total: 3,
        sha256: record.fileSha256,
        payload: 'YWJj',
      ).encode(),
    );
    expect(chunk?.type, 'voice_chunk');
    expect(chunk?.data['id'], record.id);
    expect(chunk?.data['index'], 1);
    expect(chunk?.data['total'], 3);

    final request = DirectChatEnvelope.decode(
      DirectChatEnvelope.voiceRequest(record.id).encode(),
    );
    expect(request?.type, 'voice_request');
    expect(request?.data['id'], record.id);
  });

  test('merged forwards preserve sender and message summaries on both peers',
      () {
    final record = DirectChatRecord(
      id: 'forward-1',
      conversationId: 'peer-b',
      originDeviceId: 'device-a',
      originSequence: 9,
      direction: DirectChatDirection.outgoing,
      kind: DirectChatKind.forward,
      text: 'Chat history',
      senderId: 'device-a',
      senderName: 'Alice',
      senderAvatar: '',
      sentAt: DateTime.utc(2026, 8, 3),
      delivery: DirectChatDelivery.queued,
      forwardTitle: 'Alice and VPS',
      forwardItems: const <DirectChatForwardItem>[
        DirectChatForwardItem(
          senderName: 'Alice',
          kind: DirectChatKind.text,
          text: 'hello',
        ),
        DirectChatForwardItem(
          senderName: 'VPS',
          kind: DirectChatKind.file,
          text: 'Sent file: report.pdf',
          fileName: 'report.pdf',
        ),
      ],
    );

    final restored = DirectChatRecord.fromJson(
      DirectChatEnvelope.decode(DirectChatEnvelope.message(record).encode())!
          .data,
    );
    expect(restored.kind, DirectChatKind.forward);
    expect(restored.forwardTitle, 'Alice and VPS');
    expect(restored.forwardItems, hasLength(2));
    expect(restored.forwardItems.last.fileName, 'report.pdf');
  });

  test('chat envelope preserves multilingual and supplementary characters', () {
    const content = '简体中文 𠀀 𠮷 😀 ♜ € e\u0301';
    final record = DirectChatRecord(
      id: 'unicode-1',
      conversationId: 'peer-b',
      originDeviceId: 'device-a',
      originSequence: 10,
      direction: DirectChatDirection.outgoing,
      kind: DirectChatKind.text,
      text: content,
      senderId: 'device-a',
      senderName: '用户😀',
      senderAvatar: '',
      sentAt: DateTime.utc(2026, 8, 3),
      delivery: DirectChatDelivery.queued,
      replyToSender: '对方𠮷',
      replyToText: '引用♜',
    );

    final restored = DirectChatRecord.fromJson(
      DirectChatEnvelope.decode(DirectChatEnvelope.message(record).encode())!
          .data,
    );
    expect(restored.text, content);
    expect(restored.senderName, '用户😀');
    expect(restored.replyToSender, '对方𠮷');
    expect(restored.replyToText, '引用♜');
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

  test('paired IP resolves through the canonical ID and fingerprint', () {
    final pairing = DirectPairing(
      peerId: '654321',
      displayName: 'Direct peer',
      lanEndpoint: '198.51.100.44:21118',
      publicEndpoint: '',
      fingerprint: List<String>.filled(64, 'b').join(),
      updatedAt: DateTime.utc(2026, 8, 3),
    );

    final target = DirectPairingStore.resolveConnectionTargetValue(
      '198.51.100.44:21118',
      pairings: {'654321': pairing},
    );

    expect(target, startsWith('654321@198.51.100.44:21118?key='));
  });

  test('paired device ID prefers its latest direct IP endpoint', () {
    final pairing = DirectPairing(
      peerId: '654321',
      displayName: 'Direct peer',
      lanEndpoint: '198.51.100.44:21118',
      publicEndpoint: '',
      fingerprint: List<String>.filled(64, 'b').join(),
      updatedAt: DateTime.utc(2026, 8, 3),
    );

    final target = DirectPairingStore.resolveConnectionTargetValue(
      '654321',
      pairings: {'654321': pairing},
    );

    expect(target, startsWith('654321@198.51.100.44:21118?key='));
  });

  test('unpaired device IDs remain valid core connection targets', () {
    expect(DirectPairingStore.isDeviceId('654321'), isTrue);
    expect(DirectPairingStore.isDeviceId('peer-office-01'), isTrue);
    expect(DirectPairingStore.isDeviceId('192.168.1.8:21118'), isFalse);
    expect(DirectPairingStore.isDeviceId(''), isFalse);
  });

  test('pairing QR payload accepts a signed direct target', () {
    final payload = Uri(
      scheme: 'luoda',
      host: 'pair',
      queryParameters: <String, String>{
        'v': '2',
        'id': 'peer-qr',
        'name': 'Office PC',
        'lan': '192.168.1.8:21118',
        'wan': '203.0.113.8:21118',
        'fp': List<String>.filled(64, 'a').join(),
        'role': 'companion',
        'sync': 'companion-secret',
        'ts': '2026-07-17T08:30:00Z',
      },
    ).toString();

    final pairing = DirectPairingStore.parsePayload(payload);
    expect(pairing, isNotNull);
    expect(pairing!.peerId, 'peer-qr');
    expect(pairing.displayName, 'Office PC');
    expect(pairing.connectionTarget, contains('192.168.1.8:21118'));
    expect(pairing.connectionTarget, contains('fallback=203.0.113.8:21118'));
    expect(pairing.companion, isTrue);
  });

  test('pairing QR payload rejects unsigned or malformed targets', () {
    final unsigned = Uri(
      scheme: 'luoda',
      host: 'pair',
      queryParameters: <String, String>{
        'v': '2',
        'id': 'peer-qr',
        'lan': '192.168.1.8:21118',
      },
    ).toString();
    final fingerprint = List<String>.filled(64, 'a').join();
    final malformed =
        'luoda://pair?v=2&id=peer-qr&fp=$fingerprint&lan=not-an-endpoint';

    expect(DirectPairingStore.parsePayload(unsigned), isNull);
    expect(DirectPairingStore.parsePayload(malformed), isNull);
    expect(DirectPairingStore.parsePayload('not-a-qr-code'), isNull);
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
