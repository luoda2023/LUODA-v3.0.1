import 'dart:async';

import 'package:flutter/foundation.dart';

typedef EventCallback<Data> = Future<dynamic> Function(Data data);

abstract class BaseEvent<EventType, Data> {
  EventType type;
  Data data;

  /// Constructor.
  BaseEvent(this.type, this.data);

  /// Consume this event.
  @visibleForTesting
  Future<dynamic> consume() async {
    final cb = findCallback(type);
    if (cb == null) {
      return null;
    } else {
      return cb(data);
    }
  }

  EventCallback<Data>? findCallback(EventType type);
}

abstract class BaseEventLoop<EventType, Data> {
  final List<BaseEvent<EventType, Data>> _evts = [];
  Timer? _timer;
  bool _draining = false;
  bool _closed = false;

  List<BaseEvent<EventType, Data>> get evts => _evts;

  Future<void> onReady() async {
    _closed = false;
    _scheduleDrain();
  }

  /// An Event is about to be consumed.
  Future<void> onPreConsume(BaseEvent<EventType, Data> evt) async {}

  /// An Event was consumed.
  Future<void> onPostConsume(BaseEvent<EventType, Data> evt) async {}

  /// Events are all handled and cleared.
  Future<void> onEventsClear() async {}

  /// Events start to consume.
  Future<void> onEventsStartConsuming() async {}

  void _scheduleDrain() {
    if (_closed || _draining || _timer?.isActive == true || _evts.isEmpty) {
      return;
    }
    _timer = Timer(Duration.zero, () async {
      _timer = null;
      await _drain();
    });
  }

  Future<void> _drain() async {
    if (_closed || _draining || _evts.isEmpty) {
      return;
    }
    _draining = true;
    try {
      await onEventsStartConsuming();
      while (!_closed && _evts.isNotEmpty) {
        final evt = _evts.first;
        _evts.removeAt(0);
        await onPreConsume(evt);
        await evt.consume();
        await onPostConsume(evt);
      }
      if (!_closed) {
        await onEventsClear();
      }
    } finally {
      _draining = false;
      _scheduleDrain();
    }
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _timer = null;
  }

  void pushEvent(BaseEvent<EventType, Data> evt) {
    _evts.add(evt);
    _scheduleDrain();
  }

  void clear() {
    _evts.clear();
  }
}
