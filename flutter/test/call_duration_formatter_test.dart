import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/formatter/call_duration.dart';

void main() {
  group('formatCallDuration', () {
    test('formats zero and short durations as halfwidth MM:SS', () {
      expect(formatCallDuration(0), '00:00');
      expect(formatCallDuration(1), '00:01');
      expect(formatCallDuration(9), '00:09');
      expect(formatCallDuration(12), '00:12');
    });

    test('formats minutes and preserves two digit seconds', () {
      expect(formatCallDuration(60), '01:00');
      expect(formatCallDuration(72), '01:12');
      expect(formatCallDuration(4 * 60 + 52), '04:52');
      expect(formatCallDuration(59 * 60 + 59), '59:59');
    });

    test('allows durations longer than one hour without wrapping minutes', () {
      expect(formatCallDuration(60 * 60), '60:00');
      expect(formatCallDuration(60 * 60 + 7), '60:07');
      expect(formatCallDuration(125 * 60 + 3), '125:03');
    });

    test('clamps negative input to zero', () {
      expect(formatCallDuration(-1), '00:00');
      expect(formatCallDuration(-3600), '00:00');
    });

    test('never emits fullwidth digits or punctuation', () {
      final value = formatCallDuration(4 * 60 + 5);
      expect(value, '04:05');
      expect(value, isNot(contains('：')));
      expect(value, isNot(matches(RegExp(r'[０-９]'))));
    });
  });
}
