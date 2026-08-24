import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'direct_chat_sqlite.dart';
import 'direct_chat_storage.dart';
import 'direct_pairing.dart';
import 'string_utils.dart';

enum DirectChatDelivery { queued, sent, delivered, failed }

enum DirectChatDirection { incoming, outgoing }

enum DirectChatKind {
 text,
 file,
 voice,
 forward,
 image,
 location,
 contact,
}

/// 个人名片消息：把一个联系人（好友/陌生人）以名片形式发给对话对方。
/// 与位置消息一样编码在消息 text 里：`[contact]peerId|name|platform`，
/// 不改变底层协议，老版本显示为纯文本，新版本渲染为名片卡片。
class DirectChatContact {
  const DirectChatContact({
    required this.peerId,
    this.name = '',
    this.platform = '',
  });

  final String peerId;
  final String name;
  final String platform;

  String encode() {
    final n = name.trim();
    final p = platform.trim();
    return '[contact]$peerId${n.isEmpty ? '' : '|$n'}'
        '${p.isEmpty ? '' : '|$p'}';
  }

  static DirectChatContact? tryParse(String text) {
    final t = text.trim();
    if (!t.startsWith('[contact]')) return null;
    final body = t.substring('[contact]'.length);
    final parts = body.split('|');
    if (parts.isEmpty || parts.first.trim().isEmpty) return null;
    final peerId = parts.first.trim();
    final name = parts.length > 1 ? parts[1].trim() : '';
    final platform = parts.length > 2 ? parts[2].trim() : '';
    return DirectChatContact(
      peerId: peerId,
      name: name,
      platform: platform,
    );
  }
}

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

/// Thin facade over [DirectChatSqlite] that preserves the exact public API
/// every caller (62 sites) already uses. All persistence now goes through
/// SQLite (WAL mode, indexed queries, no FileLock) — the same approach
/// WeChat's WCDB uses internally.
class DirectChatRepository {
  DirectChatRepository._();

  static final instance = DirectChatRepository._();

/// Test hook: isolates the repository from the real on-disk store.
@visibleForTesting
static DirectChatStorage? debugStorageOverride;

/// Test hook: overrides the SQLite database directory for isolation.
@visibleForTesting
static String? debugDbDirOverride;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  DirectChatSqlite get _db => DirectChatSqlite.instance;

/// Test hook: clears all persisted state so each test starts fresh.
@visibleForTesting
Future<void> resetForTest() async {
// Point the SQLite store at the test's temp dir if an override is set.
DirectChatSqlite.debugDbDirOverride = debugDbDirOverride;
await _db.resetForTest();
}

