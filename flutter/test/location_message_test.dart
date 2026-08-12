import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';

void main() {
  group('DirectChatLocation encode/parse', () {
    test('round-trips coordinates with a name', () {
      const loc = DirectChatLocation(
        latitude: 30.2741,
        longitude: 120.1551,
        name: 'Hangzhou',
      );
      final encoded = loc.encode();
      expect(encoded, startsWith('[location]'));
      final parsed = DirectChatLocation.tryParse(encoded);
      expect(parsed, isNotNull);
      expect(parsed!.latitude, closeTo(30.2741, 0.000001));
      expect(parsed.longitude, closeTo(120.1551, 0.000001));
      expect(parsed.name, 'Hangzhou');
    });

    test('round-trips coordinates without a name', () {
      const loc = DirectChatLocation(latitude: -33.8688, longitude: 151.2093);
      final parsed = DirectChatLocation.tryParse(loc.encode());
      expect(parsed, isNotNull);
      expect(parsed!.name, isEmpty);
      expect(parsed.latitude, closeTo(-33.8688, 0.000001));
    });

    test('rejects malformed payloads', () {
      expect(DirectChatLocation.tryParse('hello world'), isNull);
      expect(DirectChatLocation.tryParse(''), isNull);
      expect(DirectChatLocation.tryParse('[location]abc,def'), isNull);
      expect(DirectChatLocation.tryParse('[location]'), isNull);
      // Out of range coordinates are rejected.
      expect(DirectChatLocation.tryParse('[location]95.0,120.0'), isNull);
      expect(DirectChatLocation.tryParse('[location]30.0,190.0'), isNull);
    });

    test('a normal chat message is not mistaken for a location', () {
      const text = 'Meet me at [location] near the station';
      expect(DirectChatLocation.tryParse(text), isNull);
    });
  });
}
