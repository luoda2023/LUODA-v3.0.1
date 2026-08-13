import 'dart:async';
import 'dart:io';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';
import 'package:luoda_flutter/common/widgets/location_detail_page.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../mobile/pages/home_page.dart';
import '../../models/meeting_group_model.dart';
import 'package:luoda_flutter/common/direct_viewer_invite.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../wechat_ui_tokens.dart';
import '../email_draft_service.dart';
import '../string_utils.dart';
import 'file_viewer.dart';
import 'file_preview_types.dart';
import 'system_share.dart';
import 'message_context_region.dart';
import 'message_source_label.dart';
import 'rich_text_builder.dart';
import 'voice_message_controls.dart';
import '../../models/ai_config_model.dart';
import 'ai_config_page.dart';

const _reactionEmojis = [
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🙏',
  '👏',
  '🎉',
  '🔥',
  '💯',
  '🤔',
  '👀',
];

enum ChatPageType {
  mobileMain,
  desktopCM,
  desktopHome,
}

typedef PasteImageCallback = Future<bool> Function(bool notifyIfEmpty);

/// 消息长按菜单项：value 传给 [_handleWeChatContextAction]，
/// group 相同的项之间不加分隔线（新增分组时 +1）。
class _ChatMenuAction {
  const _ChatMenuAction(this.value, this.icon, this.label,
      {this.color, this.group = 0});

  final String value;
  final IconData icon;
  final String label;
  final Color? color;
  final int group;
}

typedef ForwardMessagesCallback = Future<bool> Function(
  String targetPeerId,
  List<ChatForwardItem> items,
  bool merged,
);

class ChatForwardItem {
  const ChatForwardItem({
    required this.senderName,
    required this.kind,
    required this.text,
    required this.fileName,
    required this.fileSize,
    required this.localPath,
    required this.voiceDurationMs,
  });

  factory ChatForwardItem.fromMessage(ChatMessage message) {
    final properties = message.customProperties;
    final kindName = (properties?['ldesk_kind'] ?? 'text').toString();
    return ChatForwardItem(
      senderName:
          sanitizeInvalidUtf16(message.user.firstName ?? message.user.id)
              .trim(),
      kind: DirectChatKind.values.firstWhere(
        (value) => value.name == kindName,
        orElse: () => DirectChatKind.text,
      ),
      text: sanitizeInvalidUtf16(message.text).trim(),
      fileName: sanitizeInvalidUtf16(
        (properties?['ldesk_file_name'] ?? '').toString(),
      ),
      fileSize: int.tryParse('${properties?['ldesk_file_size'] ?? 0}') ?? 0,
      localPath: sanitizeInvalidUtf16(
        (properties?['ldesk_local_path'] ?? '').toString(),
      ),
      voiceDurationMs:
          int.tryParse('${properties?['ldesk_voice_duration_ms'] ?? 0}') ?? 0,
    );
  }

  final String senderName;
  final DirectChatKind kind;
  final String text;
  final String fileName;
  final int fileSize;
  final String localPath;
  final int voiceDurationMs;

  DirectChatForwardItem toSummary() => DirectChatForwardItem(
        senderName: senderName,
        kind: kind,
        text: text,
        fileName: fileName,
        voiceDurationMs: voiceDurationMs,
      );
}

/// Shared emoji pack used by both the PC and mobile composers.
/// WeChat-style chat faces and symbols.
/// Free Unicode emoji pack — commonly used chat faces and symbols.
const kDotChatEmojiList = <String>[
  '😀',
  '😂',
  '🤣',
  '😊',
  '😍',
  '🥰',
  '😘',
  '😜',
  '🤔',
  '😎',
  '😢',
  '😭',
  '😤',
  '😡',
  '🥺',
  '😱',
  '🤯',
  '😴',
  '🤤',
  '😷',
  '👍',
  '👎',
  '👏',
  '🙏',
  '💪',
  '✌️',
  '🤝',
  '👋',
  '🖐️',
  '🤞',
  '❤️',
  '🧡',
  '💛',
  '💚',
  '💙',
  '💜',
  '🖤',
  '🤍',
  '💔',
  '💯',
  '🔥',
  '⭐',
  '🎉',
  '🎊',
  '🥇',
  '✅',
  '❌',
  '💡',
  '📌',
  '🎯',
  '🍕',
  '🍔',
  '☕',
  '🍺',
  '🎂',
  '🌈',
  '🌹',
  '🌸',
  '☀️',
  '🌙',
  '🐶',
  '🐱',
  '🦊',
  '🐼',
  '🐧',
  '🦄',
  '🐝',
  '🐙',
  '🐳',
  '🦋',
  '😅',
  '🙃',
  '😏',
  '😌',
  '🤗',
  '🤩',
  '😇',
  '🤐',
  '🥱',
  '😈',
];

class ChatPage extends StatelessWidget implements PageShape {
  late final ChatModel chatModel;
  final ChatPageType? type;
  final VoidCallback? onAttachFile;
  final VoidCallback? onRemoteAssist;
  final VoidCallback? onSendImage;
  final VoidCallback? onTakePhoto;
  final VoidCallback? onSendLocation;
  final VoidCallback? onScreenshot;
  final PasteImageCallback? onPasteImage;
  final ForwardMessagesCallback? onForwardMessages;
  final bool peerOffline;
  final GlobalKey<_MobileChatComposerState> _mobileComposerKey =
      GlobalKey<_MobileChatComposerState>();

  ChatPage({
    ChatModel? chatModel,
    this.type,
    this.onAttachFile,
    this.onRemoteAssist,
    this.onSendImage,
    this.onTakePhoto,
    this.onSendLocation,
    this.onScreenshot,
    this.onPasteImage,
    this.onForwardMessages,
    this.peerOffline = false,
  }) {
    this.chatModel = chatModel ?? gFFI.chatModel;
    this.chatModel.refreshLocalIdentity();
  }

  @override
  final title = translate("Messages");

