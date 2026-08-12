import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';

DirectPairing _pairing({
  required String peerId,
  String displayName = '',
  String lanEndpoint = '192.168.31.10:21118',
  String fingerprint = 'AA:BB:CC',
  String accountId = '',
  String avatar = '',
}) =>
    DirectPairing(
      peerId: peerId,
      displayName: displayName,
      lanEndpoint: lanEndpoint,
      publicEndpoint: '',
      fingerprint: fingerprint,
      updatedAt: DateTime.utc(2026, 8, 8),
      accountId: accountId,
      avatar: avatar,
    );

final _t1 = DateTime.utc(2026, 8, 1);
final _t2 = DateTime.utc(2026, 8, 10);

void main() {
  group('DirectPairingStore.normalizeBluetoothPeerId', () {
    test('accepts bt: peer ids with and without inner colons', () {
      expect(
        DirectPairingStore.normalizeBluetoothPeerId('bt:AA:BB:CC:DD:EE:FF'),
        'bt:AABBCCDDEEFF',
      );
      expect(
        DirectPairingStore.normalizeBluetoothPeerId('bt:aabbccddeeff'),
        'bt:AABBCCDDEEFF',
      );
      expect(
        DirectPairingStore.normalizeBluetoothPeerId('BT:AABBCCDDEEFF'),
        'bt:AABBCCDDEEFF',
      );
    });

    test('accepts raw MACs', () {
      expect(
        DirectPairingStore.normalizeBluetoothPeerId('AA:BB:CC:DD:EE:FF'),
        'bt:AABBCCDDEEFF',
      );
      expect(
        DirectPairingStore.normalizeBluetoothPeerId('aabbccddeeff'),
        'bt:AABBCCDDEEFF',
      );
    });

    test('rejects non-MAC values', () {
      expect(DirectPairingStore.normalizeBluetoothPeerId(''), '');
      expect(DirectPairingStore.normalizeBluetoothPeerId('bt:ZZ'), '');
      expect(
        DirectPairingStore.normalizeBluetoothPeerId('bt:AABBCCDDEE'),
        '',
      );
      expect(
        DirectPairingStore.normalizeBluetoothPeerId('192.168.31.10:21118'),
        '',
      );
    });
  });

  group('DirectPairingStore.realDeviceIdValue', () {
    test('bridges a stale conversation id to the real device id', () {
      final pairings = <String, DirectPairing>{
        '423156': _pairing(
          peerId: '423156',
          displayName: 'A',
          accountId: '999986',
        ),
      };
      expect(
        DirectPairingStore.realDeviceIdValue('999986', pairings: pairings),
        '423156',
      );
      expect(
        DirectPairingStore.realDeviceIdValue('423156', pairings: pairings),
        '423156',
      );
      expect(
        DirectPairingStore.realDeviceIdValue('980966', pairings: pairings),
        '980966',
      );
    });
  });

  group('DirectPairingStore.migrateStalePairingValue', () {
    test('migrates the pairing keyed by the stale account id', () {
      final pairings = <String, DirectPairing>{
        '999986': _pairing(
          peerId: '999986',
          displayName: '????A',
          fingerprint: 'aa:bb:cc',
          avatar: 'avatar-1',
        ),
      };
      final (migrated, staleKey) =
          DirectPairingStore.migrateStalePairingValue(
        pairings,
        peerId: '423156',
        accountId: '999986',
        fingerprint: 'AA:BB:CC',
      );
      expect(staleKey, '999986');
      expect(migrated, isNotNull);
      expect(migrated!.peerId, '423156');
      expect(migrated.displayName, '????A');
      expect(migrated.avatar, 'avatar-1');
      expect(migrated.accountId, '999986');
    });

    test('migrates any pairing with an identical fingerprint', () {
      final pairings = <String, DirectPairing>{
        '999986': _pairing(
          peerId: '999986',
          displayName: 'A',
          fingerprint: '11:22:33:44',
        ),
      };
      final (migrated, staleKey) =
          DirectPairingStore.migrateStalePairingValue(
        pairings,
        peerId: '423156',
        accountId: '',
        fingerprint: '11223344',
      );
      expect(staleKey, '999986');
      expect(migrated!.peerId, '423156');
      expect(migrated.accountId, '999986');
    });

    test('does not migrate when fingerprints differ', () {
      final pairings = <String, DirectPairing>{
        '999986': _pairing(
          peerId: '999986',
          displayName: 'A',
          fingerprint: 'aa:bb:cc',
        ),
      };
      final (migrated, staleKey) =
          DirectPairingStore.migrateStalePairingValue(
        pairings,
        peerId: '423156',
        accountId: '999986',
        fingerprint: 'DE:AD:BE:EF',
      );
      expect(migrated, isNull);
      expect(staleKey, isNull);
    });

    test('keeps an existing account binding on the migrated pairing', () {
      final pairings = <String, DirectPairing>{
        '777777': _pairing(
          peerId: '777777',
          displayName: 'B',
          fingerprint: '11:22:33:44',
          accountId: 'old-account',
        ),
      };
      final (migrated, staleKey) =
          DirectPairingStore.migrateStalePairingValue(
        pairings,
        peerId: '888888',
        accountId: '',
        fingerprint: '11:22:33:44',
      );
      expect(staleKey, '777777');
      expect(migrated!.accountId, 'old-account');
    });
  });


  group('DirectPairing legacy shared-port fallback', () {
    test('legacy shared ports are detected', () {
      expect(DirectPairingStore.isLegacySharedDirectEndpoint('192.168.31.10:21118'), isTrue);
      expect(DirectPairingStore.isLegacySharedDirectEndpoint('36.134.211.189:21128'), isTrue);
      expect(DirectPairingStore.isLegacySharedDirectEndpoint('192.168.31.10:20830'), isTrue);
      expect(DirectPairingStore.isLegacySharedDirectEndpoint('192.168.31.42:37794'), isFalse);
      expect(DirectPairingStore.isLegacySharedDirectEndpoint('192.168.31.42'), isFalse);
    });

    test('only-legacy endpoints fall back to bare-ID dialing', () {
      final pairing = _pairing(
        peerId: '423156',
        lanEndpoint: '192.168.31.199:21118',
        fingerprint: 'AA:BB:CC',
      );
      expect(pairing.preferredEndpoint, isEmpty);
      expect(pairing.connectionTarget, '423156?key=AABBCC');
    });

    test('fresh machine-unique endpoint is preferred over legacy history', () {
      final pairing = DirectPairing(
        peerId: '423156',
        displayName: 'A',
        lanEndpoint: '192.168.31.199:21118',
        publicEndpoint: '',
        fingerprint: 'AA:BB:CC',
        updatedAt: DateTime.utc(2026, 8, 8),
        endpointHistory: <DirectEndpointObservation>[
          DirectEndpointObservation(
            endpoint: '192.168.31.199:21118',
            firstSeenAt: _t1,
            lastSeenAt: _t1,
            connectionCount: 65,
            secure: true,
            streamType: 'TCP',
          ),
          DirectEndpointObservation(
            endpoint: '192.168.31.42:37794',
            firstSeenAt: _t2,
            lastSeenAt: _t2,
            connectionCount: 3,
            secure: true,
            streamType: 'TCP',
          ),
        ],
      );
      expect(pairing.preferredEndpoint, '192.168.31.42:37794');
      expect(pairing.connectionTarget,
          '423156@192.168.31.42:37794?key=AABBCC&fallback=192.168.31.199:21118');
    });
  });
}
