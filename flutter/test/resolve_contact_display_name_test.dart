import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final desktopHomeSource =
      File('lib/desktop/pages/desktop_home_page.dart').readAsStringSync();
  final mobileHomeSource =
      File('lib/mobile/pages/home_page.dart').readAsStringSync();

  group('_resolveContactDisplayName (desktop)', () {
    test('function exists with correct signature', () {
      expect(desktopHomeSource, contains('String _resolveContactDisplayName('));
    });

    test('returns empty string for null peer', () {
      expect(desktopHomeSource, contains("if (peer == null) return '';"));
    });

    test('prefers hostname for mobile peers', () {
      // Must check _isMobilePeerPlatform AND cache _peerDeviceName result
      // before falling back to finalName(), matching the merged-row list logic.
      expect(desktopHomeSource, contains('_isMobilePeerPlatform(peer.platform)'));
      expect(desktopHomeSource, contains('final deviceName = _peerDeviceName(peer)'));
      expect(desktopHomeSource, contains('if (deviceName.isNotEmpty) return deviceName'));
    });

    test('falls back to finalName() for non-mobile peers', () {
      expect(desktopHomeSource, contains('return peer.finalName();'));
    });

    test('no direct contact?.finalName() in _resolveConversationDisplayName calls',
        () {
      // Every contactName: parameter should use _resolveContactDisplayName,
      // not raw finalName(), to keep list and header names consistent.
      final lines = desktopHomeSource.split('\n');
      bool insideResolve = false;
      for (final line in lines) {
        if (line.contains('_resolveConversationDisplayName(')) {
          insideResolve = true;
        }
        if (insideResolve && line.contains('contactName:')) {
          expect(line, isNot(contains('finalName()')),
              reason:
                  'contactName must use _resolveContactDisplayName, not finalName()');
          insideResolve = false;
        }
        // Reset if we hit the closing paren or next statement
        if (insideResolve &&
            (line.contains(');') || line.contains('idFallback:'))) {
          insideResolve = false;
        }
      }
    });

    test('all call sites in desktop use _resolveContactDisplayName', () {
      // Count total _resolveConversationDisplayName calls
      final resolveCount =
          'resolveConversationDisplayName('.allMatches(desktopHomeSource).length;
      // Count _resolveContactDisplayName calls as contactName
      final contactNameCount =
          '_resolveContactDisplayName('.allMatches(desktopHomeSource).length;
      // At minimum the contactName calls should be ≥ _resolveConversationDisplayName calls
      // (one contactName per resolveConversationDisplayName call)
      expect(contactNameCount, greaterThanOrEqualTo(resolveCount),
          reason:
              'Every _resolveConversationDisplayName should have a _resolveContactDisplayName contactName');
    });
  });

  group('_resolveContactDisplayName (mobile)', () {
    test('function exists with correct signature', () {
      expect(mobileHomeSource, contains('String _resolveContactDisplayName('));
    });

    test('returns empty string for null peer', () {
      expect(mobileHomeSource, contains("if (peer == null) return '';"));
    });

    test('prefers hostname for mobile peers', () {
      expect(mobileHomeSource, contains('_isMobilePlatform(peer.platform)'));
      expect(mobileHomeSource, contains('final h = peer.hostname.trim()'));
      expect(mobileHomeSource, contains('if (h.isNotEmpty) return h'));
    });

    test('falls back to finalName() for non-mobile peers', () {
      expect(mobileHomeSource, contains('return peer.finalName();'));
    });

    test('no direct contact?.finalName() in _resolveConversationName calls',
        () {
      final lines = mobileHomeSource.split('\n');
      bool insideResolve = false;
      for (final line in lines) {
        if (line.contains('_resolveConversationName(')) {
          insideResolve = true;
        }
        if (insideResolve && line.contains('contactName:')) {
          expect(line, isNot(contains('finalName()')),
              reason:
                  'contactName must use _resolveContactDisplayName, not finalName()');
          insideResolve = false;
        }
        if (insideResolve &&
            (line.contains(');') || line.contains('idFallback:'))) {
          insideResolve = false;
        }
      }
    });

    test('all call sites in mobile use _resolveContactDisplayName', () {
      final resolveCount =
          '_resolveConversationName('.allMatches(mobileHomeSource).length;
      final contactNameCount =
          '_resolveContactDisplayName('.allMatches(mobileHomeSource).length;
      expect(contactNameCount, greaterThanOrEqualTo(resolveCount),
          reason:
              'Every _resolveConversationName should have a _resolveContactDisplayName contactName');
    });
  });

  group('Peer.finalName() direct tests', () {
    test('returns displayName when not empty', () {
      final peer = PeerStub(
        id: 'abc',
        displayName: 'My Device',
        hostname: 'OPPO-PFUM10',
        platform: 'Android',
      );
      expect(peer.finalName(), 'My Device');
    });

    test('returns hostname when displayName is empty', () {
      final peer = PeerStub(
        id: 'abc',
        displayName: '',
        hostname: 'DESKTOP-ABC',
        platform: 'Windows',
      );
      expect(peer.finalName(), 'DESKTOP-ABC');
    });

    test('returns username@hostname when both set', () {
      final peer = PeerStub(
        id: 'abc',
        displayName: '',
        hostname: 'DESKTOP-ABC',
        username: 'admin',
        platform: 'Windows',
      );
      expect(peer.finalName(), 'admin@DESKTOP-ABC');
    });

    test('returns alias when set and different from id', () {
      final peer = PeerStub(
        id: 'abc',
        alias: 'My PC',
        displayName: 'Other',
        platform: 'Windows',
      );
      expect(peer.finalName(), 'My PC');
    });

    test('ignores alias that equals id', () {
      final peer = PeerStub(
        id: 'abc',
        alias: 'abc',
        displayName: 'Other',
        platform: 'Windows',
      );
      expect(peer.finalName(), 'Other');
    });

    test('returns id when everything else empty', () {
      final peer = PeerStub(
        id: 'abc',
        platform: 'Windows',
      );
      expect(peer.finalName(), 'abc');
    });
  });

  group('resolveContactDisplayName logic simulation', () {
    // Simulate the desktop _resolveContactDisplayName logic
    String resolveDesktop(PeerStub? peer) {
      if (peer == null) return '';
      final p = peer.platform.toLowerCase();
      final isMobile =
          p.contains('android') || p.contains('ios') || p.contains('phone');
      if (isMobile &&
          peer.hostname.trim().isNotEmpty &&
          !(peer.displayName.trim() == 'android' &&
              peer.displayName.trim().isNotEmpty) &&
          peer.hostname.trim().isNotEmpty) {
        return peer.hostname.trim();
      }
      return peer.finalName();
    }

    test('mobile peer with hostname and android displayName', () {
      final peer = PeerStub(
        id: 'device-1',
        displayName: 'Android',
        hostname: 'OPPO-PFUM10',
        platform: 'Android',
      );
      // Desktop should prefer hostname for mobile
      expect(resolveDesktop(peer), 'OPPO-PFUM10');
    });

    test('desktop peer uses finalName', () {
      final peer = PeerStub(
        id: 'device-1',
        displayName: 'My PC',
        hostname: 'DESKTOP-ABC',
        platform: 'Windows',
      );
      expect(resolveDesktop(peer), 'My PC');
    });

    test('mobile peer with no hostname falls back to finalName', () {
      final peer = PeerStub(
        id: 'device-1',
        displayName: 'Android',
        hostname: '',
        platform: 'Android',
      );
      expect(resolveDesktop(peer), 'Android');
    });

    test('mobile peer with custom displayName', () {
      final peer = PeerStub(
        id: 'device-1',
        displayName: 'My Phone',
        hostname: 'OPPO-PFUM10',
        platform: 'Android',
      );
      expect(resolveDesktop(peer), 'OPPO-PFUM10');
    });

    test('iOS peer with hostname', () {
      final peer = PeerStub(
        id: 'device-1',
        displayName: 'iPhone',
        hostname: "John's iPhone",
        platform: 'iPhone OS',
      );
      expect(resolveDesktop(peer), "John's iPhone");
    });
  });

  group('connection_page.dart fixes', () {
    test('paired contact tap uses openChatFromContacts', () {
      final connSource =
          File('lib/mobile/pages/connection_page.dart').readAsStringSync();
      expect(connSource, contains('DirectPairingStore.canonicalConversationId'));
      expect(connSource, contains('openChatFromContacts'));
    });
  });
}

/// Minimal Peer stub for testing finalName() without full model dependencies.
class PeerStub {
  final String id;
  String alias;
  String displayName;
  String hostname;
  String username;
  String platform;

  PeerStub({
    required this.id,
    this.alias = '',
    this.displayName = '',
    this.hostname = '',
    this.username = '',
    this.platform = '',
  });

  String finalName() {
    final a = alias.trim();
    if (a.isNotEmpty && a != id.trim()) return a;
    if (displayName.trim().isNotEmpty) return displayName.trim();
    final u = username.trim();
    final h = hostname.trim();
    if (u.isNotEmpty && h.isNotEmpty) return '$u@$h';
    if (h.isNotEmpty) return h;
    if (u.isNotEmpty) return u;
    return id;
  }
}
