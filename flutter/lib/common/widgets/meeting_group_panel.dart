// LUODA 3.1.1 - Meeting group management panel.
//
// Provides: add/remove members, invite link generation & sharing,
// one-tap remote-assist join, member list with online indicators.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/chat_model.dart';

import '../direct_pairing.dart';
import '../join_meeting_session.dart';
import '../../models/meeting_group_model.dart';
import '../../models/peer_model.dart';
import 'friend_picker_dialog.dart';

/// Full management panel for a single meeting group.
class MeetingGroupPanel extends StatefulWidget {
  final MeetingGroup group;
  const MeetingGroupPanel({super.key, required this.group});

  @override
  State<MeetingGroupPanel> createState() => _MeetingGroupPanelState();
}

class _MeetingGroupPanelState extends State<MeetingGroupPanel> {
  MeetingGroup get _group => widget.group;
  // The host is rendered as its own tile at the top of the member card.
  // Older builds persisted the host inside [members] too, which made the
  // host appear twice; filter it out defensively.
  List<MeetingMember> get _members =>
      (_group.members ?? [])
          .where((m) => m.peerId != _group.hostPeerId)
          .toList();
  late final TextEditingController _addPeerCtrl;
  String? _inviteLink;
  // 成员列表搜索过滤与排序。
  final TextEditingController _memberSearchCtrl = TextEditingController();
  bool _memberSortNewest = true; // true=按加入时间倒序（最新在前）

  @override
  void initState() {
    super.initState();
    _addPeerCtrl = TextEditingController();
    _memberSearchCtrl.addListener(_onMemberSearchChanged);
    _refreshInviteLink();
  }

  @override
  void dispose() {
    _addPeerCtrl.dispose();
    _memberSearchCtrl.removeListener(_onMemberSearchChanged);
    _memberSearchCtrl.dispose();
    super.dispose();
  }

  void _onMemberSearchChanged() {
    if (mounted) setState(() {});
  }

  /// 过滤 + 排序后的成员列表（host 始终单独置顶，不参与排序）。
  List<MeetingMember> get _filteredMembers {
    final query = _memberSearchCtrl.text.trim().toLowerCase();
    var list = _members;
    if (query.isNotEmpty) {
      list = list
          .where((m) =>
              m.displayName.toLowerCase().contains(query) ||
              m.peerId.toLowerCase().contains(query))
          .toList();
    }
    final sorted = List<MeetingMember>.of(list);
    sorted.sort((a, b) => _memberSortNewest
        ? b.joinedAt.compareTo(a.joinedAt)
        : a.joinedAt.compareTo(b.joinedAt));
    return sorted;
  }

  void _refreshInviteLink() {
    if (_group.inviteShortCode.isNotEmpty) {
      _inviteLink =
          'luoda://meeting/${_group.meetingId}?code=${_group.inviteShortCode}&host=${_group.hostPeerId}';
    }
    setState(() {});
  }

  Future<void> _generateInvite() async {
    final code = _generateShortCode();
    _group.inviteShortCode = code;
    await MeetingGroupStore.save();
    _refreshInviteLink();
  }

