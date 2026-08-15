import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/favorites_model.dart';
import 'package:luoda_flutter/common/favorites_send.dart';
import 'package:luoda_flutter/models/chat_model.dart';

/// 发送收藏的选择器分类（与收藏页一致，发送场景不含「联系人」）。
const List<(String, IconData)> _sendCategories = <(String, IconData)>[
  ('all', Icons.apps_rounded),
  ('image', Icons.image_rounded),
  ('file', Icons.insert_drive_file_outlined),
  ('location', Icons.location_on_outlined),
  ('chat', Icons.chat_bubble_outline_rounded),
  ('voice', Icons.mic_rounded),
  ('text', Icons.notes_rounded),
];

/// 打开「从收藏选择发送」的底部选择器，带搜索框和分类筛选，
/// 选中后把该收藏项作为消息发到当前会话。
/// 手机端 + 面板与 PC 端输入栏共用此入口，保证两端体验一致。
/// 返回是否成功发送。
Future<bool> pickFavoriteToSend(
  BuildContext context,
  ChatModel chatModel, {
  required bool dark,
}) async {
  final fav = FavoritesModel.instance;
  await fav.load();
  final items = fav.items;
  if (items.isEmpty) {
    showToast(translate('favorites_empty'));
    return false;
  }
  final picked = await showModalBottomSheet<FavoriteItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: dark ? const Color(0xFF1E2024) : const Color(0xFFF7F7F7),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => _FavoriteSendPicker(items: items, dark: dark),
  );
  if (picked == null) return false;
  await sendFavoriteItemToChat(chatModel, picked);
  showToast(translate('Sent'));
  return true;
}

/// 收藏发送选择器：搜索框 + 分类筛选 + 列表。
class _FavoriteSendPicker extends StatefulWidget {
  const _FavoriteSendPicker({required this.items, required this.dark});

  final List<FavoriteItem> items;
  final bool dark;

  @override
  State<_FavoriteSendPicker> createState() => _FavoriteSendPickerState();
}

class _FavoriteSendPickerState extends State<_FavoriteSendPicker> {
  String _category = 'all';
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FavoriteItem> _filtered() {
    final target = _category == 'all' || _category == 'chat'
        ? (_category == 'chat' ? FavoriteItemType.forward : null)
        : _category;
    var items = widget.items.where((e) {
      if (target == null) return true;
      return e.type == target;
    }).toList();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items
          .where((e) =>
              (e.title ?? '').toLowerCase().contains(q) ||
              (e.subtitle ?? '').toLowerCase().contains(q) ||
              e.peerName.toLowerCase().contains(q))
          .toList();
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final primary = const Color(0xFF07C160);
    final items = _filtered();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, scrollController) => Column(
        children: <Widget>[
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: dark ? Colors.white54 : Colors.black45,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    translate('Pick from Favorites'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: dark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: dark ? Colors.white38 : Colors.black38,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF2A2D33) : const Color(0xFFF2F3F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 10),
                  Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: dark ? Colors.white38 : Colors.black38,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(
                        fontSize: 14,
                        color: dark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: translate('Search favorites'),
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: dark ? Colors.white30 : Colors.black26,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 9),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 30, minHeight: 30),
                      icon: Icon(
                        Icons.cancel_rounded,
                        size: 16,
                        color: dark ? Colors.white30 : Colors.black26,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          // 分类筛选（横向 chip）
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _sendCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final key = _sendCategories[index].$1;
                final icon = _sendCategories[index].$2;
                final selected = _category == key;
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _category = key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? primary.withOpacity(dark ? 0.22 : 0.12)
                          : (dark
                              ? const Color(0xFF2A2D33)
                              : const Color(0xFFF2F3F5)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          icon,
                          size: 15,
                          color: selected
                              ? primary
                              : (dark ? Colors.white54 : Colors.black45),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          translate('favorites_cat_$key'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected
                                ? primary
                                : (dark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          // 列表
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      translate('favorites_empty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: dark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return _favoritePickTile(context, item, dark);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Widget _favoritePickTile(
  BuildContext sheetContext,
  FavoriteItem item,
  bool dark,
) {
  final IconData icon;
  final Color color;
  switch (item.type) {
    case FavoriteItemType.image:
      icon = Icons.image_outlined;
      color = const Color(0xFF3B82F6);
    case FavoriteItemType.file:
      icon = Icons.insert_drive_file_outlined;
      color = const Color(0xFF3B82F6);
    case FavoriteItemType.location:
      icon = Icons.location_on_rounded;
      color = const Color(0xFF07C160);
    case FavoriteItemType.voice:
      icon = Icons.mic_rounded;
      color = const Color(0xFF07C160);
    case FavoriteItemType.forward:
      icon = Icons.forward_rounded;
      color = const Color(0xFF8B5CF6);
    default:
      icon = Icons.notes_rounded;
      color = const Color(0xFFF59E0B);
  }
  final title = item.title ?? '';
  final sub = <String>[
    item.peerName,
    if ((item.subtitle ?? '').isNotEmpty) item.subtitle!,
  ].join(' · ');
  return ListTile(
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: color),
    ),
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14.5,
        color: dark ? Colors.white : Colors.black87,
      ),
    ),
    subtitle: Text(
      sub,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: dark ? Colors.white38 : Colors.black45,
      ),
    ),
    onTap: () => Navigator.pop(sheetContext, item),
  );
}
