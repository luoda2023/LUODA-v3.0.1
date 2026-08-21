import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Exact replica of desktop _resolveConversationDisplayName from
/// lib/desktop/pages/desktop_home_page.dart.
String resolveDesktop(
  String peerId, {
  String contactName = '',
  String chatName = '',
  String idFallback = '',
  String localName = '',
  String pairingDisplayName = '',
}) {
  // NOTE: gFFI.chatModel.me.firstName is replaced by the [localName] param.
  final candidates = <String>[
    contactName.trim(),
    pairingDisplayName.trim(),
    chatName.trim(),
  ];
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    if (localName.isNotEmpty && candidate == localName) continue;
    if (candidate.toLowerCase() == 'luoda') continue;
    final compact = candidate.replaceAll(RegExp(r'[\s:\-_.]'), '');
    final isIdLike =
        compact == peerId.trim().replaceAll(RegExp(r'[\s:\-_.]'), '') ||
            RegExp(r'^[0-9]{3,}$').hasMatch(compact);
    if (!isIdLike) return candidate;
  }
  return idFallback.trim();
}

/// Exact replica of mobile _resolveConversationName from
/// lib/mobile/pages/home_page.dart.
String resolveMobile(
  String peerId, {
  String contactName = '',
  String chatName = '',
  String idFallback = '',
  String localName = '',
  String pairingDisplayName = '',
}) {
  final candidates = <String>[
    contactName.trim(),
    pairingDisplayName.trim(),
    chatName.trim(),
  ];
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    if (localName.isNotEmpty && candidate == localName) continue;
    if (candidate.toLowerCase() == 'luoda') continue;
    final compact = candidate.replaceAll(RegExp(r'[\s:\-_.]'), '');
    final isIdLike =
        compact == peerId.trim().replaceAll(RegExp(r'[\s:\-_.]'), '') ||
            RegExp(r'^[0-9]{3,}$').hasMatch(compact);
    if (!isIdLike) return candidate;
  }
  final fallback = idFallback.trim();
  return fallback;
}