  String _generateShortCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rand = List.generate(
        6, (_) => chars[DateTime.now().microsecond % chars.length]);
    // Shuffle with microseconds
    final r = (DateTime.now().microsecondsSinceEpoch % 100000).toString();
    return '${rand.join()}${r.substring(0, 2)}';
  }

  Future<void> _addMember(String peerId) async {
    final trimmed = peerId.trim();
    if (trimmed.isEmpty) return;
    if (trimmed == _group.hostPeerId || trimmed == gFFI.serverModel.id) {
      showToast(translate('Already a member'));
      return;
    }
    if (_members.any((m) => m.peerId == trimmed)) {
      showToast(translate('Already a member'));
      return;
    }
    final peer = gFFI.recentPeersModel.peers.firstWhereOrNull(
      (p) => p.id == trimmed,
    );
    final displayName = peer?.alias.isNotEmpty == true
        ? peer!.alias
        : peer?.username.isNotEmpty == true
            ? peer!.username
            : trimmed;
    MeetingGroupStore.addMember(_group.meetingId, trimmed, displayName);
    _addPeerCtrl.clear();
    setState(() {});
    // Non-blocking system message - don't wait for broken chat send
    final chatModel = _activeGroupChatModel();
    if (chatModel != null) {
      final key = chatModel.currentKey;
      if (key.peerId == _group.conversationId) {
        chatModel.sendText(
            '${translate('System')}: $displayName ${translate('joined the group')}');
      }
    }
  }

  Future<void> _removeMember(MeetingMember member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(translate('Remove member')),
        content: Text('${translate('Remove')} ${member.displayName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(translate('Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(translate('Remove'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    MeetingGroupStore.removeMember(_group.meetingId, member.peerId);
    setState(() {});
  }

  void _copyInviteLink() {
    if (_inviteLink == null) return;
    Clipboard.setData(ClipboardData(text: _inviteLink!));
    showToast(translate('Link copied'));
  }

  void _shareToChat(String peerId) {
    if (_inviteLink == null) {
      showToast(translate('Generate an invite link first'));
      return;
    }
    final text = '${translate('Join meeting')}: ${_group.title}\n$_inviteLink';
    gFFI.chatModel.sendText(text);
    showToast(translate('Invite sent'));
  }

  void _joinRemoteSession() {
    // 发起人/演示人可控制，其他成员只读观看（进入观看）。
    unawaited(joinMeetingSession(context, _group));
  }

  /// 开始演示（仅发起人 host 可用）。
  ///
  /// 演示人 = 自己：本机作为共享端，开启远程协助（被观看）并广播
  /// 邀请链接给成员，成员点击"进入观看"。
  /// 演示人 = 别人：向演示人发送"开始演示"请求消息，对方接受后
  /// 分享屏幕，成员再进入观看。
  Future<void> _startPresentation() async {
    if (!_group.isHost) return;
    final presenterId = _group.presenterPeerId.isNotEmpty
        ? _group.presenterPeerId
        : _group.hostPeerId;
    if (presenterId == gFFI.serverModel.id ||
        await DirectPairingStore.isSelfTarget(presenterId)) {
      // 演示人 = 自己：本机开始共享屏幕（远程协助被控端）。
      _group.activeSessionEndpoint = gFFI.serverModel.id;
      await MeetingGroupStore.save();
      if (mounted) setState(() {});
      showToast(translate('You are the presenter - share your screen'));
      // 广播"演示已开始"到会议群聊，成员可点击进入观看。
      final chatModel = _activeGroupChatModel();
      if (chatModel != null &&
          chatModel.currentKey.peerId == _group.conversationId) {
        chatModel.sendText(
            '${translate('System')}: ${translate('Presentation started - tap to watch')}');
      }
      return;
    }
    // 演示人 = 别人：向演示人发送"开始演示"请求消息。
    final chatModel = gFFI.chatModel;
    final originalKey = chatModel.currentKey;
    chatModel.changeCurrentKey(MessageKey(presenterId, ChatModel.clientModeID));
    final body =
        '${translate('Meeting invite')}：${_group.hostDisplayName} '
        '${translate('invited you to present in')}《${_group.title}》'
        '\n${_inviteLink ?? ''}';
    chatModel.sendText(body);
    chatModel.changeCurrentKey(originalKey);
    showToast('${translate('Presenter')}: ${_group.presenterDisplayName} '
        '${translate('request sent')}');
  }

  /// 修改演示人（仅 host 可操作）：从会议成员（含发起人自己）中单选。
  Future<void> _changePresenter() async {
    if (!_group.isHost) return;
    // 演示人必须来自会议参与者：发起人自己 + 已添加的成员。
    final candidates = <Peer>[
      // 发起人自己（若无配对记录则用占位 Peer）。
      () {
        final hostPeer = gFFI.recentPeersModel.peers
            .firstWhereOrNull((p) => p.id.trim() == _group.hostPeerId);
        return hostPeer ??
            Peer(
              id: _group.hostPeerId,
              hash: '',
              password: '',
              username: _group.hostDisplayName,
              hostname: _group.hostDisplayName,
              platform: '',
              alias: '',
              tags: const [],
              forceAlwaysRelay: false,
              rdpPort: '',
              rdpUsername: '',
              loginName: '',
              device_group_name: '',
              note: '',
            );
      }(),
      // 会议成员：优先取配对记录（昵称更友好），无记录时用成员名构造占位。
      for (final m in _members)
        () {
          final peer = gFFI.recentPeersModel.peers
              .firstWhereOrNull((p) => p.id.trim() == m.peerId);
          return peer ??
              Peer(
                id: m.peerId,
                hash: '',
                password: '',
                username: m.displayName,
                hostname: m.displayName,
                platform: '',
                alias: '',
                tags: const [],
                forceAlwaysRelay: false,
                rdpPort: '',
                rdpUsername: '',
                loginName: '',
                device_group_name: '',
                note: '',
              );
        }(),
    ];
    final picked = await showFriendPickerDialog(
      context,
      peers: candidates,
      title: translate('Choose presenter'),
      maxSelections: 1,
    );
    if (picked == null || picked.isEmpty) return;
    final chosen = picked.first;
    MeetingGroupStore.setPresenter(
      _group.meetingId,
      chosen.id,
      chosen.finalName(),
    );
    _group.presenterPeerId = chosen.id;
    _group.presenterDisplayName = chosen.finalName();
    if (mounted) setState(() {});
    showToast('${translate('Presenter')}: ${chosen.finalName()}');
  }

  ChatModel? _activeGroupChatModel() {
    // Find the active chat model for this group's conversation
    if (gFFI.chatModel.currentKey.peerId == _group.conversationId) {
      return gFFI.chatModel;
    }
    return null;
  }

  Future<void> _editTitle() async {
    final theme = Theme.of(context);
    final controller = TextEditingController(text: _group.title);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(translate('Group name')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: InputDecoration(
            hintText: translate('Group name'),
            filled: true,
            fillColor: Theme.of(ctx).brightness == Brightness.dark
                ? const Color(0xFF1E2024)
                : const Color(0xFFF2F3F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(translate('Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(translate('Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || value == _group.title) return;
    _group.title = value;
    await MeetingGroupStore.save();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final isHost = _group.isHost;
    final surface = dark ? MyTheme.surfaceDark : Colors.white;
    final border = dark ? MyTheme.borderDark : MyTheme.borderLight;

    return Scaffold(
      // WeChat 聊天信息页：浅灰背景 + 白色圆角分组卡片，无阴影。
      backgroundColor: dark ? MyTheme.canvasDark : const Color(0xFFF7F7F7),
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 46,
        elevation: 0,
        backgroundColor: dark ? MyTheme.surfaceDark : const Color(0xFFEDEDED),
        title: Text(
          translate('Chat info'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          if (_group.hasActiveSession)
            IconButton(
              tooltip: translate('Join remote session'),
              icon: const Icon(Icons.desktop_windows_rounded),
              color: theme.colorScheme.primary,
              onPressed: _joinRemoteSession,
            ),
          _GroupPopupMenu(
            group: _group,
            onInviteGenerated: _generateInvite,
            onInviteCopied: _copyInviteLink,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                // 手机窄屏不限宽（与上一级列表同宽），仅 PC 宽窗口限宽保持美观
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width > 700
                      ? 680
                      : double.infinity,
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    _buildHeaderCard(context),
                    const SizedBox(height: 10),
                    _buildInfoGroup(context, isHost),
                    if (isHost) ...[
                      const SizedBox(height: 10),
                      _buildPresentationCard(context, surface, border),
                      const SizedBox(height: 10),
                      _buildInviteCard(context, surface, border),
                    ],
                    if (_group.hasActiveSession) ...[
                      const SizedBox(height: 10),
                      _buildActiveSessionBanner(context, theme),
                    ],
                    const SizedBox(height: 10),
                    _buildMembersCard(context, surface, border),
                    const SizedBox(height: 20),
                    // 微信风格底部红色危险按钮：解散/退出。
                    _buildDangerButton(context),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
          if (isHost) _buildAddMemberBar(context, surface, border),
        ],
      ),
    );
  }

  /// 微信风格分组卡片容器：白底圆角 12，无阴影，细描边。
  Widget _groupCard({
    required Color surface,
    required Color border,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }

  /// 顶部头像卡（微信聊天信息页：大圆角头像 + 名称 + 副标题，居中）。
  Widget _buildHeaderCard(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final isHost = _group.isHost;
    final surface = dark ? MyTheme.surfaceDark : Colors.white;
    final border = dark ? MyTheme.borderDark : MyTheme.borderLight;
    final presenterLabel = _group.presenterDisplayName.isNotEmpty
        ? _group.presenterDisplayName
        : _group.hostDisplayName;

    return _groupCard(
      surface: surface,
      border: border,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF0FAF57), Color(0xFF07C160)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.videocam_rounded,
                    color: Colors.white, size: 32),
              ),
              if (isHost)
                Positioned(
                  right: 0,
                  top: 0,
                  child: InkWell(
                    onTap: _editTitle,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: MyTheme.primarySoft,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.edit_rounded,
                          color: MyTheme.primary, size: 14),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _group.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${translate('Meeting')} · '
            '${_members.length + 1} ${translate('Members')} · '
            '$presenterLabel ${translate('presents')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withOpacity(0.45),
            ),
          ),
        ],
      ),
    );
  }

  /// 会议信息分组（微信风格：白色分组内多行，行间细分隔线）。
  Widget _buildInfoGroup(BuildContext context, bool isHost) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = dark ? MyTheme.surfaceDark : Colors.white;
    final border = dark ? MyTheme.borderDark : MyTheme.borderLight;
    final presenterLabel = _group.presenterDisplayName.isNotEmpty
        ? _group.presenterDisplayName
        : _group.hostDisplayName;
    return _groupCard(
      surface: surface,
      border: border,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _infoRow(
            context,
            icon: Icons.person_rounded,
            label: translate('Host'),
            value: _group.hostDisplayName,
          ),
          _infoDivider(dark),
          _infoRow(
            context,
            icon: Icons.people_alt_rounded,
            label: translate('Members'),
            value: '${_members.length + 1}',
          ),
          if (_group.inviteShortCode.isNotEmpty) ...[
            _infoDivider(dark),
            _infoRow(
              context,
              icon: Icons.tag_rounded,
              label: translate('Invite code'),
              value: _group.inviteShortCode,
              trailing: IconButton(
                tooltip: translate('Copy link'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: _copyInviteLink,
              ),
            ),
          ],
          _infoDivider(dark),
          _infoRow(
            context,
            icon: Icons.present_to_all_rounded,
            label: translate('Presenter'),
            value: presenterLabel,
            valueColor: const Color(0xFFE65100),
            trailing: isHost
                ? TextButton(
                    onPressed: _changePresenter,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                    ),
                    child: Text(translate('Change')),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  /// 底部红色危险按钮（微信风格）：host 解散会议，成员退出会议。
  Widget _buildDangerButton(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? MyTheme.surfaceDark : Colors.white;
    final border = dark ? MyTheme.borderDark : MyTheme.borderLight;
    final label = _group.isHost
        ? translate('Delete group')
        : translate('Leave meeting');
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withOpacity(0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _group.isHost ? _deleteGroup : _leaveMeeting,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFA5151),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(translate('Delete group')),
        content: Text(translate('Delete this meeting group permanently?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(translate('Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(translate('Delete'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await MeetingGroupStore.remove(_group.meetingId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _leaveMeeting() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(translate('Leave meeting')),
        content: Text('${translate('Leave')} ${_group.title}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(translate('Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(translate('Leave'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (_group.hostPeerId == gFFI.serverModel.id) return;
    MeetingGroupStore.removeMember(_group.meetingId, gFFI.serverModel.id);
    if (context.mounted) Navigator.of(context).pop();
  }


  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon,
              size: 18, color: theme.colorScheme.onSurface.withOpacity(0.42)),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _infoDivider(bool dark) {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 44,
      color: dark ? const Color(0xFF3A3D43) : const Color(0x80E5E5E5),
    );
  }

  /// 演示控制卡（仅 host）：发起演示到演示人电脑，或结束演示。
  Widget _buildPresentationCard(
      BuildContext context, Color surface, Color border) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final presenterLabel = _group.presenterDisplayName.isNotEmpty
        ? _group.presenterDisplayName
        : _group.hostDisplayName;
    final isSelfPresenter = _group.presenterPeerId.isEmpty
        ? _group.isHost
        : _group.presenterPeerId == gFFI.serverModel.id;
    return _groupCard(
      surface: surface,
      border: border,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.present_to_all_rounded,
                    size: 18, color: Color(0xFFE65100)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  translate('Presentation'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: dark
                  ? MyTheme.surfaceDark
                  : const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_pin_circle_rounded,
                    size: 16, color: Color(0xFFE65100)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${translate('Presenter')}: $presenterLabel'
                    '${isSelfPresenter ? '  (${translate('You')})' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _changePresenter,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                  label: Text(translate('Change presenter')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                  ),
                  onPressed: _startPresentation,
                  icon: const Icon(Icons.screen_share_rounded, size: 17),
                  label: Text(
                    _group.hasActiveSession
                        ? translate('End presentation')
                        : translate('Start presentation'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            translate('Only host and presenter can control the mouse'),
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteCard(BuildContext context, Color surface, Color border) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return _groupCard(
      surface: surface,
      border: border,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: MyTheme.primarySoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.group_add_rounded,
                    size: 18, color: MyTheme.primary),
              ),
              const SizedBox(width: 10),
              Text(
                translate('Invite members'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_inviteLink == null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _generateInvite,
                icon: const Icon(Icons.add_link_rounded, size: 18),
                label: Text(translate('Generate invite link')),
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: dark
                    ? MyTheme.surfaceDark
                    : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    translate('Invite code'),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _group.inviteShortCode,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: MyTheme.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyInviteLink,
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: Text(translate('Copy link')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _shareToChat(''),
                    icon: const Icon(Icons.share_rounded, size: 17),
                    label: Text(translate('Share to chat')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveSessionBanner(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MyTheme.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyTheme.primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: MyTheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.desktop_windows_rounded,
                size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              translate('Host is sharing screen - tap to view'),
              style: TextStyle(
                fontSize: 13,
                color: MyTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded,
              size: 15, color: MyTheme.primary),
        ],
      ),
    );
  }

  Widget _buildMembersCard(BuildContext context, Color surface, Color border) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final members = _filteredMembers;
    final total = _members.length + 1;
    final active = _group.hasActiveSession;
    final isHost = _group.isHost;
    return _groupCard(
      surface: surface,
      border: border,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                Text(
                  translate('Members'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: MyTheme.primarySoft,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$total',
                    style: const TextStyle(
                      fontSize: 11,
                      color: MyTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                // 排序切换：按加入时间倒序 / 正序。
                InkWell(
                  onTap: () => setState(() => _memberSortNewest =
                      !_memberSortNewest),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: MyTheme.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _memberSortNewest
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 14,
                          color: MyTheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _memberSortNewest
                              ? translate('Newest')
                              : translate('Oldest'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MyTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF07C160).withOpacity(0.12)
                        : dark
                            ? const Color(0xFF2B2D32)
                            : const Color(0xFFF0F2F5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF07C160)
                              : dark
                                  ? const Color(0xFF4A4F58)
                                  : const Color(0xFFB8BEC7),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        active ? translate('Live') : translate('Not started'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active
                              ? const Color(0xFF07C160)
                              : dark
                                  ? Colors.white70
                                  : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 成员搜索框（按昵称 / ID 过滤）。
          if (total > 2 || _memberSearchCtrl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
              child: TextField(
                controller: _memberSearchCtrl,
                decoration: InputDecoration(
                  hintText: translate('Search members'),
                  isDense: true,
                  filled: true,
                  fillColor: dark
                      ? const Color(0xFF1E2024)
                      : const Color(0xFFF2F3F5),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _memberSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () =>
                              _memberSearchCtrl.clear(),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          // 微信成员网格：host + 成员 + (host) 添加，5 列。
          if (members.isEmpty && _memberSearchCtrl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  translate('No matching members'),
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withOpacity(0.45),
                  ),
                ),
              ),
            )
          else
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              mainAxisSpacing: 10,
              crossAxisSpacing: 4,
              childAspectRatio: 0.82,
              children: [
                // host 始终置顶（搜索时也保留，除非搜索词完全不含 host）。
                if (_memberHostMatches)
                  _MemberGridTile(
                    peerId: _group.hostPeerId,
                    displayName: _group.hostDisplayName,
                    isHost: true,
                    isPresenter: _group.presenterPeerId.isEmpty
                        ? true
                        : _group.presenterPeerId == _group.hostPeerId,
                    online: _memberOnline(_group.hostPeerId),
                    onRemove: null,
                  ),
                for (var i = 0; i < members.length; i++)
                  _MemberGridTile(
                    peerId: members[i].peerId,
                    displayName: members[i].displayName,
                    isHost: false,
                    isPresenter:
                        _group.presenterPeerId == members[i].peerId,
                    online: _memberOnline(members[i].peerId),
                    onRemove:
                        isHost ? () => _removeMember(members[i]) : null,
                  ),
                if (isHost &&
                    (_memberSearchCtrl.text.isEmpty ||
                        _memberHostMatches))
                  _MemberGridTile.addTile(onTap: _openFriendPicker),
              ],
            ),
        ],
      ),
    );
  }

  /// host 是否匹配当前搜索词。
  bool get _memberHostMatches {
    final query = _memberSearchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return _group.hostDisplayName.toLowerCase().contains(query) ||
        _group.hostPeerId.toLowerCase().contains(query);
  }

  bool _memberOnline(String peerId) {
    return gFFI.serverModel.clients.any(
      (c) => c.peerId == peerId && c.authorized && !c.disconnected,
    );
  }

  Widget _buildAddMemberBar(BuildContext context, Color surface, Color border) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: surface,
          border: Border(
              top: BorderSide(
                  color: dark ? const Color(0xFF3A3D43) : const Color(0x80E5E5E5))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addPeerCtrl,
                    decoration: InputDecoration(
                      hintText: translate('Enter peer ID or name'),
                      isDense: true,
                      filled: true,
                      fillColor: dark
                          ? const Color(0xFF1E2024)
                          : const Color(0xFFF2F3F5),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: MyTheme.primary, width: 1.2),
                      ),
                    ),
                    onSubmitted: (v) => _addMember(v),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: translate('Choose from contacts'),
                  child: Material(
                    color: MyTheme.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _openFriendPicker,
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        child: const Icon(Icons.people_alt_rounded,
                            color: MyTheme.primary, size: 22),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: MyTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.person_add_rounded, size: 20),
                  onPressed: () => _addMember(_addPeerCtrl.text),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openFriendPicker,
                style: TextButton.styleFrom(
                  foregroundColor: MyTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.group_add_rounded, size: 16),
                label: Text(
                  translate('Select from friends'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the WeChat-style contact picker and adds the selected peers.
  Future<void> _openFriendPicker() async {
    final peers = List<Peer>.of(gFFI.recentPeersModel.peers);
    final excluded = <String>{
      _group.hostPeerId,
      gFFI.serverModel.id,
      for (final m in _members) m.peerId,
    };
    final picked = await showFriendPickerDialog(
      context,
      peers: peers,
      excludePeerIds: excluded,
      title: translate('Select from friends'),
    );
    if (picked == null || picked.isEmpty) return;
    await _addMembersFromFriends(picked);
  }

  /// Batch-adds peers picked from the contact list and notifies each one.
  Future<void> _addMembersFromFriends(List<Peer> picked) async {
    final added = <Peer>[];
    for (final peer in picked) {
      final trimmed = peer.id.trim();
      if (trimmed.isEmpty ||
          trimmed == _group.hostPeerId ||
          trimmed == gFFI.serverModel.id) {
        continue;
      }
      if (_members.any((m) => m.peerId == trimmed)) continue;
      final displayName = peer.alias.isNotEmpty
          ? peer.alias
          : peer.username.isNotEmpty
              ? peer.username
              : peer.finalName();
      MeetingGroupStore.addMember(_group.meetingId, trimmed, displayName);
      added.add(peer);
    }
    if (added.isEmpty) {
      showToast(translate('Already a member'));
      return;
    }
    setState(() {});
    showToast('${translate('Added')} ${added.length} ${translate('members')}');

    // Group system message.
    final chatModel = _activeGroupChatModel();
    if (chatModel != null &&
        chatModel.currentKey.peerId == _group.conversationId) {
      chatModel.sendText(
          '${translate('System')}: ${added.length} ${translate('members joined the group')}');
    }

    // Notify each newly added member with a private invite message.
    for (final peer in added) {
      await _notifyFriendInvited(peer);
    }
  }

  /// Sends a private invite notice to [peer] by briefly switching to their
  /// conversation, then restoring the previous one.
  Future<void> _notifyFriendInvited(Peer peer) async {
    try {
      final chatModel = gFFI.chatModel;
      final originalKey = chatModel.currentKey;
      final friendKey = MessageKey(peer.id, ChatModel.clientModeID);
      chatModel.changeCurrentKey(friendKey);
      final body =
          '${translate('Meeting invite')}：${_group.hostDisplayName} ${translate('invited you to join')}《${_group.title}》';
      final link = _inviteLink;
      chatModel.sendText(link != null ? '$body\n$link' : body);
      chatModel.changeCurrentKey(originalKey);
    } catch (e) {
      debugPrint('meeting notify friend invite failed: $e');
    }
  }
}

class _MemberGridTile extends StatelessWidget {
  final String peerId;
  final String displayName;
  final bool isHost;
  final bool isPresenter;
  final bool online;
  final VoidCallback? onRemove;

  const _MemberGridTile({
    required this.peerId,
    required this.displayName,
    required this.isHost,
    this.isPresenter = false,
    this.online = false,
    this.onRemove,
  }) : _addOnTap = null;

  /// 微信风格“+”添加成员格子（仅 host 显示）。
  const _MemberGridTile.addTile({required VoidCallback onTap})
      : peerId = '',
        displayName = '',
        isHost = false,
        isPresenter = false,
        online = false,
        onRemove = null,
        _addOnTap = onTap;

  final VoidCallback? _addOnTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final avatarColor = isHost
        ? MyTheme.primarySoft
        : dark
            ? const Color(0xFF2B2D32)
            : const Color(0xFFF0F2F5);
    final avatarTextColor =
        isHost ? MyTheme.primary : dark ? Colors.white70 : Colors.black54;

    if (_addOnTap != null) {
      // “+”添加成员格子。
      return InkWell(
        onTap: _addOnTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: avatarColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.add_rounded,
                  size: 26, color: dark ? Colors.white54 : Colors.black38),
            ),
            const SizedBox(height: 6),
            Text(
              translate('Add'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: avatarColor,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: avatarTextColor,
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: online
                      ? const Color(0xFF07C160)
                      : dark
                          ? const Color(0xFF4A4F58)
                          : const Color(0xFFB8BEC7),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: dark ? MyTheme.surfaceDark : Colors.white,
                      width: 1.8),
                ),
              ),
            ),
            if (isHost)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: MyTheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    translate('Host'),
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (isPresenter && !isHost)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    translate('Presenter'),
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withOpacity(0.75),
          ),
        ),
        if (onRemove != null)
          GestureDetector(
            onTap: onRemove,
            child: Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                translate('Remove'),
                style: const TextStyle(
                    fontSize: 9, color: Color(0xFFFA5151)),
              ),
            ),
          ),
      ],
    );
  }
}


class _GroupPopupMenu extends StatelessWidget {
  final MeetingGroup group;
  final VoidCallback? onInviteGenerated;
  final VoidCallback? onInviteCopied;

  const _GroupPopupMenu({
    required this.group,
    this.onInviteGenerated,
    this.onInviteCopied,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) async {
        switch (action) {
          case 'generate_invite':
            onInviteGenerated?.call();
          case 'copy_invite':
            onInviteCopied?.call();
          case 'delete_group':
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text(translate('Delete group')),
                content:
                    Text(translate('Delete this meeting group permanently?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(translate('Cancel'))),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(translate('Delete'),
                        style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await MeetingGroupStore.remove(group.meetingId);
              if (context.mounted) Navigator.of(context).pop();
            }
        }
      },
      itemBuilder: (ctx) => [
        if (group.isHost)
          PopupMenuItem(
              value: 'generate_invite',
              child: Text(translate('Generate invite link'))),
        if (group.inviteShortCode.isNotEmpty)
          PopupMenuItem(
              value: 'copy_invite', child: Text(translate('Copy invite link'))),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete_group',
          child: Text(translate('Delete group'),
              style: const TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}
