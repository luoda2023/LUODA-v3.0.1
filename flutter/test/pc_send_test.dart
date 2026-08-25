import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';

void main() {
  test('resolveConnectionTarget returns non-null for ID-only peer', () {
    // A device ID like "835149" should resolve to itself
    // (not null) so _startDirectChat can dial it.
    final result = DirectPairingStore.resolveConnectionTargetValue(
      '835149',
      pairings: {},
    );
    print('resolveConnectionTarget("835149") = $result');
    expect(result, isNotNull);
  });
}
