import 'dart:convert';
import 'dart:io';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/foundation.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/widgets/file_preview_types.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:path/path.dart' as p;

/// 收藏项类型（与微信收藏分类对应）。
class FavoriteItemType {
  static const String image = 'image'; // 图片
  static const String file = 'file'; // 文件
  static const String location = 'location'; // 位置
  static const String text = 'text'; // 文字 / 聊天记录
  static const String voice = 'voice'; // 语音
  static const String forward = 'forward'; // 聊天记录（多条转发）
}

/// 一条收藏记录：可以收藏图片 / 文件 / 位置 / 文字 / 语音 / 聊天记录。
class FavoriteItem {
  final String id; // 唯一 id
  final String type; // FavoriteItemType
  final String peerId; // 来源联系人 id
  final String peerName; // 来源联系人名称
  final int createdAt; // 收藏时间（毫秒）
  final String? title; // 文本内容 / 文件名 / 位置名
  final String? subtitle; // 副标题（文件大小 / 地址 / 语音时长等）
  final String? localPath; // 图片 / 文件本地路径
  final int fileSize;
  final Map<String, dynamic> extra; // 位置坐标等扩展数据

  const FavoriteItem({
    required this.id,
    required this.type,
    required this.peerId,
    required this.peerName,
    required this.createdAt,
    this.title,
    this.subtitle,
    this.localPath,
    this.fileSize = 0,
    this.extra = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'peer_id': peerId,
        'peer_name': peerName,
        'created_at': createdAt,
        'title': title,
        'subtitle': subtitle,
        'local_path': localPath,
        'file_size': fileSize,
        'extra': extra,
      };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
        id: (json['id'] ?? '').toString(),
        type: (json['type'] ?? FavoriteItemType.text).toString(),
        peerId: (json['peer_id'] ?? '').toString(),
        peerName: (json['peer_name'] ?? '').toString(),
        createdAt: int.tryParse('${json['created_at'] ?? 0}') ?? 0,
        title: json['title']?.toString(),
        subtitle: json['subtitle']?.toString(),
        localPath: json['local_path']?.toString(),
        fileSize: int.tryParse('${json['file_size'] ?? 0}') ?? 0,
        extra: (json['extra'] is Map<String, dynamic>)
            ? json['extra'] as Map<String, dynamic>
            : <String, dynamic>{},
      );

