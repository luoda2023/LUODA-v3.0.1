// LUODA 3.1.1 - Meeting group management panel.
//
// Provides: add/remove members, invite link generation & sharing,
// one-tap remote-assist join, member list with online indicators.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/chat_model.dart';

import '../../models/meeting_group_model.dart';

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

  @override
  void initState() {
    super.initState();
    _addPeerCtrl = TextEditingController();
    _refreshInviteLink();
  }

  @override
  void dispose() {
    _addPeerCtrl.dispose();
    super.dispose();
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
    if (!_group.hasActiveSession || _group.activeSessionEndpoint.isEmpty) {
      showToast(translate('No active session'));
      return;
    }
    // Navigate to connect with the active session endpoint
    connect(context, _group.activeSessionEndpoint,
        isFileTransfer: false, isViewCamera: false, isTerminal: false);
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
            border: const OutlineInputBorder(),
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
      backgroundColor: dark ? MyTheme.canvasDark : const Color(0xFFF5F6F7),
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 46,
        elevation: 0,
        backgroundColor: dark ? MyTheme.surfaceDark : const Color(0xFFEDEDED),
        title: Text(
          _group.title,
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _buildMeetingCard(context, isHost),
                const SizedBox(height: 14),
                if (isHost) ...[
                  _buildInviteCard(context, surface, border),
                  const SizedBox(height: 14),
                ],
                if (_group.hasActiveSession) ...[
                  _buildActiveSessionBanner(context, theme),
                  const SizedBox(height: 14),
                ],
                _buildMembersCard(context, surface, border),
                const SizedBox(height: 24),
              ],
            ),
          ),
          if (isHost) _buildAddMemberBar(context, surface, border),
        ],
      ),
    );
  }

  Widget _buildMeetingCard(BuildContext context, bool isHost) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0FAF57), Color(0xFF07C160)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF07C160).withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.videocam_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _group.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      translate('Meeting details'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
              if (isHost)
                InkWell(
                  onTap: _editTitle,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _heroChip(
                  icon: Icons.person_rounded,
                  label: _group.hostDisplayName,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _heroChip(
                  icon: Icons.people_alt_rounded,
                  label: '${translate('Members')} ${_members.length + 1}',
                ),
              ),
              if (_group.inviteShortCode.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _heroChip(
                    icon: Icons.tag_rounded,
                    label: _group.inviteShortCode,
                    onTap: _group.inviteShortCode.isNotEmpty
                        ? _copyInviteLink
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCard(BuildContext context, Color surface, Color border) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border.withOpacity(0.6)),
      ),
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
    final members = _members;
    final active = _group.hasActiveSession;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border.withOpacity(0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
                    '${members.length + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: MyTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
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
          Divider(
              height: 1,
              thickness: 0.5,
              color: dark ? const Color(0xFF3A3D43) : const Color(0x80E5E5E5)),
          _MemberTile(
            peerId: _group.hostPeerId,
            displayName: _group.hostDisplayName,
            isHost: true,
            joinedAt: _group.createdAt,
            onRemove: null,
            showDivider: members.isNotEmpty,
          ),
          for (var i = 0; i < members.length; i++)
            _MemberTile(
              peerId: members[i].peerId,
              displayName: members[i].displayName,
              isHost: false,
              joinedAt: members[i].joinedAt,
              onRemove: _group.isHost ? () => _removeMember(members[i]) : null,
              showDivider: i < members.length - 1,
            ),
        ],
      ),
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
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addPeerCtrl,
                decoration: InputDecoration(
                  hintText: translate('Enter peer ID or name'),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onSubmitted: (v) => _addMember(v),
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
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final String peerId;
  final String displayName;
  final bool isHost;
  final DateTime joinedAt;
  final VoidCallback? onRemove;
  final bool showDivider;

  const _MemberTile({
    required this.peerId,
    required this.displayName,
    required this.isHost,
    required this.joinedAt,
    this.onRemove,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final border = dark ? MyTheme.borderDark : MyTheme.borderLight;
    final online = gFFI.serverModel.clients.any(
      (c) => c.peerId == peerId && c.authorized && !c.disconnected,
    );
    final avatarColor = isHost
        ? MyTheme.primarySoft
        : dark
            ? const Color(0xFF2B2D32)
            : const Color(0xFFE8E8E8);
    final avatarTextColor =
        isHost ? MyTheme.primary : dark ? Colors.white70 : Colors.black54;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: avatarColor,
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: avatarTextColor,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: online
                            ? const Color(0xFF07C160)
                            : dark
                                ? const Color(0xFF4A4F58)
                                : const Color(0xFFB8BEC7),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: dark
                                ? MyTheme.surfaceDark
                                : Colors.white,
                            width: 1.6),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isHost) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: MyTheme.primarySoft,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              translate('Host'),
                              style: const TextStyle(
                                fontSize: 10,
                                color: MyTheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${translate('Joined')} ${_formatDate(joinedAt)}'
                      '${online ? '  \u2022  ${translate('Online')}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: translate('Remove'),
                  icon: const Icon(Icons.remove_circle_outline_rounded,
                      size: 20),
                  color: Colors.red.withOpacity(0.6),
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 52,
            endIndent: 0,
            color: border.withOpacity(0.55),
          ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
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
