import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/utils/event_loop.dart';

enum _EventType { value }

class _Event extends BaseEvent<_EventType, int> {
  _Event(int data, this.onConsume) : super(_EventType.value, data);

  final Future<void> Function(int value) onConsume;

  @override
  EventCallback<int>? findCallback(_EventType type) => onConsume;
}

class _Loop extends BaseEventLoop<_EventType, int> {}

void main() {
  test('events begin draining immediately without an idle polling delay',
      () async {
    final loop = _Loop();
    final consumed = Completer<void>();

    await loop.onReady();
    loop.pushEvent(_Event(7, (value) async {
      expect(value, 7);
      consumed.complete();
    }));

    await consumed.future.timeout(const Duration(milliseconds: 50));
    await loop.close();
  });

  test('events pushed during a drain retain order and are not lost', () async {
    final loop = _Loop();
    final values = <int>[];
    final consumed = Completer<void>();

    await loop.onReady();
    loop.pushEvent(_Event(1, (value) async {
      values.add(value);
      loop.pushEvent(_Event(2, (next) async {
        values.add(next);
        consumed.complete();
      }));
    }));

    await consumed.future.timeout(const Duration(milliseconds: 100));
    expect(values, <int>[1, 2]);
    await loop.close();
  });
}
