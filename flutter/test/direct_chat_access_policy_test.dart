import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat_policy.dart';

void main() {
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

    test('background reconnect requires friend and previous acceptance', () {
      final policy = DirectChatPolicySnapshot(
        audience: DirectChatAudience.everyone,
        peerPolicies: const <String, String>{'friend-peer': 'allow'},
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
        isFalse,
      );
    });
  });
}
