import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../mobile/pages/home_page.dart';

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
                : const Color(0xFFF5F5F6)
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
              final fallback = Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: str2color(name),
                  borderRadius: BorderRadius.circular(8),
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
                    size: 36,
                    borderRadius: 8,
                    fallback: fallback,
                  ) ??
                  fallback;
            }

            return Stack(
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final chat = DashChat(
                    onSend: chatModel.send,
                    currentUser: chatModel.me,
                    messages: chatModel
                            .messages[chatModel.currentKey]?.chatMessages ??
                        [],
                    readOnly: readOnly,
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
                      textColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF181818),
                      maxWidth: constraints.maxWidth * 0.7,
                      messageTextBuilder: (message, _, __) {
                        final isOwnMessage = message.user.id == chatModel.me.id;
                        final foreground =
                            dark ? Colors.white : const Color(0xFF181818);
                        final properties = message.customProperties;
                        final delivery =
                            (properties?['ldesk_delivery'] ?? '').toString();
                        final isFile = properties?['ldesk_kind'] == 'file';
                        final fileName =
                            (properties?['ldesk_file_name'] ?? '').toString();
                        final fileSize = int.tryParse(
                              '${properties?['ldesk_file_size'] ?? 0}',
                            ) ??
                            0;
                        String deliveryLabel() {
                          switch (delivery) {
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

                        String fileSizeLabel() {
                          if (fileSize < 1024) return '$fileSize B';
                          if (fileSize < 1024 * 1024) {
                            return '${(fileSize / 1024).toStringAsFixed(1)} KB';
                          }
                          return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
                        }

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
                                          ),
                                        ),
                                        Text(
                                          fileSizeLabel(),
                                          style: TextStyle(
                                            color: foreground.withOpacity(0.52),
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
                                  height: 1.35,
                                ),
                              ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  "${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}",
                                  style: TextStyle(
                                    color: foreground.withOpacity(0.52),
                                    fontSize: 11,
                                  ),
                                ),
                                if (isOwnMessage &&
                                    deliveryLabel().isNotEmpty) ...<Widget>[
                                  const SizedBox(width: 5),
                                  Text(
                                    deliveryLabel(),
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
                  return SelectionArea(child: chat);
                }),
              ],
            ).paddingOnly(bottom: isDesktopHome ? 0 : 8);
          },
        ),
      ),
    );
  }
}
