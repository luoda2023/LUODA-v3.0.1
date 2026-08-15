import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/favorites_model.dart';
import 'package:luoda_flutter/common/favorites_send.dart';
import 'package:luoda_flutter/models/chat_model.dart';

/// 打开「从收藏选择发送」的底部选择器，选中后把该收藏项作为消息发到当前会话。
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
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (_, scrollController) => Column(
        children: <Widget>[
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
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: items.length,
              itemBuilder: (_, index) {
                final item = items[index];
                return _favoritePickTile(sheetContext, item, dark);
              },
            ),
          ),
        ],
      ),
    ),
  );
  if (picked == null) return false;
  await sendFavoriteItemToChat(chatModel, picked);
  showToast(translate('Sent'));
  return true;
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
