import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../common.dart';
import 'platform_model.dart';

const kCategoryStoreOption = 'contact_categories';
const kPeerCategoryMapOption = 'contact_peer_category_map';

/// 分类模型 - 持久化存储在本地 key-value store
class ContactCategory {
  final String id;
  String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  ContactCategory({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ContactCategory.create({
    required String id,
    required String name,
  }) {
    final now = DateTime.now();
    return ContactCategory(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
    );
  }

  ContactCategory copyWith({
    String? name,
  }) {
    return ContactCategory(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ContactCategory.fromJson(Map<String, dynamic> json) =>
      ContactCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

/// 联系人分类状态管理
class ContactCategoryModel {
  final RxList<ContactCategory> categories = <ContactCategory>[].obs;
  final RxMap<String, String> _peerCategoryMap = <String, String>{}.obs;

  /// 获取所有分类名称（按创建时间排序）
  List<String> get categoryNames => categories.map((c) => c.name).toList();

  /// 获取联系人的分类名称，未分类返回 null
  String? getPeerCategory(String peerId) => _peerCategoryMap[peerId];

  /// 设置联系人的分类
  void setPeerCategory(String peerId, String categoryName) {
    _peerCategoryMap[peerId] = categoryName;
    _savePeerCategoryMap();
  }

  /// 移除联系人的分类
  void removePeerCategory(String peerId) {
    _peerCategoryMap.remove(peerId);
    _savePeerCategoryMap();
  }

  /// 获取属于某个分类的所有联系人 ID
  List<String> getPeersInCategory(String categoryName) {
    return _peerCategoryMap.entries
        .where((entry) => entry.value == categoryName)
        .map((entry) => entry.key)
        .toList();
  }

  /// 创建新分类
  void addCategory(String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;
    if (categories.any((c) => c.name.toLowerCase() == trimmedName.toLowerCase())) {
      return; // 分类名已存在
    }
    final newCategory = ContactCategory.create(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: trimmedName,
    );
    categories.add(newCategory);
    _saveCategories();
  }

  /// 重命名分类
  void renameCategory(String oldId, String newName) {
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) return;
    final idx = categories.indexWhere((c) => c.id == oldId);
    if (idx == -1) return;
    // 检查重名
    if (categories.any((c) => c.name.toLowerCase() == trimmedName.toLowerCase())) {
      return;
    }
    // 更新分类名
    final oldName = categories[idx].name;
    final updated = categories[idx].copyWith(name: trimmedName);
    categories[idx] = updated;
    // 更新所有属于该分类的联系人映射
    for (final entry in _peerCategoryMap.entries.toList()) {
      if (entry.value == oldName) {
        _peerCategoryMap[entry.key] = trimmedName;
      }
    }
    _saveCategories();
    _savePeerCategoryMap();
  }

  /// 删除分类（联系人变为未分类）
  void deleteCategory(String id) {
    final category = categories.firstWhereOrNull((c) => c.id == id);
    if (category == null) return;
    // 将该分类下的所有联系人变为未分类
    for (final peerId in getPeersInCategory(category.name)) {
      _peerCategoryMap.remove(peerId);
    }
    categories.removeWhere((c) => c.id == id);
    _saveCategories();
    _savePeerCategoryMap();
  }

  /// 获取分类下的联系人数量
  int getCategoryCount(String categoryName) {
    return getPeersInCategory(categoryName).length;
  }

  /// 持久化分类列表
  void _saveCategories() {
    final json = categories.map((c) => c.toJson()).toList();
    bind.mainSetLocalOption(key: kCategoryStoreOption, value: jsonEncode(json));
  }

  /// 持久化联系人-分类映射
  void _savePeerCategoryMap() {
    bind.mainSetLocalOption(
      key: kPeerCategoryMapOption,
      value: jsonEncode(_peerCategoryMap),
    );
  }

  /// 从持久化存储加载
  void load() {
    // 加载分类列表
    final rawCategories = bind.mainGetLocalOption(key: kCategoryStoreOption);
    if (rawCategories.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCategories);
        if (decoded is List) {
          categories.assignAll(
            decoded.map((item) => ContactCategory.fromJson(item as Map<String, dynamic>)),
          );
        }
      } catch (e) {
        debugPrint('Failed to load contact categories: $e');
      }
    }

    // 加载联系人-分类映射
    final rawMap = bind.mainGetLocalOption(key: kPeerCategoryMapOption);
    if (rawMap.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMap);
        if (decoded is Map) {
          _peerCategoryMap.assignAll(Map<String, String>.fromEntries(
            decoded.entries.map((e) => MapEntry(e.key.toString(), e.value.toString())),
          ));
        }
      } catch (e) {
        debugPrint('Failed to load peer category map: $e');
      }
    }
  }

  /// 清空所有数据（用于重置）
  void clear() {
    categories.clear();
    _peerCategoryMap.clear();
    bind.mainSetLocalOption(key: kCategoryStoreOption, value: '');
    bind.mainSetLocalOption(key: kPeerCategoryMapOption, value: '');
  }
}
