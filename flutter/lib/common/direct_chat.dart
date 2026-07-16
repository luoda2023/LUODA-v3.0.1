import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'direct_chat_storage.dart';

enum DirectChatDelivery { queued, sent, delivered, failed }

enum DirectChatDirection { incoming, outgoing }

enum DirectChatKind { text, file }

class DirectChatRecord {
  const DirectChatRecord({
    required this.id,
    required this.conversationId,
    required this.originDeviceId,
    required this.originSequence,
    required this.direction,
    required this.kind,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.sentAt,
    required this.delivery,
    this.fileName = '',
    this.fileSize = 0,
    this.fileSha256 = '',
  });

  final String id;
  final String conversationId;
  final String originDeviceId;
  final int originSequence;
  final DirectChatDirection direction;
  final DirectChatKind kind;
  final String text;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final DateTime sentAt;
  final DirectChatDelivery delivery;
  final String fileName;
  final int fileSize;
  final String fileSha256;

  bool get isOutgoing => direction == DirectChatDirection.outgoing;

  DirectChatRecord copyWith({
    String? conversationId,
    DirectChatDirection? direction,
    DirectChatDelivery? delivery,
  }) {
    return DirectChatRecord(
      id: id,
      conversationId: conversationId ?? this.conversationId,
      originDeviceId: originDeviceId,
      originSequence: originSequence,
      direction: direction ?? this.direction,
      kind: kind,
      text: text,
      senderId: senderId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      sentAt: sentAt,
      delivery: delivery ?? this.delivery,
      fileName: fileName,
      fileSize: fileSize,
      fileSha256: fileSha256,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'conversation_id': conversationId,
        'origin_device_id': originDeviceId,
        'origin_sequence': originSequence,
        'direction': direction.name,
        'kind': kind.name,
        'text': text,
        'sender_id': senderId,
        'sender_name': senderName,
        'sender_avatar': senderAvatar,
        'sent_at': sentAt.toUtc().toIso8601String(),
        'delivery': delivery.name,
        if (fileName.isNotEmpty) 'file_name': fileName,
        if (fileSize > 0) 'file_size': fileSize,
        if (fileSha256.isNotEmpty) 'file_sha256': fileSha256,
      };

  factory DirectChatRecord.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, String key, T fallback) {
      final name = (json[key] ?? '').toString();
      return values.firstWhere(
        (value) => value.name == name,
        orElse: () => fallback,
      );
    }

    return DirectChatRecord(
      id: (json['id'] ?? '').toString(),
      conversationId: (json['conversation_id'] ?? '').toString(),
      originDeviceId: (json['origin_device_id'] ?? '').toString(),
      originSequence: int.tryParse('${json['origin_sequence'] ?? 0}') ?? 0,
      direction: enumValue(
        DirectChatDirection.values,
        'direction',
        DirectChatDirection.incoming,
      ),
      kind: enumValue(DirectChatKind.values, 'kind', DirectChatKind.text),
      text: (json['text'] ?? '').toString(),
      senderId: (json['sender_id'] ?? '').toString(),
      senderName: (json['sender_name'] ?? '').toString(),
      senderAvatar: (json['sender_avatar'] ?? '').toString(),
      sentAt: DateTime.tryParse((json['sent_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      delivery: enumValue(
        DirectChatDelivery.values,
        'delivery',
        DirectChatDelivery.queued,
      ),
      fileName: (json['file_name'] ?? '').toString(),
      fileSize: int.tryParse('${json['file_size'] ?? 0}') ?? 0,
      fileSha256: (json['file_sha256'] ?? '').toString(),
    );
  }
}

class DirectChatEnvelope {
  const DirectChatEnvelope(this.type, this.data);

  static const prefix = 'LDESK_CHAT_V1:';

  final String type;
  final Map<String, dynamic> data;

  String encode() {
    final bytes = utf8.encode(jsonEncode(<String, dynamic>{
      'type': type,
      'data': data,
    }));
    return '$prefix${base64UrlEncode(bytes)}';
  }

  static DirectChatEnvelope? decode(String value) {
    if (!value.startsWith(prefix)) return null;
    try {
      final encoded = value.substring(prefix.length);
      final decoded = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(base64Url.decode(encoded))) as Map,
      );
      return DirectChatEnvelope(
        (decoded['type'] ?? '').toString(),
        Map<String, dynamic>.from(decoded['data'] as Map? ?? const {}),
      );
    } catch (_) {
      return null;
    }
  }

  static DirectChatEnvelope message(DirectChatRecord record) =>
      DirectChatEnvelope('message', record.toJson());

  static DirectChatEnvelope receipt(String messageId) =>
      DirectChatEnvelope('receipt', <String, dynamic>{'id': messageId});

  static DirectChatEnvelope syncRequest(Map<String, int> cursor) =>
      DirectChatEnvelope('sync_request', <String, dynamic>{'cursor': cursor});

  static DirectChatEnvelope replicaRequest({
    required String secret,
    required Map<String, int> cursor,
    required bool requestReply,
  }) =>
      DirectChatEnvelope('replica_request', <String, dynamic>{
        'secret': secret,
        'cursor': cursor,
        'request_reply': requestReply,
      });

  static DirectChatEnvelope replicaMessage(
    DirectChatRecord record,
    String secret,
  ) =>
      DirectChatEnvelope('replica_message', <String, dynamic>{
        'secret': secret,
        'record': record.toJson(),
      });
}

