import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../mobile/pages/home_page.dart';
import '../wechat_ui_tokens.dart';

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

  ChatPage({
    ChatModel? chatModel,
    this.type,
    this.onAttachFile,
    this.onRemoteAssist,
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
            final showComposerTools =
                onAttachFile != null || onRemoteAssist != null;
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

            String deliveryLabel(ChatMessage message) {
              switch ((message.customProperties?['ldesk_delivery'] ?? '')
                  .toString()) {
                case 'queued':
                  return translate('Waiting to send');
                case 'sent':
                  return translate('Sent');
                case 'delivered':
                  return translate('Delivered');
                case 'failed':
                  return translate('Failed');
                default:
                  return '';
              }
            }

            String fileSizeLabel(int fileSize) {
              if (fileSize < 1024) return '$fileSize B';
              if (fileSize < 1024 * 1024) {
                return '${(fileSize / 1024).toStringAsFixed(1)} KB';
              }
              return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
            }

            Widget messageBody(
              ChatMessage message, {
              required bool isOwnMessage,
              required bool includeMetadata,
            }) {
              final foreground = dark ? Colors.white : const Color(0xFF181818);
              final properties = message.customProperties;
              final isFile = properties?['ldesk_kind'] == 'file';
              final fileName =
                  (properties?['ldesk_file_name'] ?? '').toString();
              final fileSize = int.tryParse(
                    '${properties?['ldesk_file_size'] ?? 0}',
                  ) ??
                  0;
              return Column(
                crossAxisAlignment: isOwnMessage
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: <Widget>[
                  if (isFile && fileName.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.insert_drive_file_outlined,
                          size: 24,
                          color: foreground.withOpacity(0.78),
                        ),
                        const SizedBox(width: 8),
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
                    )
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
                            deliveryLabel(message).isNotEmpty) ...<Widget>[
                          const SizedBox(width: 5),
                          Text(
                            deliveryLabel(message),
                            style: TextStyle(
                              color: foreground.withOpacity(0.52),
                              fontSize: 11,
                            ),
                          ),
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
                      : kWeChatListSurfaceColor;
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
                    if (isOwnMessage && deliveryLabel(message).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 2),
                        child: Text(
                          deliveryLabel(message),
                          style: TextStyle(
                            color: deliveryLabel(message) == translate('Failed')
                                ? Theme.of(context).colorScheme.error
                                : dark
                                    ? const Color(0xFF999CA2)
                                    : const Color(0xFF999999),
                            fontSize: 11,
                            height: 1.2,
                          ),
                        ),
                      ),
                  ],
                ),
              );
              final avatar = messageAvatar(message.user, null, null);
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
                  final chat = DashChat(
                    onSend: chatModel.send,
                    currentUser: chatModel.me,
                    messages: chatModel
                            .messages[chatModel.currentKey]?.chatMessages ??
                        [],
                    readOnly: isDesktopHome ? true : readOnly,
                    inputOptions: InputOptions(
                      focusNode: chatModel.inputNode,
                      textController: chatModel.textController,
                      alwaysShowSend: isDesktopHome,
                      leading: showComposerTools
                          ? <Widget>[
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
                                constraints.maxWidth *
                                    (isDesktopHome ? 0.62 : 0.76),
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
                      _DesktopChatComposer(
                        chatModel: chatModel,
                        enabled: !readOnly,
                        dark: dark,
                        onAttachFile: onAttachFile,
                        onRemoteAssist: onRemoteAssist,
                      ),
                    ],
                  );
                }),
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
  });

  final ChatModel chatModel;
  final bool enabled;
  final bool dark;
  final VoidCallback? onAttachFile;
  final VoidCallback? onRemoteAssist;

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
      height: 142,
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
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
            height: 46,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 12, 7),
              child: Row(
                children: <Widget>[
                  if (onAttachFile != null)
                    _ComposerToolButton(
                      icon: Icons.folder_outlined,
                      tooltip: translate('File Transfer'),
                      enabled: enabled,
                      onPressed: onAttachFile,
                    ),
                  if (onRemoteAssist != null)
                    _ComposerToolButton(
                      icon: Icons.desktop_windows_outlined,
                      tooltip: translate('Remote Desktop'),
                      enabled: enabled,
                      onPressed: onRemoteAssist,
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
                              ? const Color(0xFF07C160)
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
