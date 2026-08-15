import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/models/chat_model.dart';

void main() {
  group('ChatModel.computeRange (Shift-click continuous multi-select)', () {
    const ids = <String>['m1', 'm2', 'm3', 'm4', 'm5'];

    test('selects forward range between anchor and target', () {
      expect(
        ChatModel.computeRange(ids, 'm1', 'm3'),
        <String>['m1', 'm2', 'm3'],
      );
    });

    test('selects backward range between anchor and target', () {
      expect(
        ChatModel.computeRange(ids, 'm5', 'm3'),
        <String>['m3', 'm4', 'm5'],
      );
    });

    test('anchor equal to target selects a single message', () {
      expect(ChatModel.computeRange(ids, 'm3', 'm3'), <String>['m3']);
    });

    test('degenerates to single select when target is absent', () {
      expect(ChatModel.computeRange(ids, 'm2', 'm9'), <String>['m9']);
    });

    test('full range covers the whole list', () {
      expect(
        ChatModel.computeRange(ids, 'm1', 'm5'),
        <String>['m1', 'm2', 'm3', 'm4', 'm5'],
      );
    });
  });
}
