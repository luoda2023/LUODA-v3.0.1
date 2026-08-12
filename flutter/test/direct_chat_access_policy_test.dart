import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat_policy.dart';

void main() {
  test('a direct chat session with a transport error is not ready', () {
    expect(
      isDirectChatSessionReady(
        closed: false,
        peerInfoReady: true,
        connectionError: 'Reset by the peer',
      ),
      isFalse,
    );
    expect(
      isDirectChatSessionReady(
        closed: false,
        peerInfoReady: true,
        connectionError: null,
      ),
      isTrue,
    );
  });

  test('mobile chat status and reconnect use the live session predicate', () {
    final source =
        File('lib/mobile/pages/connection_page.dart').readAsStringSync();
    final startDirectChat = source
        .split('Future<void> _startDirectChat(String id) async {')[1]
        .split('Widget _buildPairedContacts()')[0];
    final messageStatus = source
        .split('bool _isPairedContactOnline(')[1]
        .split('void onFocusChanged()')[0];

    expect(
      'isDirectChatSessionReady('.allMatches(startDirectChat).length,
      greaterThanOrEqualTo(2),
    );
    expect(messageStatus, contains('isDirectChatSessionReady('));
  });

  test('mobile sends inline attachments without a file-transfer session', () {
    final source = File('lib/mobile/pages/home_page.dart').readAsStringSync();
    final sendPickedFiles = source
        .split('Future<void> _sendPickedFiles(')[1]
        .split('Future<bool> _forwardConversationMessages(')[0];

    expect(sendPickedFiles, contains('canInlineDirectChatFile(file.size)'));
    expect(sendPickedFiles, contains('final transferFiles ='));
    expect(
      sendPickedFiles.indexOf('await gFFI.chatModel.sendFileRecord('),
      lessThan(
          sendPickedFiles.indexOf('await _ensureDirectFileSession(peerId)')),
    );
  });

  test('permission denial recognizes stable and legacy wire messages', () {
    expect(
        isDirectChatPermissionDenied('direct-chat-permission-denied'), isTrue);
    expect(
      isDirectChatPermissionDenied(
        'Direct messages rejected by this contact',
      ),
      isTrue,
    );
    expect(isDirectChatPermissionDenied('Remote desktop is offline'), isFalse);
  });

  group('direct chat access policy', () {
    test('history alone never promotes a peer to friend', () {
      final policy = DirectChatPolicySnapshot(
        audience: DirectChatAudience.friendsOnly,
        peerPolicies: const <String, String>{},
      );

      expect(policy.isFriend('history-peer'), isFalse);
      expect(
        policy.acceptsIncomingChat(
          'history-peer',
          identityVerified: true,
        ),
        isFalse,
      );
    });

    test('explicit friend is accepted in friends-only mode', () {
      final policy = DirectChatPolicySnapshot(
        audience: DirectChatAudience.friendsOnly,
        peerPolicies: const <String, String>{'friend-peer': 'allow'},
      );

      expect(policy.isFriend('friend-peer'), isTrue);
      expect(
        policy.acceptsIncomingChat(
          'friend-peer',
          identityVerified: true,
        ),
        isTrue,
      );
    });

    test('verified stranger is accepted only in everyone mode', () {
      final friendsOnly = DirectChatPolicySnapshot(
        audience: DirectChatAudience.friendsOnly,
        peerPolicies: const <String, String>{},
      );
      final everyone = DirectChatPolicySnapshot(
        audience: DirectChatAudience.everyone,
        peerPolicies: const <String, String>{},
      );

      expect(
        friendsOnly.acceptsIncomingChat(
          'stranger-peer',
          identityVerified: true,
        ),
        isFalse,
      );
      expect(
        everyone.acceptsIncomingChat(
          'stranger-peer',
          identityVerified: true,
        ),
        isTrue,
      );
      expect(
        everyone.acceptsIncomingChat(
          'stranger-peer',
          identityVerified: false,
        ),
        isFalse,
      );
    });

    test('deny always overrides global audience', () {
      final policy = DirectChatPolicySnapshot(
        audience: DirectChatAudience.everyone,
        peerPolicies: const <String, String>{'blocked-peer': 'deny'},
      );

      expect(
        policy.acceptsIncomingChat(
          'blocked-peer',
          identityVerified: true,
        ),
        isFalse,
      );
    });

    test('background reconnect requires previous acceptance and no denial', () {
      final policy = DirectChatPolicySnapshot(
        audience: DirectChatAudience.everyone,
        peerPolicies: const <String, String>{
          'friend-peer': 'allow',
          'blocked-peer': 'deny',
        },
      );

      expect(
        policy.shouldAutoReconnect(
          'friend-peer',
          previouslyAccepted: true,
        ),
        isTrue,
      );
      expect(
        policy.shouldAutoReconnect(
          'friend-peer',
          previouslyAccepted: false,
        ),
        isFalse,
      );
      expect(
        policy.shouldAutoReconnect(
          'stranger-peer',
          previouslyAccepted: true,
        ),
        isTrue,
      );
      expect(
        policy.shouldAutoReconnect(
          'blocked-peer',
          previouslyAccepted: true,
        ),
        isFalse,
      );
    });
  });
}