  /// 从一条聊天消息构造收藏项；返回 null 表示该消息不可收藏。
  factory FavoriteItem.fromMessage(ChatMessage message, {String peerName = ''}) {
    final properties = message.customProperties ?? <String, dynamic>{};
    final kind = (properties['ldesk_kind'] ?? 'text').toString();
    final location = DirectChatLocation.tryParse(message.text ?? '');
    final localPath = (properties['ldesk_local_path'] ?? '').toString();
    final fileName = (properties['ldesk_file_name'] ?? '').toString();
    final fileSize =
        int.tryParse('${properties['ldesk_file_size'] ?? 0}') ?? 0;

    final String type;
    String? title;
    String? subtitle;
    Map<String, dynamic> extra = <String, dynamic>{};

    if (location != null) {
      type = FavoriteItemType.location;
      title = location.name.isNotEmpty ? location.name : '位置';
      subtitle = location.address;
      extra = <String, dynamic>{
        'lat': location.latitude,
        'lng': location.longitude,
        'name': location.name ?? '',
        'address': location.address ?? '',
      };
    } else if (kind == 'file' || kind == 'voice') {
      final isImage =
          fileName.isNotEmpty && filePreviewKindForName(fileName) == FilePreviewKind.image;
      if (kind == 'voice') {
        type = FavoriteItemType.voice;
        title = fileName.isNotEmpty ? fileName : '语音';
      } else if (isImage) {
        type = FavoriteItemType.image;
        title = fileName;
      } else {
        type = FavoriteItemType.file;
        title = fileName.isNotEmpty ? fileName : '文件';
        subtitle = formatFavoriteSize(fileSize);
      }
    } else if (kind == 'forward') {
      type = FavoriteItemType.forward;
      title = (properties['ldesk_forward_title'] ?? message.text ?? '')
          .toString();
      if (title.isEmpty) title = '聊天记录';
      // 保存完整聊天记录：标题 + 每条消息（发送者/内容/类型/文件名等）。
      final items = properties['ldesk_forward_items'];
      if (items is List) {
        extra['forward_items'] = items
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
      extra['forward_title'] = title;
    } else {
      type = FavoriteItemType.text;
      title = message.text ?? '';
    }

    return FavoriteItem(
      id: (properties['ldesk_id'] ?? '').toString().isNotEmpty
          ? 'msg-${properties['ldesk_id']}'
          : 'msg-${message.createdAt.microsecondsSinceEpoch}',
      type: type,
      peerId: message.user.id,
      peerName: peerName.isNotEmpty
          ? peerName
          : (message.user.firstName ?? ''),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      title: title,
      subtitle: subtitle,
      localPath: localPath.isNotEmpty ? localPath : null,
      fileSize: fileSize,
      extra: extra,
    );
  }

  /// 收藏的多条聊天记录（extra['messages']），每条结构见 fromMessages。
  List<Map<String, dynamic>> get chatMessages {
    final raw = extra['messages'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  /// 合并转发内容（extra['forward_items']），格式同 ldesk_forward_items。
  List<Map<String, dynamic>> get forwardItems {
    final raw = extra['forward_items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  /// 从多条聊天消息构造「聊天记录」收藏项：保留每条消息的收发时间、
  /// 发送者与内容，打开收藏后可按聊天记录样式完整回看。
  factory FavoriteItem.fromMessages({
    required List<ChatMessage> messages,
    required String peerId,
    required String peerName,
    required String meId,
    String category = FavoriteItemType.forward,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final msgs = <Map<String, dynamic>>[];
    for (final m in messages) {
      final properties = m.customProperties ?? <String, dynamic>{};
      final kind = (properties['ldesk_kind'] ?? 'text').toString();
      final location = DirectChatLocation.tryParse(m.text ?? '');
      final sender = m.user.firstName ?? m.user.id;
      final isMe = m.user.id == meId;
      final localPath = (properties['ldesk_local_path'] ?? '').toString();
      final fileName = (properties['ldesk_file_name'] ?? '').toString();
      final fileSize =
          int.tryParse('${properties['ldesk_file_size'] ?? 0}') ?? 0;
      final item = <String, dynamic>{
        'kind': kind,
        'text': m.text ?? '',
        'created_at': m.createdAt.millisecondsSinceEpoch,
        'sender': sender,
        'is_me': isMe,
        if (localPath.isNotEmpty) 'local_path': localPath,
        if (fileName.isNotEmpty) 'file_name': fileName,
        if (fileSize > 0) 'file_size': fileSize,
        if (location != null) ...<String, dynamic>{
          'lat': location.latitude,
          'lng': location.longitude,
          'name': location.name ?? '',
          'address': location.address ?? '',
        },
      };
      msgs.add(item);
    }
    final preview = switch (msgs.length) {
      0 => '聊天记录',
      1 => (msgs.first['text'] ?? '').toString().trim(),
      _ =>
        '${(msgs.first['text'] ?? '').toString().trim()}…（共 ${msgs.length} 条）',
    };
    return FavoriteItem(
      id: 'history-${now}-${messages.hashCode}',
      type: category,
      peerId: peerId,
      peerName: peerName,
      createdAt: now,
      title: preview,
      extra: <String, dynamic>{
        'messages': msgs,
        'count': msgs.length,
      },
    );
  }

  /// 判断某条消息是否已被收藏（按消息 id）。
  static bool sameMessage(FavoriteItem a, FavoriteItem b) =>
      a.id == b.id && a.peerId == b.peerId;
}

String formatFavoriteSize(int fileSize) {
  if (fileSize <= 0) return '';
  if (fileSize < 1024) return '$fileSize B';
  if (fileSize < 1024 * 1024) {
    return '${(fileSize / 1024).toStringAsFixed(1)} KB';
  }
  return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// 收藏仓库：本地 JSON 存储（PC 与手机共用），线程安全的 ChangeNotifier。
/// 联系人收藏继续使用原有 favoritePeersModel（mainGetFav），本模型只负责
/// 消息类收藏（图片 / 文件 / 位置 / 文字 / 语音 / 聊天记录）。
class FavoritesModel extends ChangeNotifier {
  FavoritesModel._();

  static FavoritesModel? _instance;
  static FavoritesModel get instance => _instance ??= FavoritesModel._();

  static const String _storageKey = 'favorite_items_v2';

  List<FavoriteItem> _items = <FavoriteItem>[];
  bool _loaded = false;

  List<FavoriteItem> get items => List<FavoriteItem>.unmodifiable(_items);

  bool get isLoaded => _loaded;

  /// 读取本地收藏（幂等，可多次调用）。
  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = bind.mainGetLocalOption(key: _storageKey);
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _items = decoded          .whereType<Map>()
          .map((e) => FavoriteItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
        }
      }
    } catch (e) {
      debugPrint('FavoritesModel.load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await bind.mainSetLocalOption(
        key: _storageKey,
        value: jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      // 存储不可用（如测试环境无原生绑定）时仅保留内存态。
      debugPrint('FavoritesModel._save failed: $e');
    }
    notifyListeners();
  }

  /// 收藏一条消息；已收藏则取消。返回操作后的收藏状态。
  Future<bool> toggleMessage(
    ChatMessage message, {
    String peerName = '',
  }) async {
    await load();
    final item = FavoriteItem.fromMessage(message, peerName: peerName);
    final existingIndex =
        _items.indexWhere((e) => FavoriteItem.sameMessage(e, item));
    if (existingIndex >= 0) {
      _items.removeAt(existingIndex);
      await _save();
      return false;
    }
    _items.insert(0, item);
    await _save();
    return true;
  }

  /// 判断某条消息是否已收藏。
  bool isMessageFavorited(ChatMessage message) {
    final item = FavoriteItem.fromMessage(message);
    return _items.any((e) => FavoriteItem.sameMessage(e, item));
  }

  /// 收藏多条聊天记录（保留每条收发时间，打开可按聊天记录样式回看）。
  /// 已存在相同聊天记录（同来源、同首条消息时间）时取消收藏。
  Future<bool> toggleChatHistory({
    required List<ChatMessage> messages,
    required String peerId,
    required String peerName,
    required String meId,
    String category = FavoriteItemType.forward,
  }) async {
    await load();
    if (messages.isEmpty) return false;
    final item = FavoriteItem.fromMessages(
      messages: messages,
      peerId: peerId,
      peerName: peerName,
      meId: meId,
      category: category,
    );
    final firstTs = messages.first.createdAt.millisecondsSinceEpoch;
    final existingIndex = _items.indexWhere(
      (e) =>
          e.type == category &&
          e.peerId == peerId &&
          (e.chatMessages.isNotEmpty
              ? (e.chatMessages.first['created_at'] ?? 0) == firstTs
              : false),
    );
    if (existingIndex >= 0) {
      _items.removeAt(existingIndex);
      await _save();
      return false;
    }
    _items.insert(0, item);
    await _save();
    return true;
  }

  /// 删除单条收藏。
  Future<void> remove(String id) async {
    await load();
    _items.removeWhere((e) => e.id == id);
    await _save();
  }

  /// 批量删除。
  Future<void> removeAll(Iterable<String> ids) async {
    await load();
    final set = ids.toSet();
    _items.removeWhere((e) => set.contains(e.id));
    await _save();
  }

  /// 按类型过滤（'chat' 映射到聊天记录 forward）。
  List<FavoriteItem> byType(String? type) {
    if (type == null || type == 'all') return List<FavoriteItem>.from(_items);
    final target = type == 'chat' ? FavoriteItemType.forward : type;
    return _items.where((e) => e.type == target).toList();
  }

  /// 文件路径可能失效（文件被移动/删除），用于收藏页判断。
  bool pathExists(FavoriteItem item) {
    final path = item.localPath;
    if (path == null || path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 图片收藏项的文件名（从路径取 basename）。
  String fileNameOf(FavoriteItem item) {
    final path = item.localPath;
    if (path == null || path.isEmpty) return item.title ?? '';
    return p.basename(path);
  }
}
