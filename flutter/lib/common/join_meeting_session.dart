import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../common.dart';
import '../models/meeting_group_model.dart';

/// 加入会议实时会话，按权限分流：
///
/// - 发起人（host）与指定的演示人（presenter）→ 普通连接（可操控鼠标/键盘）
/// - 其他成员 → viewer 只读连接（进入观看，无法操控）
///
/// viewer 模式需要 host 在分享会话时生成的观看令牌
/// （[MeetingGroup.viewerToken]，由 host 通过邀请链接广播给成员）。
Future<void> joinMeetingSession(
  BuildContext context,
  MeetingGroup group, {
  bool forceViewer = false,
}) async {
  if (!group.hasActiveSession || group.activeSessionEndpoint.isEmpty) {
    showToast(translate('No active session yet'));
    return;
  }
  final canControl = !forceViewer && (group.isHost || group.isPresenter);
  if (canControl) {
    // 发起人 / 演示人：完整控制权
    connect(context, group.activeSessionEndpoint,
        isFileTransfer: false, isViewCamera: false, isTerminal: false);
    return;
  }
  // 其他成员：只读观看
  if (group.viewerToken.isEmpty) {
    showToast(translate('Waiting for host to enable viewing'));
    return;
  }
  final viewerId = const Uuid().v4();
  final displayName =
      (gFFI.chatModel.me.firstName ?? '').trim().isNotEmpty
          ? gFFI.chatModel.me.firstName!.trim()
          : translate('Viewer');
  connect(
    context,
    group.activeSessionEndpoint,
    isFileTransfer: false,
    isViewCamera: false,
    isTerminal: false,
    viewerToken: group.viewerToken,
    viewerId: viewerId,
    viewerDisplayName: displayName,
  );
}

/// 会议群聊内收到 viewer 邀请链接时调用：解析出令牌与 endpoint 并保存到
/// 会议，供成员点"进入观看"时直接使用。
///
/// 链接格式 `luoda://join/<token>?endpoint=<endpoint>` 或纯 token 文本。
void captureMeetingViewerToken(MeetingGroup group, String link) {
  final trimmed = link.trim();
  if (trimmed.isEmpty) return;
  String? token;
  String? endpoint;
  final uri = Uri.tryParse(trimmed);
  if (uri != null &&
      uri.scheme.toLowerCase() == 'luoda' &&
      uri.host.toLowerCase() == 'join' &&
      uri.pathSegments.isNotEmpty) {
    token = uri.pathSegments.first.trim();
    final ep = uri.queryParameters['endpoint']?.trim();
    if (ep != null && ep.isNotEmpty) endpoint = ep;
  } else if (!trimmed.contains(':') && trimmed.length >= 8) {
    // 可能是纯短码（12 位 Crockford），去空格/连字符后校验
    final normalized = trimmed.replaceAll(RegExp(r'[- ]'), '');
    if (normalized.length >= 8 && normalized.length <= 32) {
      token = normalized;
    }
  }
  if (token == null || token.isEmpty) return;
  if (group.viewerToken != token) {
    MeetingGroupStore.setViewerToken(group.meetingId, token);
    showToast(translate('Viewing enabled by host'));
  }
  // 同步 endpoint，保证成员无需手动输入连接目标。
  if (endpoint != null && endpoint.isNotEmpty &&
      group.activeSessionEndpoint != endpoint) {
    group.activeSessionEndpoint = endpoint;
    MeetingGroupStore.setSessionEndpoint(group.meetingId, endpoint);
  }
}
