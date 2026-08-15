import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/favorites_model.dart';

/// 聊天记录收藏详情页：按微信聊天记录样式展示被收藏的完整聊天过程，
/// 每条消息带收发时间、发送者与内容（图片/文件/位置/语音/文字等）。
class FavoriteChatHistoryPage extends StatefulWidget {
  const FavoriteChatHistoryPage({
    super.key,
    required this.item,
  });

  final FavoriteItem item;

  @override
  State<FavoriteChatHistoryPage> createState() =>
      _FavoriteChatHistoryPageState();
}

class _FavoriteChatHistoryPageState extends State<FavoriteChatHistoryPage> {
  List<Map<String, dynamic>> get _messages => widget.item.chatMessages;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF15171B) : const Color(0xFFEDEDED);
    final items = _messages;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xFF1C1E23) : Colors.white,
        foregroundColor: dark ? Colors.white : Colors.black87,
        elevation: 0,
        centerTitle: false,
        title: Text(
          widget.item.title?.isNotEmpty == true
              ? widget.item.title!
              : translate('Chat history'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: translate('Copy'),
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: _copyAll,
          ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Text(
                translate('favorites_empty'),
                style: TextStyle(
                  fontSize: 14,
                  color: dark ? Colors.white38 : Colors.black38,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: items.length,
              itemBuilder: (_, index) {
                final item = items[index];
                return _MessageBubble(
                  item: item,
                  dark: dark,
                  showTime: _shouldShowTime(index),
                );
              },
            ),
    );
  }

  bool _shouldShowTime(int index) {
    if (index == 0) return true;
    final prev = _messages[index - 1];
    final cur = _messages[index];
    final prevTs = int.tryParse('${prev['created_at'] ?? 0}') ?? 0;
    final curTs = int.tryParse('${cur['created_at'] ?? 0}') ?? 0;
    // 相邻消息间隔超过 5 分钟或发送者不同时，显示时间分隔。
    if ((prev['sender'] ?? '') != (cur['sender'] ?? '')) return true;
    return (curTs - prevTs).abs() > 5 * 60 * 1000;
  }

  Future<void> _copyAll() async {
    final buffer = StringBuffer();
    for (final item in _messages) {
      final ts = int.tryParse('${item['created_at'] ?? 0}') ?? 0;
      final sender = (item['sender'] ?? '').toString();
      final text = _summary(item);
      final time = _formatFullTime(ts);
      if (sender.isNotEmpty) {
        buffer.writeln('$sender $time');
      }
      buffer.writeln(text);
      buffer.writeln();
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) showToast(translate('Copied'));
  }

  String _summary(Map<String, dynamic> item) {
    final kind = (item['kind'] ?? '').toString();
    final text = (item['text'] ?? '').toString().trim();
    if (kind == 'file' || kind == 'image') {
      final fileName = (item['file_name'] ?? '').toString().trim();
      return '[${translate('File')}] ${fileName.isEmpty ? text : fileName}';
    }
    if (kind == 'voice') {
      return '[${translate('Voice')}]';
    }
    if (DirectChatLocation.tryParse(text) != null) {
      return '[${translate('Location')}]';
    }
    return text.isEmpty ? ' ' : text;
  }

  String _formatFullTime(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    if (sameDay) return hm;
    if (dt.year == now.year) return '${dt.month}月${dt.day}日 $hm';
    return '${dt.year}/${dt.month}/${dt.day} $hm';
  }
}

/// 单条聊天记录气泡（微信聊天记录样式：居中时间 + 左右气泡）。
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.item,
    required this.dark,
    required this.showTime,
  });

  final Map<String, dynamic> item;
  final bool dark;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final isMe = item['is_me'] == true;
    final ts = int.tryParse('${item['created_at'] ?? 0}') ?? 0;
    final sender = (item['sender'] ?? '').toString();
    final text = (item['text'] ?? '').toString().trim();
    final kind = (item['kind'] ?? '').toString();
    final isLocation = DirectChatLocation.tryParse(text) != null;

    final timeText = _formatTime(ts);
    final isImage = kind == 'image';
    final localPath = (item['local_path'] ?? '').toString();
    final hasImage = isImage && localPath.isNotEmpty && File(localPath).existsSync();

    final bubbleColor =
        isMe ? const Color(0xFF07C160) : (dark ? const Color(0xFF2A2D33) : Colors.white);
    final textColor =
        isMe ? Colors.white : (dark ? Colors.white : const Color(0xFF222222));

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          if (showTime)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 10),
              child: Text(
                timeText,
                style: TextStyle(
                  fontSize: 11,
                  color: dark ? Colors.white30 : Colors.black38,
                ),
              ),
            ),
          if (sender.isNotEmpty && !isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                sender,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: dark ? Colors.white38 : Colors.black45,
                ),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Container(
              padding: EdgeInsets.all(isLocation ? 0 : 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(10),
                border: isLocation
                    ? null
                    : Border.all(
                        color: dark
                            ? const Color(0xFF3A3D43)
                            : const Color(0xFFE5E5E5),
                        width: 0.5,
                      ),
              ),
              child: isLocation
                  ? _locationCard(text, dark)
                  : hasImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(localPath),
                            width: 180,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              text,
                              style: TextStyle(color: textColor, fontSize: 14),
                            ),
                          ),
                        )
                      : _content(text, kind, textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationCard(String text, bool dark) {
    final loc = DirectChatLocation.tryParse(text);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 230,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2D33) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: dark ? const Color(0xFF3A3D43) : const Color(0xFFE5E5E5),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
          Container(
            height: 90,
            alignment: Alignment.center,
            color: const Color(0xFFDCE8DC),
            child: const Icon(
              Icons.location_on_rounded,
              size: 34,
              color: Color(0xFFFA5151),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  loc?.name.isNotEmpty == true ? loc!.name : translate('Location'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: dark ? Colors.white : const Color(0xFF222222),
                  ),
                ),
                if (loc?.address.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    loc!.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: dark ? Colors.white38 : const Color(0xFF888888),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _content(String text, String kind, Color textColor) {
    if (kind == 'file') {
      final fileName = (item['file_name'] ?? '').toString().trim();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.insert_drive_file_outlined, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              fileName.isEmpty ? text : fileName,
              style: TextStyle(color: textColor, fontSize: 14),
            ),
          ),
        ],
      );
    }
    if (kind == 'voice') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.mic_rounded, size: 18),
          const SizedBox(width: 6),
          Text(
            translate('Voice'),
            style: TextStyle(color: textColor, fontSize: 14),
          ),
        ],
      );
    }
    return SelectableText(
      text.isEmpty ? ' ' : text,
      style: TextStyle(
        color: textColor,
        fontSize: 14,
        height: 1.4,
      ),
    );
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) return hm;
    if (dt.year == now.year) return '${dt.month}月${dt.day}日 $hm';
    return '${dt.year}/${dt.month}/${dt.day} $hm';
  }
}