class DirectChatRepository {
  DirectChatRepository._();

  static final instance = DirectChatRepository._();

  final DirectChatStorage _storage = DirectChatStorage();
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  Future<_DirectChatState>? _loading;
  Future<void> _pendingWrite = Future<void>.value();

  Future<_DirectChatState> _state() => _loading ??= _load();

  Future<_DirectChatState> _load() async {
    try {
      final raw = await _storage.read();
      if (raw != null && raw.isNotEmpty) {
        return _decodeState(raw);
      }
    } catch (error) {
      debugPrint('Failed to load direct chat history: $error');
    }
    return _DirectChatState(deviceId: const Uuid().v4());
  }

  _DirectChatState _decodeState(String raw) => _DirectChatState.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );

  Future<_DirectChatState> _freshState() async {
    late _DirectChatState state;
    await _storage.update((raw) async {
      if (raw == null || raw.isEmpty) {
        state = await _state();
        return jsonEncode(state.toJson());
      }
      state = _decodeState(raw);
      return raw;
    });
    _loading = Future<_DirectChatState>.value(state);
    return state;
  }

  Future<T> _write<T>(Future<T> Function(_DirectChatState state) action) async {
    final previous = _pendingWrite;
    final done = Completer<void>();
    _pendingWrite = done.future;
    await previous;
    try {
      late T result;
      await _storage.update((raw) async {
        final state =
            raw == null || raw.isEmpty ? await _state() : _decodeState(raw);
        result = await action(state);
        _loading = Future<_DirectChatState>.value(state);
        return jsonEncode(state.toJson());
      });
      revision.value++;
      return result;
    } finally {
      done.complete();
    }
  }

  Future<String> get deviceId async => (await _state()).deviceId;

  Future<DirectChatRecord> createOutgoing({
    required String conversationId,
    required DirectChatKind kind,
    required String text,
    required String senderId,
    required String senderName,
    required String senderAvatar,
    String fileName = '',
    int fileSize = 0,
    String fileSha256 = '',
  }) {
    return _write((state) async {
      final record = DirectChatRecord(
        id: const Uuid().v4(),
        conversationId: conversationId,
        originDeviceId: state.deviceId,
        originSequence: state.nextSequence++,
        direction: DirectChatDirection.outgoing,
        kind: kind,
        text: text,
        senderId: senderId,
        senderName: senderName,
        senderAvatar: senderAvatar,
        sentAt: DateTime.now().toUtc(),
        delivery: DirectChatDelivery.queued,
        fileName: fileName,
        fileSize: fileSize,
        fileSha256: fileSha256,
      );
      state.records[record.id] = record;
      return record;
    });
  }

  Future<DirectChatRecord> createIncomingLegacy({
    required String conversationId,
    required String text,
    required String senderId,
    required String senderName,
    required String senderAvatar,
  }) {
    return _write((state) async {
      final record = DirectChatRecord(
        id: const Uuid().v4(),
        conversationId: conversationId,
        originDeviceId: 'legacy:$conversationId',
        originSequence: state.nextSequence++,
        direction: DirectChatDirection.incoming,
        kind: DirectChatKind.text,
        text: text,
        senderId: senderId,
        senderName: senderName,
        senderAvatar: senderAvatar,
        sentAt: DateTime.now().toUtc(),
        delivery: DirectChatDelivery.delivered,
      );
      state.records[record.id] = record;
      return record;
    });
  }

  Future<bool> upsert(DirectChatRecord record) {
    return _write((state) async {
      if (record.id.isEmpty || record.conversationId.isEmpty) return false;
      final previous = state.records[record.id];
      if (previous == null) {
        state.records[record.id] = record;
        return true;
      }
      if (_deliveryRank(record.delivery) > _deliveryRank(previous.delivery)) {
        state.records[record.id] = previous.copyWith(delivery: record.delivery);
      }
      return false;
    });
  }

  Future<void> markDelivery(String id, DirectChatDelivery delivery) {
    return _write((state) async {
      final record = state.records[id];
      if (record != null) {
        state.records[id] = record.copyWith(delivery: delivery);
      }
    });
  }

  Future<void> markUndeliveredFailed(String conversationId) {
    return _write((state) async {
      for (final entry in state.records.entries.toList(growable: false)) {
        final record = entry.value;
        if (record.conversationId == conversationId &&
            record.isOutgoing &&
            record.delivery != DirectChatDelivery.delivered) {
          state.records[entry.key] =
              record.copyWith(delivery: DirectChatDelivery.failed);
        }
      }
    });
  }

  Future<void> remapConversation(String from, String to) {
    if (from.isEmpty || to.isEmpty || from == to) return Future<void>.value();
    return _write((state) async {
      for (final entry in state.records.entries.toList(growable: false)) {
        if (entry.value.conversationId == from) {
          state.records[entry.key] = entry.value.copyWith(conversationId: to);
        }
      }
    });
  }

  Future<List<DirectChatRecord>> forConversation(String conversationId) async {
    await _pendingWrite;
    final records = (await _freshState())
        .records
        .values
        .where((record) => record.conversationId == conversationId)
        .toList();
    records.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return records;
  }

  Future<List<String>> conversationIds() async {
    await _pendingWrite;
    final latest = <String, DateTime>{};
    for (final record in (await _freshState()).records.values) {
      final previous = latest[record.conversationId];
      if (previous == null || record.sentAt.isAfter(previous)) {
        latest[record.conversationId] = record.sentAt;
      }
    }
    final ids = latest.keys.toList(growable: false);
    ids.sort((a, b) => latest[b]!.compareTo(latest[a]!));
    return ids;
  }

  Future<Map<String, int>> cursor({String? conversationId}) async {
    await _pendingWrite;
    final result = <String, int>{};
    for (final record in (await _freshState()).records.values) {
      if (conversationId != null && record.conversationId != conversationId) {
        continue;
      }
      final current = result[record.originDeviceId] ?? 0;
      if (record.originSequence > current) {
        result[record.originDeviceId] = record.originSequence;
      }
    }
    return result;
  }

  Future<List<DirectChatRecord>> afterCursor(
    Map<String, int> cursor, {
    String? conversationId,
    bool outgoingOnly = false,
  }) async {
    await _pendingWrite;
    final records = (await _freshState()).records.values.where((record) {
      if (conversationId != null && record.conversationId != conversationId) {
        return false;
      }
      if (outgoingOnly && !record.isOutgoing) return false;
      return record.originSequence > (cursor[record.originDeviceId] ?? 0);
    }).toList();
    records.sort((a, b) {
      final byTime = a.sentAt.compareTo(b.sentAt);
      return byTime != 0
          ? byTime
          : a.originSequence.compareTo(b.originSequence);
    });
    return records;
  }

  Future<List<DirectChatRecord>> pendingFor(String conversationId) async {
    final records = await forConversation(conversationId);
    return records
        .where((record) =>
            record.isOutgoing &&
            record.delivery != DirectChatDelivery.delivered)
        .toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  }

  static int _deliveryRank(DirectChatDelivery delivery) {
    switch (delivery) {
      case DirectChatDelivery.queued:
        return 0;
      case DirectChatDelivery.failed:
        return 1;
      case DirectChatDelivery.sent:
        return 2;
      case DirectChatDelivery.delivered:
        return 3;
    }
  }
}

