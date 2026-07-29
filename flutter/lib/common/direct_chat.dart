import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'direct_chat_storage.dart';

enum DirectChatDelivery { queued, sent, delivered, failed }

enum DirectChatDirection { incoming, outgoing }

enum DirectChatKind { text, file, voice }

enum DirectChatDisposition { active, recalled, destroyed }

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
    this.localPath = '',
    this.inlineBytes = '',
    this.voiceDurationMs = 0,
    this.disposition = DirectChatDisposition.active,
    this.expiresAt,
    this.replyToId = '',
    this.replyToText = '',
    this.reactions = const {},
    this.isEdited = false,
    this.editedAt,
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
  final String localPath;
  // Transient: inlined file/image bytes (base64) carried only in the wire
  // envelope, never persisted to history (keeps storage small).
  final String inlineBytes;
  final DirectChatDisposition disposition;
  final int voiceDurationMs;
  final DateTime? expiresAt;
  final String replyToId;
  final String replyToText;
  // Reactions: emoji -> list of device IDs who reacted
  final Map<String, List<String>> reactions;
  final bool isEdited;
  final DateTime? editedAt;

  bool get isOutgoing => direction == DirectChatDirection.outgoing;
  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());

  DirectChatRecord copyWith({
    String? conversationId,
    String? text,
    DirectChatDirection? direction,
    DirectChatDelivery? delivery,
    int? originSequence,
    DirectChatDisposition? disposition,
    DateTime? expiresAt,
    String? localPath,
    String? inlineBytes,
    String? replyToId,
    String? replyToText,
    Map<String, List<String>>? reactions,
    bool? isEdited,
    DateTime? editedAt,
  }) {
    return DirectChatRecord(
      id: id,
      conversationId: conversationId ?? this.conversationId,
      originDeviceId: originDeviceId,
      originSequence: originSequence ?? this.originSequence,
      direction: direction ?? this.direction,
      kind: kind,
      text: text ?? this.text,
      senderId: senderId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      sentAt: sentAt,
      delivery: delivery ?? this.delivery,
      disposition: disposition ?? this.disposition,
      fileName: fileName,
      fileSize: fileSize,
      fileSha256: fileSha256,
      localPath: localPath ?? this.localPath,
      inlineBytes: inlineBytes ?? this.inlineBytes,
      voiceDurationMs: voiceDurationMs,
      expiresAt: expiresAt ?? this.expiresAt,
      replyToId: replyToId ?? this.replyToId,
      replyToText: replyToText ?? this.replyToText,
      reactions: reactions ?? this.reactions,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
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
        'disposition': disposition.name,
        if (fileName.isNotEmpty) 'file_name': fileName,
        if (fileSize > 0) 'file_size': fileSize,
        if (fileSha256.isNotEmpty) 'file_sha256': fileSha256,
        if (localPath.isNotEmpty) 'local_path': localPath,
        if (voiceDurationMs > 0) 'voice_duration_ms': voiceDurationMs,
        if (expiresAt != null)
          'expires_at': expiresAt!.toUtc().toIso8601String(),
        if (replyToId.isNotEmpty) 'reply_to_id': replyToId,
        if (replyToText.isNotEmpty) 'reply_to_text': replyToText,
        if (reactions.isNotEmpty)
          'reactions': reactions.map((k, v) => MapEntry(k, v)),
        if (isEdited) 'is_edited': true,
        if (editedAt != null)
          'edited_at': editedAt!.toUtc().toIso8601String(),
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
      disposition: enumValue(DirectChatDisposition.values, 'disposition',
          DirectChatDisposition.active),
      fileName: (json['file_name'] ?? '').toString(),
      fileSize: int.tryParse('${json['file_size'] ?? 0}') ?? 0,
      fileSha256: (json['file_sha256'] ?? '').toString(),
      localPath: (json['local_path'] ?? '').toString(),
      voiceDurationMs: int.tryParse('${json['voice_duration_ms'] ?? 0}') ?? 0,
      expiresAt: DateTime.tryParse((json['expires_at'] ?? '').toString()),
      replyToId: (json['reply_to_id'] ?? '').toString(),
      replyToText: (json['reply_to_text'] ?? '').toString(),
      reactions: _parseReactions(json['reactions']),
      isEdited: json['is_edited'] == true,
      editedAt: DateTime.tryParse((json['edited_at'] ?? '').toString()),
    );
  }

  static Map<String, List<String>> _parseReactions(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, List<String>>{};
    for (final entry in (raw as Map).entries) {
      final emoji = entry.key.toString();
      final list = entry.value;
      if (list is List) {
        result[emoji] = list.map((e) => e.toString()).toList();
      }
    }
    return result;
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

  static DirectChatEnvelope message(DirectChatRecord record) {
    final data = record.toJson();
    if (record.inlineBytes.isNotEmpty) {
      data['inline_bytes'] = record.inlineBytes;
    }
    return DirectChatEnvelope('message', data);
  }

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

  static DirectChatEnvelope voiceChunk({
    required String messageId,
    required int index,
    required int total,
    required String sha256,
    required String payload,
  }) =>
      DirectChatEnvelope('voice_chunk', <String, dynamic>{
        'id': messageId,
        'index': index,
        'total': total,
        'sha256': sha256,
        'payload': payload,
      });

  static DirectChatEnvelope voiceRequest(String messageId) =>
      DirectChatEnvelope('voice_request', <String, dynamic>{'id': messageId});

  static DirectChatEnvelope typing() =>
      DirectChatEnvelope('typing', <String, dynamic>{});

  static DirectChatEnvelope reaction({
    required String messageId,
    required String emoji,
    required String deviceId,
    required bool add,
  }) =>
      DirectChatEnvelope('reaction', <String, dynamic>{
        'id': messageId,
        'emoji': emoji,
        'device_id': deviceId,
        'add': add,
      });

  static DirectChatEnvelope edit({
    required String messageId,
    required String newText,
  }) =>
      DirectChatEnvelope('edit', <String, dynamic>{
        'id': messageId,
        'text': newText,
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
    String? raw;
    try {
      raw = await _storage.read();
    } catch (error) {
      debugPrint('Failed to refresh direct chat history: $error');
      return _state();
    }
    if (raw != null && raw.isNotEmpty) {
      final state = _decodeState(raw);
      _loading = Future<_DirectChatState>.value(state);
      return state;
    }

    late _DirectChatState state;
    await _storage.update((current) async {
      if (current == null || current.isEmpty) {
        state = await _state();
        return jsonEncode(state.toJson());
      }
      state = _decodeState(current);
      return current;
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

  Future<DirectChatRecord>     createOutgoing({
    String? id,
    required String conversationId,
    required DirectChatKind kind,
    required String text,
    required String senderId,
    required String senderName,
    required String senderAvatar,
    String fileName = '',
    int fileSize = 0,
    String fileSha256 = '',
    String localPath = '',
    String inlineBytes = '',
    int voiceDurationMs = 0,
    String replyToId = '',
    String replyToText = '',
  }) {
    return _write((state) async {
      final record = DirectChatRecord(
        id: id ?? const Uuid().v4(),
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
        localPath: localPath,
        inlineBytes: inlineBytes,
        voiceDurationMs: voiceDurationMs,
        replyToId: replyToId,
        replyToText: replyToText,
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
      final newerMutation = record.originDeviceId == previous.originDeviceId &&
          record.originSequence > previous.originSequence;
      if (newerMutation) {
        state.records[record.id] = record;
        return true;
      }
      if (_deliveryRank(record.delivery) > _deliveryRank(previous.delivery)) {
        state.records[record.id] = previous.copyWith(delivery: record.delivery);
        return true;
      }
      return false;
    });
  }

  Future<DirectChatRecord?> mutateOutgoing(
    String conversationId,
    String id,
    DirectChatDisposition disposition,
  ) {
    return _write((state) async {
      final record = state.records[id];
      if (record == null ||
          record.conversationId != conversationId ||
          !record.isOutgoing ||
          record.disposition == DirectChatDisposition.destroyed ||
          (record.disposition == DirectChatDisposition.recalled &&
              disposition == DirectChatDisposition.recalled)) {
        return null;
      }
      final updated = record.copyWith(
        originSequence: state.nextSequence++,
        delivery: DirectChatDelivery.queued,
        disposition: disposition,
      );
      state.records[id] = updated;
      return updated;
    });
  }

  Future<DirectChatRecord?> setSelfDestruct(
    String conversationId,
    String id,
    Duration duration,
  ) {
    return _write((state) async {
      final record = state.records[id];
      if (record == null ||
          record.conversationId != conversationId ||
          !record.isOutgoing ||
          record.disposition != DirectChatDisposition.active ||
          duration <= Duration.zero) {
        return null;
      }
      final updated = record.copyWith(
        originSequence: state.nextSequence++,
        delivery: DirectChatDelivery.queued,
        expiresAt: DateTime.now().toUtc().add(duration),
      );
      state.records[id] = updated;
      return updated;
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

  /// Toggle a reaction on a message. Returns updated record or null.
  Future<DirectChatRecord?> toggleReaction(
    String id,
    String emoji,
    String deviceId,
  ) {
    return _write((state) async {
      final record = state.records[id];
      if (record == null ||
          record.disposition != DirectChatDisposition.active) {
        return null;
      }
      final reactions =
          Map<String, List<String>>.from(record.reactions);
      final users = List<String>.from(reactions[emoji] ?? []);
      if (users.contains(deviceId)) {
        users.remove(deviceId);
        if (users.isEmpty) {
          reactions.remove(emoji);
        } else {
          reactions[emoji] = users;
        }
      } else {
        users.add(deviceId);
        reactions[emoji] = users;
      }
      final updated = record.copyWith(
        reactions: reactions,
      );
      state.records[id] = updated;
      return updated;
    });
  }

  /// Edit the text of an outgoing message.
  Future<DirectChatRecord?> editText(String id, String newText) {
    return _write((state) async {
      final record = state.records[id];
      if (record == null ||
          !record.isOutgoing ||
          record.disposition != DirectChatDisposition.active) {
        return null;
      }
      final updated = record.copyWith(
        text: newText,
        isEdited: true,
        editedAt: DateTime.now().toUtc(),
        originSequence: state.nextSequence++,
      );
      state.records[id] = updated;
      return updated;
    });
  }

  /// Get all media (file/image) records for a conversation.
  Future<List<DirectChatRecord>> mediaForConversation(
    String conversationId,
  ) async {
    await _pendingWrite;
    final records = (await _freshState())
        .records
        .values
        .where((r) =>
            r.conversationId == conversationId &&
            r.kind == DirectChatKind.file &&
            r.disposition == DirectChatDisposition.active &&
            !r.isExpired)
        .toList();
    records.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return records;
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

  Future<void> markUndeliveredQueued(String conversationId) {
    return _write((state) async {
      for (final entry in state.records.entries.toList(growable: false)) {
        final record = entry.value;
        if (record.conversationId == conversationId &&
            record.isOutgoing &&
            record.delivery != DirectChatDelivery.delivered) {
          state.records[entry.key] =
              record.copyWith(delivery: DirectChatDelivery.queued);
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

  /// Returns records for a conversation, newest first.
  /// If [limit] is set, only the newest [limit] records are returned.
  Future<List<DirectChatRecord>> forConversation(
    String conversationId, {
    int? limit,
  }) async {
    await _pendingWrite;
    final records = (await _freshState())
        .records
        .values
        .where((record) =>
            record.conversationId == conversationId &&
            record.disposition != DirectChatDisposition.destroyed &&
            !record.isExpired)
        .toList();
    records.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    if (limit != null && limit > 0 && records.length > limit) {
      return records.sublist(0, limit);
    }
    return records;
  }

  Future<List<String>> conversationIds() async {
    await _pendingWrite;
    final latest = <String, DateTime>{};
    for (final record in (await _freshState()).records.values) {
      if (record.disposition == DirectChatDisposition.destroyed &&
          (!record.isOutgoing ||
              record.delivery == DirectChatDelivery.delivered)) {
        continue;
      }
      if (record.isExpired) continue;
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
    await _pendingWrite;
    final records = (await _freshState())
        .records
        .values
        .where((record) => record.conversationId == conversationId)
        .toList();
    return records
        .where((record) =>
            record.isOutgoing &&
            !record.isExpired &&
            record.delivery != DirectChatDelivery.delivered)
        .toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  }

  Future<DirectChatRecord?> find(String id) async {
    await _pendingWrite;
    return (await _freshState()).records[id];
  }

  Future<void> deleteRecord(String id, String conversationId) {
    return _write((state) async {
      final record = state.records[id];
      if (record != null && record.conversationId == conversationId) {
        state.records.remove(id);
      }
    });
  }

  Future<void> deleteConversations(Iterable<String> conversationIds) {
    final ids = conversationIds.toSet();
    return _write((state) async {
      state.records
          .removeWhere((_, record) => ids.contains(record.conversationId));
    });
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

/// Maximum inline payload for a chat file/image message (5 MB). Larger files
/// are sent as metadata only — full file-transfer-subsystem delivery is not yet
/// wired, so keep attachments within this budget (covers images & small docs).
const int kMaxInlineChatFileBytes = 5 * 1024 * 1024;

/// Persists inline file bytes received over chat and returns the saved path so
/// the preview UI can open them directly. Returns null on any error.
Future<String?> saveInlineChatFile(String fileName, List<int> bytes) async {
  try {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}luoda_chat_received');
    await dir.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[^0-9a-zA-Z._\-]'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (e) {
    debugPrint('Failed to save inline chat file: $e');
    return null;
  }
}
