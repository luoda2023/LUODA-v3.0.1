// LUODA 3.1.1 - WeChat-style contact picker for adding meeting members.
//
// Full-screen multi-select dialog with:
//   * a rounded search field,
//   * group tabs (All / Friends / Strangers),
//   * circular multi-select checkboxes,
//   * a bottom bar with the running selection count + confirm button.

import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';

import '../../common.dart';
import '../../models/peer_model.dart';
import '../direct_chat_policy.dart';

/// Opens the contact picker and resolves with the selected peers (or null
/// when the user cancels).
Future<List<Peer>?> showFriendPickerDialog(
  BuildContext context, {
  required List<Peer> peers,
  Set<String> excludePeerIds = const <String>{},
  String? title,
}) {
  return showDialog<List<Peer>>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _FriendPickerDialog(
      peers: peers,
      excludePeerIds: excludePeerIds,
      title: title,
    ),
  );
}

class _FriendPickerDialog extends StatefulWidget {
  const _FriendPickerDialog({
    required this.peers,
    required this.excludePeerIds,
    this.title,
  });

  final List<Peer> peers;
  final Set<String> excludePeerIds;
  final String? title;

  @override
  State<_FriendPickerDialog> createState() => _FriendPickerDialogState();
}

class _FriendPickerDialogState extends State<_FriendPickerDialog> {
  final Set<String> _selected = <String>{};
  String _query = '';
  int _tab = 0; // 0 = All, 1 = Friends, 2 = Strangers
  late final DirectChatAccessController _access =
      DirectChatAccessController.instance;

  static const _tabs = <String>['All', 'Friends', 'Strangers'];

  List<Peer> get _visiblePeers {
    final all = widget.peers
        .where((p) => !widget.excludePeerIds.contains(p.id.trim()))
        .where((p) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.finalName().toLowerCase().contains(q) ||
          p.id.toLowerCase().contains(q) ||
          p.username.toLowerCase().contains(q);
    }).toList();
    if (_tab == 0) return all;
    final isFriend = _tab == 1;
    return all
        .where((p) => _access.isFriend(p.id) == isFriend)
        .toList(growable: false);
  }

  void _toggle(String peerId) {
    setState(() {
      if (!_selected.remove(peerId)) _selected.add(peerId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = dark ? MyTheme.surfaceDark : Colors.white;
    final visible = _visiblePeers;

    return material.Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: surface,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(theme, dark),
            _buildSearchBar(theme, dark),
            _buildTabs(theme, dark),
            const Divider(height: 1, thickness: 0.5),
            Expanded(
              child: visible.isEmpty
                  ? _buildEmpty(theme)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: 72,
                        color: dark
                            ? const Color(0xFF2A2D33)
                            : const Color(0x0F000000),
                      ),
                      itemBuilder: (context, index) =>
                          _buildRow(theme, visible[index], dark),
                    ),
            ),
            _buildBottomBar(theme, dark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded,
                color: theme.colorScheme.onSurface, size: 22),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.title ?? translate('Choose from contacts'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              translate('Cancel'),
              style: const TextStyle(color: MyTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2D33) : const Color(0xFFF2F3F5),
          borderRadius: BorderRadius.circular(19),
        ),
        child: TextField(
          onChanged: (v) => setState(() => _query = v.trim()),
          style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: translate('Search contacts'),
            hintStyle: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
            prefixIcon: Icon(Icons.search_rounded,
                size: 20,
                color: theme.colorScheme.onSurface.withOpacity(0.4)),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 9),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs(ThemeData theme, bool dark) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tab = i),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        translate(_tabs[i]),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              _tab == i ? FontWeight.w700 : FontWeight.w500,
                          color: _tab == i
                              ? MyTheme.primary
                              : theme.colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 24,
                        height: 3,
                        decoration: BoxDecoration(
                          color: _tab == i ? MyTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(ThemeData theme, Peer peer, bool dark) {
    final isFriend = _access.isFriend(peer.id);
    final selected = _selected.contains(peer.id);
    final name = peer.finalName();
    return InkWell(
      onTap: () => _toggle(peer.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _avatar(peer, isFriend, dark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        peer.id,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                      if (peer.online) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: MyTheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isFriend)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: MyTheme.primarySoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    translate('Friends'),
                    style: const TextStyle(
                        fontSize: 10, color: MyTheme.primary),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            _checkbox(selected),
          ],
        ),
      ),
    );
  }

  Widget _avatar(Peer peer, bool isFriend, bool dark) {
    if (peer.avatar.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          peer.avatar,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatar(peer, isFriend),
        ),
      );
    }
    return _fallbackAvatar(peer, isFriend);
  }

  Widget _fallbackAvatar(Peer peer, bool isFriend) {
    final name = peer.finalName();
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isFriend ? MyTheme.primarySoft : const Color(0xFFE2E4E8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isFriend ? MyTheme.primary : const Color(0xFF8A9099),
          ),
        ),
      ),
    );
  }

  Widget _checkbox(bool selected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? MyTheme.primary : Colors.transparent,
        border: Border.all(
          color: selected ? MyTheme.primary : const Color(0xFFC8CCD2),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : null,
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline_rounded,
              size: 48, color: theme.colorScheme.onSurface.withOpacity(0.25)),
          const SizedBox(height: 8),
          Text(
            translate('No contacts to forward to'),
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme, bool dark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        color: dark ? MyTheme.surfaceDark : Colors.white,
        border: Border(
          top: BorderSide(
              color: dark ? const Color(0xFF2A2D33) : const Color(0x14000000)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selected.isEmpty
                    ? translate('Selected')
                    : '${translate('Selected')} ${_selected.length}',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MyTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(110, 40),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: _selected.isEmpty
                  ? null
                  : () {
                      final picked = widget.peers
                          .where((p) => _selected.contains(p.id))
                          .toList(growable: false);
                      Navigator.pop(context, picked);
                    },
              child: Text(
                '${translate('Confirm')}${_selected.isEmpty ? '' : '(${_selected.length})'}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
