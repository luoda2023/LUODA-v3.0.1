import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/favorites_model.dart';
import 'package:luoda_flutter/models/chat_model.dart';

/// 把一条收藏项作为消息发送到当前打开的会话。
/// 支持：文字 / 位置 / 图片 / 文件 / 语音 / 聊天记录（合并转发）。
/// 返回是否发送成功。
Future<bool> sendFavoriteItemToChat(
  ChatModel chatModel,
  FavoriteItem item,
) async {
  final key = chatModel.currentKey;
  if (key == null || key.peerId.isEmpty) return false;

  switch (item.type) {
    case FavoriteItemType.location:
      final lat = double.tryParse('${item.extra['lat'] ?? ''}');
      final lng = double.tryParse('${item.extra['lng'] ?? ''}');
      if (lat == null || lng == null) return false;
      chatModel.sendText(
        DirectChatLocation(
          latitude: lat,
          longitude: lng,
          name: (item.extra['name'] ?? item.title ?? '').toString(),
          address: (item.extra['address'] ?? item.subtitle ?? '').toString(),
        ).encode(),
      );
      return true;

    case FavoriteItemType.image:
    case FavoriteItemType.file:
    case FavoriteItemType.voice:
      final path = item.localPath;
      if (path == null || path.isEmpty) return false;
      await chatModel.sendFileRecord(
        fileName: fileNameOfFavorite(item),
        fileSize: item.fileSize,
        localPath: path,
      );
      return true;

    case FavoriteItemType.forward:
      // 聊天记录：合并转发（保留发送者/内容）。
      final msgs = item.chatMessages;
      if (msgs.isNotEmpty) {
        final items = <DirectChatForwardItem>[
          for (final m in msgs)
            DirectChatForwardItem(
              senderName: (m['sender'] ?? '').toString(),
              kind: _kindOf(m),
              text: (m['text'] ?? '').toString(),
              fileName: (m['file_name'] ?? '').toString(),
              voiceDurationMs:
                  int.tryParse('${m['voice_duration_ms'] ?? 0}') ?? 0,
            ),
        ];
        await chatModel.sendForwardBundle(
          title: item.title?.isNotEmpty == true
              ? item.title!
              : '${item.peerName}的聊天记录',
          items: items,
        );
        return true;
      }
      final forwardItems = item.forwardItems;
      if (forwardItems.isNotEmpty) {
        final items = <DirectChatForwardItem>[
          for (final m in forwardItems)
            DirectChatForwardItem(
              senderName: (m['sender_name'] ?? '').toString(),
              kind: _kindOfName(
                (m['kind'] ?? '').toString(),
              ),
              text: (m['text'] ?? '').toString(),
              fileName: (m['file_name'] ?? '').toString(),
              voiceDurationMs:
                  int.tryParse('${m['voice_duration_ms'] ?? 0}') ?? 0,
            ),
        ];
        await chatModel.sendForwardBundle(
          title: (item.extra['forward_title'] ?? item.title ?? '')
              .toString(),
          items: items,
        );
        return true;
      }
      return false;

    case FavoriteItemType.text:
    default:
      final text = item.title ?? '';
      if (text.trim().isEmpty) return false;
      chatModel.sendText(text);
      return true;
  }
}

String fileNameOfFavorite(FavoriteItem item) {
  final path = item.localPath;
  if (path != null && path.isNotEmpty) {
    final parts = path.split(RegExp(r'[/\\]'));
    final name = parts.isNotEmpty ? parts.last : '';
    if (name.isNotEmpty) return name;
  }
  return item.title ?? 'file';
}

DirectChatKind _kindOf(Map<String, dynamic> m) =>
    _kindOfName((m['kind'] ?? 'text').toString());

DirectChatKind _kindOfName(String name) {
  return DirectChatKind.values.firstWhere(
    (value) => value.name == name,
    orElse: () => DirectChatKind.text,
  );
}
