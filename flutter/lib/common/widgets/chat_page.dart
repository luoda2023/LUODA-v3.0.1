import 'dart:io';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../mobile/pages/home_page.dart';
import '../../models/meeting_group_model.dart';
import 'package:luoda_flutter/common/direct_viewer_invite.dart';
import '../wechat_ui_tokens.dart';
import 'file_viewer.dart';
import 'voice_message_controls.dart';

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

  Future<void> _showMessageActions(
    BuildContext context,
    ChatMessage message,
  ) async {
    final properties = message.customProperties;
    final id = (properties?['ldesk_id'] ?? '').toString();
    final disposition =
        (properties?['ldesk_disposition'] ?? 'active').toString();
    final delivery = (properties?['ldesk_delivery'] ?? '').toString();
    if (id.isEmpty ||
        message.user.id != chatModel.me.id ||
        disposition != 'active') {
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Primary actions: Recall & Destroy — always visible at top
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionChip(
                        icon: Icons.undo_rounded,
                        label: translate('Recall'),
                        color: Theme.of(sheetContext).colorScheme.primary,
                        onTap: () => Navigator.pop(sheetContext, 'recall'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionChip(
                        icon: Icons.delete_forever_outlined,
                        label: translate('Destroy'),
                        color: Theme.of(sheetContext).colorScheme.error,
                        onTap: () => Navigator.pop(sheetContext, 'destroy'),
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.forward_rounded, size: 22),
                title: Text(translate('Forward'),
                    style: const TextStyle(fontSize: 14)),
                onTap: () => Navigator.pop(sheetContext, 'forward'),
                dense: true,
              ),
              if (delivery == 'failed')
                ListTile(
                  leading: const Icon(Icons.refresh_rounded, size: 22),
                  title: Text(translate('Retry send'),
                      style: const TextStyle(fontSize: 14)),
                  onTap: () => Navigator.pop(sheetContext, 'retry'),
                  dense: true,
                ),
              const Divider(height: 1),
              // Self-destruct sub-actions
              ListTile(
                leading: const Icon(Icons.timer_outlined, size: 22),
                title: Text(translate('Self-destruct in 1 minute'),
                    style: const TextStyle(fontSize: 14)),
                onTap: () => Navigator.pop(sheetContext, 'expire-60'),
                dense: true,
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined, size: 22),
                title: Text(translate('Self-destruct in 5 minutes'),
                    style: const TextStyle(fontSize: 14)),
                onTap: () => Navigator.pop(sheetContext, 'expire-300'),
                dense: true,
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined, size: 22),
                title: Text(translate('Self-destruct in 1 hour'),
                    style: const TextStyle(fontSize: 14)),
                onTap: () => Navigator.pop(sheetContext, 'expire-3600'),
                dense: true,
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'forward') {
      await _showForwardPicker(context, message);
      return;
    }
    if (action == 'destroy') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(translate('Destroy message')),
          content: Text(translate('Destroy message on both devices?')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(translate('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(translate('Destroy')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
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
              return Column(
                crossAxisAlignment: isOwnMessage
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: <Widget>[
                  if (isVoice && messageId.isNotEmpty)
                    VoiceMessageBubble(
                      chatModel: chatModel,
                      messageId: messageId,
                      durationMs: voiceDurationMs,
                    )
                  else if (isFile && fileName.isNotEmpty)
                    InkWell(
                      onTap: () => showFileViewer(
                        context,
                        fileName: fileName,
                        fileSize: fileSize,
                        localPath: localPath,
                      ),
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
                    Text(
                      message.text,
                      style: TextStyle(
                        color: foreground,
                        fontSize: isDesktopHome ? 14 : 15,
                        height: 1.42,
                        letterSpacing: 0,
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
              final bubbleColor = isOwnMessage
                  ? dark
                      ? const Color(0xFF3B7F55)
                      : kWeChatOutgoingBubbleColor
                  : dark
                      ? const Color(0xFF2B2D32)
                      : kWeChatIncomingBubbleColor;
              final name = (message.user.firstName ?? '').trim();
              final bubble = Stack(
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
                    child: messageBody(
                      message,
                      isOwnMessage: isOwnMessage,
                      includeMetadata: false,
                    ),
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
                              if (hasDelivery(message) && selfDestructLabel(message).isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Text('·'),
                                ),
                              if (selfDestructLabel(message).isNotEmpty)
                                Text(selfDestructLabel(message)),
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
              final actionButton = canManage
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // LUODA FIX: prominent one-tap Recall button.
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
                          onPressed: () => _showMessageActions(context, message),
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
                          messageColumn,
                          const SizedBox(width: 4),
                          actionButton,
                          const SizedBox(width: 4),
                          const SizedBox(width: 11),
                          avatar,
                        ]
                      : <Widget>[
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
                      dateSeparatorBuilder: (date) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '${date.hour.toString().padLeft(2, '0')}:'
                          '${date.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: dark
                                ? const Color(0xFF999CA2)
                                : const Color(0xFF999999),
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                    messageOptions: MessageOptions(
                      showCurrentUserAvatar:
                          isDesktopHome || type == ChatPageType.mobileMain,
                      showOtherUsersAvatar:
                          isDesktopHome || type == ChatPageType.mobileMain,
                      showOtherUsersName: false,
                      onLongPressMessage: (message) =>
                          _showMessageActions(context, message),
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
                  if (!isDesktopHome) return messageList;
                  return Column(
                    children: <Widget>[
                      Expanded(child: messageList),
                      Builder(builder: (ctx) {
                        final peerId = chatModel.currentKey.peerId;
                        if (peerId.isEmpty || !chatModel.isPeerTyping(peerId)) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
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
                      }),
                      _DesktopChatComposer(
                        chatModel: chatModel,
                        enabled: !readOnly,
                        dark: dark,
                        onAttachFile: onAttachFile,
                        onRemoteAssist: onRemoteAssist,
                        onPasteImage: onPasteImage,
                      ),
                    ],
                  );
                }),
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

class _DesktopChatComposer extends StatelessWidget {
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
    final foreground = dark ? const Color(0xFFF2F2F2) : const Color(0xFF222222);
    final muted = dark ? const Color(0xFF999CA2) : const Color(0xFF777777);
    return Container(
      height: 118,
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF25272C) : kWeChatCanvasColor,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(9),
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
                          fixedSize: const Size(68, 30),
                          minimumSize: const Size(68, 30),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
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
                        ),
                        child: Text(
                          translate('Send'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
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