class _DirectChatState {
  _DirectChatState({
    required this.deviceId,
    this.nextSequence = 1,
    Map<String, DirectChatRecord>? records,
  }) : records = records ?? <String, DirectChatRecord>{};

  final String deviceId;
  int nextSequence;
  final Map<String, DirectChatRecord> records;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': 1,
        'device_id': deviceId,
        'next_sequence': nextSequence,
        'records': records.values.map((record) => record.toJson()).toList(),
      };

  factory _DirectChatState.fromJson(Map<String, dynamic> json) {
    final records = <String, DirectChatRecord>{};
    for (final value in json['records'] as List<dynamic>? ?? const []) {
      try {
        final record = DirectChatRecord.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        if (record.id.isNotEmpty) records[record.id] = record;
      } catch (_) {}
    }
    final deviceId = (json['device_id'] ?? '').toString();
    final maxLocalSequence = records.values
        .where((record) => record.originDeviceId == deviceId)
        .fold<int>(
            0,
            (max, record) =>
                record.originSequence > max ? record.originSequence : max);
    final storedNext = int.tryParse('${json['next_sequence'] ?? 1}') ?? 1;
    return _DirectChatState(
      deviceId: deviceId.isEmpty ? const Uuid().v4() : deviceId,
      nextSequence:
          storedNext > maxLocalSequence ? storedNext : maxLocalSequence + 1,
      records: records,
    );
  }
}
