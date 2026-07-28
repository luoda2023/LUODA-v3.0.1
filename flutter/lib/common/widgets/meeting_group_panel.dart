// LUODA 3.1.1 — Meeting group management panel.
//
// Provides: add/remove members, invite link generation & sharing,
// one-tap remote-assist join, member list with online indicators.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:uuid/uuid.dart';

import '../../common.dart';
import '../../desktop/pages/desktop_home_page.dart';
import '../../models/meeting_group_model.dart';
import '../../models/platform_model.dart';
import '../hbbs/hbbs.dart';

/// Full management panel for a single meeting group.
class MeetingGroupPanel extends StatefulWidget {
  final MeetingGroup group;
  const MeetingGroupPanel({super.key, required this.group});

  @override
  State<MeetingGroupPanel> createState() => _MeetingGroupPanelState();
}

class _MeetingGroupPanelState extends State<MeetingGroupPanel> {
  MeetingGroup get _group => widget.group;
  List<MeetingMember> get _members => _group.members ?? [];
  late final TextEditingController _titleCtrl;
  late final TextEditingController _addPeerCtrl;
  String? _inviteLink;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: _group.title);
    _addPeerCtrl = TextEditingController();
    _refreshInviteLink();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _addPeerCtrl.dispose();
    super.dispose();
  }

  void _refreshInviteLink() {
    if (_group.inviteShortCode.isNotEmpty) {
      _inviteLink = 'luoda://meeting/${_group.meetingId}?code=${_group.inviteShortCode}&host=${_group.hostPeerId}';
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
    final rand = List.generate(6, (_) => chars[DateTime.now().microsecond % chars.length]);
    // Shuffle with microseconds
    final r = (DateTime.now().microsecondsSinceEpoch % 100000).toString();
    return '${rand.join()}${r.substring(0, 2)}';
  }

  Future<void> _addMember(String peerId) async {
    final trimmed = peerId.trim();
    if (trimmed.isEmpty) return;
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
    _group.members ??= [];
    _group.members!.add(MeetingMember(
      peerId: trimmed,
      displayName: displayName,
      joinedAt: DateTime.now().toUtc(),
    ));
    await MeetingGroupStore.save();
    _addPeerCtrl.clear();
    setState(() {});
    // Also send a system message in the group chat
    final chatModel = _activeGroupChatModel();
    if (chatModel != null) {
      final key = chatModel.currentKey;
      if (key.peerId == _group.conversationId) {
        chatModel.sendText('${translate('System')}: $displayName ${translate('joined the group')}');
      }
    }
  }

  Future<void> _removeMember(MeetingMember member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(translate('Remove member')),
        content: Text('${translate('Remove')} ${member.displayName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(translate('Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(translate('Remove'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    _group.members!.removeWhere((m) => m.peerId == member.peerId);
    await MeetingGroupStore.save();
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isHost = _group.isHost;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _titleCtrl,
          style: Theme.of(context).textTheme.titleMedium,
          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Group name'),
          enabled: isHost,
          onSubmitted: (v) async {
            _group.title = v.trim().isNotEmpty ? v.trim() : _group.title;
            await MeetingGroupStore.save();
          },
        ),
        actions: [
          if (_group.hasActiveSession)
            IconButton(
              tooltip: translate('Join remote session'),
              icon: const Icon(Icons.desktop_windows_rounded),
              color: Theme.of(context).colorScheme.primary,
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
          // Invite link section
          if (isHost)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1E232B) : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _inviteLink == null
                        ? TextButton.icon(
                            icon: const Icon(Icons.add_link_rounded, size: 18),
                            label: Text(translate('Generate invite link')),
                            onPressed: _generateInvite,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                translate('Invite link'),
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _inviteLink!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                  ),
                  if (_inviteLink != null) ...[
                    IconButton(
                      tooltip: translate('Copy link'),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: _copyInviteLink,
                    ),
                    IconButton(
                      tooltip: translate('Share to chat'),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      onPressed: () => _shareToChat(''),
                    ),
                  ],
                ],
              ),
            ),
          // Active session banner
          if (_group.hasActiveSession)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.desktop_windows_rounded,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      translate('Host is sharing screen — tap to view'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    onPressed: _joinRemoteSession,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // Section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${translate('Members')} (${_members.length + 1})',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          // Member list
          Expanded(
            child: ListView(
              children: [
                // Host
                _MemberTile(
                  peerId: _group.hostPeerId,
                  displayName: _group.hostDisplayName,
                  isHost: true,
                  joinedAt: _group.createdAt,
                  onRemove: null,
                ),
                // Members
                ..._members.map((m) => _MemberTile(
                      peerId: m.peerId,
                      displayName: m.displayName,
                      isHost: false,
                      joinedAt: m.joinedAt,
                      onRemove: isHost ? () => _removeMember(m) : null,
                    )),
              ],
            ),
          ),
          // Add member bar (host only)
          if (isHost)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addPeerCtrl,
                        decoration: InputDecoration(
                          hintText: translate('Enter peer ID or name'),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onSubmitted: (v) => _addMember(v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.person_add_rounded, size: 20),
                      onPressed: () => _addMember(_addPeerCtrl.text),
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

class _MemberTile extends StatelessWidget {
  final String peerId;
  final String displayName;
  final bool isHost;
  final DateTime joinedAt;
  final VoidCallback? onRemove;

  const _MemberTile({
    required this.peerId,
    required this.displayName,
    required this.isHost,
    required this.joinedAt,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final online = gFFI.serverModel.clients.any(
      (c) => c.peerId == peerId && c.authorized && !c.disconnected,
    );
    return ListTile(
      leading: Badge(
        isLabelVisible: online,
        backgroundColor: const Color(0xFF07C160),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: isHost
              ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
              : dark
                  ? const Color(0xFF2B2D32)
                  : const Color(0xFFE8E8E8),
          child: Text(
            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isHost
                  ? Theme.of(context).colorScheme.primary
                  : dark
                      ? Colors.white70
                      : Colors.black54,
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          if (isHost)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  translate('Host'),
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${translate('Joined')}: ${_formatDate(joinedAt)}${online ? ' · ${translate('Online')}' : ''}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: onRemove != null
          ? IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
              color: Colors.red.withOpacity(0.6),
              onPressed: onRemove,
            )
          : null,
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
                title: Text(translate('Delete group')),
                content: Text(translate('Delete this meeting group permanently?')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(translate('Cancel'))),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(translate('Delete'), style: const TextStyle(color: Colors.red)),
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
          PopupMenuItem(value: 'generate_invite', child: Text(translate('Generate invite link'))),
        if (group.inviteShortCode.isNotEmpty)
          PopupMenuItem(value: 'copy_invite', child: Text(translate('Copy invite link'))),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete_group',
          child: Text(translate('Delete group'), style: const TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}
