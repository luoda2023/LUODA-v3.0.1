// LUODA 3.1.1 - Meeting group member browser dialog.
//
// WeChat-style "chat info" sheet for a meeting group chat window:
// shows every participant (host + members), role badge, online state,
// joined time, with search. The host can remove members and dissolve
// the group right from this dialog.

import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart' hide Dialog;

import '../../models/meeting_group_model.dart';

/// Open the member browser for [group].
///
/// Returns `true` if the group was dissolved (so callers can tear down
/// the open chat window), `false`/`null` otherwise.
Future<bool?> showMeetingMembersDialog(
  BuildContext context,
  MeetingGroup group,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => MeetingMembersDialog(group: group),
  );
}

class MeetingMembersDialog extends StatefulWidget {
  final MeetingGroup group;
  const MeetingMembersDialog({super.key, required this.group});

  @override
  State<MeetingMembersDialog> createState() => _MeetingMembersDialogState();
}

class _MeetingMembersDialogState extends State<MeetingMembersDialog> {
  MeetingGroup get _group => widget.group;
  bool get _isHost => _group.isHost;
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isOnline(String peerId) {
    if (peerId == gFFI.serverModel.id) return true;
    return gFFI.serverModel.clients
        .any((c) => c.peerId == peerId && c.authorized && !c.disconnected);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _removeMember(MeetingMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(translate('Remove member')),
        content:
            Text('${translate('Remove')} ${member.displayName} '
                '${translate('from the group')}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(translate('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(translate('Remove'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    MeetingGroupStore.removeMember(_group.meetingId, member.peerId);
    setState(() {});
    showToast('${member.displayName} ${translate('removed')}');
  }

  Future<void> _dissolveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(translate('Dissolve meeting')),
        content: Text(translate('Dissolve group hint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(translate('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(translate('Dissolve'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await MeetingGroupStore.remove(_group.meetingId);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = dark ? MyTheme.surfaceDark : Colors.white;
    final border = dark ? MyTheme.borderDark : MyTheme.borderLight;
    final q = _query.trim().toLowerCase();

    final host = MeetingMember(
      peerId: _group.hostPeerId,
      displayName: _group.hostDisplayName.isNotEmpty
          ? _group.hostDisplayName
          : translate('Host'),
      joinedAt: _group.createdAt,
    );
    final members = (_group.members ?? [])
        .where((m) => m.peerId != _group.hostPeerId)
        .where((m) =>
            q.isEmpty ||
            m.displayName.toLowerCase().contains(q) ||
            m.peerId.toLowerCase().contains(q))
        .toList();
    final total = (_group.members?.length ?? 0) + 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: group title + member count + close.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _group.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          translate('Members') + ' ($total)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: translate('Close'),
                    icon: const Icon(Icons.close_rounded, size: 22),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            // Search field.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: translate('Search members'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: dark
                      ? const Color(0xFF2A2C31)
                      : const Color(0xFFF2F2F3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            Divider(height: 1, color: border.withOpacity(0.6)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  _MemberRow(
                    member: host,
                    isHost: true,
                    online: true,
                    canRemove: false,
                  ),
                  for (final m in members)
                    _MemberRow(
                      member: m,
                      isHost: false,
                      online: _isOnline(m.peerId),
                      canRemove: _isHost,
                      onRemove: () => _removeMember(m),
                    ),
                  if (members.isEmpty && q.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Text(
                          translate('No members found'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.45),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: border.withOpacity(0.6)),
            // Footer actions.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  if (_isHost)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(
                            color: Colors.red.withOpacity(0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _dissolveGroup,
                        icon: const Icon(Icons.delete_forever_rounded, size: 18),
                        label: Text(translate('Dissolve meeting')),
                      ),
                    )
                  else
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: MyTheme.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${translate('Members')}: $total  ·  '
                          '${translate('Host')}: ${_group.hostDisplayName}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: MyTheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
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
}

class _MemberRow extends StatelessWidget {
  final MeetingMember member;
  final bool isHost;
  final bool online;
  final bool canRemove;
  final VoidCallback? onRemove;

  const _MemberRow({
    required this.member,
    required this.isHost,
    required this.online,
    required this.canRemove,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final avatarColor = isHost
        ? MyTheme.primarySoft
        : dark
            ? const Color(0xFF2B2D32)
            : const Color(0xFFE8E8E8);
    final avatarTextColor =
        isHost ? MyTheme.primary : dark ? Colors.white70 : Colors.black54;
    final name = member.displayName.isNotEmpty
        ? member.displayName
        : member.peerId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: avatarColor,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 15,
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
                        color: dark ? MyTheme.surfaceDark : Colors.white,
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
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isHost
                            ? MyTheme.primarySoft
                            : dark
                                ? const Color(0xFF33363C)
                                : const Color(0xFFF0F1F2),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        translate(isHost ? 'Host' : 'Member'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isHost
                              ? MyTheme.primary
                              : theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${online ? translate('Online') : translate('Offline')}'
                  '  ·  ${translate('Joined')} '
                  '${_formatJoined(member.joinedAt)}'
                  '${isHost ? '' : '  ·  ${member.peerId}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.45),
                  ),
                ),
              ],
            ),
          ),
          if (canRemove)
            IconButton(
              tooltip: translate('Remove'),
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
              color: Colors.red.withOpacity(0.6),
              onPressed: onRemove,
            ),
          if (isHost && !canRemove)
            Icon(
              Icons.admin_panel_settings_outlined,
              size: 18,
              color: MyTheme.primary.withOpacity(0.7),
            ),
        ],
      ),
    );
  }
}

String _formatJoined(DateTime joinedAt) {
  final local = joinedAt.toLocal();
  final now = DateTime.now();
  final sameYear = local.year == now.year;
  final two = (int v) => v.toString().padLeft(2, '0');
  if (sameYear) {
    return '${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
