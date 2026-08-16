import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/widgets/friend_picker_dialog.dart';
import 'package:luoda_flutter/models/chat_model.dart';

/// 从联系人列表选择一位好友/陌生人，把 TA 的个人名片发到当前会话。
/// 手机端与 PC 端输入栏共用此入口，保证两端体验一致。
/// 返回是否成功发送。
Future<bool> pickContactToSend(
  BuildContext context,
  ChatModel chatModel,
) async {
  final peers = gFFI.recentPeersModel.peers
      .where((p) =>
          p.id.trim().isNotEmpty && !p.id.trim().startsWith('meeting:'))
      .toList();
  if (peers.isEmpty) {
    showToast(translate('No contacts to forward to'));
    return false;
  }
  final picked = await showFriendPickerDialog(
    context,
    peers: peers,
    title: translate('Send Contact Card'),
    maxSelections: 1,
  );
  if (picked == null || picked.isEmpty) return false;
  final peer = picked.first;
  final card = DirectChatContact(
    peerId: peer.id,
    name: peer.finalName(),
    platform: peer.platform,
  );
  chatModel.sendText(card.encode());
  showToast(translate('Sent'));
  return true;
}