  @override
  final icon = unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum);

  @override
  final appBarActions = [
    PopupMenuButton<MessageKey>(
        tooltip: "",
        icon: unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum,
            icon: Icon(Icons.group)),
        itemBuilder: (context) {
          // only mobile need [appBarActions], just bind gFFI.chatModel
          final chatModel = gFFI.chatModel;
          return chatModel.messages.entries.map((entry) {
            final key = entry.key;
            final user = entry.value.chatUser;
            final client = gFFI.serverModel.clients
                .firstWhereOrNull((e) => e.id == key.connId);
            final connected =
                gFFI.serverModel.clients.any((e) => e.id == key.connId);
            return PopupMenuItem<MessageKey>(
              child: Row(
                children: [
                  Icon(
                          key.isOut
                              ? Icons.call_made_rounded
                              : Icons.call_received_rounded,
                          color: MyTheme.accent)
                      .marginOnly(right: 6),
                  Expanded(
                    child: Text(
                      "${user.firstName}   ${user.id}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  Text(
                    translate(connected ? 'Online' : 'Offline'),
                    style: TextStyle(
                      fontSize: 12,
                      color: connected ? MyTheme.accent : MyTheme.mutedLight,
                    ),
                  ).marginOnly(left: 6),
                  if (client != null)
                    unreadMessageCountBuilder(client.unreadChatMessageCount)
                        .marginOnly(left: 4)
                ],
              ),
              value: key,
            );
          }).toList();
        },
        onSelected: (key) {
          gFFI.chatModel.changeCurrentKey(key);
        })
  ];

  String _messageTranslationKey(ChatMessage message) {
    final recordId =
        (message.customProperties?['ldesk_id'] ?? '').toString().trim();
    if (recordId.isNotEmpty) return recordId;
    return '${message.user.id}:${message.createdAt.microsecondsSinceEpoch}:'
        '${message.text.hashCode}';
  }

  /// 收集消息的完整操作项（PC 右键与手机端长按共用），
  /// 返回 (动作列表, 是否显示表情回应行)。
  ({List<_ChatMenuAction> actions, bool showReactions}) _buildMessageActions(
      ChatMessage message) {
    final properties = message.customProperties;
    final id = (properties?['ldesk_id'] ?? '').toString();
    final disposition =
        (properties?['ldesk_disposition'] ?? 'active').toString();
    final delivery = (properties?['ldesk_delivery'] ?? '').toString();
    final isOwnMessage = message.user.id == chatModel.me.id;
    final canMutate = id.isNotEmpty && disposition == 'active';
    final actions = <_ChatMenuAction>[];

    actions.add(const _ChatMenuAction(
        'copy', Icons.copy_rounded, 'Copy', group: 0));
    // Share to WeChat / other apps via the system share sheet (mobile only).
    if (isMobile) {
      actions.add(const _ChatMenuAction(
          'share', Icons.share_outlined, 'Share', group: 0));
    }
    if (disposition == 'active') {
      actions.add(const _ChatMenuAction(
          'reply', Icons.reply_rounded, 'Reply', group: 0));
    }
    if (id.isNotEmpty && canMutate) {
      actions.add(const _ChatMenuAction(
          'select', Icons.checklist_rounded, 'Select', group: 1));
    }
    actions.add(const _ChatMenuAction(
        'info', Icons.info_outline_rounded, 'Info', group: 1));

    // AI Translate — only if configured and message is text
    if (AiConfig.current.enabled &&
        (message.text?.isNotEmpty == true ||
            (properties?['ldesk_kind'] == 'text'))) {
      actions.add(const _ChatMenuAction(
          'translate', Icons.translate_rounded, 'Translate', group: 2));
    }

    // Send to email — only if email is configured
    if (AiConfig.current.email.isNotEmpty &&
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
            .hasMatch(AiConfig.current.email)) {
      actions.add(const _ChatMenuAction(
          'send-email', Icons.email_outlined, 'Send to email', group: 2));
      actions.add(const _ChatMenuAction('send-email-batch',
          Icons.archive_outlined, 'Send 20 recent to email', group: 2));
    }

    if (isOwnMessage && canMutate) {
      if (properties?['ldesk_kind'] == 'text') {
        actions.add(const _ChatMenuAction(
            'edit', Icons.edit_rounded, 'Edit', group: 3));
      }
      actions.add(const _ChatMenuAction(
          'recall', Icons.undo_rounded, 'Recall', group: 3));
      actions.add(const _ChatMenuAction('destroy',
          Icons.delete_forever_outlined, 'Destroy',
          color: Color(0xFFFA5151), group: 3));
      actions.add(const _ChatMenuAction(
          'forward', Icons.forward_rounded, 'Forward', group: 3));
      if (delivery == 'failed') {
        actions.add(const _ChatMenuAction(
            'retry', Icons.refresh_rounded, 'Retry send', group: 3));
      }
      actions.add(const _ChatMenuAction('expire-60', Icons.timer_outlined,
          'Self-destruct in 1 minute', group: 4));
      actions.add(const _ChatMenuAction('expire-300', Icons.timer_outlined,
          'Self-destruct in 5 minutes', group: 4));
      actions.add(const _ChatMenuAction('expire-3600', Icons.timer_outlined,
          'Self-destruct in 1 hour', group: 4));
    }

    if (canMutate) {
      actions.add(const _ChatMenuAction('delete',
          Icons.delete_outline_rounded, 'Delete',
          color: Color(0xFFFA5151), group: 5));
    }

    return (
      actions: actions,
      showReactions: id.isNotEmpty && canMutate,
    );
  }

  /// WeChat PC style floating context menu — positioned near the message,
  /// with rounded corners, icon + text items, and clean dividers.
  Future<String?> _showWeChatContextMenu(
    BuildContext context,
    ChatMessage message, {
    required Offset position,
    bool alignToAvatarLeft = false,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPos = overlay.globalToLocal(position);
    final overlaySize = overlay.size;
    // WeChat PC alignment: for own messages, the menu anchors its
    // top-right corner to the avatar's top-left. Position the menu so it
    // appears above and to the left of the avatar (mirrors WeChat PC).
    final anchorPoint =
        alignToAvatarLeft ? localPos.translate(-36, 0) : localPos;
    final anchor = RelativeRect.fromRect(
      anchorPoint & const Size(1, 1),
      Offset.zero & overlaySize,
    );

    final built = _buildMessageActions(message);
    final items = <PopupMenuEntry<String>>[];
    int? lastGroup;
    void addItem(_ChatMenuAction action) {
      if (lastGroup != null && action.group != lastGroup) {
        items.add(const PopupMenuDivider(height: 1));
      }
      lastGroup = action.group;
      items.add(PopupMenuItem<String>(
        value: action.value,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(action.icon, size: 18, color: action.color),
            const SizedBox(width: 10),
            Text(translate(action.label),
                style: TextStyle(fontSize: 13, color: action.color)),
          ],
        ),
      ));
    }

    if (built.showReactions) {
      items.add(const PopupMenuDivider(height: 1));
      items.add(
        PopupMenuItem<String>(
          enabled: false,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _reactionEmojis.map((emoji) {
                return GestureDetector(
                  onTap: () => Navigator.pop(context, 'react:$emoji'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      );
      items.add(const PopupMenuDivider(height: 1));
    }
    for (final action in built.actions) {
      addItem(action);
    }

    return showMenu<String>(
      context: context,
      position: anchor,
      items: items,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2B2D32)
          : Colors.white,
    );
  }

  /// 手机端长按操作面板：微信手机版风格底部面板，
  /// 功能与 PC 右键菜单完全一致（撤回/销毁/转发/编辑/阅后即焚/删除等）。
  Future<String?> _showMobileMessageActions(
      BuildContext context, ChatMessage message) async {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF23262B) : Colors.white;
    final built = _buildMessageActions(message);

    final rows = <Widget>[];
    int? lastGroup;
    for (final action in built.actions) {
      if (lastGroup != null && action.group != lastGroup) {
        rows.add(Container(
          height: 6,
          color: dark ? const Color(0xFF1B1E23) : const Color(0xFFF2F3F5),
        ));
      }
      lastGroup = action.group;
      rows.add(InkWell(
        onTap: () => Navigator.pop(context, action.value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: <Widget>[
              Icon(action.icon,
                  size: 21,
                  color: action.color ??
                      theme.colorScheme.onSurface.withOpacity(0.85)),
              const SizedBox(width: 14),
              Text(
                translate(action.label),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: action.color ?? theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ));
    }

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        Widget reactionRow() {
          return Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _reactionEmojis.map((emoji) {
                return InkWell(
                  onTap: () => Navigator.pop(sheetContext, 'react:$emoji'),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                );
              }).toList(),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: dark
                      ? Colors.white.withOpacity(0.2)
                      : Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (built.showReactions) reactionRow(),
                      ...rows,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  /// 打开消息操作菜单（桌面端右键与手机端长按共用入口）：
  /// - mobileMain：微信手机版风格底部面板
  /// - 其他（desktopHome 等）：浮动弹出菜单
  /// 多选模式下不弹菜单，避免与勾选操作冲突。
  Future<void> _openMessageActions(
    BuildContext context,
    ChatMessage message, {
    required Offset position,
    required bool alignToAvatarLeft,
  }) async {
    if (chatModel.isMultiSelectMode) return;
    final String? action;
    if (type == ChatPageType.mobileMain) {
      action = await _showMobileMessageActions(context, message);
    } else {
      action = await _showWeChatContextMenu(
        context,
        message,
        position: position,
        alignToAvatarLeft: alignToAvatarLeft,
      );
    }
    if (context.mounted) {
      await _handleWeChatContextAction(context, action, message);
    }
  }

  /// WeChat PC clean delete confirmation — minimal, no heavy icon decorations.
  Future<bool> _showWeChatConfirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
        actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        title: Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: Text(message,
            style: const TextStyle(fontSize: 13), textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              minimumSize: const Size(80, 36),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child:
                Text(translate('Cancel'), style: const TextStyle(fontSize: 13)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(80, 36),
              backgroundColor: confirmColor ?? kWeChatPrimaryColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(confirmLabel,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Handle the result from the WeChat-style context menu above.
  Future<void> _handleWeChatContextAction(
    BuildContext context,
    String? action,
    ChatMessage message,
  ) async {
    if (action == null) return;
    if (action.startsWith('react:')) {
      final emoji = action.substring('react:'.length);
      chatModel.toggleReaction(message, emoji);
      return;
    }
    final properties = message.customProperties;
    final id = (properties?['ldesk_id'] ?? '').toString();
    final isOwnMessage = message.user.id == chatModel.me.id;

    if (action == 'copy') {
      await chatModel.copyMessage(message);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(translate('Copied to clipboard'))),
        );
      }
      return;
    }
    if (action == 'reply') {
      chatModel.setReplyTo(message);
      chatModel.inputNode.requestFocus();
      return;
    }
    if (action == 'delete') {
      final confirmed = await _showWeChatConfirm(
        context,
        title: translate('Delete message'),
        message: translate('Delete this message locally?'),
        confirmLabel: translate('Delete'),
        confirmColor: Colors.redAccent,
      );
      if (!confirmed) return;
      await chatModel.deleteLocally(message);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(translate('Message deleted'))),
        );
      }
      return;
    }
    if (action == 'edit') {
      if (!context.mounted) return;
      final controller = TextEditingController(text: message.text ?? '');
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
          actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          title: Text(translate('Edit message'),
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: translate('Edit your message...'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(12),
              isDense: true,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(
                minimumSize: const Size(80, 36),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(translate('Cancel'),
                  style: const TextStyle(fontSize: 13)),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              style: FilledButton.styleFrom(
                minimumSize: const Size(80, 36),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child:
                  Text(translate('Save'), style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
      if (result == null || result.isEmpty || !context.mounted) return;
      final ok = await chatModel.editMessage(message, result);
      if (context.mounted && ok) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(translate('Message edited'))),
        );
      }
      return;
    }
    if (action == 'select') {
      _enterMultiSelect(message);
      return;
    }
    if (action == 'info') {
      _showMessageInfo(context, message);
      return;
    }
    if (action == 'translate') {
      final text = message.text ?? '';
      if (text.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(translate('No text to translate'))),
          );
        }
        return;
      }
      final translationId = _messageTranslationKey(message);
      if (!chatModel.beginMessageTranslation(translationId)) return;
      try {
        final translated = await AiService.translate(text);
        if (translated != null && translated.trim().isNotEmpty) {
          chatModel.completeMessageTranslation(translationId, translated);
          return;
        }
      } catch (error) {
        debugPrint('Message translation failed: $error');
      }
      chatModel.failMessageTranslation(translationId);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(translate('Translation failed'))),
        );
      }
      return;
    }
    if (action == 'send-email') {
      final text = message.text ?? '';
      final fileName =
          (message.customProperties?['ldesk_file_name'] ?? '').toString();
      final content = fileName.isNotEmpty ? '$fileName\n\n$text' : text;
      if (content.trim().isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(translate('No content to send'))),
          );
        }
        return;
      }
      final email = AiConfig.current.email;
      final opened = await EmailDraftService.openDraft(
        recipient: email,
        subject:
            '${translate("Chat message")} - ${message.user.firstName ?? ''}',
        body: content,
      );
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(translate(
              opened ? 'Email draft opened' : 'Unable to open email client',
            )),
          ),
        );
      }
      return;
    }
    if (action == 'send-email-batch') {
      final allMessages =
          chatModel.messages[chatModel.currentKey]?.chatMessages ?? [];
      if (allMessages.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(translate('No messages to send'))),
          );
        }
        return;
      }
      // Find the clicked message index (newest first: index 0 = newest)
      final msgId = (message.customProperties?['ldesk_id'] ?? '').toString();
      int clickedIdx = 0;
      if (msgId.isNotEmpty) {
        clickedIdx = allMessages.indexWhere(
            (m) => (m.customProperties?['ldesk_id'] ?? '').toString() == msgId);
        if (clickedIdx < 0) clickedIdx = 0;
      }
      // Collect 20 messages starting from clicked, going older
      final endIdx = (clickedIdx + 20 > allMessages.length)
          ? allMessages.length
          : clickedIdx + 20;
      final selected = allMessages.sublist(clickedIdx, endIdx);
      final reversed = selected.reversed.toList();

      try {
        final body = EmailDraftService.formatMessages(
          reversed.map(
            (item) => EmailDraftMessage(
              sender: item.user.firstName ?? item.user.id,
              sentAt: item.createdAt,
              text: item.text,
              fileName:
                  (item.customProperties?['ldesk_file_name'] ?? '').toString(),
            ),
          ),
          fileLabel: translate('File'),
        );
        final opened = await EmailDraftService.openDraft(
          recipient: AiConfig.current.email,
          subject: translate('Chat messages'),
          body: body,
        );
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(translate(
                opened ? 'Email draft opened' : 'Unable to open email client',
              )),
            ),
          );
        }
      } catch (e) {
        debugPrint('Export failed: $e');
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('${translate("Export failed")}: $e')),
          );
        }
      }
      return;
    }
    if (action == 'share') {
      await _shareMessageToSystem(context, message);
      return;
    }
    if (action == 'forward') {
      await _showForwardPicker(context, <ChatMessage>[message]);
      return;
    }
    if (action == 'destroy') {
      final confirmed = await _showWeChatConfirm(
        context,
        title: translate('Destroy message'),
        message: translate('Destroy message on both devices?'),
        confirmLabel: translate('Destroy'),
        confirmColor: Colors.redAccent,
      );
      if (!confirmed) return;
    }
    late final bool changed;
    late final String successText;
    if (action == 'retry') {
      changed = await chatModel.retryMessage(message);
      successText = 'Message queued for retry';
    } else if (action.startsWith('expire-')) {
      final seconds = int.tryParse(action.substring('expire-'.length)) ?? 0;
      changed = await chatModel.setSelfDestructMessage(
        message,
        Duration(seconds: seconds),
      );
      successText = 'Self-destruct timer set';
    } else if (action == 'recall') {
      changed = await chatModel.recallMessage(message);
      successText = 'Message recalled';
    } else {
      changed = await chatModel.destroyMessage(message);
      successText = 'Message destroyed';
    }
    if (!context.mounted || !changed) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(translate(successText))),
    );
  }

  /// Share a message to WeChat / other apps via the system share sheet.
  /// Text messages share their text; image/file messages share the local
  /// file; location messages share a map link; voice shares nothing.
  Future<void> _shareMessageToSystem(
    BuildContext context,
    ChatMessage message,
  ) async {
    final properties = message.customProperties ?? const <String, dynamic>{};
    final kind = (properties['ldesk_kind'] ?? 'text').toString();
    final localPath = (properties['ldesk_local_path'] ?? '').toString();
    final fileName = (properties['ldesk_file_name'] ?? '').toString();
    final fileExists =
        localPath.trim().isNotEmpty && File(localPath).existsSync();
    bool ok = false;
    if (fileExists) {
      // Image / file / voice message: share the actual file.
      ok = await shareToSystemApp(
        text: fileName.trim(),
        files: <String>[localPath],
      );
    } else if (kind == 'text' ||
        (message.text?.isNotEmpty == true &&
            (kind.isEmpty || kind == 'text'))) {
      ok = await shareTextToSystemApp(message.text ?? '');
    } else if (kind == 'location') {
      final loc = DirectChatLocation.tryParse(message.text ?? '');
      if (loc != null) {
        final lat = loc.latitude.toStringAsFixed(6);
        final lng = loc.longitude.toStringAsFixed(6);
        final name = loc.name.isEmpty ? translate('My Location') : loc.name;
        ok = await shareTextToSystemApp(
          '$name\nhttps://uri.amap.com/marker?position=$lng,$lat&name=$name\nhttps://api.map.baidu.com/marker?location=$lat,$lng&title=$name',
        );
      }
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(translate('Nothing to share'))),
      );
    }
  }

  Future<void> _showForwardPicker(
    BuildContext context,
    List<ChatMessage> messages,
  ) async {
    if (messages.isEmpty) return;
    var merged = false;
    if (messages.length > 1) {
      final mode = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(translate('Forward messages')),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'individual'),
              child: ListTile(
                leading: const Icon(Icons.send_outlined),
                title: Text(translate('Forward individually')),
                subtitle: Text(translate('Send each message separately')),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'merged'),
              child: ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(translate('Merge and forward')),
                subtitle: Text(translate('Send as one chat history card')),
              ),
            ),
          ],
        ),
      );
      if (mode == null || !context.mounted) return;
      merged = mode == 'merged';
    }

    final currentPeerId = chatModel.currentKey.peerId;
    final targets = <String, String>{};
    for (final pairing in DirectPairingStore.load().values) {
      if (pairing.peerId != currentPeerId) {
        targets[pairing.peerId] =
            pairing.displayName.isEmpty ? pairing.peerId : pairing.displayName;
      }
    }
    for (final peer in gFFI.recentPeersModel.peers) {
      if (peer.id != currentPeerId && peer.id.isNotEmpty) {
        targets.putIfAbsent(
          peer.id,
          () => peer.alias.trim().isNotEmpty
              ? peer.alias.trim()
              : peer.displayName.trim().isNotEmpty
                  ? peer.displayName.trim()
                  : peer.id,
        );
      }
    }
    if (targets.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(translate('No contacts to forward to'))),
        );
      }
      return;
    }
    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(translate('Forward to')),
        children: <Widget>[
          SizedBox(
            width: 360,
            height: (targets.length * 58.0).clamp(100, 420).toDouble(),
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final entry in targets.entries)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialogContext, entry.key),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(entry.value.isNotEmpty
                            ? entry.value.characters.first.toUpperCase()
                            : '?'),
                      ),
                      title: Text(entry.value),
                      subtitle: entry.value == entry.key
                          ? null
                          : Text(entry.key, maxLines: 1),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    final sorted = messages.toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final items =
        sorted.map(ChatForwardItem.fromMessage).toList(growable: false);
    final handled = onForwardMessages != null
        ? await onForwardMessages!(target, items, merged)
        : await _forwardWithCurrentModel(target, items, merged);
    if (!handled || !context.mounted) return;
    chatModel.exitMultiSelect();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(translate('Forwarded'))),
    );
  }

  Future<bool> _forwardWithCurrentModel(
    String targetPeerId,
    List<ChatForwardItem> items,
    bool merged,
  ) async {
    final ensureConnection = chatModel.ensureChatConnection;
    if (ensureConnection == null) return false;
    await ensureConnection(targetPeerId, force: false);
    if (chatModel.currentKey.peerId != targetPeerId) return false;
    if (merged) {
      final senders = items
          .map((item) => item.senderName)
          .where((name) => name.isNotEmpty)
          .toSet()
          .take(2)
          .join(', ');
      await chatModel.sendForwardBundle(
        title: senders.isEmpty ? translate('Chat history') : senders,
        items: items.map((item) => item.toSummary()).toList(growable: false),
      );
      return true;
    }
    for (final item in items) {
      if (item.kind == DirectChatKind.file &&
          item.localPath.isNotEmpty &&
          File(item.localPath).existsSync()) {
        await chatModel.sendFileRecord(
          fileName: item.fileName,
          fileSize: item.fileSize,
          localPath: item.localPath,
        );
      } else if (item.kind == DirectChatKind.voice) {
        chatModel.sendText(
          '[${translate('Voice')}] '
          '${(item.voiceDurationMs / 1000).ceil()}s',
        );
      } else if (item.text.isNotEmpty) {
        chatModel.sendText(item.text);
      }
    }
    return true;
  }

  List<ChatMessage> _selectedMessagesForForward() {
    final selected = chatModel.selectedMessageIds;
    final messages =
        chatModel.messages[chatModel.currentKey]?.chatMessages ?? const [];
    return messages
        .where(
          (message) => selected.contains(
            (message.customProperties?['ldesk_id'] ?? '').toString(),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _openMessageFilePreview(
    BuildContext context, {
    required String fileName,
    required int fileSize,
    required String localPath,
  }) async {
    List<String>? siblingPaths;
    if (filePreviewKindForName(fileName) == FilePreviewKind.image) {
      final records = await chatModel.mediaForConversation();
      final paths = <String>[];
      for (final record in records.reversed) {
        final path = record.localPath.trim();
        if (path.isEmpty ||
            filePreviewKindForName(record.fileName) != FilePreviewKind.image ||
            !File(path).existsSync() ||
            paths.contains(path)) {
          continue;
        }
        paths.add(path);
      }
      if (localPath.isNotEmpty &&
          File(localPath).existsSync() &&
          !paths.contains(localPath)) {
        paths.add(localPath);
      }
      if (paths.length > 1) siblingPaths = paths;
    }
    if (!context.mounted) return;
    await showFileViewer(
      context,
      fileName: fileName,
      fileSize: fileSize,
      localPath: localPath,
      siblingPaths: siblingPaths,
    );
  }

  /// Show message delivery info dialog.
  void _showMessageInfo(BuildContext context, ChatMessage message) {
    final properties = message.customProperties;
    final delivery = (properties?['ldesk_delivery'] ?? '').toString();
    final kind = (properties?['ldesk_kind'] ?? 'text').toString();
    final isEdited = properties?['ldesk_is_edited'] == true;
    final editedAt = properties?['ldesk_edited_at'];
    final reactions = properties?['ldesk_reactions'] as Map<String, dynamic>?;
    String deliveryLabel;
    switch (delivery) {
      case 'queued':
        deliveryLabel = translate('Waiting to send');
        break;
      case 'sent':
        deliveryLabel = translate('Sent');
        break;
      case 'delivered':
        deliveryLabel = translate('Delivered');
        break;
      case 'failed':
        deliveryLabel = translate('Failed');
        break;
      default:
        deliveryLabel = delivery;
    }
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(translate('Message info')),
        children: <Widget>[
          _infoRow(ctx, translate('Status'), deliveryLabel),
          _infoRow(
              ctx,
              translate('Type'),
              kind == 'voice'
                  ? translate('Voice')
                  : kind == 'file'
                      ? translate('File')
                      : translate('Text')),
          _infoRow(
              ctx,
              translate('Time'),
              '${message.createdAt.month}/${message.createdAt.day} '
              '${message.createdAt.hour.toString().padLeft(2, '0')}:'
              '${message.createdAt.minute.toString().padLeft(2, '0')}'),
          if (isEdited)
            _infoRow(ctx, translate('Edited'), editedAt?.toString() ?? ''),
          if (reactions != null && reactions.isNotEmpty)
            _infoRow(
              ctx,
              translate('Reactions'),
              reactions.entries
                  .map((e) => '${e.key} ${(e.value as List).length}')
                  .join('  '),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.6),
                    fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  /// Enter multi-select mode with the given message pre-selected.
  void _enterMultiSelect(ChatMessage message) {
    final id = (message.customProperties?['ldesk_id'] ?? '').toString();
    if (id.isNotEmpty) chatModel.enterMultiSelect(id);
  }

  /// Show media gallery for the current conversation.
  Future<void> _showMediaGallery(BuildContext context) async {
    final records = await chatModel.mediaForConversation();
    if (!context.mounted || records.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(translate('No media in this conversation'))),
        );
      }
      return;
    }
    final siblingPaths = records.reversed
        .where(
          (record) =>
              record.localPath.isNotEmpty &&
              filePreviewKindForName(record.fileName) ==
                  FilePreviewKind.image &&
              File(record.localPath).existsSync(),
        )
        .map((record) => record.localPath)
        .toSet()
        .toList(growable: false);
    final dark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.3,
        builder: (_, scrollController) => GridView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: records.length,
          itemBuilder: (_, index) {
            final record = records[index];
            final isImage = record.localPath.isNotEmpty &&
                filePreviewKindForName(record.fileName) ==
                    FilePreviewKind.image;
            return GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                showFileViewer(
                  context,
                  fileName: record.fileName,
                  fileSize: record.fileSize,
                  localPath: record.localPath,
                  siblingPaths: siblingPaths.length > 1 ? siblingPaths : null,
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color:
                      dark ? const Color(0xFF2B2D32) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(record.localPath),
                          fit: BoxFit.cover,
                          cacheWidth: 320,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (_, __, ___) =>
                              _mediaPlaceholder(record, dark),
                        ),
                      )
                    : _mediaPlaceholder(record, dark),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _mediaPlaceholder(DirectChatRecord record, bool dark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          filePreviewIcon(record.fileName),
          size: 32,
          color: dark ? const Color(0xFF999CA2) : const Color(0xFF888888),
        ),
        const SizedBox(height: 4),
        Text(
          record.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: dark ? const Color(0xFF999CA2) : const Color(0xFF888888),
          ),
        ),
      ],
    );
  }

  /// Show clear history confirmation dialog — WeChat PC clean style.
  Future<void> _showClearHistoryDialog(BuildContext context) async {
    final confirmed = await _showWeChatConfirm(
      context,
      title: translate('Clear chat history'),
      message: translate('Delete all messages in this conversation?'),
      confirmLabel: translate('Clear'),
      confirmColor: Colors.redAccent,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await chatModel.clearConversation();
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
            content: Text(translate(
          ok ? 'Chat history cleared' : 'Failed to clear chat history',
        ))),
      );
    }
  }

  /// Multi-select bottom action bar with batch delete.
  Widget multiSelectBottomBar(BuildContext context, bool dark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? kWeChatCanvasColorDark : const Color(0xFFF8F8F8),
        border: Border(
            top: BorderSide(
          color: dark ? const Color(0xFF3A3D43) : const Color(0x80E5E5E5),
        )),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
          top: false,
          child: Row(children: [
            TextButton(
              onPressed: () => chatModel.exitMultiSelect(),
              child: Text(translate('Cancel')),
            ),
            const Spacer(),
            Text(
              '${chatModel.selectedMessageIds.length} ${translate('selected')}',
              style: TextStyle(
                color: dark ? const Color(0xFF999CA2) : const Color(0xFF888888),
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => chatModel.selectAllInConversation(),
              child: Text(translate('Select all')),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: chatModel.selectedMessageIds.isEmpty
                  ? null
                  : () => _showForwardPicker(
                        context,
                        _selectedMessagesForForward(),
                      ),
              icon: const Icon(Icons.forward_outlined, size: 18),
              label: Text(translate('Forward')),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: chatModel.selectedMessageIds.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(translate('Delete messages')),
                          content: Text(
                              '${translate('Delete')} ${chatModel.selectedMessageIds.length} ${translate('messages')}?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(translate('Cancel')),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    Theme.of(ctx).colorScheme.error,
                              ),
                              child: Text(translate('Delete')),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true || !context.mounted) return;
                      final deleted = await chatModel.batchDeleteMessages(
                        Set<String>.from(chatModel.selectedMessageIds),
                      );
                      chatModel.exitMultiSelect();
                      if (context.mounted && !deleted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                              content:
                                  Text(translate('Failed to delete messages'))),
                        );
                      }
                    },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(translate('Delete')),
            ),
          ])),
    );
  }

  List<Map<String, dynamic>> _forwardItems(ChatMessage message) {
    final raw = message.customProperties?['ldesk_forward_items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  String _forwardItemSummary(Map<String, dynamic> item) {
    final kind = (item['kind'] ?? '').toString();
    final text = (item['text'] ?? '').toString().trim();
    if (kind == DirectChatKind.file.name) {
      final fileName = (item['file_name'] ?? '').toString().trim();
      return '[${translate('File')}] ${fileName.isEmpty ? text : fileName}';
    }
    if (kind == DirectChatKind.voice.name) {
      final duration = int.tryParse('${item['voice_duration_ms'] ?? 0}') ?? 0;
      return '[${translate('Voice')}] ${(duration / 1000).ceil()}s';
    }
    if (kind == DirectChatKind.forward.name) {
      return '[${translate('Chat history')}]';
    }
    return text;
  }

  Future<void> _showForwardBundleDetails(
    BuildContext context,
    String title,
    List<Map<String, dynamic>> items,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title.isEmpty ? translate('Chat history') : title),
        content: SizedBox(
          width: 440,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 16),
            itemBuilder: (_, index) {
              final item = items[index];
              final sender = (item['sender_name'] ?? '').toString();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (sender.isNotEmpty)
                    Text(
                      sender,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    _forwardItemSummary(item),
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(translate('Close')),
          ),
        ],
      ),
    );
  }

  Widget _buildForwardBundle(
    BuildContext context,
    ChatMessage message, {
    required bool dark,
    required bool isOwnMessage,
  }) {
    final items = _forwardItems(message);
    final title =
        (message.customProperties?['ldesk_forward_title'] ?? '').toString();
    final foreground = dark ? Colors.white : const Color(0xFF181818);
    final secondary = foreground.withOpacity(0.62);
    final border = dark
        ? const Color(0xFF4A4D54)
        : Colors.black.withOpacity(isOwnMessage ? 0.13 : 0.09);
    return InkWell(
      onTap: items.isEmpty
          ? null
          : () => _showForwardBundleDetails(context, title, items),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title.isEmpty ? translate('Chat history') : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            for (final item in items.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${(item['sender_name'] ?? '').toString()}: '
                  '${_forwardItemSummary(item)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              '${items.length} ${translate('messages')}',
              style: TextStyle(color: secondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// Small icon button used in the chat toolbar.
  Widget _toolbarIconButton(
    BuildContext context,
    bool dark, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: dark ? const Color(0x442B2D32) : const Color(0x44FFFFFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 16,
              color: dark ? const Color(0xFF999CA2) : const Color(0xFF999999),
            ),
          ),
        ),
      ),
    );
  }

  /// Rich text renderer — supports **bold**, *italic*, `code`,
  /// [color=red]text[/color], [size=20]text[/size], markdown tables, and URLs.
  Widget _buildRichText(String text, Color foreground, bool isDesktopHome) {
    return RichChatText(
      text: text,
      foreground: foreground,
      defaultSize: isDesktopHome ? 14 : 15,
      // PC 端保留文字选择（右键弹消息菜单）；手机端关闭选择，
      // 长按消息统一弹出微信手机版风格的操作面板。
      enableSelection: isDesktopHome,
      contextMenuBuilder: (_, __) => const SizedBox.shrink(),
    );
  }

  /// 定位消息卡片：地点名 + 坐标，点击弹出高德/百度/腾讯/系统地图选择。
  /// 微信风格位置卡片：上半部分缩略地图（高德瓦片，无 key），下半部分
  /// 白色区域显示地点名称 + 详细地址（或坐标）。点击打开全屏地图详情页。
  Widget _buildLocationCard(
    BuildContext context,
    DirectChatLocation loc,
    Color foreground,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = loc.name.isNotEmpty ? loc.name : translate('Location');
    final subtitle = loc.address.isNotEmpty
        ? loc.address
        : '${loc.latitude.toStringAsFixed(6)}, '
            '${loc.longitude.toStringAsFixed(6)}';
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => LocationDetailPage(location: loc),
          ),
        );
      },
      child: Container(
        width: 220,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: dark ? const Color(0xFF3A3D43) : const Color(0xFFE2E2E2),
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Colors.black12, blurRadius: 4),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 220,
              height: 96,
              child: flutter_map.FlutterMap(
                options: flutter_map.MapOptions(
                  initialCenter: latlong2.LatLng(loc.latitude, loc.longitude),
                  initialZoom: 16,
                  interactionOptions: const flutter_map.InteractionOptions(
                    flags: flutter_map.InteractiveFlag.none,
                  ),
                ),
                children: <Widget>[
                  flutter_map.TileLayer(
                    urlTemplate:
                        'https://webrd0{s}.is.autonavi.com/appmaptile'
                        '?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                    subdomains: const <String>['1', '2', '3', '4'],
                    userAgentPackageName: 'com.luoda.remote',
                    maxNativeZoom: 19,
                  ),
                  flutter_map.MarkerLayer(
                    markers: <flutter_map.Marker>[
                      flutter_map.Marker(
                        point: latlong2.LatLng(loc.latitude, loc.longitude),
                        width: 36,
                        height: 36,
                        child: const Icon(
                          Icons.location_on_rounded,
                          size: 30,
                          color: Color(0xFFFF4D4F),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: dark ? const Color(0xFFEDEDED) : const Color(0xFF222222),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: dark ? const Color(0xFF9A9DA3) : const Color(0xFF888888),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 弹出地图选择：高德 / 百度 / 腾讯 / 系统地图，用浏览器或 App 打开。
  Future<void> _openLocationMaps(
    BuildContext context,
    DirectChatLocation loc,
  ) async {
    final theme = Theme.of(context);
    final name = Uri.encodeComponent(
      loc.name.isNotEmpty ? loc.name : '${loc.latitude},${loc.longitude}',
    );
    final lat = loc.latitude.toStringAsFixed(6);
    final lng = loc.longitude.toStringAsFixed(6);
    final options = <(IconData, String, String)>[
      (
        Icons.map_rounded,
        translate('Amap'),
        'https://uri.amap.com/marker?position=$lng,$lat&name=$name',
      ),
      (
        Icons.public_rounded,
        translate('Baidu Maps'),
        'https://api.map.baidu.com/marker?location=$lat,$lng&title=$name',
      ),
      (
        Icons.location_city_rounded,
        translate('Tencent Maps'),
        'https://apis.map.qq.com/uri/v1/marker?marker=coord:$lat,$lng;title:$name',
      ),
      (
        Icons.explore_outlined,
        translate('System Map'),
        'geo:$lat,$lng?q=$lat,$lng($name)',
      ),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Text(
                translate('Open location in'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            for (final option in options)
              ListTile(
                leading: Icon(option.$1, color: const Color(0xFF07C160)),
                title: Text(option.$2),
                onTap: () {
                  Navigator.pop(sheetContext);
                  launchUrlString(
                    option.$3,
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: chatModel,
      child: Container(
        color: type == ChatPageType.desktopHome
            ? Theme.of(context).brightness == Brightness.dark
                ? kWeChatCanvasColorDark
                : kWeChatCanvasColor
            : type == ChatPageType.mobileMain
                ? Theme.of(context).brightness == Brightness.dark
                    ? kWeChatCanvasColorDark
                    : const Color(0xFFEDEDED)
                : Theme.of(context).scaffoldBackgroundColor,
        child: Consumer<ChatModel>(
          builder: (context, chatModel, child) {
            final currentKey = chatModel.currentKey;
            final isDesktopHome = type == ChatPageType.desktopHome;
            final dark = Theme.of(context).brightness == Brightness.dark;
            debugPrint('CHATPAGE_DIAG isDesktopHome=' +
                isDesktopHome.toString() +
                ' peer=' +
                chatModel.currentKey.peerId +
                ' msgs=' +
                (chatModel.messages[chatModel.currentKey]?.chatMessages
                            ?.length ??
                        0)
                    .toString() +
                ' multi=' +
                chatModel.isMultiSelectMode.toString() +
                ' search=' +
                chatModel.chatSearchVisible.toString());
            debugPrint('WINDOW_DIAG mqw=' +
                MediaQuery.sizeOf(context).width.toStringAsFixed(1) +
                ' mqh=' +
                MediaQuery.sizeOf(context).height.toStringAsFixed(1) +
                ' dpr=' +
                MediaQuery.devicePixelRatioOf(context).toString());
            final pv = WidgetsBinding.instance.platformDispatcher.views.first;
            debugPrint('PHYS_DIAG pw=' +
                pv.physicalSize.width.toStringAsFixed(1) +
                ' ph=' +
                pv.physicalSize.height.toStringAsFixed(1) +
                ' dpr=' +
                pv.devicePixelRatio.toString());
            final readOnly = currentKey.peerId.isEmpty ||
                type == ChatPageType.desktopCM &&
                    gFFI.serverModel.clients
                            .firstWhereOrNull(
                                (e) => e.id == chatModel.currentKey.connId)
                            ?.disconnected ==
                        true;
            Widget composerTool(
              IconData icon,
              String tooltip,
              VoidCallback? onPressed,
            ) {
              return Tooltip(
                message: translate(tooltip),
                child: IconButton(
                  tooltip: '',
                  onPressed: onPressed,
                  constraints: BoxConstraints.tightFor(
                    width: isDesktopHome ? 36 : 48,
                    height: isDesktopHome ? 36 : 48,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(icon, size: isDesktopHome ? 20 : 22),
                ),
              );
            }

            Widget messageAvatar(
              ChatUser user,
              Function? onPressAvatar,
              Function? onLongPressAvatar,
            ) {
              final name = (user.firstName ?? user.id).trim();
              final initial = name.isEmpty ? '?' : name.characters.first;
              final avatarSize = isDesktopHome ? 40.0 : 42.0;
              final fallback = Container(
                width: avatarSize,
                height: avatarSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: str2color(name),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
              return buildAvatarWidget(
                    avatar: user.profileImage ?? '',
                    size: avatarSize,
                    borderRadius: 6,
                    fallback: fallback,
                  ) ??
                  fallback;
            }

            /// Overlays a small phone badge on the bottom-right corner when
            /// the peer message was sent from a mobile client.
            Widget maybePhoneBadge(ChatMessage message, Widget avatar) {
              final isPeerMobile = message.user.id != chatModel.me.id &&
                  message.customProperties?['ldesk_src_platform'] == 'mobile';
              if (!isPeerMobile) return avatar;
              return SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned.fill(child: avatar),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(Icons.phone_android_rounded,
                            size: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              );
            }

            bool hasDelivery(ChatMessage message) {
              final d = (message.customProperties?['ldesk_delivery'] ?? '')
                  .toString();
              return d == 'queued' ||
                  d == 'sent' ||
                  d == 'delivered' ||
                  d == 'failed';
            }

            String aiReplyLabel(ChatMessage message) {
              final aiReply =
                  message.customProperties?['ldesk_ai_reply'] == 'true';
              final isLoading =
                  message.customProperties?['ldesk_ai_loading'] == 'true';
              if (isLoading) return '${translate("AI thinking")}...';
              if (aiReply) return translate('AI auto-reply');
              return '';
            }

            String connSourceEndpointOf(ChatMessage message) {
              final raw = message.customProperties?['ldesk_conn_endpoint']
                      ?.toString()
                      .trim() ??
                  '';
              return DirectPairingStore.connEndpointOf(raw);
            }

            String connSourceLabelOf(ChatMessage message) {
              if (chatModel.isFileHelperConversation) return '';
              final props = message.customProperties;
              return messageSourceLabel(
                srcPlatform: props?['ldesk_src_platform']?.toString(),
                connMode: props?['ldesk_conn_mode']?.toString() ?? '',
                connEndpoint: connSourceEndpointOf(message),
                connPort:
                    int.tryParse('${props?['ldesk_conn_port'] ?? ''}') ?? 0,
                fallbackTarget: chatModel.currentKey.peerId,
                ipSource: props?['ldesk_conn_source']?.toString(),
              );
            }

            Widget deliveryWidget(ChatMessage message) {
              final d = (message.customProperties?['ldesk_delivery'] ?? '')
                  .toString();
              if (d.isEmpty) return const SizedBox.shrink();
              IconData icon;
              Color? color;
              String label;
              switch (d) {
                case 'queued':
                  icon = Icons.access_time_rounded;
                  label = translate('Waiting to send');
                  break;
                case 'sent':
                  icon = Icons.done_rounded;
                  label = translate('Sent');
                  break;
                case 'delivered':
                  icon = Icons.done_all_rounded;
                  label = translate('Delivered');
                  break;
                case 'failed':
                  icon = Icons.error_outline_rounded;
                  color = Colors.redAccent;
                  label = translate('Failed');
                  break;
                default:
                  return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 13, color: (color ?? Colors.grey).withOpacity(0.5)),
                  const SizedBox(width: 3),
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color: (color ?? Colors.grey).withOpacity(0.5))),
                ],
              );
            }

            String selfDestructLabel(ChatMessage message) {
              final expiresAt = DateTime.tryParse(
                (message.customProperties?['ldesk_expires_at'] ?? '')
                    .toString(),
              );
              if (expiresAt == null) return '';
              final remaining = expiresAt.difference(DateTime.now().toUtc());
              if (remaining <= Duration.zero) return translate('Expiring');
              if (remaining.inMinutes < 1) {
                return '${translate('Self-destruct')} ${remaining.inSeconds}s';
              }
              if (remaining.inHours < 1) {
                return '${translate('Self-destruct')} ${remaining.inMinutes}m';
              }
              return '${translate('Self-destruct')} ${remaining.inHours}h';
            }

            String fileSizeLabel(int fileSize) {
              if (fileSize < 1024) return '$fileSize B';
              if (fileSize < 1024 * 1024) {
                return '${(fileSize / 1024).toStringAsFixed(1)} KB';
              }
              return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
            }

            Widget _buildInviteCard(
                BuildContext context, String link, Color foreground) {
              // 会议群邀请: luoda://meeting/{meetingId}
              if (link.startsWith('luoda://meeting/')) {
                final meetingId = link.split('luoda://meeting/').last.trim();
                final theme = Theme.of(context);
                final dark = theme.brightness == Brightness.dark;
                return GestureDetector(
                  onTap: () {
                    final group = MeetingGroupStore.find(meetingId);
                    if (group != null) {
                      // 已有此会议记录，切换到会议聊天
                    } else {
                      showToast(translate('Opening meeting...'));
                    }
                  },
                  child: Container(
                    width: 240,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: dark
                          ? const Color(0xFF2A3A2A)
                          : const Color(0xFFEDF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: dark
                            ? const Color(0xFF3A6A3A)
                            : const Color(0xFFB8E8B8),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(Icons.groups_rounded,
                                size: 18,
                                color: dark
                                    ? const Color(0xFF7AE87A)
                                    : const Color(0xFF1A8E1A)),
                            const SizedBox(width: 8),
                            Text(
                              translate('Meeting Invitation'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: dark
                                    ? Colors.white
                                    : const Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          translate('Join meeting group to watch and chat'),
                          style: TextStyle(
                              fontSize: 11,
                              color: dark
                                  ? Colors.white70
                                  : const Color(0xFF666666)),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A8E1A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            translate('Join'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // 远程桌面邀请: luoda://join/{short_code}?endpoint={endpoint}
              final invite = ViewerInviteLink.tryParse(Uri.parse(link));
              if (invite == null) {
                return Text(link, style: TextStyle(color: foreground));
              }
              final theme = Theme.of(context);
              final dark = theme.brightness == Brightness.dark;
              return GestureDetector(
                onTap: () {
                  publishViewerInvite(Uri.parse(link));
                },
                child: Container(
                  width: 240,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF2A3A4A)
                        : const Color(0xFFE8F4FD),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: dark
                          ? const Color(0xFF3A5A7A)
                          : const Color(0xFFB8D4E8),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.videocam_rounded,
                              size: 18,
                              color: dark
                                  ? const Color(0xFF7AB8E8)
                                  : const Color(0xFF1A73E8)),
                          const SizedBox(width: 8),
                          Text(
                            translate('Join Remote Session'),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color:
                                  dark ? Colors.white : const Color(0xFF1A1A1A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        translate('Click to join and watch the remote session'),
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              dark ? Colors.white70 : const Color(0xFF666666),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: dark
                              ? const Color(0xFF1A73E8)
                              : const Color(0xFF1A73E8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          translate('Join'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget messageBody(
              ChatMessage message, {
              required bool isOwnMessage,
              required bool includeMetadata,
            }) {
              final foreground = dark ? Colors.white : const Color(0xFF181818);
              final properties = message.customProperties;
              final recalled = properties?['ldesk_disposition'] == 'recalled';
              final isFile = !recalled && properties?['ldesk_kind'] == 'file';
              final isVoice = !recalled && properties?['ldesk_kind'] == 'voice';
              final isForward =
                  !recalled && properties?['ldesk_kind'] == 'forward';
              final recordId = (properties?['ldesk_id'] ?? '').toString();
              final messageId = _messageTranslationKey(message);
              final translated = chatModel.messageTranslation(messageId);
              final translating =
                  chatModel.isMessageTranslationPending(messageId);
              final voiceDurationMs = int.tryParse(
                    '${properties?['ldesk_voice_duration_ms'] ?? 0}',
                  ) ??
                  0;
              final fileName =
                  (properties?['ldesk_file_name'] ?? '').toString();
              final fileSize = int.tryParse(
                    '${properties?['ldesk_file_size'] ?? 0}',
                  ) ??
                  0;
              final localPath =
                  (properties?['ldesk_local_path'] ?? '').toString();
              final isImageAttachment = isFile &&
                  filePreviewKindForName(fileName) == FilePreviewKind.image &&
                  localPath.isNotEmpty;
              final replyToText =
                  (properties?['ldesk_reply_to_text'] ?? '').toString();
              final replyToSender =
                  (properties?['ldesk_reply_to_sender'] ?? '').toString();
              final reactions =
                  properties?['ldesk_reactions'] as Map<String, dynamic>?;
              final isEdited = properties?['ldesk_is_edited'] == true;
              return Column(
                crossAxisAlignment: isOwnMessage
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: <Widget>[
                  // Quote reply indicator
                  if (replyToText.isNotEmpty)
                    Container(
                      constraints:
                          BoxConstraints(maxWidth: isDesktopHome ? 400 : 300),
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: isOwnMessage
                            ? Colors.black.withOpacity(0.12)
                            : Colors.black.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.08),
                        ),
                      ),
                      child: Text(
                        replyToSender.isEmpty
                            ? replyToText
                            : '$replyToSender: $replyToText',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground.withOpacity(0.65),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                  if (isForward)
                    _buildForwardBundle(
                      context,
                      message,
                      dark: dark,
                      isOwnMessage: isOwnMessage,
                    )
                  else if (isVoice && recordId.isNotEmpty)
                    VoiceMessageBubble(
                      chatModel: chatModel,
                      messageId: recordId,
                      durationMs: voiceDurationMs,
                    )
                  else if (isImageAttachment)
                    InkWell(
                      onTap: () {
                        unawaited(_openMessageFilePreview(
                          context,
                          fileName: fileName,
                          fileSize: fileSize,
                          localPath: localPath,
                        ));
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isDesktopHome ? 280 : 240,
                            maxHeight: isDesktopHome ? 240 : 220,
                          ),
                          child: Image.file(
                            File(localPath),
                            fit: BoxFit.contain,
                            cacheWidth: 560,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => Container(
                              width: 160,
                              height: 96,
                              alignment: Alignment.center,
                              color: dark
                                  ? const Color(0xFF303238)
                                  : const Color(0xFFF0F0F0),
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: foreground.withOpacity(0.55),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (isFile && fileName.isNotEmpty)
                    InkWell(
                      onTap: () {
                        unawaited(_openMessageFilePreview(
                          context,
                          fileName: fileName,
                          fileSize: fileSize,
                          localPath: localPath,
                        ));
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: isDesktopHome ? 270 : 236,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        fileName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: foreground,
                                          fontSize: isDesktopHome ? 14 : 15,
                                          fontWeight: FontWeight.w500,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        fileSizeLabel(fileSize),
                                        style: TextStyle(
                                          color: foreground.withOpacity(0.5),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 48,
                                  height: 52,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: <Widget>[
                                      Icon(
                                        Icons.insert_drive_file_rounded,
                                        size: 48,
                                        color: filePreviewColor(fileName, 0.88),
                                      ),
                                      Positioned(
                                        bottom: 8,
                                        child: Text(
                                          fileExtensionLabel(fileName),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 18),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.desktop_windows_rounded,
                                  size: 12,
                                  color: foreground.withOpacity(0.38),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '点聊',
                                  style: TextStyle(
                                    color: foreground.withOpacity(0.42),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (message.text.trim().startsWith('luoda://join/') ||
                      message.text.trim().startsWith('luoda://meeting/'))
                    _buildInviteCard(context, message.text.trim(), foreground)
                  else if (DirectChatLocation.tryParse(message.text)
                      case final DirectChatLocation loc)
                    _buildLocationCard(context, loc, foreground)
                  else
                    _buildRichText(message.text, foreground, isDesktopHome),
                  if (translating || translated?.isNotEmpty == true)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.only(top: 7),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: foreground.withOpacity(0.14),
                          ),
                        ),
                      ),
                      child: translating
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: foreground.withOpacity(0.55),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  translate('Translating...'),
                                  style: TextStyle(
                                    color: foreground.withOpacity(0.62),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : SelectableText(
                              translated!,
                              style: TextStyle(
                                color: foreground.withOpacity(0.82),
                                fontSize: isDesktopHome ? 13 : 14,
                                height: 1.45,
                              ),
                            ),
                    ),
                  // Reaction bar
                  if (reactions != null && reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: reactions.entries.map((entry) {
                          final emoji = entry.key;
                          final users = (entry.value as List<dynamic>)
                              .map((e) => e.toString())
                              .toList();
                          final isActive = users.contains(chatModel.me.id);
                          return GestureDetector(
                            onTap: () =>
                                chatModel.toggleReaction(message, emoji),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? kWeChatPrimaryColor.withOpacity(0.15)
                                    : Colors.black.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: isActive
                                    ? Border.all(
                                        color: kWeChatPrimaryColor
                                            .withOpacity(0.4),
                                        width: 1)
                                    : null,
                              ),
                              child: Text(
                                '$emoji ${users.length}',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  // (Edited) marker
                  if (isEdited && !recalled)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        translate('(edited)'),
                        style: TextStyle(
                          color: foreground.withOpacity(0.4),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  if (includeMetadata)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${message.createdAt.hour.toString().padLeft(2, '0')}:'
                          '${message.createdAt.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: foreground.withOpacity(0.2),
                            fontSize: 10,
                          ),
                        ),
                        if (isOwnMessage && hasDelivery(message)) ...<Widget>[
                          const SizedBox(width: 5),
                          deliveryWidget(message),
                        ],
                      ],
                    ).marginOnly(top: 3),
                ],
              );
            }

            Widget weChatMessageRow(
              ChatMessage message,
              ChatMessage? previousMessage,
              ChatMessage? nextMessage,
              bool isAfterDateSeparator,
              bool isBeforeDateSeparator,
              double maxBubbleWidth,
            ) {
              final isOwnMessage = message.user.id == chatModel.me.id;
              final properties = message.customProperties;
              final attachmentName =
                  (properties?['ldesk_file_name'] ?? '').toString();
              final isFileAttachment =
                  properties?['ldesk_kind'] == DirectChatKind.file.name;
              final isImageAttachment = isFileAttachment &&
                  filePreviewKindForName(attachmentName) ==
                      FilePreviewKind.image &&
                  (properties?['ldesk_local_path'] ?? '').toString().isNotEmpty;
              final isAiReply = !isOwnMessage &&
                  (message.customProperties?['ldesk_ai_reply'] == 'true' ||
                      message.customProperties?['ldesk_ai_loading'] == 'true');
              final attachmentBubbleColor =
                  dark ? const Color(0xFF2B2D32) : const Color(0xFFF1F1F1);
              final bubbleColor = isFileAttachment
                  ? attachmentBubbleColor
                  : isOwnMessage
                      ? dark
                          ? kWeChatOutgoingBubbleColorDark
                          : kWeChatOutgoingBubbleColor
                      : dark
                          ? kWeChatIncomingBubbleColorDark
                          : kWeChatIncomingBubbleColor;
              final connSourceLabel = connSourceLabelOf(message);
              // 每条消息前置一条灰色小字：标明该消息来自哪个端口、哪种连接方式
              // （PC/手机 + ID连接/公网IP/局域网IP/蓝牙），PC 与手机端显示一致。
              final showMessageSource = connSourceLabel.isNotEmpty &&
                  connSourceLabel != translate('Source not recorded');
              final content = messageBody(
                message,
                isOwnMessage: isOwnMessage,
                includeMetadata: false,
              );
              final bubble = isImageAttachment
                  ? ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                      child: content,
                    )
                  : isAiReply
                      ? Container(
                          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: content,
                        )
                      : Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            Container(
                              constraints:
                                  BoxConstraints(maxWidth: maxBubbleWidth),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                // LUODA FIX: light-mode incoming bubbles are white on a
                                // near-white canvas (#F7F7F7) — invisible. Add a 1px
                                // border in light mode so peer messages have clear edges.
                                // Dark mode keeps the original flat fill (no border) so
                                // the bubble doesn't feel "outlined" against dark canvas.
                                color: bubbleColor,
                                borderRadius: BorderRadius.circular(5),
                                border: !dark && !isOwnMessage
                                    ? Border.all(
                                        color: kWeChatIncomingBubbleBorder,
                                        width: 1,
                                      )
                                    : null,
                              ),
                              child: content,
                            ),
                            Positioned(
                              top: 11,
                              left: isOwnMessage ? null : -6,
                              right: isOwnMessage ? -6 : null,
                              child: CustomPaint(
                                size: const Size(7, 10),
                                painter: _ChatBubbleTailPainter(
                                  color: bubbleColor,
                                  pointsRight: isOwnMessage,
                                ),
                              ),
                            ),
                          ],
                        );
              final messageColumn = Flexible(
                child: MessageContextRegion(
                  // 桌面端右键 / 移动端长按：都弹出消息操作菜单。
                  onSecondaryTap: (position) {
                    unawaited(_openMessageActions(
                      context,
                      message,
                      position: position,
                      alignToAvatarLeft: isOwnMessage,
                    ));
                  },
                  onLongPress: (position) {
                    unawaited(_openMessageActions(
                      context,
                      message,
                      position: position,
                      alignToAvatarLeft: isOwnMessage,
                    ));
                  },
                  child: Column(
                    crossAxisAlignment: isOwnMessage
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: <Widget>[
                      if (showMessageSource)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: 4, left: 2, right: 2),
                          child: Text(
                            connSourceLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.2,
                              color: (dark
                                      ? const Color(0xFFA9ADB5)
                                      : const Color(0xFF6B7280))
                                  .withOpacity(0.2),
                            ),
                          ),
                        ),
                      bubble,
                      if (isAiReply && aiReplyLabel(message).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 2),
                          child: Text(
                            aiReplyLabel(message),
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              color: dark
                                  ? const Color(0xFF999CA2)
                                  : const Color(0xFF999999),
                            ),
                          ),
                        ),
                      if (isOwnMessage &&
                          (hasDelivery(message) ||
                              selfDestructLabel(message).isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 4, right: 2),
                          child: DefaultTextStyle.merge(
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              color: dark
                                  ? const Color(0xFF999CA2)
                                  : const Color(0xFF999999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasDelivery(message))
                                  deliveryWidget(message),
                                if (hasDelivery(message) &&
                                    (selfDestructLabel(message).isNotEmpty ||
                                        aiReplyLabel(message).isNotEmpty))
                                  const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 4),
                                    child: Text('·'),
                                  ),
                                if (selfDestructLabel(message).isNotEmpty)
                                  Text(selfDestructLabel(message)),
                                if (selfDestructLabel(message).isNotEmpty &&
                                    aiReplyLabel(message).isNotEmpty)
                                  const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 4),
                                    child: Text('·'),
                                  ),
                                if (aiReplyLabel(message).isNotEmpty)
                                  Text(aiReplyLabel(message),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: kWeChatPrimaryColor,
                                        fontWeight: FontWeight.w500,
                                      )),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
              final avatar = maybePhoneBadge(
                  message, messageAvatar(message.user, null, null));
              final avatarKey = GlobalKey();
              final inMultiSelect = chatModel.isMultiSelectMode;
              final messageId =
                  (message.customProperties?['ldesk_id'] ?? '').toString();
              final isSelected =
                  chatModel.selectedMessageIds.contains(messageId);
              // Multi-select checkbox
              Widget multiSelectCheckbox = const SizedBox.shrink();
              if (inMultiSelect && messageId.isNotEmpty) {
                multiSelectCheckbox = GestureDetector(
                  onTap: () => chatModel.toggleSelection(messageId),
                  child: Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          isSelected ? kWeChatPrimaryColor : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? kWeChatPrimaryColor
                            : (dark
                                ? const Color(0xFF555A62)
                                : const Color(0xFFCCCCCC)),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                );
              }
              final messageRow = Padding(
                padding: EdgeInsets.fromLTRB(
                  isDesktopHome ? 24 : 12,
                  isDesktopHome ? 10 : 8,
                  isDesktopHome ? 24 : 12,
                  2,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: isOwnMessage
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  children: isOwnMessage
                      ? <Widget>[
                          if (inMultiSelect) multiSelectCheckbox,
                          messageColumn,
                          const SizedBox(width: 11),
                          KeyedSubtree(key: avatarKey, child: avatar),
                        ]
                      : <Widget>[
                          if (inMultiSelect) multiSelectCheckbox,
                          avatar,
                          const SizedBox(width: 11),
                          messageColumn,
                        ],
                ),
              );
              final rowWidget = messageRow;
              if (!chatModel.chatSearchVisible ||
                  !chatModel.isChatSearchMatch(message)) {
                return rowWidget;
              }
              return AnimatedContainer(
                key: chatModel.chatSearchKeyFor(message),
                duration: const Duration(milliseconds: 180),
                color: chatModel.isCurrentChatSearchResult(message)
                    ? kWeChatPrimaryColor.withOpacity(dark ? 0.16 : 0.1)
                    : Colors.transparent,
                child: rowWidget,
              );
            }

            return Stack(
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final useWeChatMessages =
                      isDesktopHome || type == ChatPageType.mobileMain;
                  final scaledBubbleWidth =
                      constraints.maxWidth * (isDesktopHome ? 0.62 : 0.76);
                  final bubbleWidthCap = isDesktopHome ? 560.0 : 420.0;
                  final responsiveBubbleWidth =
                      scaledBubbleWidth > bubbleWidthCap
                          ? bubbleWidthCap
                          : scaledBubbleWidth;
                  final chat = DashChat(
                    onSend: chatModel.send,
                    currentUser: chatModel.me,
                    messages: chatModel
                            .messages[chatModel.currentKey]?.chatMessages ??
                        <ChatMessage>[],
                    readOnly: isDesktopHome ||
                        readOnly ||
                        type == ChatPageType.mobileMain,
                    inputOptions: InputOptions(
                      focusNode: chatModel.inputNode,
                      textController: chatModel.textController,
                      alwaysShowSend: isDesktopHome,
                      leading: type == ChatPageType.mobileMain
                          ? <Widget>[
                              VoiceMessageRecorderButton(
                                chatModel: chatModel,
                                enabled: !readOnly,
                              ),
                              if (onAttachFile != null)
                                composerTool(
                                  Icons.attach_file_rounded,
                                  'File Transfer',
                                  onAttachFile,
                                ),
                              if (onRemoteAssist != null)
                                composerTool(
                                  Icons.desktop_windows_outlined,
                                  'Remote Desktop',
                                  onRemoteAssist,
                                ),
                              const SizedBox(width: 4),
                            ]
                          : null,
                      inputTextStyle: TextStyle(
                          fontSize: isDesktopHome ? 14 : 15,
                          fontFamilyFallback: kChatEmojiFontFallback,
                          color: Theme.of(context).textTheme.titleLarge?.color),
                      inputDecoration: InputDecoration(
                        isDense: true,
                        hintText: translate('Write a message'),
                        filled: !isDesktopHome,
                        fillColor: isDesktopHome
                            ? Colors.transparent
                            : Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF2B2D32)
                                : Colors.white,
                        hintStyle: TextStyle(
                          fontSize: isDesktopHome ? 14 : 15,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? MyTheme.mutedDark
                              : MyTheme.mutedLight,
                        ),
                        contentPadding: isDesktopHome
                            ? const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 12,
                              )
                            : const EdgeInsets.all(10),
                        border: isDesktopHome
                            ? InputBorder.none
                            : OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.0),
                                borderSide: const BorderSide(
                                  width: 1,
                                  style: BorderStyle.solid,
                                ),
                              ),
                      ),
                      inputMaxLines: isDesktopHome ? 5 : 3,
                      inputToolbarMargin:
                          isDesktopHome ? EdgeInsets.zero : null,
                      inputToolbarPadding: isDesktopHome
                          ? const EdgeInsets.fromLTRB(12, 8, 12, 10)
                          : const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      inputToolbarStyle: isDesktopHome
                          ? BoxDecoration(
                              color:
                                  dark ? const Color(0xFF25272C) : Colors.white,
                              border: Border(
                                top: BorderSide(
                                  color: Theme.of(context)
                                      .dividerColor
                                      .withOpacity(0.75),
                                ),
                              ),
                            )
                          : null,
                      sendButtonBuilder: defaultSendButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        color: MyTheme.accent,
                        icon: Icons.send_rounded,
                      ),
                    ),
                    messageListOptions: MessageListOptions(
                      showDateSeparator: useWeChatMessages,
                      separatorFrequency: SeparatorFrequency.hours,
                      dateSeparatorBuilder: (date) {
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final yesterday =
                            today.subtract(const Duration(days: 1));
                        final msgDate =
                            DateTime(date.year, date.month, date.day);
                        String label;
                        if (msgDate == today) {
                          label = '${translate('Today')} '
                              '${date.hour.toString().padLeft(2, '0')}:'
                              '${date.minute.toString().padLeft(2, '0')}';
                        } else if (msgDate == yesterday) {
                          label = '${translate('Yesterday')} '
                              '${date.hour.toString().padLeft(2, '0')}:'
                              '${date.minute.toString().padLeft(2, '0')}';
                        } else if (date.year == now.year) {
                          label = '${date.month}/${date.day} '
                              '${date.hour.toString().padLeft(2, '0')}:'
                              '${date.minute.toString().padLeft(2, '0')}';
                        } else {
                          label = '${date.year}/${date.month}/${date.day} '
                              '${date.hour.toString().padLeft(2, '0')}:'
                              '${date.minute.toString().padLeft(2, '0')}';
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: (dark
                                      ? const Color(0xFF999CA2)
                                      : const Color(0xFF999999))
                                  .withOpacity(0.2),
                              fontSize: 10,
                              height: 1.2,
                            ),
                          ),
                        );
                      },
                    ),
                    messageOptions: MessageOptions(
                      showCurrentUserAvatar:
                          isDesktopHome || type == ChatPageType.mobileMain,
                      showOtherUsersAvatar:
                          isDesktopHome || type == ChatPageType.mobileMain,
                      showOtherUsersName: false,
                      onLongPressMessage: (message) async {
                        final String? action;
                        if (type == ChatPageType.mobileMain) {
                          // 手机端：微信手机版风格底部操作面板。
                          action = await _showMobileMessageActions(
                              context, message);
                        } else {
                          action = await _showWeChatContextMenu(
                            context,
                            message,
                            position: Offset.zero,
                          );
                        }
                        if (context.mounted) {
                          await _handleWeChatContextAction(
                              context, action, message);
                        }
                      },
                      avatarBuilder:
                          isDesktopHome || type == ChatPageType.mobileMain
                              ? messageAvatar
                              : null,
                      messageRowBuilder: useWeChatMessages
                          ? (message,
                                  previousMessage,
                                  nextMessage,
                                  isAfterDateSeparator,
                                  isBeforeDateSeparator) =>
                              weChatMessageRow(
                                message,
                                previousMessage,
                                nextMessage,
                                isAfterDateSeparator,
                                isBeforeDateSeparator,
                                responsiveBubbleWidth,
                              )
                          : null,
                      textColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF181818),
                      maxWidth: constraints.maxWidth * 0.7,
                      messageTextBuilder: (message, _, __) {
                        final isOwnMessage = message.user.id == chatModel.me.id;
                        return messageBody(
                          message,
                          isOwnMessage: isOwnMessage,
                          includeMetadata: true,
                        );
                      },
                      messageDecorationBuilder:
                          (message, previousMessage, nextMessage) {
                        final isOwnMessage = message.user.id == chatModel.me.id;
                        final bubbleColor = isDesktopHome
                            ? isOwnMessage
                                ? dark
                                    ? kWeChatOutgoingBubbleColorDark
                                    : const Color(0xFF95EC69)
                                : dark
                                    ? kWeChatIncomingBubbleColorDark
                                    : Colors.white
                            : isOwnMessage
                                ? dark
                                    ? kWeChatOutgoingBubbleColorDark
                                    : const Color(0xFF95EC69)
                                : dark
                                    ? kWeChatIncomingBubbleColorDark
                                    : Colors.white;
                        return defaultMessageDecoration(
                          color: bubbleColor,
                          borderTopLeft: 8,
                          borderTopRight: 8,
                          borderBottomRight: isOwnMessage ? 2 : 8,
                          borderBottomLeft: isOwnMessage ? 8 : 2,
                        );
                      },
                    ),
                  ).workaroundFreezeLinuxMint();
                  final messageList = chat;
                  // Typing indicator — shared between desktop and mobile
                  final peerId = chatModel.currentKey.peerId;
                  Widget typingBar = const SizedBox.shrink();
                  if (peerId.isNotEmpty && chatModel.isPeerTyping(peerId)) {
                    typingBar = Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                dark
                                    ? const Color(0xFF999CA2)
                                    : const Color(0xFF999999),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            translate('Typing...'),
                            style: TextStyle(
                              fontSize: 12,
                              color: dark
                                  ? const Color(0xFF999CA2)
                                  : const Color(0xFF999999),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  // Reply preview bar
                  final replyMsg = chatModel.replyToMessage;
                  Widget replyBar = const SizedBox.shrink();
                  if (replyMsg != null) {
                    final replyUser = replyMsg.user.id == chatModel.me.id
                        ? translate('Me')
                        : (replyMsg.user.firstName ?? replyMsg.user.id);
                    replyBar = Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: dark
                            ? kWeChatCanvasColorDark
                            : const Color(0xFFF7F7F7),
                        border: Border(
                          top: BorderSide(
                            color: dark
                                ? const Color(0xFF3A3D43)
                                : const Color(0xFFE2E2E2),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 36,
                            decoration: BoxDecoration(
                              color: kWeChatPrimaryColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${translate('Replying to')} $replyUser',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: kWeChatPrimaryColor,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  replyMsg.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: dark
                                        ? const Color(0xFF999CA2)
                                        : const Color(0xFF888888),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => chatModel.cancelReply(),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            constraints: const BoxConstraints.tightFor(
                                width: 32, height: 32),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    );
                  }
                  // "Load older messages" banner — shown at the top when
                  // the conversation has more history beyond the initial load.
                  Widget loadOlderBar = const SizedBox.shrink();
                  if (chatModel.hasOlderMessages(chatModel.currentKey) &&
                      chatModel.messages[chatModel.currentKey]?.chatMessages
                              .isNotEmpty ==
                          true) {
                    loadOlderBar = GestureDetector(
                      onTap: () =>
                          chatModel.loadOlderMessages(chatModel.currentKey),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        color: Colors.transparent,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.unfold_more_rounded,
                                  size: 16,
                                  color: dark
                                      ? const Color(0xFF999CA2)
                                      : const Color(0xFF999999)),
                              const SizedBox(width: 6),
                              Text(
                                translate('Load older messages'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: dark
                                      ? const Color(0xFF999CA2)
                                      : const Color(0xFF999999),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  if (!isDesktopHome) {
                    return Column(
                      children: <Widget>[
                        loadOlderBar,
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                _mobileComposerKey.currentState?.closePanels(),
                            child: _buildMessageArea(
                              context: context,
                              dark: dark,
                              messageList: messageList,
                              chatModel: chatModel,
                              isDesktopHome: isDesktopHome,
                            ),
                          ),
                        ),
                        replyBar,
                        typingBar,
                        _MobileChatComposer(
                          key: _mobileComposerKey,
                          chatModel: chatModel,
                          enabled: !readOnly,
                          dark: dark,
                          onAttachFile: onAttachFile,
                          onRemoteAssist: onRemoteAssist,
                          onSendImage: onSendImage,
                          onTakePhoto: onTakePhoto,
                          onSendLocation: onSendLocation,
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: <Widget>[
                      loadOlderBar,
                      Expanded(
                          child: _buildMessageArea(
                        context: context,
                        dark: dark,
                        messageList: messageList,
                        chatModel: chatModel,
                        isDesktopHome: isDesktopHome,
                      )),
                      replyBar,
                      typingBar,
                      _DesktopChatComposer(
                        chatModel: chatModel,
                        enabled: !readOnly,
                        dark: dark,
                        onAttachFile: onAttachFile,
                        onRemoteAssist: onRemoteAssist,
                        onSendImage: onSendImage,
                        onScreenshot: onScreenshot,
                        onPasteImage: onPasteImage,
                      ),
                    ],
                  );
                }),
                // Toolbar buttons (top-right corner)
                if (isDesktopHome && chatModel.currentKey.peerId.isNotEmpty)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _toolbarIconButton(
                          context,
                          dark,
                          icon: Icons.perm_media_outlined,
                          tooltip: translate('Shared media'),
                          onTap: () => _showMediaGallery(context),
                        ),
                        const SizedBox(width: 4),
                        _toolbarIconButton(
                          context,
                          dark,
                          icon: Icons.delete_sweep_outlined,
                          tooltip: translate('Clear chat history'),
                          onTap: () => _showClearHistoryDialog(context),
                        ),
                      ],
                    ),
                  ),
                // Multi-select bottom action bar
                if (chatModel.isMultiSelectMode)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: multiSelectBottomBar(context, dark),
                  ),
                if (chatModel.chatSearchVisible)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: dark
                          ? const Color(0xF22B2D32)
                          : const Color(0xF2FFFFFF),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              autofocus: false,
                              focusNode: chatModel.chatSearchFocusNode,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: translate('Search messages...'),
                                prefixIcon:
                                    const Icon(Icons.search_rounded, size: 20),
                                suffixIcon: chatModel.chatSearchText.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded,
                                            size: 18),
                                        onPressed: () =>
                                            chatModel.updateChatSearch(''),
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              onChanged: chatModel.updateChatSearch,
                              controller: chatModel.chatSearchController,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 52,
                            child: Text(
                              chatModel.chatSearchText.trim().isEmpty
                                  ? ''
                                  : chatModel.chatSearchMatches.isEmpty
                                      ? translate('No results')
                                      : '${chatModel.chatSearchMatchIndex + 1}/${chatModel.chatSearchMatches.length}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(letterSpacing: 0),
                            ),
                          ),
                          IconButton(
                            constraints: const BoxConstraints.tightFor(
                              width: 34,
                              height: 34,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                            tooltip: translate('Previous result'),
                            onPressed:
                                chatModel.canSelectPreviousChatSearchResult
                                    ? chatModel.selectPreviousChatSearchResult
                                    : null,
                          ),
                          IconButton(
                            constraints: const BoxConstraints.tightFor(
                              width: 34,
                              height: 34,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            tooltip: translate('Next result'),
                            onPressed: chatModel.canSelectNextChatSearchResult
                                ? chatModel.selectNextChatSearchResult
                                : null,
                          ),
                          IconButton(
                            constraints: const BoxConstraints.tightFor(
                              width: 34,
                              height: 34,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.close_rounded),
                            tooltip: translate('Close search'),
                            onPressed: chatModel.closeChatSearch,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ).paddingOnly(bottom: isDesktopHome ? 0 : 8);
          },
        ),
      ),
    );
  }

  /// Wraps the DashChat message list with a clearly-visible empty-state card.
  ///
  /// Previous version used `0xFFEAECEF` card bg on `0xFFF7F7F7` canvas (≈5%
  /// luminance difference), making the card blend into the background. The
  /// hint text `0xFF6E7178` had a contrast ratio ≈3.87:1 against the card
  /// background, below the WCAG AA minimum of 4.5:1.
  ///
  /// This version uses a pure white card with a soft shadow, dark text, and
  /// an explanatory subtitle — impossible to miss on any theme.
  Widget _buildMessageArea({
    required BuildContext context,
    required bool dark,
    required Widget messageList,
    required ChatModel chatModel,
    required bool isDesktopHome,
  }) {
    final messages = chatModel.messages[chatModel.currentKey]?.chatMessages;
    final hasMessages = messages != null && messages.isNotEmpty;
    if (hasMessages) {
      return messageList;
    }
    // Empty state — visible card with icon, heading, and subtitle.
    final cardBg = dark ? const Color(0xFF2E3139) : const Color(0xFFFFFFFF);
    final cardBorder = dark ? const Color(0xFF3D404A) : const Color(0xFFE2E2E7);
    final iconColor = dark ? const Color(0xFF5A5D66) : const Color(0xFFB0B0B5);
    final headingColor =
        dark ? const Color(0xFFAAADB5) : const Color(0xFF3C3C43);
    final subColor = dark ? const Color(0xFF727580) : const Color(0xFF8E8E93);
    final shadowColor = dark ? Colors.black26 : const Color(0x14000000);
    final peerId = chatModel.currentKey.peerId;
    final heading = peerId.isEmpty
        ? translate('Select a conversation')
        : translate('No messages yet');
    final subtitle = peerId.isEmpty
        ? translate('Choose a contact from the left sidebar to start chatting')
        : translate('Type a message below to start the conversation');
    // Use a solid background instead of stacking on the grey DashChat canvas,
    // which was previously the primary source of the "everything is grey" look.
    final emptyCard = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 36),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cardBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 52, color: iconColor),
              const SizedBox(height: 18),
              Text(
                heading,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: headingColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: subColor,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (isDesktopHome) return emptyCard;
    // Mobile: keep the custom WeChat-style composer visible below the empty
    // card so a first message can be typed without needing to receive one.
    return Stack(
      children: <Widget>[
        Positioned.fill(child: messageList),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: emptyCard,
        ),
      ],
    );
  }
}

/// WeChat-style composer for the mobile chat page.
///
/// Layout mirrors WeChat's chat input: a voice button on the left, a rounded
/// text field in the middle, and emoji / "+" buttons (or a send button while
/// text is present) on the right. The emoji panel shares the exact same emoji
/// pack as the PC composer (kDotChatEmojiList).
class _MobileChatComposer extends StatefulWidget {
  const _MobileChatComposer({
    super.key,
    required this.chatModel,
    required this.enabled,
    required this.dark,
    this.onAttachFile,
    this.onRemoteAssist,
    this.onSendImage,
    this.onTakePhoto,
    this.onSendLocation,
  });

  final ChatModel chatModel;
  final bool enabled;
  final bool dark;
  final VoidCallback? onAttachFile;
  final VoidCallback? onRemoteAssist;
  final VoidCallback? onSendImage;
  final VoidCallback? onTakePhoto;
  final VoidCallback? onSendLocation;

  @override
  State<_MobileChatComposer> createState() => _MobileChatComposerState();
}

class _MobileChatComposerState extends State<_MobileChatComposer> {
  bool _showEmojiPanel = false;
  bool _showMorePanel = false;

  /// Closes any open panel (used when the message area is tapped).
  void closePanels() {
    if (!_showEmojiPanel && !_showMorePanel) return;
    setState(() {
      _showEmojiPanel = false;
      _showMorePanel = false;
    });
  }

  void _toggleEmoji() {
    setState(() {
      _showEmojiPanel = !_showEmojiPanel;
      _showMorePanel = false;
    });
    if (_showEmojiPanel) {
      widget.chatModel.inputNode.unfocus();
    } else {
      widget.chatModel.inputNode.requestFocus();
    }
  }

  void _toggleMore() {
    setState(() {
      _showMorePanel = !_showMorePanel;
      _showEmojiPanel = false;
    });
    if (_showMorePanel) {
      widget.chatModel.inputNode.unfocus();
    } else {
      widget.chatModel.inputNode.requestFocus();
    }
  }

  void _closePanelsOnInputTap() {
    if (!_showEmojiPanel && !_showMorePanel) return;
    setState(() {
      _showEmojiPanel = false;
      _showMorePanel = false;
    });
  }

  void _insertEmoji(String emoji) {
    final controller = widget.chatModel.textController;
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _deleteLastEmoji() {
    final controller = widget.chatModel.textController;
    final text = controller.text;
    if (text.isEmpty) return;
    final sel = controller.selection;
    if (sel.isValid && !sel.isCollapsed) {
      controller.value = TextEditingValue(
        text: text.replaceRange(sel.start, sel.end, ''),
        selection: TextSelection.collapsed(offset: sel.start),
      );
      return;
    }
    final graphemes = text.characters;
    if (graphemes.isEmpty) return;
    final remaining = graphemes.take(graphemes.length - 1).toString();
    controller.value = TextEditingValue(
      text: remaining,
      selection: TextSelection.collapsed(offset: remaining.length),
    );
  }

  void _send() {
    final text = widget.chatModel.textController.text.trim();
    if (!widget.enabled || text.isEmpty) return;
    widget.chatModel.sendText(text);
    widget.chatModel.textController.clear();
    if (_showEmojiPanel || _showMorePanel) {
      setState(() {
        _showEmojiPanel = false;
        _showMorePanel = false;
      });
    } else {
      widget.chatModel.inputNode.requestFocus();
    }
  }

  void _runTool(VoidCallback action) {
    closePanels();
    action();
  }

  Widget _toolButton(IconData icon, bool active, VoidCallback onPressed) {
    final dark = widget.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Icon(
          icon,
          size: 26,
          color: active
              ? kWeChatPrimaryColor
              : dark
                  ? const Color(0xFFB8BBC2)
                  : const Color(0xFF555555),
        ),
      ),
    );
  }

  Widget _buildEmojiPanel() {
    final dark = widget.dark;
    final bg = dark ? const Color(0xFF1E2024) : const Color(0xFFF7F7F7);
    final border = dark ? const Color(0xFF3A3D43) : const Color(0xFFE5E5E5);
    return Container(
      height: 238,
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border, width: 0.5)),
      ),
      child: Column(
        children: <Widget>[
          Container(
            height: 34,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: kWeChatPrimaryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                translate('Emoji'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kWeChatPrimaryColor,
                ),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                childAspectRatio: 1.05,
              ),
              itemCount: kDotChatEmojiList.length,
              itemBuilder: (_, i) => InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _insertEmoji(kDotChatEmojiList[i]),
                child: Center(
                  child: Text(
                    kDotChatEmojiList[i],
                    style: const TextStyle(
                      fontSize: 24,
                      fontFamilyFallback: kChatEmojiFontFallback,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 42,
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: Row(
              children: <Widget>[
                _panelBarButton(
                  icon: Icons.backspace_outlined,
                  onTap: _deleteLastEmoji,
                ),
                const Spacer(),
                _panelBarButton(
                  label: translate('Send'),
                  filled: true,
                  onTap: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelBarButton({
    IconData? icon,
    String? label,
    bool filled = false,
    required VoidCallback onTap,
  }) {
    final dark = widget.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        width: icon != null ? 44 : 64,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? kWeChatPrimaryColor
              : dark
                  ? const Color(0xFF2B2D32)
                  : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: filled
              ? null
              : Border.all(
                  color:
                      dark ? const Color(0xFF3A3D43) : const Color(0xFFE2E2E2),
                  width: 0.5,
                ),
        ),
        child: icon != null
            ? Icon(
                icon,
                size: 22,
                color: dark ? const Color(0xFFB8BBC2) : const Color(0xFF555555),
              )
            : Text(
                label ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildMorePanel() {
    final dark = widget.dark;
    final bg = dark ? const Color(0xFF1E2024) : const Color(0xFFF7F7F7);
    final border = dark ? const Color(0xFF3A3D43) : const Color(0xFFE5E5E5);
    final items = <(IconData, String, VoidCallback)>[
      if (widget.onAttachFile != null)
        (
          Icons.folder_outlined,
          translate('File Transfer'),
          () => _runTool(widget.onAttachFile!),
        ),
      if (widget.onSendImage != null)
        (
          Icons.image_outlined,
          translate('Send Image'),
          () => _runTool(widget.onSendImage!),
        ),
      if (widget.onTakePhoto != null)
        (
          Icons.camera_alt_outlined,
          translate('Take Photo'),
          () => _runTool(widget.onTakePhoto!),
        ),
      if (widget.onSendLocation != null)
        (
          Icons.location_on_outlined,
          translate('Location'),
          () => _runTool(widget.onSendLocation!),
        ),
      if (widget.onRemoteAssist != null)
        (
          Icons.desktop_windows_outlined,
          translate('Remote Desktop'),
          () => _runTool(widget.onRemoteAssist!),
        ),
    ];
    // 微信风格：2 行网格（每行 4 个），窄屏/小屏也不会超出右侧边框。
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Wrap(
        spacing: 24,
        runSpacing: 14,
        children: <Widget>[
          for (final item in items) _moreItem(item.$1, item.$2, item.$3),
        ],
      ),
    );
  }

  Widget _moreItem(IconData icon, String label, VoidCallback onTap) {
    final dark = widget.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF2B2D32) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      dark ? const Color(0xFF3A3D43) : const Color(0xFFE2E2E2),
                  width: 0.5,
                ),
              ),
              child: Icon(
                icon,
                size: 26,
                color:
                    dark ? const Color(0xFFB8BBC2) : const Color(0xFF555555),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color:
                    dark ? const Color(0xFF999CA2) : const Color(0xFF777777),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final dark = widget.dark;
    final fieldBg = dark ? const Color(0xFF2B2D32) : Colors.white;
    final border = dark ? const Color(0xFF3A3D43) : const Color(0xFFE2E2E2);
    return Container(
      color: dark ? const Color(0xFF1F2125) : const Color(0xFFF7F7F7),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          VoiceMessageRecorderButton(
            chatModel: widget.chatModel,
            enabled: widget.enabled,
            onInteractionStart: closePanels,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 40, maxHeight: 92),
              decoration: BoxDecoration(
                color: fieldBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border, width: 0.5),
              ),
              child: TextField(
                controller: widget.chatModel.textController,
                focusNode: widget.chatModel.inputNode,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                onTap: _closePanelsOnInputTap,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color:
                      dark ? const Color(0xFFF2F2F2) : const Color(0xFF222222),
                  fontFamilyFallback: kChatEmojiFontFallback,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: translate('Write a message'),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: dark
                        ? const Color(0xFF999CA2)
                        : const Color(0xFF999999),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.chatModel.textController,
            builder: (context, value, _) {
              final hasText = widget.enabled && value.text.trim().isNotEmpty;
              if (hasText) {
                return GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 54,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kWeChatPrimaryColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      translate('Send'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _toolButton(
                    Icons.emoji_emotions_outlined,
                    _showEmojiPanel,
                    _toggleEmoji,
                  ),
                  _toolButton(
                    Icons.add_circle_outline,
                    _showMorePanel,
                    _toggleMore,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_showEmojiPanel) _buildEmojiPanel(),
        if (_showMorePanel) _buildMorePanel(),
        if (AiConfig.current.profiles.isNotEmpty)
          _AiModelSelector(
            dark: Theme.of(context).brightness == Brightness.dark,
            chatModel: widget.chatModel,
            onOpen: closePanels,
          ),
        _buildInputBar(),
      ],
    );
  }
}

class _DesktopChatComposer extends StatefulWidget {
  const _DesktopChatComposer({
    required this.chatModel,
    required this.enabled,
    required this.dark,
    this.onAttachFile,
    this.onRemoteAssist,
    this.onSendImage,
    this.onScreenshot,
    this.onPasteImage,
  });

  final ChatModel chatModel;
  final bool enabled;
  final bool dark;
  final VoidCallback? onAttachFile;
  final VoidCallback? onRemoteAssist;
  final VoidCallback? onSendImage;
  final VoidCallback? onScreenshot;
  final PasteImageCallback? onPasteImage;

  @override
  State<_DesktopChatComposer> createState() => _DesktopChatComposerState();
}

class _DesktopChatComposerState extends State<_DesktopChatComposer> {
  static const double _collapsedHeight = 132;
  static const double _expandedHeight = 260;

  bool _atOverlayVisible = false;
  List<MeetingMember> _atCandidates = [];
  int _atCursorPos = -1;
  final LayerLink _layerLink = LayerLink();
  final ScrollController _inputScrollController = ScrollController();
  bool _inputFocused = false;
  bool _showEmojiPicker = false;
  bool _inputExpanded = false;

  ChatModel get chatModel => widget.chatModel;
  bool get enabled => widget.enabled;
  bool get dark => widget.dark;
  VoidCallback? get onAttachFile => widget.onAttachFile;
  VoidCallback? get onRemoteAssist => widget.onRemoteAssist;
  VoidCallback? get onSendImage => widget.onSendImage;
  VoidCallback? get onScreenshot => widget.onScreenshot;
  PasteImageCallback? get onPasteImage => widget.onPasteImage;

  void _insertEmoji(String emoji) {
    final controller = chatModel.textController;
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  @override
  /// 截图时是否隐藏本窗口（剪刀右侧下拉箭头可切换，持久化存储）。
  bool _screenshotHideWindow = true;

  void initState() {
    super.initState();
    _screenshotHideWindow =
        bind.mainGetLocalOption(key: 'screenshot_hide_window') != '0';
    chatModel.textController.addListener(_onTextChanged);
    chatModel.inputNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    chatModel.textController.removeListener(_onTextChanged);
    chatModel.inputNode.removeListener(_onFocusChanged);
    _inputScrollController.dispose();
    super.dispose();
  }

  void _toggleInputExpanded() {
    setState(() {
      _inputExpanded = !_inputExpanded;
      _showEmojiPicker = false;
      _atOverlayVisible = false;
    });
    chatModel.inputNode.requestFocus();
  }

  void _closeTransientPanels() {
    if (!_showEmojiPicker && !_atOverlayVisible) return;
    setState(() {
      _showEmojiPicker = false;
      _atOverlayVisible = false;
    });
  }

  void _runToolAction(VoidCallback action) {
    _closeTransientPanels();
    action();
  }

  void _onFocusChanged() {
    setState(() => _inputFocused = chatModel.inputNode.hasFocus);
  }

  void _onTextChanged() {
    final text = chatModel.textController.text;
    final sel = chatModel.textController.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) {
      setState(() => _atOverlayVisible = false);
      return;
    }
    final cursor = sel.baseOffset;
    if (cursor <= 0 || text.isEmpty) {
      setState(() => _atOverlayVisible = false);
      return;
    }
    // Check if we just typed '@' or are inside an '@...' sequence
    final charBefore = text[cursor - 1];
    if (charBefore == '@') {
      _showAtPicker();
      return;
    }
    if (_atOverlayVisible) {
      // Check if we are still inside an '@...' sequence
      final before = text.substring(0, cursor);
      final atIdx = before.lastIndexOf('@');
      if (atIdx >= 0 && atIdx < cursor) {
        final afterAt = before.substring(atIdx + 1);
        // Allow alphanumeric, Chinese chars, no spaces
        if (afterAt.isNotEmpty && !afterAt.contains(' ')) {
          _filterCandidates(afterAt);
          return;
        }
      }
      setState(() => _atOverlayVisible = false);
    }
  }

  void _showAtPicker() {
    final peerId = chatModel.currentKey.peerId;
    if (!peerId.startsWith('meeting:')) return; // not a group chat
    final meetingId = peerId.substring('meeting:'.length);
    final group = MeetingGroupStore.find(meetingId);
    if (group == null || group.members == null || group.members!.isEmpty) {
      return;
    }
    setState(() {
      _atCandidates =
          group.members!.where((m) => m.peerId != chatModel.me.id).toList();
      _atOverlayVisible = true;
      _atCursorPos = chatModel.textController.selection.baseOffset;
    });
  }

  void _filterCandidates(String query) {
    final peerId = chatModel.currentKey.peerId;
    if (!peerId.startsWith('meeting:')) return;
    final meetingId = peerId.substring('meeting:'.length);
    final group = MeetingGroupStore.find(meetingId);
    if (group == null || group.members == null) return;
    final lower = query.toLowerCase();
    setState(() {
      _atCandidates = group.members!
          .where((m) =>
              m.peerId != chatModel.me.id &&
              (m.displayName.toLowerCase().contains(lower) ||
                  m.peerId.toLowerCase().contains(lower)))
          .toList();
    });
  }

  void _selectMember(MeetingMember member) {
    final text = chatModel.textController.text;
    final sel = chatModel.textController.selection;
    final cursor = sel.baseOffset;
    // Find the start of the @ sequence
    final before = text.substring(0, cursor);
    final atIdx = before.lastIndexOf('@');
    if (atIdx < 0) return;
    final newText =
        '${text.substring(0, atIdx)}@${member.displayName} ${text.substring(cursor)}';
    chatModel.textController.text = newText;
    chatModel.textController.selection = TextSelection.collapsed(
      offset: atIdx + member.displayName.length + 2, // @Name<space>
    );
    setState(() => _atOverlayVisible = false);
  }

  Widget _buildEmojiPanel() {
    final bg = dark ? const Color(0xFF1E2024) : const Color(0xFFF5F5F5);
    final border = dark ? const Color(0xFF3A3D43) : const Color(0xFFE2E2E2);
    return Container(
      height: 164,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border.all(color: border),
      ),
      child: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 40,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        ),
        itemCount: kDotChatEmojiList.length,
        itemBuilder: (_, i) => InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _insertEmoji(kDotChatEmojiList[i]),
          child: Center(
            child: Text(
              kDotChatEmojiList[i],
              style: const TextStyle(
                fontSize: 22,
                fontFamilyFallback: kChatEmojiFontFallback,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pasteClipboardText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text;
    if (pasted == null || pasted.isEmpty || !enabled) return;
    final controller = chatModel.textController;
    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, pasted),
      selection: TextSelection.collapsed(offset: start + pasted.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _handlePasteShortcut() async {
    final pastedImage = await onPasteImage?.call(false) ?? false;
    if (!pastedImage) await _pasteClipboardText();
  }

  KeyEventResult _handleComposerKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (enabled) unawaited(_handlePasteShortcut());
    return KeyEventResult.handled;
  }

  void _send() {
    final text = chatModel.textController.text.trim();
    if (!enabled || text.isEmpty) return;
    chatModel.sendText(text);
    chatModel.textController.clear();
    chatModel.inputNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('COMPOSER_DIAG build enabled=' +
        enabled.toString() +
        ' expanded=' +
        _inputExpanded.toString());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final pos = box.localToGlobal(Offset.zero);
        debugPrint('COMPOSER_POS w=' +
            box.size.width.toStringAsFixed(1) +
            ' h=' +
            box.size.height.toStringAsFixed(1) +
            ' x=' +
            pos.dx.toStringAsFixed(1) +
            ' y=' +
            pos.dy.toStringAsFixed(1));
      } else {
        debugPrint('COMPOSER_POS null box');
      }
    });
    final border = dark ? const Color(0xFF3A3D43) : const Color(0xFFE2E2E2);
    final focusedBorder = dark ? const Color(0xFF4CAF50) : kWeChatPrimaryColor;
    final foreground = dark ? const Color(0xFFF2F2F2) : const Color(0xFF222222);
    final muted = dark ? const Color(0xFF999CA2) : const Color(0xFF777777);
    final composerHeight = _inputExpanded ? _expandedHeight : _collapsedHeight;
    final composerIconButtonTheme = IconButtonThemeData(
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return const BorderSide(color: kWeChatPrimaryColor, width: 0.5);
          }
          return const BorderSide(color: Colors.transparent, width: 0.5);
        }),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
    final composer = IconButtonTheme(
      data: composerIconButtonTheme,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: composerHeight,
        margin: const EdgeInsets.fromLTRB(8, 2, 8, 8),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF25272C) : kWeChatCanvasColor,
          border: Border.all(
            color: _inputFocused ? focusedBorder : border,
            width: 0.25,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Focus(
                      onKeyEvent: _handleComposerKeyEvent,
                      child: Scrollbar(
                        controller: _inputScrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        interactive: true,
                        thickness: 6,
                        radius: const Radius.circular(3),
                        child: TextField(
                          controller: chatModel.textController,
                          focusNode: chatModel.inputNode,
                          scrollController: _inputScrollController,
                          enabled: enabled,
                          onTap: _closeTransientPanels,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            height: 1.45,
                            letterSpacing: 0,
                            fontFamilyFallback: kChatEmojiFontFallback,
                          ),
                          decoration: InputDecoration(
                            hintText: translate('Write a message'),
                            hoverColor: Colors.transparent,
                            hintStyle: TextStyle(
                              color: muted,
                              fontSize: 14,
                              height: 1.45,
                            ),
                            contentPadding:
                                const EdgeInsets.fromLTRB(14, 10, 52, 8),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 12,
                    child: Tooltip(
                      message:
                          translate(_inputExpanded ? 'Collapse' : 'Expand'),
                      child: IconButton(
                        onPressed: _toggleInputExpanded,
                        constraints: const BoxConstraints.tightFor(
                            width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        splashRadius: 17,
                        icon: Icon(
                          _inputExpanded
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          size: 21,
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 42,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 10, 5),
                child: Row(
                  children: <Widget>[
                    if (onScreenshot != null)
                      _ComposerToolButton(
                        // PC端截图按钮用剪刀图标（桌面输入栏专用）
                        icon: Icons.content_cut_rounded,
                        tooltip: translate('Screenshot'),
                        enabled: enabled,
                        onPressed: () => _runToolAction(onScreenshot!),
                      ),
                    if (onScreenshot != null)
                      // 剪刀右侧下拉箭头：选择截图时是否隐藏本窗口。
                      PopupMenuButton<bool>(
                        tooltip: translate('Screenshot options'),
                        enabled: enabled,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints.tightFor(width: 26, height: 42),
                        icon: Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.55),
                        ),
                        onSelected: (hide) {
                          _screenshotHideWindow = hide;
                          bind.mainSetLocalOption(
                            key: 'screenshot_hide_window',
                            value: hide ? '1' : '0',
                          );
                          showToast(hide
                              ? translate('Screenshot hides this window')
                              : translate('Screenshot keeps window visible'));
                        },
                        itemBuilder: (menuContext) => <PopupMenuEntry<bool>>[
                          CheckedPopupMenuItem<bool>(
                            value: true,
                            checked: _screenshotHideWindow,
                            child: Text(translate('Hide this window')),
                          ),
                          CheckedPopupMenuItem<bool>(
                            value: false,
                            checked: !_screenshotHideWindow,
                            child: Text(translate('Keep window visible')),
                          ),
                        ],
                      ),
                    if (onAttachFile != null)
                      _ComposerToolButton(
                        icon: Icons.folder_outlined,
                        tooltip: translate('File Transfer'),
                        enabled: enabled,
                        onPressed: () => _runToolAction(onAttachFile!),
                      ),
                    if (onSendImage != null)
                      _ComposerToolButton(
                        icon: Icons.image_outlined,
                        tooltip: translate('Send Image'),
                        enabled: enabled,
                        onPressed: () => _runToolAction(onSendImage!),
                      ),
                    if (onRemoteAssist != null)
                      _ComposerToolButton(
                        icon: Icons.desktop_windows_outlined,
                        tooltip: translate('Remote Desktop'),
                        enabled: enabled,
                        onPressed: () => _runToolAction(onRemoteAssist!),
                      ),
                    _ComposerToolButton(
                      icon: Icons.emoji_emotions_outlined,
                      tooltip: translate('Emoji'),
                      enabled: enabled,
                      onPressed: () => setState(() {
                        _showEmojiPicker = !_showEmojiPicker;
                        _atOverlayVisible = false;
                      }),
                    ),
                    VoiceMessageRecorderButton(
                      chatModel: chatModel,
                      enabled: enabled,
                      onInteractionStart: _closeTransientPanels,
                    ),
                    if (AiConfig.current.profiles.isNotEmpty)
                      _AiModelSelector(
                        dark: dark,
                        chatModel: chatModel,
                        onOpen: _closeTransientPanels,
                      ),
                    const Spacer(),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: chatModel.textController,
                      builder: (context, value, _) {
                        final canSend = enabled && value.text.trim().isNotEmpty;
                        return TextButton(
                          onPressed: canSend ? _send : null,
                          style: TextButton.styleFrom(
                            fixedSize: const Size(72, 32),
                            minimumSize: const Size(72, 32),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            backgroundColor: canSend
                                ? kWeChatPrimaryColor
                                : dark
                                    ? const Color(0xFF35383E)
                                    : const Color(0xFFF0F0F0),
                            foregroundColor: canSend
                                ? Colors.white
                                : dark
                                    ? const Color(0xFF777A80)
                                    : const Color(0xFFB5B5B5),
                            disabledForegroundColor: dark
                                ? const Color(0xFF777A80)
                                : const Color(0xFFB5B5B5),
                            elevation: canSend ? 1 : 0,
                            shadowColor: canSend
                                ? kWeChatPrimaryColor.withOpacity(0.4)
                                : Colors.transparent,
                          ),
                          child: Text(
                            translate('Send'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final withEmoji = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showEmojiPicker) _buildEmojiPanel(),
        composer,
      ],
    );
    if (!_atOverlayVisible) return withEmoji;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        withEmoji,
        if (_atOverlayVisible && _atCandidates.isNotEmpty)
          Positioned(
            bottom: composerHeight + 4,
            left: 16,
            right: 16,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              color: dark ? const Color(0xFF2B2D32) : Colors.white,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: _atCandidates.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 52,
                    color: (dark
                            ? const Color(0xFF3A3D43)
                            : const Color(0xFFEEEEEE))
                        .withOpacity(0.5),
                  ),
                  itemBuilder: (_, i) {
                    final m = _atCandidates[i];
                    return InkWell(
                      onTap: () => _selectMember(m),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: kWeChatPrimaryColor,
                              child: Text(
                                m.displayName.isNotEmpty
                                    ? m.displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              m.displayName,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ComposerToolButton extends StatelessWidget {
  const _ComposerToolButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        constraints: const BoxConstraints.tightFor(width: 40, height: 36),
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 22),
      ),
    );
  }
}

class _ChatBubbleTailPainter extends CustomPainter {
  const _ChatBubbleTailPainter({
    required this.color,
    required this.pointsRight,
  });

  final Color color;
  final bool pointsRight;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointsRight) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, size.height * 0.45)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(0, size.height * 0.45)
        ..lineTo(size.width, size.height)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ChatBubbleTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointsRight != pointsRight;
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(
              color: color.withOpacity(0.35),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AI model selector badge — shows current model below the chat input.
/// Tap to switch to another configured model.
class _AiModelSelector extends StatefulWidget {
  final bool dark;
  final ChatModel chatModel;
  final VoidCallback? onOpen;

  const _AiModelSelector({
    required this.dark,
    required this.chatModel,
    this.onOpen,
  });

  @override
  State<_AiModelSelector> createState() => _AiModelSelectorState();
}

class _AiModelSelectorState extends State<_AiModelSelector> {
  bool _updating = false;

  ChatModel get chatModel => widget.chatModel;
  bool get dark => widget.dark;

  @override
  void initState() {
    super.initState();
    AiConfig.onChange = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    AiConfig.clearOnChange();
    super.dispose();
  }

  void _showModelPicker() {
    final profiles = AiConfig.current.profiles
        .asMap()
        .entries
        .where(
          (entry) =>
              entry.value.enabled &&
              entry.value.profileType == AiProfileType.text,
        )
        .toList(growable: false);
    if (profiles.length <= 1) return;
    widget.onOpen?.call();

    final active = AiConfig.current.getProfileByType(AiProfileType.text);
    final activeIdx = profiles.indexWhere((entry) => entry.value == active);
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy - profiles.length * 44.0 - 16,
        position.dx + 240,
        position.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 4,
      items: List.generate(profiles.length, (i) {
        final entry = profiles[i];
        final p = entry.value;
        final isActive = i == activeIdx;
        return PopupMenuItem<String>(
          enabled: !isActive && !_updating,
          height: 44,
          child: Row(
            children: [
              Icon(
                isActive ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: isActive ? kWeChatPrimaryColor : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.displayLabel,
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      p.model,
                      style: TextStyle(
                        fontSize: 11,
                        color: dark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kWeChatPrimaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    translate('Active'),
                    style: const TextStyle(
                      fontSize: 10,
                      color: kWeChatPrimaryColor,
                    ),
                  ),
                ),
            ],
          ),
          onTap: () async {
            setState(() => _updating = true);
            await AiConfig.setActiveProfile(entry.key);
            if (mounted) {
              setState(() => _updating = false);
            }
          },
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = AiConfig.current.profiles
        .where(
          (profile) =>
              profile.enabled && profile.profileType == AiProfileType.text,
        )
        .toList(growable: false);
    if (profiles.isEmpty) return const SizedBox.shrink();

    final active = AiConfig.current.getProfileByType(AiProfileType.text);
    final multiple = profiles.length > 1;
    final foreground = dark ? const Color(0xFF888B91) : const Color(0xFF888888);
    final remaining = AiConfig.current.remainingFor(active);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: GestureDetector(
        onTap: multiple ? _showModelPicker : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 13,
              color: active.enabled
                  ? kWeChatPrimaryColor
                  : foreground.withOpacity(0.5),
            ),
            const SizedBox(width: 4),
            Text(
              active.displayLabel,
              style: TextStyle(
                fontSize: 12,
                color: foreground,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (remaining >= 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: remaining == 0
                      ? Colors.red.withOpacity(0.15)
                      : kWeChatPrimaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  remaining == 0 ? '已用完' : '剩余 $remaining',
                  style: TextStyle(
                    fontSize: 10,
                    color: remaining == 0 ? Colors.red : kWeChatPrimaryColor,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 3),
            IconButton(
              icon: Icon(
                Icons.settings_outlined,
                size: 15,
                color: foreground,
              ),
              constraints: const BoxConstraints.tightFor(
                width: 20,
                height: 20,
              ),
              padding: EdgeInsets.zero,
              splashRadius: 10,
              tooltip: translate('AI Settings'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiConfigPage()),
                );
              },
            ),
            if (multiple) ...[
              const SizedBox(width: 3),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: foreground,
              ),
            ],
            if (_updating) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: foreground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
