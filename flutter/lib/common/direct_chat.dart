import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'direct_chat_storage.dart';
import 'direct_pairing.dart';
import 'string_utils.dart';
import '../models/platform_model.dart';

enum DirectChatDelivery { queued, sent, delivered, failed }

enum DirectChatDirection { incoming, outgoing }

enum DirectChatKind { text, file, voice, forward }

enum DirectChatDisposition { active, recalled, destroyed }

/// Registered by the Bluetooth bridge so wire envelopes are routed over an
/// RFCOMM link when the conversation is a Bluetooth peer (bt:<mac>).
typedef BtWireSink = bool Function(String conversationId, String envelope);

/// Returns true when the envelope was handled over Bluetooth.
BtWireSink? btWireSink;

/// A shared location payload sent as a chat message. Encoded inside the
/// message text as `[location]lat,lng|name` so it survives the existing
/// text wire format without protocol changes.
class DirectChatLocation {
  const DirectChatLocation({
    required this.latitude,
    required this.longitude,
    this.name = '',
    this.address = '',
  });

  final double latitude;
  final double longitude;
  final String name;

  /// 详细地址（高德逆地理编码结果，如“上海市青浦区赵巷镇业煌路99弄”）。
  /// 旧版本地会把 name|address 整体当作 name 显示，新版本拆开显示。
  final String address;

  String encode() {
    final n = name.trim();
    final a = address.trim();
    final lat = latitude.toStringAsFixed(6);
    final lng = longitude.toStringAsFixed(6);
    if (a.isNotEmpty) {
      return '[location]$lat,$lng|$n|$a';
    }
    return '[location]$lat,$lng${n.isEmpty ? '' : '|$n'}';
  }

  static DirectChatLocation? tryParse(String text) {
    final m = RegExp(
      r'^\[location\](-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)\|?(.*)$',
      dotAll: true,
    ).firstMatch(text.trim());
    if (m == null) return null;
    final lat = double.tryParse(m.group(1) ?? '');
    final lng = double.tryParse(m.group(2) ?? '');
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    final rest = (m.group(3) ?? '').trim();
    if (rest.isEmpty) {
      return DirectChatLocation(latitude: lat, longitude: lng);
    }
    // 新格式：name|address；旧格式：name。地址本身不含 |。
    final sep = rest.indexOf('|');
    if (sep < 0) {
      return DirectChatLocation(
        latitude: lat,
        longitude: lng,
        name: rest,
      );
    }
    return DirectChatLocation(
      latitude: lat,
      longitude: lng,
      name: rest.substring(0, sep).trim(),
      address: rest.substring(sep + 1).trim(),
    );
  }

  bool get isDecoded => latitude != 0 || longitude != 0;
}

/// Current device platform label used to tag outgoing messages so the
/// receiver can show a phone badge on the avatar.
String get directChatPlatformLabel =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS) ? 'mobile' : 'desktop';

String normalizeDirectPeerName(
  String value, {
  required String fallback,
}) {
  final name = sanitizeInvalidUtf16(value).trim();
  if (name.isEmpty ||
      name == 'ОТ' ||
      name == '我' ||
      name.toLowerCase() == 'me') {
    return sanitizeInvalidUtf16(fallback).trim();
  }
  return name;
}

class DirectChatForwardItem {
  const DirectChatForwardItem({
    required this.senderName,
    required this.kind,
    required this.text,
    this.fileName = '',
    this.voiceDurationMs = 0,
  });

