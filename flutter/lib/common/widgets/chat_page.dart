import 'dart:io';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../mobile/pages/home_page.dart';
import '../../models/meeting_group_model.dart';
import 'package:luoda_flutter/common/direct_viewer_invite.dart';
import '../wechat_ui_tokens.dart';
import 'file_viewer.dart';
import 'rich_text_builder.dart';
import 'voice_message_controls.dart';
import '../../models/ai_config_model.dart';

const _reactionEmojis = [
  '👍', '❤️', '😂', '😮', '😢', '🙏',
  '👏', '🎉', '🔥', '💯', '🤔', '👀',
];

enum ChatPageType {
  mobileMain,
  desktopCM,
  desktopHome,
}

class ChatPage extends StatelessWidget implements PageShape {
  late final ChatModel chatModel;
  final ChatPageType? type;
  final VoidCallback? onAttachFile;
  final VoidCallback? onRemoteAssist;
  final VoidCallback? onPasteImage;

  ChatPage({
    ChatModel? chatModel,
    this.type,
    this.onAttachFile,
    this.onRemoteAssist,
    this.onPasteImage,
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

  /// WeChat PC style floating context menu — positioned near the message,
  /// with rounded corners, icon + text items, and clean dividers.
  /// Replaces the old bottom sheet that looked nothing like WeChat.
  Future<String?> _showWeChatContextMenu(
    BuildContext context,
    ChatMessage message, {
    required Offset position,
  }) async {
    final properties = message.customProperties;
    final id = (properties?['ldesk_id'] ?? '').toString();
    final disposition =
        (properties?['ldesk_disposition'] ?? 'active').toString();
    final delivery = (properties?['ldesk_delivery'] ?? '').toString();
    final isOwnMessage = message.user.id == chatModel.me.id;
    if (id.isEmpty) return null;
    if (isOwnMessage && disposition != 'active') return null;
    if (!isOwnMessage && disposition != 'active') return null;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPos = overlay.globalToLocal(position);
    final anchor = RelativeRect.fromRect(
      localPos & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    // Build menu items — keep it clean like WeChat PC
    final items = <PopupMenuEntry<String>>[];
    void addItem(String value, IconData icon, String label, {Color? color}) {
      items.add(PopupMenuItem<String>(
        value: value,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 13, color: color)),
          ],
        ),
      ));
    }

    addItem('copy', Icons.copy_rounded, translate('Copy'));
    addItem('reply', Icons.reply_rounded, translate('Reply'));
    items.add(const PopupMenuDivider(height: 1));

    // Reactions inline — compact row of emojis
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

    addItem('select', Icons.checklist_rounded, translate('Select'));
    addItem('info', Icons.info_outline_rounded, translate('Info'));

    // AI Translate — only if configured and message is text
    if (AiConfig.current.enabled &&
        (message.text?.isNotEmpty == true ||
            (properties?['ldesk_kind'] == 'text'))) {
      items.add(const PopupMenuDivider(height: 1));
      addItem('translate', Icons.translate_rounded, translate('Translate'));
    }

    // Send to email — only if email is configured
    if (AiConfig.current.email.isNotEmpty &&
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(AiConfig.current.email)) {
      items.add(const PopupMenuDivider(height: 1));
      addItem('send-email', Icons.email_outlined, translate('Send to email'));
      addItem('send-email-batch', Icons.archive_outlined, translate('Export 20 recent (ZIP)'));
    }

    if (isOwnMessage) {
      items.add(const PopupMenuDivider(height: 1));
      if (properties?['ldesk_kind'] == 'text') {
        addItem('edit', Icons.edit_rounded, translate('Edit'));
      }
      addItem('recall', Icons.undo_rounded, translate('Recall'));
      addItem('destroy', Icons.delete_forever_outlined,
          translate('Destroy'),
          color: Colors.redAccent);
      addItem('forward', Icons.forward_rounded, translate('Forward'));
      if (delivery == 'failed') {
        addItem('retry', Icons.refresh_rounded, translate('Retry send'));
      }
      items.add(const PopupMenuDivider(height: 1));
      addItem('expire-60', Icons.timer_outlined,
          translate('Self-destruct in 1 minute'));
      addItem('expire-300', Icons.timer_outlined,
          translate('Self-destruct in 5 minutes'));
      addItem('expire-3600', Icons.timer_outlined,
          translate('Self-destruct in 1 hour'));
    }