  Future<String> get deviceId => _db.deviceId;

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
    return _db.createOutgoing(
      id: id,
      conversationId: conversationId,
      kind: kind,
      text: text,
      senderId: senderId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      fileName: fileName,
      fileSize: fileSize,
      fileSha256: fileSha256,
      localPath: localPath,
      inlineBytes: inlineBytes,
      voiceDurationMs: voiceDurationMs,
      replyToId: replyToId,
      replyToSender: replyToSender,
      replyToText: replyToText,
      forwardTitle: forwardTitle,
      forwardItems: forwardItems,
      connectionTarget: connectionTarget,
      recordSource: recordSource,
    ).then((record) {
      revision.value++;
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
    return _db.createIncomingLegacy(
      conversationId: conversationId,
      text: text,
      senderId: senderId,
      senderName: senderName,
      senderAvatar: senderAvatar,
    ).then((record) {
      revision.value++;
      return record!;
    });
  }

  Future<bool> upsert(DirectChatRecord record) {
    return _db.upsert(record).then((changed) {
      if (changed) revision.value++;
      return changed;
    });
  }

  Future<DirectChatRecord?> mutateOutgoing(
    String conversationId,
    String id,
    DirectChatDisposition disposition,
  ) {
    return _db.mutateOutgoing(conversationId, id, disposition).then((r) {
      if (r != null) revision.value++;
      return r;
    });
  }

  Future<DirectChatRecord?> setSelfDestruct(
    String conversationId,
    String id,
    Duration duration,
  ) {
    return _db.setSelfDestruct(conversationId, id, duration).then((r) {
      if (r != null) revision.value++;
      return r;
    });
  }

  Future<void> markDelivery(String id, DirectChatDelivery delivery) {
    return _db.markDelivery(id, delivery).then((_) {
      revision.value++;
    });
  }

  Future<DirectChatRecord?> toggleReaction(
    String id,
    String emoji,
    String deviceId,
  ) {
    return _db.toggleReaction(id, emoji, deviceId).then((r) {
      if (r != null) revision.value++;
      return r;
    });
  }

  Future<DirectChatRecord?> editText(String id, String newText) {
    return _db.editText(id, newText).then((r) {
      if (r != null) revision.value++;
      return r;
    });
  }

  Future<List<DirectChatRecord>> mediaForConversation(
          String conversationId) =>
      _db.mediaForConversation(conversationId);

  Future<void> markUndeliveredFailed(String conversationId) {
    return _db.markUndeliveredFailed(conversationId).then((_) {
      revision.value++;
    });
  }

  Future<void> markUndeliveredQueued(String conversationId) {
    return _db.markUndeliveredQueued(conversationId).then((_) {
      revision.value++;
    });
  }

  Future<void> remapConversation(String from, String to) {
    return _db.remapConversation(from, to).then((_) {
      revision.value++;
    });
  }

  Future<Map<String, String>> mergeSamePersonConversations() async {
    // Delegate to the pairing store's canonical conversation id.
    // The old JSON store re-wrote every record in a single transaction;
    // with SQLite we do per-record UPDATE which is faster and safer.
    final pairings = DirectPairingStore.load();
    final conversations = await _db.conversationIds();
    final remap = <String, String>{};
    for (final convId in conversations) {
      if (convId.isEmpty || convId == 'filehelper') continue;
      final canonical =
          DirectPairingStore.canonicalConversationIdValue(
              convId, pairings: pairings);
      if (canonical.isNotEmpty && canonical != convId) {
        await _db.remapConversation(convId, canonical);
        remap[convId] = canonical;
      }
    }
    if (remap.isNotEmpty) revision.value++;
    return remap;
  }

  Future<bool> linkReceivedTransferFile({
    required String conversationId,
    required String fileName,
    required int fileSize,
    required String localPath,
  }) {
    return _db.linkReceivedTransferFile(
      conversationId: conversationId,
      fileName: fileName,
      fileSize: fileSize,
      localPath: localPath,
    ).then((updated) {
      if (updated) revision.value++;
      return updated;
    });
  }

  Future<List<DirectChatRecord>> forConversation(
    String conversationId, {
    int? limit,
  }) =>
      _db.forConversation(conversationId, limit: limit);

  Future<List<String>> conversationIds() => _db.conversationIds();

  Future<Map<String, DirectChatRecord>> latestConversations() =>
      _db.latestConversations();

  Future<Map<String, int>> cursor({String? conversationId}) =>
      _db.cursor(conversationId: conversationId);

  Future<List<DirectChatRecord>> afterCursor(
    Map<String, int> cursor, {
    String? conversationId,
    bool outgoingOnly = false,
  }) =>
      _db.afterCursor(cursor,
          conversationId: conversationId,
          outgoingOnly: outgoingOnly);

  Future<List<DirectChatRecord>> pendingFor(String conversationId) =>
      _db.pendingFor(conversationId);

  Future<DirectChatRecord?> find(String id) => _db.find(id);

  Future<void> deleteRecord(String id, String conversationId) {
    return _db.deleteRecord(id, conversationId).then((_) {
      revision.value++;
    });
  }

  Future<void> deleteConversations(Iterable<String> conversationIds) {
    return _db.deleteConversations(conversationIds).then((_) {
      revision.value++;
    });
  }

  Future<int> purgeExpired() {
    return _db.purgeExpired().then((count) {
      if (count > 0) revision.value++;
      return count;
    });
  }

  /// Detects writes by another process using a lightweight SQL aggregate
  /// (COUNT + MAX(sent_at)) instead of the old JSON-store mtime+signature
  /// poll. SQLite WAL makes cross-process writes instantly visible.
  Future<bool> hasExternalStorageChanges() =>
      _db.hasExternalChanges();
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