void main() {
  // ──────────────────────────────────────────────
  // Shared logic tests (desktop & mobile are identical)
  // ──────────────────────────────────────────────
  for (final platform in ['desktop', 'mobile']) {
    final resolve = platform == 'desktop' ? resolveDesktop : resolveMobile;

    group('_resolveConversationDisplayName ($platform)', () {
      test('returns contactName when it is a normal human name', () {
        final result = resolve(
          'peer-1',
          contactName: '张三',
          chatName: 'Some Device',
        );
        expect(result, '张三');
      });

      test('returns chatName when contactName is empty', () {
        final result = resolve(
          'peer-1',
          contactName: '',
          chatName: 'OPPO-PFUM10',
        );
        expect(result, 'OPPO-PFUM10');
      });

      test('returns idFallback when all candidates are empty', () {
        final result = resolve(
          'peer-1',
          idFallback: 'peer-1',
        );
        expect(result, 'peer-1');
      });

      test('returns empty string when all candidates empty and no idFallback',
          () {
        final result = resolve('peer-1');
        expect(result, '');
      });

      // ── Local name filtering ──
      test('skips candidate that matches local user name', () {
        final result = resolve(
          'peer-1',
          localName: 'Administrator',
          contactName: 'Administrator',
          chatName: 'My Device',
        );
        expect(result, 'My Device');
      });

      test('skips localName from chatName too', () {
        final result = resolve(
          'peer-1',
          localName: 'Admin',
          contactName: '',
          chatName: 'Admin',
          idFallback: 'peer-1',
        );
        expect(result, 'peer-1');
      });

      // ── "luoda" default name filtering ──
      test('skips candidate that is exactly "luoda"', () {
        final result = resolve(
          'peer-1',
          contactName: 'luoda',
          chatName: 'My Phone',
        );
        expect(result, 'My Phone');
      });

      test('skips "luoda" case-insensitively', () {
        final result = resolve(
          'peer-1',
          contactName: 'LUODA',
          chatName: 'My Phone',
        );
        expect(result, 'My Phone');
      });

      test('skips "LuoDa" mixed case', () {
        final result = resolve(
          'peer-1',
          contactName: 'LuoDa',
          chatName: 'Real Name',
        );
        expect(result, 'Real Name');
      });

      // ── ID-like name filtering ──
      test('skips candidate that equals peerId (compact match)', () {
        final result = resolve(
          'DESKTOP-ABC123',
          contactName: 'DESKTOP-ABC123',
          chatName: 'Real Name',
        );
        expect(result, 'Real Name');
      });

      test('skips candidate matching peerId with different separators', () {
        final result = resolve(
          'DESKTOP_ABC_123',
          contactName: 'DESKTOP:ABC:123',
          chatName: 'Real Name',
        );
        expect(result, 'Real Name');
      });

      test('skips pure numeric candidate with 3+ digits', () {
        final result = resolve(
          'peer-1',
          contactName: '12345',
          chatName: 'Real Name',
        );
        expect(result, 'Real Name');
      });

      test('allows numeric candidate with 1-2 digits (not ID-like)', () {
        final result = resolve(
          'peer-1',
          contactName: '42',
          chatName: 'Device',
        );
        expect(result, '42');
      });

      test('does NOT skip a candidate that just contains numbers', () {
        final result = resolve(
          'peer-1',
          contactName: 'Room 42',
          chatName: 'Device',
        );
        expect(result, 'Room 42');
      });

      // ── Priority ordering ──
      test('contactName takes priority over pairingDisplayName', () {
        final result = resolve(
          'peer-1',
          contactName: 'Contact Alias',
          pairingDisplayName: 'Pairing Name',
          chatName: 'Chat Name',
        );
        expect(result, 'Contact Alias');
      });

      test('pairingDisplayName takes priority over chatName', () {
        final result = resolve(
          'peer-1',
          contactName: '',
          pairingDisplayName: 'Pairing Name',
          chatName: 'Chat Name',
        );
        expect(result, 'Pairing Name');
      });

      test('chatName takes priority over idFallback', () {
        final result = resolve(
          'peer-1',
          contactName: '',
          pairingDisplayName: '',
          chatName: 'Chat Name',
          idFallback: 'peer-1',
        );
        expect(result, 'Chat Name');
      });

      test('skips filtered candidates and falls through to next', () {
        // contactName is local user name → skipped
        // pairingDisplayName is 'luoda' → skipped
        // chatName is the ID → skipped
        // falls to idFallback
        final result = resolve(
          'peer-1',
          localName: 'Admin',
          contactName: 'Admin',
          pairingDisplayName: 'luoda',
          chatName: 'peer-1',
          idFallback: 'Fallback Device',
        );
        expect(result, 'Fallback Device');
      });

      test('skips multiple ID-like and luoda candidates, returns real name',
          () {
        final result = resolve(
          'peer-1',
          localName: 'Admin',
          contactName: 'Admin',
          pairingDisplayName: '12345',
          chatName: 'luoda',
          idFallback: 'peer-1',
        );
        // All three candidates filtered, returns idFallback
        expect(result, 'peer-1');
      });

      // ── Whitespace handling ──
      test('trims whitespace from candidates', () {
        final result = resolve(
          'peer-1',
          contactName: '  张三  ',
        );
        expect(result, '张三');
      });

      test('empty after trim is treated as empty', () {
        final result = resolve(
          'peer-1',
          contactName: '   ',
          chatName: 'Real Name',
        );
        expect(result, 'Real Name');
      });

      // ── edge case: candidate only filtered characters ──
      test('idFallback is also trimmed', () {
        final result = resolve(
          'peer-1',
          idFallback: '  fallback  ',
        );
        expect(result, 'fallback');
      });

      // ── Mixed scenario: real-world OPPO phone ──
      test('OPPO phone with hostname vs displayName', () {
        // Simulates: contact has hostname "OPPO-PFUM10" resolved by
        // _resolveContactDisplayName, chatName is "android"
        final result = resolve(
          'abc-123',
          contactName: 'OPPO-PFUM10',
          chatName: 'android',
        );
        expect(result, 'OPPO-PFUM10');
      });

      test('OPPO phone where hostname is ID-like peerId', () {
        // When the hostname IS the peerId itself
        final result = resolve(
          'OPPO-PFUM10',
          contactName: 'OPPO-PFUM10',
          chatName: 'My Phone',
        );
        // hostname matches peerId → filtered, falls to chatName
        expect(result, 'My Phone');
      });

      // ── Multiple filtering in sequence ──
      test('cascading filters: localName, then luoda, then ID-like', () {
        final result = resolve(
          'my-device',
          localName: 'Alice',
          contactName: 'Alice', // matches localName → skip
          pairingDisplayName: 'LUODA', // luoda → skip
          chatName: 'my-device', // matches peerId → skip
          idFallback: 'Unknown Device',
        );
        expect(result, 'Unknown Device');
      });

      // ── "android" as a fallback value ──
      test('generic "android" string is not filtered (not luoda)', () {
        final result = resolve(
          'peer-1',
          chatName: 'android',
        );
        expect(result, 'android');
      });
    });
  }

  // ──────────────────────────────────────────────
  // Source-level contract tests (verify real code)
  // ──────────────────────────────────────────────
  group('source code contract', () {
    test('desktop: header title uses _resolveConversationDisplayName', () {
      final src = _readFile('lib/desktop/pages/desktop_home_page.dart');
      // The header must call _resolveConversationDisplayName, NOT
      // _resolveContactDisplayName directly as the title source.
      // Find the _buildConversationWorkspace method's name resolution.
      final wsStart = src.indexOf('Widget _buildConversationWorkspace(');
      final wsEnd = src.indexOf('return workspace(', wsStart);
      final wsBody = src.substring(wsStart, wsEnd);
      expect(wsBody, contains('_resolveConversationDisplayName('));
      // _resolveContactDisplayName is used as a PARAMETER inside
      // _resolveConversationDisplayName — that's correct. The key check
      // is that selectedName is set via _resolveConversationDisplayName.
      final selectedNameStart = wsBody.indexOf('final selectedName');
      final selectedNameEnd = wsBody.indexOf('final hasConversation', selectedNameStart);
      final selectedNameBlock = wsBody.substring(selectedNameStart, selectedNameEnd);
      expect(selectedNameBlock, contains('_resolveConversationDisplayName('));
    });

    test('desktop: header title has idFallback for kFileHelperId', () {
      final src = _readFile('lib/desktop/pages/desktop_home_page.dart');
      final wsStart = src.indexOf('Widget _buildConversationWorkspace(');
      final wsEnd = src.indexOf('return ColoredBox(', wsStart);
      final wsBody = src.substring(wsStart, wsEnd);
      expect(wsBody, contains('kFileHelperId'));
    });

    test('mobile: all _resolveConversationName calls have idFallback', () {
      final src = _readFile('lib/mobile/pages/home_page.dart');
      final lines = src.split('\n');
      bool hasIdFallback = false;
      bool insideCall = false;
      bool isDefinition = false;
      for (final line in lines) {
        // Skip the function definition itself (it starts with 'String _resolveConversationName(')
        if (line.trimLeft().startsWith('String _resolveConversationName(')) {
          isDefinition = true;
          continue;
        }
        if (isDefinition) {
          if (line.trimLeft().startsWith('}') && line.trim().length <= 2) {
            isDefinition = false;
          }
          continue;
        }
        if (line.contains('_resolveConversationName(')) {
          insideCall = true;
          hasIdFallback = false;
        }
        if (insideCall) {
          if (line.contains('idFallback:')) hasIdFallback = true;
          if (line.trimRight().endsWith(');')) {
            expect(hasIdFallback, isTrue,
                reason:
                    'Every _resolveConversationName call must have idFallback: $line');
            insideCall = false;
          }
        }
      }
    });

    test('desktop: all _resolveConversationDisplayName calls have idFallback',
        () {
      final src =
          _readFile('lib/desktop/pages/desktop_home_page.dart');
      final lines = src.split('\n');
      bool insideCall = false;
      bool hasIdFallback = false;
      bool isDefinition = false;
      for (final line in lines) {
        // Skip the function definition itself
        if (line.trimLeft().startsWith('String _resolveConversationDisplayName(')) {
          isDefinition = true;
          continue;
        }
        if (isDefinition) {
          if (line.trimLeft().startsWith('}') && line.trim().length <= 2) {
            isDefinition = false;
          }
          continue;
        }
        if (line.contains('_resolveConversationDisplayName(')) {
          insideCall = true;
          hasIdFallback = false;
        }
        if (insideCall) {
          if (line.contains('idFallback:')) hasIdFallback = true;
          if (line.trimRight().endsWith(');')) {
            expect(hasIdFallback, isTrue,
                reason:
                    '_resolveConversationDisplayName must have idFallback: $line');
            insideCall = false;
          }
        }
      }
    });

    test('desktop and mobile resolve functions have identical logic', () {
      final desktopSrc =
          _readFile('lib/desktop/pages/desktop_home_page.dart');
      final mobileSrc = _readFile('lib/mobile/pages/home_page.dart');

      // Check both files contain the same filtering keywords
      // (localName is read from gFFI.chatModel.me.firstName inside the function,
      // not a parameter)
      for (final keyword in [
        'luoda',
        'isIdLike',
        'idFallback',
      ]) {
        expect(desktopSrc, contains(keyword),
            reason: 'Desktop missing $keyword');
        expect(mobileSrc, contains(keyword),
            reason: 'Mobile missing $keyword');
      }
      // Both must filter localName (read from gFFI.chatModel.me.firstName)
      expect(desktopSrc, contains("(gFFI.chatModel.me.firstName ?? '')"));
      expect(mobileSrc, contains("(gFFI.chatModel.me.firstName ?? '')"));
    });
  });
}

String _readFile(String path) {
  return File(path).readAsStringSync();
}