    items.add(const PopupMenuDivider(height: 1));
    addItem('delete', Icons.delete_outline_rounded,
        translate('Delete'),
        color: Colors.redAccent);

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
            style: const TextStyle(fontSize: 13),
            textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              minimumSize: const Size(80, 36),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(translate('Cancel'),
                style: const TextStyle(fontSize: 13)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
          actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          title: Text(translate('Edit message'),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: translate('Edit your message...'),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
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
              child: Text(translate('Save'),
                  style: const TextStyle(fontSize: 13)),
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
      // Show a loading indicator in a snackbar
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(translate('Translating...')),
            ],
          ),
          duration: const Duration(seconds: 30),
        ),
      );
      final translated = await AiService.translate(text);
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      if (translated != null) {
        // Show translated text in a dialog
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
            actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            title: Text(translate('Translation'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            content: SelectableText(translated,
                style: const TextStyle(fontSize: 14, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  minimumSize: const Size(80, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(translate('Close'),
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(translate('Translation failed'))),
          );
        }
      }
      return;
    }
    if (action == 'send-email') {
      final text = message.text ?? '';
      final fileName = (message.customProperties?['ldesk_file_name'] ?? '').toString();
      final content = fileName.isNotEmpty ? '$fileName\n\n$text' : text;
      if (content.trim().isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(translate('No content to send'))),
          );
        }
        return;
      }
      // Use mailto: to open system email client
      final email = AiConfig.current.email;
      final subject = Uri.encodeComponent(
          '${translate("Chat message")} - ${message.user.firstName ?? ''}');
      final body = Uri.encodeComponent(content);
      final uri = Uri.parse('mailto:$email?subject=$subject&body=$body');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(translate('Unable to open email client'))),
          );
        }
      }
      return;
    }
    if (action == 'send-email-batch') {
      final allMessages = chatModel.messages[chatModel.currentKey]?.chatMessages ?? [];
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
        clickedIdx = allMessages.indexWhere((m) =>
            (m.customProperties?['ldesk_id'] ?? '').toString() == msgId);
        if (clickedIdx < 0) clickedIdx = 0;
      }
      // Collect 20 messages starting from clicked, going older
      final endIdx = (clickedIdx + 20 > allMessages.length)
          ? allMessages.length
          : clickedIdx + 20;
      final selected = allMessages.sublist(clickedIdx, endIdx);
      final reversed = selected.reversed.toList();

      // Build a temp directory with export content
      try {
        final dir = await Directory.systemTemp.createTemp('luoda_chat_export_');
        final chatFile = File('${dir.path}/chat_log.txt');
        final chatBuf = StringBuffer();
        for (final m in reversed) {
          final who = m.user.firstName ?? m.user.id;
          final time = m.createdAt.toLocal().toString().substring(0, 19);
          final text = m.text ?? '';
          final fname = (m.customProperties?['ldesk_file_name'] ?? '').toString();
          final localPath = (m.customProperties?['ldesk_local_path'] ?? '').toString();
          chatBuf.writeln('[$time] $who: ${fname.isNotEmpty ? "[${translate("File")}] $fname" : text}');
          if (text.isNotEmpty && fname.isNotEmpty) chatBuf.writeln('  $text');
          chatBuf.writeln('');
          // Copy attachment file if available (images, docs)
          if (localPath.isNotEmpty) {
            final src = File(localPath);
            if (await src.exists()) {
              try {
                await src.copy('${dir.path}/$fname');
              } catch (_) {}
            }
          }
        }
        await chatFile.writeAsString(chatBuf.toString());

        // Create ZIP via system command
        final zipPath = '${dir.path}.zip';
        if (isWindows) {
          await Process.run('powershell', [
            '-NoProfile', '-Command',
            'Compress-Archive', '-Path', dir.path, '-DestinationPath', zipPath, '-Force',
          ]);
        } else {
          await Process.run('zip', ['-rj', zipPath, dir.path]);
        }

        // Open the folder containing the ZIP
        final zipFile = File(zipPath);
        if (await zipFile.exists()) {
          if (isWindows) {
            await Process.run('explorer', ['/select,${zipPath}']);
          } else if (isMacOS) {
            await Process.run('open', ['-R', zipPath]);
          } else {
            await Process.run('xdg-open', [dir.parent.path]);
          }
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text('${translate("Exported")}: $zipPath')),
            );
          }
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
    if (action == 'forward') {
      await _showForwardPicker(context, message);
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

  Future<void> _showForwardPicker(
    BuildContext context,
    ChatMessage message,
  ) async {
    final peers = gFFI.recentPeersModel.peers.toList();
    if (peers.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(translate('No contacts to forward to'))),
        );
      }
      return;
    }
    final currentPeerId = chatModel.currentKey.peerId;
    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(translate('Forward to')),
        children: <Widget>[
          for (final peer in peers)
            if (peer.id != currentPeerId)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, peer.id),
                child: ListTile(
                  leading: CircleAvatar(child: Text(peer.id.isNotEmpty ? peer.id[0].toUpperCase() : '?')),
                  title: Text(peer.id),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    final forwardText = message.text.trim();
    if (forwardText.isEmpty) return;
    // Save current key, switch to target, send, switch back
    final savedKey = chatModel.currentKey;
    chatModel.changeCurrentKey(MessageKey(target, ChatModel.clientModeID));
    chatModel.sendText(forwardText);
    chatModel.changeCurrentKey(savedKey);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(translate('Forwarded'))),
    );
  }

  /// Open file preview in an independent OS window.
  /// All file types (image/audio/text/other) are handled by FilePreviewPage.
  /// Legacy _showImagePreview removed — use showFileViewer() instead.

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
          _infoRow(ctx, translate('Type'), kind == 'voice'
              ? translate('Voice')
              : kind == 'file'
                  ? translate('File')
                  : translate('Text')),
          _infoRow(ctx, translate('Time'),
              '${message.createdAt.month}/${message.createdAt.day} '
              '${message.createdAt.hour.toString().padLeft(2, '0')}:'
              '${message.createdAt.minute.toString().padLeft(2, '0')}'),
          if (isEdited)
            _infoRow(
                ctx, translate('Edited'), editedAt?.toString() ?? ''),
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
                ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp']
                    .contains(record.fileName.split('.').last.toLowerCase());
            return GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                showFileViewer(
                  context,
                  fileName: record.fileName,
                  fileSize: record.fileSize,
                  localPath: record.localPath,
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF2B2D32)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(record.localPath),
                          fit: BoxFit.cover,
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
    final ext = record.fileName.contains('.')
        ? record.fileName.split('.').last.toLowerCase()
        : '';
    const img = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'};
    final icon = img.contains(ext) ? Icons.image_outlined
        : ['mp3','wav','ogg','flac','m4a'].contains(ext) ? Icons.audio_file_outlined
        : ['mp4','avi','mov','mkv'].contains(ext) ? Icons.video_file_outlined
        : ext == 'pdf' ? Icons.picture_as_pdf_outlined
        : ['zip','rar','7z','tar','gz'].contains(ext) ? Icons.folder_zip_outlined
        : ['doc','docx'].contains(ext) ? Icons.description_outlined
        : ['xls','xlsx'].contains(ext) ? Icons.table_chart_outlined
        : Icons.insert_drive_file_outlined;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
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
        SnackBar(content: Text(translate(
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
        color: dark ? const Color(0xFF1F2228) : const Color(0xFFF8F8F8),
        border: Border(top: BorderSide(
          color: dark ? const Color(0xFF3A3D43) : const Color(0xFFDDDDDD),
        )),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6, offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(top: false, child: Row(children: [
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
        FilledButton.tonalIcon(
          onPressed: chatModel.selectedMessageIds.isEmpty ? null : () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(translate('Delete messages')),
                content: Text('${translate('Delete')} ${chatModel.selectedMessageIds.length} ${translate('messages')}?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(translate('Cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error,
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
                SnackBar(content: Text(translate('Failed to delete messages'))),
              );
            }
          },
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(translate('Delete')),
        ),
      ])),
    );
  }

  /// Small icon button used in the chat toolbar.
  Widget _toolbarIconButton(
    BuildContext context, bool dark, {
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
              color: dark
                  ? const Color(0x442B2D32)
                  : const Color(0x44FFFFFF),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: chatModel,
      child: Container(
        color: type == ChatPageType.desktopHome
            ? Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1C1E23)
                : kWeChatCanvasColor
            : type == ChatPageType.mobileMain
                ? Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1F2228)
                    : const Color(0xFFEDEDED)
                : Theme.of(context).scaffoldBackgroundColor,
        child: Consumer<ChatModel>(
          builder: (context, chatModel, child) {
            final currentKey = chatModel.currentKey;
            final isDesktopHome = type == ChatPageType.desktopHome;
            final dark = Theme.of(context).brightness == Brightness.dark;
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

            bool hasDelivery(ChatMessage message) {
              final d = (message.customProperties?['ldesk_delivery'] ?? '').toString();
              return d == 'queued' || d == 'sent' || d == 'delivered' || d == 'failed';
            }

            String aiReplyLabel(ChatMessage message) {
              final aiReply = message.customProperties?['ldesk_ai_reply'] == 'true';
              final isLoading = message.customProperties?['ldesk_ai_loading'] == 'true';
              if (isLoading) return '${translate("AI thinking")}...';
              if (aiReply) return translate('AI auto-reply');
              return '';
            }

            /// Connection source label: "via IP" for IP-originated messages.
            String _connSourceLabel(ChatMessage message) {
              final source = message.customProperties?['ldesk_conn_source']?.toString();
              if (source == 'ip') return 'via IP';
              return '';
            }

            Widget deliveryWidget(ChatMessage message) {
              final d = (message.customProperties?['ldesk_delivery'] ?? '').toString();
              if (d.isEmpty) return const SizedBox.shrink();
              IconData icon;
              Color? color;
              String label;
              switch (d) {
                case 'queued':
                  icon = Icons.access_time_rounded;
                  label = translate('Sending...');
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
                  Icon(icon, size: 13, color: color ?? Colors.grey),
                  const SizedBox(width: 3),
                  Text(label, style: TextStyle(fontSize: 11, color: color ?? Colors.grey)),
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

            /// Returns a short label for the icon overlay (e.g. "PDF", "DOC").
            String fileExtLabel(String fileName) {
              final ext = fileName.contains('.')
                  ? fileName.split('.').last.toLowerCase()
                  : '';
              if (ext.isEmpty) return '';
              if (ext.length <= 4) return ext.toUpperCase();
              return ext.substring(0, 4).toUpperCase();
            }

            IconData fileTypeIcon(String fileName) {
              final ext = fileName.contains('.')
                  ? fileName.split('.').last.toLowerCase()
                  : '';
              switch (ext) {
                case 'jpg':
                case 'jpeg':
                case 'png':
                case 'gif':
                case 'bmp':
                case 'webp':
                case 'svg':
                  return Icons.image_outlined;
                case 'mp4':
                case 'avi':
                case 'mkv':
                case 'mov':
                case 'wmv':
                case 'flv':
                  return Icons.movie_outlined;
                case 'mp3':
                case 'wav':
                case 'flac':
                case 'aac':
                case 'ogg':
                case 'wma':
                  return Icons.audiotrack_outlined;
                case 'pdf':
                  return Icons.picture_as_pdf_outlined;
                case 'doc':
                case 'docx':
                  return Icons.description_outlined;
                case 'xls':
                case 'xlsx':
                case 'csv':
                  return Icons.table_chart_outlined;
                case 'ppt':
                case 'pptx':
                  return Icons.slideshow_outlined;
                case 'zip':
                case 'rar':
                case '7z':
                case 'tar':
                case 'gz':
                  return Icons.folder_zip_outlined;
                case 'exe':
                case 'msi':
                case 'apk':
                case 'dmg':
                  return Icons.android_outlined;
                case 'txt':
                case 'md':
                case 'log':
                  return Icons.article_outlined;
                case 'json':
                case 'xml':
                case 'yaml':
                case 'yml':
                case 'toml':
                  return Icons.code_outlined;
                default:
                  return Icons.insert_drive_file_outlined;
              }
            }

            Color fileTypeColor(String fileName, double opacity) {
              final ext = fileName.contains('.')
                  ? fileName.split('.').last.toLowerCase()
                  : '';
              switch (ext) {
                case 'jpg':
                case 'jpeg':
                case 'png':
                case 'gif':
                case 'bmp':
                case 'webp':
                case 'svg':
                  return Color(0xFF4CAF50).withOpacity(opacity);
                case 'mp4':
                case 'avi':
                case 'mkv':
                case 'mov':
                  return Color(0xFFE91E63).withOpacity(opacity);
                case 'mp3':
                case 'wav':
                case 'flac':
                case 'aac':
                  return Color(0xFF9C27B0).withOpacity(opacity);
                case 'pdf':
                  return Color(0xFFF44336).withOpacity(opacity);
                case 'doc':
                case 'docx':
                  return Color(0xFF2196F3).withOpacity(opacity);
                case 'xls':
                case 'xlsx':
                case 'csv':
                  return Color(0xFF4CAF50).withOpacity(opacity);
                case 'ppt':
                case 'pptx':
                  return Color(0xFFFF9800).withOpacity(opacity);
                case 'zip':
                case 'rar':
                case '7z':
                  return Color(0xFFFFC107).withOpacity(opacity);
                default:
                  return Color(0xFF607D8B).withOpacity(opacity);
              }
            }

            Widget _buildInviteCard(BuildContext context, String link, Color foreground) {
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
                      color: dark ? const Color(0xFF2A3A2A) : const Color(0xFFEDF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: dark ? const Color(0xFF3A6A3A) : const Color(0xFFB8E8B8),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(Icons.groups_rounded, size: 18,
                                color: dark ? const Color(0xFF7AE87A) : const Color(0xFF1A8E1A)),
                            const SizedBox(width: 8),
                            Text(
                              translate('Meeting Invitation'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: dark ? Colors.white : const Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          translate('Join meeting group to watch and chat'),
                          style: TextStyle(fontSize: 11, color: dark ? Colors.white70 : const Color(0xFF666666)),
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
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
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
                              color: dark ? Colors.white : const Color(0xFF1A1A1A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        translate('Click to join and watch the remote session'),
                        style: TextStyle(
                          fontSize: 11,
                          color: dark
                              ? Colors.white70
                              : const Color(0xFF666666),
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
              final messageId = (properties?['ldesk_id'] ?? '').toString();
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
              final replyToText =
                  (properties?['ldesk_reply_to_text'] ?? '').toString();
              final reactions = properties?['ldesk_reactions'] as Map<String, dynamic>?;
              final isEdited = properties?['ldesk_is_edited'] == true;
              return Column(
                crossAxisAlignment: isOwnMessage
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: <Widget>[
                  // Quote reply indicator
                  if (replyToText.isNotEmpty)
                    Container(
                      constraints: BoxConstraints(
                          maxWidth: isDesktopHome ? 400 : 300),
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: isOwnMessage
                            ? Colors.black.withOpacity(0.12)
                            : Colors.black.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(6),
                        border: Border(
                          left: BorderSide(
                            color: isOwnMessage
                                ? const Color(0xFF7BDB8A)
                                : kWeChatPrimaryColor,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        replyToText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground.withOpacity(0.65),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                  if (isVoice && messageId.isNotEmpty)
                    VoiceMessageBubble(
                      chatModel: chatModel,
                      messageId: messageId,
                      durationMs: voiceDurationMs,
                    )
                  else if (isFile && fileName.isNotEmpty)
                    InkWell(
                      onTap: () {
                        final ext = fileName.contains('.')
                            ? fileName.split('.').last.toLowerCase()
                            : '';
                        const imageExts = {
                          'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'
                        };
                        if (imageExts.contains(ext) && localPath.isNotEmpty) {
                          showFileViewer(
                            context,
                            fileName: fileName,
                            fileSize: fileSize,
                            localPath: localPath,
                          );
                        } else {
                          showFileViewer(
                            context,
                            fileName: fileName,
                            fileSize: fileSize,
                            localPath: localPath,
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: fileTypeColor(
                                  fileName,
                                  dark ? 0.22 : 0.14,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (fileTypeIcon(fileName) ==
                                          Icons.image_outlined &&
                                      localPath.isNotEmpty)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        File(localPath),
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else ...[
                                    Icon(
                                      fileTypeIcon(fileName),
                                      size: 26,
                                      color: fileTypeColor(fileName, 0.72),
                                    ),
                                    Positioned(
                                      bottom: 5,
                                      child: Text(
                                        fileExtLabel(fileName),
                                        style: TextStyle(
                                          color: fileTypeColor(
                                            fileName,
                                            dark ? 0.95 : 0.85,
                                          ),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                  const SizedBox(height: 2),
                                  Text(
                                    fileSizeLabel(fileSize),
                                    style: TextStyle(
                                      color: foreground.withOpacity(0.56),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (message.text.trim().startsWith('luoda://join/') ||
                      message.text.trim().startsWith('luoda://meeting/'))
                    _buildInviteCard(context, message.text.trim(), foreground)
                  else
                    _buildRichText(message.text, foreground, isDesktopHome),
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
                            onTap: () => chatModel.toggleReaction(message, emoji),
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
                            color: foreground.withOpacity(0.52),
                            fontSize: 11,
                          ),
                        ),
                        if (isOwnMessage &&
                            hasDelivery(message)) ...<Widget>[
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
              double maxBubbleWidth,
            ) {
              final isOwnMessage = message.user.id == chatModel.me.id;
              final isAiReply = !isOwnMessage &&
                  (message.customProperties?['ldesk_ai_reply'] == 'true' ||
                   message.customProperties?['ldesk_ai_loading'] == 'true');
              final bubbleColor = isOwnMessage
                  ? dark
                      ? const Color(0xFF3B7F55)
                      : kWeChatOutgoingBubbleColor
                  : dark
                      ? const Color(0xFF2B2D32)
                      : kWeChatIncomingBubbleColor;
              final name = (message.user.firstName ?? '').trim();
              final content = messageBody(
                message,
                isOwnMessage: isOwnMessage,
                includeMetadata: false,
              );
              final bubble = isAiReply
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
                    constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(5),
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
                child: Column(
                  crossAxisAlignment: isOwnMessage
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: <Widget>[
                    if (!isOwnMessage && name.isNotEmpty) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 5),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: dark
                                ? const Color(0xFFA8AAAE)
                                : const Color(0xFF888888),
                            fontSize: isDesktopHome ? 12 : 13,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                    bubble,
                    if (isAiReply && aiReplyLabel(message).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 2),
                        child: Text(
                          aiReplyLabel(message),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: dark ? const Color(0xFF999CA2) : const Color(0xFF999999),
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
                            color: dark ? const Color(0xFF999CA2) : const Color(0xFF999999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasDelivery(message)) deliveryWidget(message),
                              if (hasDelivery(message) && (selfDestructLabel(message).isNotEmpty || aiReplyLabel(message).isNotEmpty))
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Text('·'),
                                ),
                              if (selfDestructLabel(message).isNotEmpty)
                                Text(selfDestructLabel(message)),
                              if (selfDestructLabel(message).isNotEmpty && aiReplyLabel(message).isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Text('·'),
                                ),
                              if (aiReplyLabel(message).isNotEmpty)
                                Text(aiReplyLabel(message),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: kWeChatPrimaryColor,
                                      fontWeight: FontWeight.w500,
                                    )),
                              // Connection source badge (IP/ID)
                              if (_connSourceLabel(message).isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(_connSourceLabel(message),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: dark ? const Color(0xFF777A80) : const Color(0xFFAAAAAA),
                                      )),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
              final avatar = messageAvatar(message.user, null, null);
              final canManage = isOwnMessage &&
                  message.customProperties?['ldesk_disposition'] == 'active';
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
                      color: isSelected
                          ? kWeChatPrimaryColor
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? kWeChatPrimaryColor
                            : (dark ? const Color(0xFF555A62) : const Color(0xFFCCCCCC)),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                );
              }
              final actionButton = canManage && !inMultiSelect
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Left-click recall button
                        IconButton(
                          onPressed: () async {
                            final changed = await chatModel.recallMessage(message);
                            if (context.mounted && changed) {
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                SnackBar(
                                    content: Text(translate('Message recalled'))),
                              );
                            }
                          },
                          tooltip: translate('Recall'),
                          visualDensity: VisualDensity.compact,
                          constraints:
                              const BoxConstraints.tightFor(width: 34, height: 34),
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            backgroundColor: dark
                                ? const Color(0x33FF6B6B)
                                : const Color(0x1AE5484D),
                          ),
                          icon: Icon(
                            Icons.undo_rounded,
                            size: 18,
                            color: dark
                                ? const Color(0xFFFF8A8A)
                                : const Color(0xFFE5484D),
                          ),
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          onPressed: () async {
                            final action = await _showWeChatContextMenu(
                              context, message,
                              position: Offset.zero,
                            );
                            if (context.mounted) {
                              await _handleWeChatContextAction(
                                  context, action, message);
                            }
                          },
                          tooltip: translate('Message actions'),
                          visualDensity: VisualDensity.compact,
                          constraints:
                              const BoxConstraints.tightFor(width: 30, height: 30),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            size: 18,
                            color: dark
                                ? const Color(0xFF999CA2)
                                : const Color(0xFF7B7B7B),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox(width: 30, height: 30);
              return Padding(
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
                          const SizedBox(width: 4),
                          actionButton,
                          const SizedBox(width: 4),
                          const SizedBox(width: 11),
                          avatar,
                        ]
                      : <Widget>[
                          if (inMultiSelect) multiSelectCheckbox,
                          avatar,
                          const SizedBox(width: 11),
                          messageColumn,
                        ],
                ),
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
                    messages: (() {
                      final allMessages = chatModel
                              .messages[chatModel.currentKey]?.chatMessages ??
                          <ChatMessage>[];
                      final searchTextLower =
                          chatModel.chatSearchText.trim().toLowerCase();
                      return searchTextLower.isEmpty
                          ? allMessages
                          : allMessages.where((m) {
                              return m.text
                                  .toLowerCase()
                                  .contains(searchTextLower);
                            }).toList();
                    })(),
                    readOnly: isDesktopHome || readOnly,
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
                        final yesterday = today.subtract(const Duration(days: 1));
                        final msgDate = DateTime(date.year, date.month, date.day);
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
                          label =
                              '${date.month}/${date.day} '
                              '${date.hour.toString().padLeft(2, '0')}:'
                              '${date.minute.toString().padLeft(2, '0')}';
                        } else {
                          label =
                              '${date.year}/${date.month}/${date.day} '
                              '${date.hour.toString().padLeft(2, '0')}:'
                              '${date.minute.toString().padLeft(2, '0')}';
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: dark
                                  ? const Color(0xFF999CA2)
                                  : const Color(0xFF999999),
                              fontSize: 12,
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
                        final action = await _showWeChatContextMenu(
                          context, message,
                          position: Offset.zero,
                        );
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
                                    ? const Color(0xFF3B7F55)
                                    : const Color(0xFF95EC69)
                                : dark
                                    ? const Color(0xFF2B2D32)
                                    : Colors.white
                            : isOwnMessage
                                ? dark
                                    ? const Color(0xFF3B7F55)
                                    : const Color(0xFF95EC69)
                                : dark
                                    ? const Color(0xFF2B2D32)
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
                  final messageList = SelectionArea(child: chat);
                  // Typing indicator — shared between desktop and mobile
                  final peerId = chatModel.currentKey.peerId;
                  Widget typingBar = const SizedBox.shrink();
                  if (peerId.isNotEmpty && chatModel.isPeerTyping(peerId)) {
                    typingBar = Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                dark ? const Color(0xFF999CA2) : const Color(0xFF999999),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            translate('Typing...'),
                            style: TextStyle(
                              fontSize: 12,
                              color: dark ? const Color(0xFF999CA2) : const Color(0xFF999999),
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
                    final replyUser =
                        replyMsg.user.id == chatModel.me.id
                            ? translate('Me')
                            : (replyMsg.user.firstName ??
                                replyMsg.user.id);
                    replyBar = Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF1F2228)
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
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
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
                            icon: const Icon(Icons.close_rounded,
                                size: 18),
                            constraints: const BoxConstraints
                                .tightFor(width: 32, height: 32),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    );
                  }
                  // Reconnect banner
                  Widget reconnectBar = const SizedBox.shrink();
                  if (chatModel.isReconnecting) {
                    reconnectBar = Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 14),
                      color: dark
                          ? const Color(0xFF3A3A1A)
                          : const Color(0xFFFFF9E6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                dark ? const Color(0xFFFFD54F)
                                    : const Color(0xFFF9A825),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            translate('Reconnecting...'),
                            style: TextStyle(
                              fontSize: 13,
                              color: dark
                                  ? const Color(0xFFFFD54F)
                                  : const Color(0xFFF9A825),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  // "Load older messages" banner — shown at the top when
                  // the conversation has more history beyond the initial load.
                  Widget loadOlderBar = const SizedBox.shrink();
                  if (chatModel.hasOlderMessages(chatModel.currentKey) &&
                      chatModel.messages[chatModel.currentKey]
                              ?.chatMessages.isNotEmpty ==
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
                        reconnectBar,
                        loadOlderBar,
                        Expanded(child: messageList),
                        replyBar,
                        typingBar,
                      ],
                    );
                  }
                  return Column(
                    children: <Widget>[
                      reconnectBar,
                      loadOlderBar,
                      Expanded(child: messageList),
                      replyBar,
                      typingBar,
                      _DesktopChatComposer(
                        chatModel: chatModel,
                        enabled: !readOnly,
                        dark: dark,
                        onAttachFile: onAttachFile,
                        onRemoteAssist: onRemoteAssist,
                        onPasteImage: onPasteImage,
                      ),
                      if (AiConfig.current.profiles.isNotEmpty)
                        _AiModelSelector(
                          dark: dark,
                          chatModel: chatModel,
                        ),
                    ],
                  );
                }),
                // Toolbar buttons (top-right corner)
                if (isDesktopHome &&
                    chatModel.currentKey.peerId.isNotEmpty)
                  Positioned(
                    top: 8, right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _toolbarIconButton(
                          context, dark,
                          icon: Icons.perm_media_outlined,
                          tooltip: translate('Shared media'),
                          onTap: () => _showMediaGallery(context),
                        ),
                        const SizedBox(width: 4),
                        _toolbarIconButton(
                          context, dark,
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
                    bottom: 0, left: 0, right: 0,
                    child: multiSelectBottomBar(context, dark),
                  ),
                if (chatModel.chatSearchVisible)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: dark ? const Color(0xF22B2D32) : const Color(0xF2FFFFFF),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              autofocus: true,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: translate('Search messages...'),
                                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                suffixIcon: chatModel.chatSearchText.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 18),
                                        onPressed: () => chatModel.updateChatSearch(''),
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8,
                                ),
                              ),
                              onChanged: chatModel.updateChatSearch,
                              controller: chatModel.chatSearchController,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: translate('Close search'),
                            onPressed: () => chatModel.toggleChatSearch(),
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
}

class _DesktopChatComposer extends StatefulWidget {
  const _DesktopChatComposer({
    required this.chatModel,
    required this.enabled,
    required this.dark,
    this.onAttachFile,
    this.onRemoteAssist,
    this.onPasteImage,
  });

  final ChatModel chatModel;
  final bool enabled;
  final bool dark;
  final VoidCallback? onAttachFile;
  final VoidCallback? onRemoteAssist;
  final VoidCallback? onPasteImage;

  @override
  State<_DesktopChatComposer> createState() => _DesktopChatComposerState();
}

class _DesktopChatComposerState extends State<_DesktopChatComposer> {
  bool _atOverlayVisible = false;
  List<MeetingMember> _atCandidates = [];
  int _atCursorPos = -1;
  final LayerLink _layerLink = LayerLink();
  bool _inputFocused = false;

  ChatModel get chatModel => widget.chatModel;
  bool get enabled => widget.enabled;
  bool get dark => widget.dark;
  VoidCallback? get onAttachFile => widget.onAttachFile;
  VoidCallback? get onRemoteAssist => widget.onRemoteAssist;
  VoidCallback? get onPasteImage => widget.onPasteImage;

  @override
  void initState() {
    super.initState();
    chatModel.textController.addListener(_onTextChanged);
    chatModel.inputNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    chatModel.textController.removeListener(_onTextChanged);
    chatModel.inputNode.removeListener(_onFocusChanged);
    super.dispose();
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
      _atCandidates = group.members!
          .where((m) => m.peerId != chatModel.me.id)
          .toList();
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
    final newText = '${text.substring(0, atIdx)}@${member.displayName} ${text.substring(cursor)}';
    chatModel.textController.text = newText;
    chatModel.textController.selection = TextSelection.collapsed(
      offset: atIdx + member.displayName.length + 2, // @Name<space>
    );
    setState(() => _atOverlayVisible = false);
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
    final border = dark ? const Color(0xFF3A3D43) : const Color(0xFFE2E2E2);
    final focusedBorder = dark
        ? const Color(0xFF4CAF50)
        : const Color(0xFF07C160);
    final foreground = dark ? const Color(0xFFF2F2F2) : const Color(0xFF222222);
    final muted = dark ? const Color(0xFF999CA2) : const Color(0xFF777777);
    final composer = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      height: 118,
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF25272C) : kWeChatCanvasColor,
        border: Border.all(
          color: _inputFocused ? focusedBorder : border,
          width: _inputFocused ? 1.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: _inputFocused
            ? [
                BoxShadow(
                  color: focusedBorder.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: chatModel.textController,
              focusNode: chatModel.inputNode,
              enabled: enabled,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                height: 1.45,
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                hintText: translate('Write a message'),
                hintStyle: TextStyle(
                  color: muted,
                  fontSize: 14,
                  height: 1.45,
                ),
                contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 10, 5),
              child: Row(
                children: <Widget>[
                  if (onAttachFile != null)
                    _ComposerToolButton(
                      icon: Icons.folder_outlined,
                      tooltip: translate('File Transfer'),
                      enabled: enabled,
                      onPressed: onAttachFile,
                    ),
                  if (onPasteImage != null)
                    _ComposerToolButton(
                      icon: Icons.image_outlined,
                      tooltip: translate('Send Image'),
                      enabled: enabled,
                      onPressed: onPasteImage,
                    ),
                  if (onRemoteAssist != null)
                    _ComposerToolButton(
                      icon: Icons.desktop_windows_outlined,
                      tooltip: translate('Remote Desktop'),
                      enabled: enabled,
                      onPressed: onRemoteAssist,
                    ),
                  VoiceMessageRecorderButton(
                    chatModel: chatModel,
                    enabled: enabled,
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
                            letterSpacing: 0.3,
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
    );
    if (!_atOverlayVisible) return composer;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        composer,
        if (_atOverlayVisible && _atCandidates.isNotEmpty)
          Positioned(
            bottom: 122,
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
                    color: dark ? const Color(0xFF3A3D43) : const Color(0xFFEEEEEE),
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

  const _AiModelSelector({
    required this.dark,
    required this.chatModel,
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
    final profiles = AiConfig.current.profiles;
    if (profiles.length <= 1) return;

    final activeIdx = AiConfig.current.activeProfileIndex;
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
        final p = profiles[i];
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            await AiConfig.setActiveProfile(i);
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
    final profiles = AiConfig.current.profiles;
    if (profiles.isEmpty) return const SizedBox.shrink();

    final active = AiConfig.currentProfile;
    final multiple = profiles.length > 1;
    final foreground = dark ? const Color(0xFF888B91) : const Color(0xFF888888);

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