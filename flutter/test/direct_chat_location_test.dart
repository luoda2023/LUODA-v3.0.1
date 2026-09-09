import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';

void main() {
  group('DirectChatLocation.encode', () {
    test('formats latitude and longitude to six decimal places', () {
      const location = DirectChatLocation(
        latitude: 31.230416,
        longitude: 121.473701,
        name: '人民广场',
      );

      expect(
        location.encode(),
        '[location]31.230416,121.473701|人民广场',
      );
    });

    test('encodes negative coordinates and name with address', () {
      const location = DirectChatLocation(
        latitude: -33.868820,
        longitude: 151.209290,
        name: 'Sydney',
        address: '1 George Street',
      );

      expect(
        location.encode(),
        '[location]-33.868820,151.209290|Sydney|1 George Street',
      );
    });

    test('trims name and address and omits empty separators', () {
      const location = DirectChatLocation(
        latitude: 0,
        longitude: 0,
        name: '  Origin  ',
        address: '  ',
      );

      expect(location.encode(), '[location]0.000000,0.000000|Origin');
    });
  });

  group('DirectChatLocation.tryParse', () {
    test('parses coordinates without a name', () {
      final location = DirectChatLocation.tryParse(
        '[location]31.230416,121.473701',
      );

      expect(location, isNotNull);
      expect(location!.latitude, closeTo(31.230416, 0.0000001));
      expect(location.longitude, closeTo(121.473701, 0.0000001));
      expect(location.name, isEmpty);
      expect(location.address, isEmpty);
    });

    test('parses the legacy name-only format', () {
      final location = DirectChatLocation.tryParse(
        '[location]31.230416,121.473701|人民广场',
      );

      expect(location, isNotNull);
      expect(location!.name, '人民广场');
      expect(location.address, isEmpty);
    });

    test('parses the new name|address format', () {
      final location = DirectChatLocation.tryParse(
        '[location]31.230416,121.473701|人民广场|上海市黄浦区人民大道',
      );

      expect(location, isNotNull);
      expect(location!.latitude, closeTo(31.230416, 0.0000001));
      expect(location.longitude, closeTo(121.473701, 0.0000001));
      expect(location.name, '人民广场');
      expect(location.address, '上海市黄浦区人民大道');
    });

    test('trims outer whitespace around the payload and fields', () {
      final location = DirectChatLocation.tryParse(
        '  [location]-33.868820,151.209290| Sydney | 1 George Street  ',
      );

      expect(location, isNotNull);
      expect(location!.latitude, closeTo(-33.868820, 0.0000001));
      expect(location.longitude, closeTo(151.209290, 0.0000001));
      expect(location.name, 'Sydney');
      expect(location.address, '1 George Street');
    });

    test('rejects latitude and longitude outside valid ranges', () {
      expect(
        DirectChatLocation.tryParse('[location]90.000001,0'),
        isNull,
      );
      expect(
        DirectChatLocation.tryParse('[location]-90.000001,0'),
        isNull,
      );
      expect(
        DirectChatLocation.tryParse('[location]0,180.000001'),
        isNull,
      );
      expect(
        DirectChatLocation.tryParse('[location]0,-180.000001'),
        isNull,
      );
    });

    test('rejects malformed or non-location payloads', () {
      expect(DirectChatLocation.tryParse('普通消息'), isNull);
      expect(DirectChatLocation.tryParse('[location]abc,121.4'), isNull);
      expect(DirectChatLocation.tryParse('[location]31.2'), isNull);
      expect(DirectChatLocation.tryParse('[location]31.2,'), isNull);
    });
  });

  group('round-trip', () {
    test('new name|address format survives encode and parse', () {
      const source = DirectChatLocation(
        latitude: 0.123456,
        longitude: -179.654321,
        name: 'Point',
        address: 'Somewhere',
      );
      final restored = DirectChatLocation.tryParse(source.encode());

      expect(restored, isNotNull);
      expect(restored!.latitude, closeTo(source.latitude, 0.0000001));
      expect(restored.longitude, closeTo(source.longitude, 0.0000001));
      expect(restored.name, source.name);
      expect(restored.address, source.address);
    });

    test('isDecoded is false only for the origin coordinate', () {
      expect(
        const DirectChatLocation(latitude: 0, longitude: 0).isDecoded,
        isFalse,
      );
      expect(
        const DirectChatLocation(latitude: 0, longitude: 1).isDecoded,
        isTrue,
      );
    });
  });
}
