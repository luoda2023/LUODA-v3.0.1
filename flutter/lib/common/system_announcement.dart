import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/platform_model.dart';

/// 一条系统通知（由 dotchat 服务器后台发布）。
class SystemAnnouncement {
  const SystemAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    required this.level,
    required this.pinned,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String content;
  final int level; // 1=普通 2=重要
  final bool pinned;
  final DateTime createdAt;

  bool get important => level >= 2;

  factory SystemAnnouncement.fromJson(Map<String, dynamic> json) {
    final raw = (json['created_at'] ?? '').toString().trim();
    var created = DateTime.now();
    if (raw.isNotEmpty) {
      created = DateTime.tryParse(raw.replaceFirst(' ', 'T')) ?? created;
    }
    return SystemAnnouncement(
      id: (json['id'] ?? 0) is int
          ? (json['id'] as int)
          : int.tryParse('${json['id'] ?? 0}') ?? 0,
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      level: int.tryParse('${json['level'] ?? 1}') ?? 1,
      pinned: (json['pinned'] ?? 0) == 1 || json['pinned'] == true,
      createdAt: created,
    );
  }
}

/// 系统通知本地状态：拉取、未读计数、已读标记。
class SystemAnnouncementStore {
  SystemAnnouncementStore._();

  static final SystemAnnouncementStore instance = SystemAnnouncementStore._();

  static const String _readKey = 'sys-announce-last-read-id';
  static const String _readSetKey = 'sys-announce-read-ids';

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  List<SystemAnnouncement> _items = const <SystemAnnouncement>[];
  int _lastReadId = 0;
  final Set<int> _readIds = <int>{};
  bool _loaded = false;

  List<SystemAnnouncement> get items => _items;

  /// 单条已读状态（含批量已读：id <= lastReadId）。
  bool isRead(SystemAnnouncement a) =>
      a.id <= _lastReadId || _readIds.contains(a.id);

  int get unreadCount {
    if (_items.isEmpty) return 0;
    return _items.where((a) => !isRead(a)).length;
  }

  int get lastReadId => _lastReadId;

  void load() {
    if (_loaded) return;
    _loaded = true;
    try {
      _lastReadId =
          int.tryParse(bind.mainGetLocalOption(key: _readKey).trim()) ?? 0;
    } catch (_) {
      _lastReadId = 0;
    }
    try {
      final raw = bind.mainGetLocalOption(key: _readSetKey).trim();
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final v in decoded) {
            final id = v is int ? v : int.tryParse('$v');
            if (id != null) _readIds.add(id);
          }
        }
      }
    } catch (_) {
      // 已读集合损坏时忽略，仅影响单条已读状态。
    }
  }

  Future<void> _saveReadState() async {
    try {
      await bind.mainSetLocalOption(key: _readKey, value: '$_lastReadId');
      await bind.mainSetLocalOption(
        key: _readSetKey,
        value: jsonEncode(_readIds.toList()..sort()),
      );
    } catch (_) {
      // 写入失败只影响下次已读状态。
    }
  }

  /// 从服务器拉取已发布的系统通知（公开接口，无需登录）。
  Future<void> refresh() async {
    try {
      final api = await bind.mainGetApiServer();
      if (api.trim().isEmpty) return;
      final url = '${api.trim()}/api/announcements';
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return;
      final data = decoded['data'];
      List<dynamic> list;
      if (data is Map<String, dynamic>) {
        list = (data['list'] is List) ? data['list'] as List : const <dynamic>[];
      } else {
        return;
      }
      final items = <SystemAnnouncement>[];
      for (final raw in list) {
        if (raw is Map<String, dynamic>) {
          items.add(SystemAnnouncement.fromJson(raw));
        }
      }
      // 重要/置顶通知排最前（重要优先于置顶，其余按 id 降序）。
      items.sort((a, b) {
        final aTop = a.important || a.pinned;
        final bTop = b.important || b.pinned;
        if (aTop != bTop) return aTop ? -1 : 1;
        return b.id.compareTo(a.id);
      });
      _items = items;
      revision.value++;
    } catch (_) {
      // 拉取失败静默忽略：下次进入/定时再试。
    }
  }

  /// 标记单条已读（点击进入详情时调用，持久化保存）。
  Future<void> markRead(int id) async {
    if (_readIds.contains(id)) return;
    _readIds.add(id);
    await _saveReadState();
    revision.value++;
  }

  /// 标记全部已读。
  Future<void> markAllRead() async {
    if (_items.isEmpty) return;
    _lastReadId = _items.map((a) => a.id).reduce(math.max);
    _readIds.clear();
    await _saveReadState();
    revision.value++;
  }
}