  final String senderName;
  final DirectChatKind kind;
  final String text;
  final String fileName;
  final int voiceDurationMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sender_name': sanitizeInvalidUtf16(senderName),
        'kind': kind.name,
        'text': sanitizeInvalidUtf16(text),
        if (fileName.isNotEmpty) 'file_name': sanitizeInvalidUtf16(fileName),
        if (voiceDurationMs > 0) 'voice_duration_ms': voiceDurationMs,
      };

  factory DirectChatForwardItem.fromJson(Map<String, dynamic> json) {
    final kindName = (json['kind'] ?? '').toString();
    return DirectChatForwardItem(
      senderName: sanitizeInvalidUtf16(
        (json['sender_name'] ?? '').toString(),
      ),
      kind: DirectChatKind.values.firstWhere(
        (value) => value.name == kindName,
        orElse: () => DirectChatKind.text,
      ),
      text: sanitizeInvalidUtf16((json['text'] ?? '').toString()),
      fileName: sanitizeInvalidUtf16((json['file_name'] ?? '').toString()),
      voiceDurationMs: int.tryParse('${json['voice_duration_ms'] ?? 0}') ?? 0,
    );
  }
}

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
    this.replyToSender = '',
    this.replyToText = '',
    this.reactions = const {},
    this.isEdited = false,
    this.editedAt,
    this.forwardTitle = '',
    this.forwardItems = const <DirectChatForwardItem>[],
    this.connMode = '',
    this.connEndpoint = '',
    this.connPort = 0,
    this.srcPlatform = '',
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
  final String replyToSender;
  final String replyToText;
  // Reactions: emoji -> list of device IDs who reacted
  final Map<String, List<String>> reactions;
  final bool isEdited;
  final DateTime? editedAt;
  final String forwardTitle;
  final List<DirectChatForwardItem> forwardItems;
  final String connMode;
  final String connEndpoint;
  final int connPort;
  final String srcPlatform;

  bool get isOutgoing => direction == DirectChatDirection.outgoing;
  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());

  DirectChatRecord copyWith({
    String? conversationId,
    String? text,
    String? senderName,
    DirectChatDirection? direction,
    DirectChatDelivery? delivery,
    int? originSequence,
    DirectChatDisposition? disposition,
    DateTime? expiresAt,
    String? localPath,
    String? inlineBytes,
    String? replyToId,
    String? replyToSender,
    String? replyToText,
    Map<String, List<String>>? reactions,
    bool? isEdited,
    DateTime? editedAt,
    String? forwardTitle,
    List<DirectChatForwardItem>? forwardItems,
    String? connMode,
    String? connEndpoint,
    int? connPort,
    String? srcPlatform,
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
      senderName: senderName ?? this.senderName,
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
      replyToSender: replyToSender ?? this.replyToSender,
      replyToText: replyToText ?? this.replyToText,
      reactions: reactions ?? this.reactions,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      forwardTitle: forwardTitle ?? this.forwardTitle,
      forwardItems: forwardItems ?? this.forwardItems,
      connMode: connMode ?? this.connMode,
      connEndpoint: connEndpoint ?? this.connEndpoint,
      connPort: connPort ?? this.connPort,
      srcPlatform: srcPlatform ?? this.srcPlatform,
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
        if (replyToSender.isNotEmpty) 'reply_to_sender': replyToSender,
        if (replyToText.isNotEmpty) 'reply_to_text': replyToText,
        if (reactions.isNotEmpty)
          'reactions': reactions.map((k, v) => MapEntry(k, v)),
        if (isEdited) 'is_edited': true,
        if (editedAt != null) 'edited_at': editedAt!.toUtc().toIso8601String(),
        if (forwardTitle.isNotEmpty) 'forward_title': forwardTitle,
        if (forwardItems.isNotEmpty)
          'forward_items':
              forwardItems.map((item) => item.toJson()).toList(growable: false),
        if (connMode.isNotEmpty) 'conn_mode': connMode,
        if (connEndpoint.isNotEmpty) 'conn_endpoint': connEndpoint,
        if (connPort > 0) 'conn_port': connPort,
        if (srcPlatform.isNotEmpty) 'src_platform': srcPlatform,
      };

  factory DirectChatRecord.fromJson(Map<String, dynamic> json) {
    String stringValue(String key) =>
        sanitizeInvalidUtf16((json[key] ?? '').toString());

    T enumValue<T extends Enum>(List<T> values, String key, T fallback) {
      final name = (json[key] ?? '').toString();
      return values.firstWhere(
        (value) => value.name == name,
        orElse: () => fallback,
      );
    }

    return DirectChatRecord(
      id: stringValue('id'),
      conversationId: stringValue('conversation_id'),
      originDeviceId: stringValue('origin_device_id'),
      originSequence: int.tryParse('${json['origin_sequence'] ?? 0}') ?? 0,
      direction: enumValue(
        DirectChatDirection.values,
        'direction',
        DirectChatDirection.incoming,
      ),
      kind: enumValue(DirectChatKind.values, 'kind', DirectChatKind.text),
      text: stringValue('text'),
      senderId: stringValue('sender_id'),
      senderName: stringValue('sender_name'),
      senderAvatar: stringValue('sender_avatar'),
      sentAt: DateTime.tryParse((json['sent_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      delivery: enumValue(
        DirectChatDelivery.values,
        'delivery',
        DirectChatDelivery.queued,
      ),
      disposition: enumValue(DirectChatDisposition.values, 'disposition',
          DirectChatDisposition.active),
      fileName: stringValue('file_name'),
      fileSize: int.tryParse('${json['file_size'] ?? 0}') ?? 0,
      fileSha256: stringValue('file_sha256'),
      localPath: stringValue('local_path'),
      voiceDurationMs: int.tryParse('${json['voice_duration_ms'] ?? 0}') ?? 0,
      expiresAt: DateTime.tryParse((json['expires_at'] ?? '').toString()),
      replyToId: stringValue('reply_to_id'),
      replyToSender: stringValue('reply_to_sender'),
      replyToText: stringValue('reply_to_text'),
      reactions: _parseReactions(json['reactions']),
      isEdited: json['is_edited'] == true,
      editedAt: DateTime.tryParse((json['edited_at'] ?? '').toString()),
      forwardTitle: stringValue('forward_title'),
      forwardItems: (json['forward_items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => DirectChatForwardItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      connMode: stringValue('conn_mode'),
      connEndpoint: stringValue('conn_endpoint'),
      connPort: int.tryParse('${json['conn_port'] ?? 0}') ?? 0,
      srcPlatform: stringValue('src_platform'),
    );
  }

  static Map<String, List<String>> _parseReactions(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, List<String>>{};
    for (final entry in raw.entries) {
      final emoji = sanitizeInvalidUtf16(entry.key.toString());
      final list = entry.value;
      if (list is List) {
        result[emoji] =
            list.map((e) => sanitizeInvalidUtf16(e.toString())).toList();
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

  static DirectChatEnvelope message(DirectChatRecord record,
      {String senderDialId = ''}) {
    final data = record.toJson();
    if (record.inlineBytes.isNotEmpty) {
      data['inline_bytes'] = record.inlineBytes;
    }
    // The sender's rendezvous dial id (e.g. 835149) lets the recipient
    // route replies back even when no pairing record exists yet. The
    // origin_device_id is only the per-install UUID and cannot be dialed.
    final dialId = senderDialId.trim();
    if (dialId.isNotEmpty) {
      data['sender_dial_id'] = dialId;
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

  /// Test hook: isolates the repository from the real on-disk store.
  @visibleForTesting
  static DirectChatStorage? debugStorageOverride;

  DirectChatStorage get _storage =>
      debugStorageOverride ?? DirectChatStorage();

  /// Test hook: clears all persisted state so each test starts fresh.
  @visibleForTesting
  Future<void> resetForTest() async {
    _loading = null;
    await _write((state) async {
      state.records.clear();
      return true;
    });
  }
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  Future<_DirectChatState>? _loading;
  Future<void> _pendingWrite = Future<void>.value();

  /// 清理已过期的消息（阅后即焚到期 / 手动销毁），防止历史存储无限增长。
  /// 过期消息本就该消失（产品语义），删除是安全的。
  Future<int> purgeExpired() async {
    final state = await _state();
    final expired = state.records.values
        .where((r) => r.isExpired)
        .map((r) => r.id)
        .toList(growable: false);
    if (expired.isEmpty) return 0;
    await _write((st) async {
      for (final id in expired) {
        st.records.remove(id);
      }
      return true;
    });
    return expired.length;
  }
  DateTime? _lastObservedStorageMtime;
  String _lastObservedStorageSignature = '';

  /// Detects chat-history records written by another process (e.g. the
  /// connection-manager window) by comparing the storage file modification
  /// time AND the store's own sequence/record signature. The mtime alone is
  /// unreliable (filesystems with coarse timestamps, atomic rename preserving
  /// mtime), which is why messages could sit in the store without the UI ever
  /// noticing until a manual tab switch ("new message only appears after the
  /// user switches chats" bug).
  int _tickSinceDeepSignatureCheck = 0;
  static const int _deepSignatureCheckEveryTicks = 15;

  Future<bool> hasExternalStorageChanges() async {
    try {
      // Fast path: the file mtime is a cheap stat and almost always the only
      // signal that changes between polls. Reading + JSON-decoding the whole
      // store every tick was the single most expensive poll in the app, so
      // skip the full read unless the mtime moved.
      final mtime = await _storage.modifiedTime();
      _tickSinceDeepSignatureCheck++;
      final mtimeUnchanged = mtime != null &&
          _lastObservedStorageMtime != null &&
          !mtime.isAfter(_lastObservedStorageMtime!);
      // mtime alone is unreliable on coarse filesystems / atomic renames, so
      // periodically re-run the full signature check as a safety net.
      if (mtimeUnchanged &&
          _lastObservedStorageSignature.isNotEmpty &&
          _tickSinceDeepSignatureCheck < _deepSignatureCheckEveryTicks) {
        return false;
      }
      _tickSinceDeepSignatureCheck = 0;
      final raw = await _storage.read();
      final signature = _storageSignature(raw);
      if (signature.isNotEmpty && signature != _lastObservedStorageSignature) {
        _lastObservedStorageSignature = signature;
        _lastObservedStorageMtime = mtime;
        return true;
      }
      if (mtime != null &&
          _lastObservedStorageMtime != null &&
          mtime.isAfter(_lastObservedStorageMtime!)) {
        _lastObservedStorageMtime = mtime;
        return true;
      }
      if (_lastObservedStorageSignature.isEmpty && signature.isNotEmpty) {
        _lastObservedStorageSignature = signature;
      }
      if (mtime != null) _lastObservedStorageMtime = mtime;
      return false;
    } catch (_) {
      return false;
    }
  }

  String _storageSignature(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final root = jsonDecode(raw);
      if (root is! Map<String, dynamic>) return '';
      final sequence = (root['next_sequence'] ?? 0).toString();
      final records = root['records'];
      final count = records is List ? records.length.toString() : '0';
      String? lastId;
      if (records is List && records.isNotEmpty) {
        final last = records.last;
        if (last is Map<String, dynamic>) {
          lastId = last['id']?.toString();
        }
      }
      return '$sequence:$count:${lastId ?? ''}';
    } catch (_) {
      return '';
    }
  }

  Future<_DirectChatState> _state() => _loading ??= _load();

  Future<_DirectChatState> _load() async {
    try {
      final raw = await _storage.read();
      if (raw != null && raw.isNotEmpty) {
        final state = _decodeState(raw);
        // Heal stores that contain undecoded DotChat envelopes (a past bug
        // persisted the raw "LDESK_CHAT_V1:..." payload). Such records are
        // always garbage: drop them so list previews show real messages.
        final sanitized = state.records.values
            .where((record) =>
                !record.text.trim().startsWith(DirectChatEnvelope.prefix) &&
                // Orphan records persisted under an empty conversation key
                // (pre-2026-08-10 key mismatch bug) are invisible in every
                // list and only waste storage; drop them.
                record.conversationId.trim().isNotEmpty)
            .toList(growable: false);
        if (sanitized.length != state.records.length) {
          final healed = _DirectChatState(
            deviceId: state.deviceId,
            nextSequence: state.nextSequence,
            records: <String, DirectChatRecord>{
              for (final record in sanitized) record.id: record,
            },
          );
          await _storage.update((_) async => jsonEncode(healed.toJson()));
          return healed;
        }
        // LUODA: the whole data folder was cloned from another machine (the
        // Rust core re-rolled the rendezvous ID and set this flag). Re-roll
        // the chat device id too, otherwise the cloned device keeps the
        // original machine's device id and its messages are dropped as
        // "self" by the owner.
        try {
          final reset =
              bind.mainGetLocalOption(key: 'direct-chat-identity-reset');
          if (reset == 'Y') {
            final fresh = _DirectChatState(
              deviceId: const Uuid().v4(),
              nextSequence: state.nextSequence,
              records: state.records,
            );
            await _storage.update((_) async => jsonEncode(fresh.toJson()));
            bind.mainSetLocalOption(
                key: 'direct-chat-identity-reset', value: '');
            revision.value++;
            debugPrint('CHAT-ID: device identity re-rolled after config clone '
                '(self-drop fix)');
            return fresh;
          }
        } catch (_) {}
        return state;
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
      var changed = false;
      await _storage.update((raw) async {
        final state =
            raw == null || raw.isEmpty ? await _state() : _decodeState(raw);
        result = await action(state);
        _loading = Future<_DirectChatState>.value(state);
        final next = jsonEncode(state.toJson());
        changed = next != raw;
        return next;
      });
      // Only bump the revision (and notify rebuilds) when the store actually
      // changed; unconditional bumps made the periodic merge pass re-trigger
      // the change detector forever.
      if (changed) revision.value++;
      return result;
    } finally {
      done.complete();
    }
  }

  Future<String> get deviceId async => (await _state()).deviceId;

  Future<DirectChatRecord> createOutgoing({
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
    String replyToSender = '',
    String replyToText = '',
    String forwardTitle = '',
    List<DirectChatForwardItem> forwardItems = const <DirectChatForwardItem>[],
    String connectionTarget = '',
    bool recordSource = true,
  }) {
    return _write((state) async {
      final sourceTarget = connectionTarget.trim().isNotEmpty
          ? connectionTarget.trim()
          : conversationId;
      final sourceMode =
          recordSource ? DirectPairingStore.classifyConnMode(sourceTarget) : '';
      final record = DirectChatRecord(
        id: id ?? const Uuid().v4(),
        conversationId: sanitizeInvalidUtf16(conversationId),
        originDeviceId: state.deviceId,
        originSequence: state.nextSequence++,
        direction: DirectChatDirection.outgoing,
        kind: kind,
        text: sanitizeInvalidUtf16(text),
        senderId: sanitizeInvalidUtf16(senderId),
        senderName: sanitizeInvalidUtf16(senderName),
        senderAvatar: sanitizeInvalidUtf16(senderAvatar),
        sentAt: DateTime.now().toUtc(),
        delivery: DirectChatDelivery.queued,
        fileName: sanitizeInvalidUtf16(fileName),
        fileSize: fileSize,
        fileSha256: fileSha256,
        localPath: sanitizeInvalidUtf16(localPath),
        inlineBytes: inlineBytes,
        voiceDurationMs: voiceDurationMs,
        replyToId: sanitizeInvalidUtf16(replyToId),
        replyToSender: sanitizeInvalidUtf16(replyToSender),
        replyToText: sanitizeInvalidUtf16(replyToText),
        forwardTitle: sanitizeInvalidUtf16(forwardTitle),
        forwardItems: forwardItems,
        connMode: sourceMode,
        connEndpoint:
            recordSource ? DirectPairingStore.connEndpointOf(sourceTarget) : '',
        connPort:
            recordSource ? DirectPairingStore.connPortOf(sourceTarget) : 0,
        srcPlatform: recordSource ? directChatPlatformLabel : '',
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
    final normalizedConversation = sanitizeInvalidUtf16(conversationId);
    final normalizedText = sanitizeInvalidUtf16(text);
    final normalizedSenderId = sanitizeInvalidUtf16(senderId);
    final now = DateTime.now().toUtc();
    return _write((state) async {
      // The session delivers the same legacy message twice (server + client
      // mode events). Return the first record instead of persisting a
      // duplicate entry for the same conversation.
      for (final existing in state.records.values) {
        if (existing.isOutgoing ||
            existing.conversationId != normalizedConversation) {
          continue;
        }
        if (existing.kind == DirectChatKind.text &&
            existing.text == normalizedText &&
            existing.senderId == normalizedSenderId &&
            now.difference(existing.sentAt).inSeconds < 10) {
          return existing;
        }
      }
      final record = DirectChatRecord(
        id: const Uuid().v4(),
        conversationId: sanitizeInvalidUtf16(conversationId),
        originDeviceId: 'legacy:$conversationId',
        originSequence: state.nextSequence++,
        direction: DirectChatDirection.incoming,
        kind: DirectChatKind.text,
        text: sanitizeInvalidUtf16(text),
        senderId: sanitizeInvalidUtf16(senderId),
        senderName: sanitizeInvalidUtf16(senderName),
        senderAvatar: sanitizeInvalidUtf16(senderAvatar),
        sentAt: DateTime.now().toUtc(),
        delivery: DirectChatDelivery.delivered,
        connMode: DirectPairingStore.classifyConnMode(conversationId),
        connEndpoint: DirectPairingStore.connEndpointOf(conversationId),
        connPort: DirectPairingStore.connPortOf(conversationId),
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
      final reactions = Map<String, List<String>>.from(record.reactions);
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
        text: sanitizeInvalidUtf16(newText),
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

  /// Merges conversations that belong to the same person into a single
  /// primary conversation. A device that reinstalls the app gets a new id and
  /// a new conversation key; without this merge the same phone shows up as
  /// several entries and new messages land in a conversation the user is not
  /// looking at ("message only appears after switching chats").
  ///
  /// A person is identified by the paired account when a pairing exists,
  /// otherwise by the sender display name plus platform. The primary key
  /// prefers the paired conversation, then the conversation with the newest
  /// record. Returns the old->new conversation remap so in-memory state can
  /// follow the storage.
  Future<Map<String, String>> mergeSamePersonConversations() async {
    final remap = <String, String>{};
    await _write((state) async {
      final pairings = DirectPairingStore.load();
      final byPerson = <String, List<DirectChatRecord>>{};
      for (final record in state.records.values) {
        final conversationId = record.conversationId.trim();
        if (conversationId.isEmpty || conversationId == 'filehelper') {
          continue;
        }
        final canonical = DirectPairingStore.canonicalConversationIdValue(
          conversationId,
          pairings: pairings,
        );
        // Account-based and pairing-resolved conversations share one person
        // key; legacy device-keyed conversations group by the exact sender
        // name so different people never collapse into one conversation.
        final String person;
        if (DirectPairingStore.stableAccountConversationId(
              conversationId,
            ).isNotEmpty ||
            (canonical.isNotEmpty && canonical != conversationId)) {
          person = 'acct:$canonical';
        } else {
          final name = record.senderName.trim();
          person = name.isNotEmpty ? 'name:$name' : 'key:$conversationId';
        }
        byPerson.putIfAbsent(person, () => <DirectChatRecord>[]).add(record);
      }
      final primaryOfPerson = <String, String>{};
      for (final entry in byPerson.entries) {
        final records = entry.value;
        if (records.length < 2) continue;
        String? primary;
        // Prefer the newest account-based conversation as the primary so
        // legacy device-keyed records merge into the person account instead
        // of the account conversation being pulled into a stale aggregate.
        DirectChatRecord? newestAccount;
        for (final record in records) {
          if (DirectPairingStore.stableAccountConversationId(
                record.conversationId,
              ).isNotEmpty &&
              (newestAccount == null ||
                  record.sentAt.isAfter(newestAccount.sentAt))) {
            newestAccount = record;
          }
        }
        if (newestAccount != null) {
          primary = newestAccount.conversationId;
        } else {
          var newest = records.first;
          for (final record in records.skip(1)) {
            if (record.sentAt.isAfter(newest.sentAt)) newest = record;
          }
          primary = newest.conversationId;
        }
        primaryOfPerson[entry.key] = primary;
      }
      for (final entry in byPerson.entries) {
        final primary = primaryOfPerson[entry.key];
        if (primary == null) continue;
        for (final record in entry.value) {
          if (record.conversationId != primary) {
            final old = record.conversationId;
            state.records[record.id] = record.copyWith(conversationId: primary);
            remap[old] = primary;
          }
        }
      }
    });
    if (remap.isNotEmpty) revision.value++;
    return remap;
  }

  /// Returns records for a conversation, newest first.
  /// If [limit] is set, only the newest [limit] records are returned.
  /// Links a file that was delivered by the transfer subsystem back to the
  /// chat record that announced it (same file name + size, empty localPath),
  /// so tapping the message can preview the received file. Returns true when
  /// at least one record was updated.
  Future<bool> linkReceivedTransferFile({
    required String conversationId,
    required String fileName,
    required int fileSize,
    required String localPath,
  }) {
    if (conversationId.isEmpty || fileName.isEmpty || localPath.isEmpty) {
      return Future<bool>.value(false);
    }
    return _write((state) async {
      var updated = false;
      for (final entry in state.records.entries) {
        final record = entry.value;
        if (record.conversationId != conversationId ||
            record.fileName != fileName ||
            record.localPath.isNotEmpty ||
            (fileSize > 0 && record.fileSize != fileSize)) {
          continue;
        }
        state.records[entry.key] = record.copyWith(localPath: localPath);
        updated = true;
      }
      return updated;
    });
  }

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

  /// Returns one newest visible record per conversation using a single
  /// storage snapshot. This keeps startup work proportional to total history
  /// instead of re-reading and decoding the same file for every conversation.
  Future<Map<String, DirectChatRecord>> latestConversations() async {
    await _pendingWrite;
    final latest = <String, DirectChatRecord>{};
    for (final record in (await _freshState()).records.values) {
      if (record.disposition == DirectChatDisposition.destroyed ||
          record.isExpired ||
          record.conversationId.isEmpty) {
        continue;
      }
      final previous = latest[record.conversationId];
      if (previous == null || record.sentAt.isAfter(previous.sentAt)) {
        latest[record.conversationId] = record;
      }
    }
    return latest;
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
/// are sent as metadata only —full file-transfer-subsystem delivery is not yet
/// wired, so keep attachments within this budget (covers images & small docs).
const int kMaxInlineChatFileBytes = 5 * 1024 * 1024;

bool canInlineDirectChatFile(int fileSize) =>
    fileSize > 0 && fileSize <= kMaxInlineChatFileBytes;

/// Persists inline file bytes received over chat and returns the saved path so
/// the preview UI can open them directly. Returns null on any error.
/// Copy a file into the built-in "File Transfer Assistant" storage so the
/// record keeps a stable local copy even if the original is moved/deleted.
Future<String?> saveFileHelperFile(String fileName, String sourcePath) async {
  try {
    final base = await getApplicationDocumentsDirectory();
    final dir =
        Directory('${base.path}${Platform.pathSeparator}luoda_file_helper');
    await dir.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[^0-9a-zA-Z._\-]'), '_');
    final target = File('${dir.path}${Platform.pathSeparator}$safeName');
    await target.writeAsBytes(await File(sourcePath).readAsBytes(),
        flush: true);
    return target.path;
  } catch (e) {
    debugPrint('Failed to save file-helper file: $e');
    return null;
  }
}

Future<String?> saveInlineChatFile(String fileName, List<int> bytes) async {
  try {
    final base = await getApplicationDocumentsDirectory();
    final dir =
        Directory('${base.path}${Platform.pathSeparator}luoda_chat_received');
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
