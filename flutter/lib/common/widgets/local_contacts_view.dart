import 'dart:async';

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/chat_model.dart';
import '../../mobile/pages/home_page.dart';
import '../../mobile/pages/scan_page.dart';
import '../direct_chat_policy.dart';
import '../direct_pairing.dart';
import '../wechat_ui_tokens.dart';
import 'direct_connection_details.dart';

/// 本地（点聊/DotChat）联系人列表。
///
/// 同一设备（同一指纹或同一会话 id）的多条配对记录合并显示为一个联系人；
/// 好友 / 陌生人按消息访问策略分组展示。
class LocalContactsView extends StatefulWidget {
  const LocalContactsView({super.key});

  @override
  State<LocalContactsView> createState() => _LocalContactsViewState();
}

class _LocalContact {
  _LocalContact({required this.peerId});

  final String peerId;
  final List<DirectPairing> devices = <DirectPairing>[];

  DirectPairing get latest => devices.reduce(
        (current, candidate) => candidate.updatedAt.isAfter(current.updatedAt)
            ? candidate
            : current,
      );

  String get name {
    final pairing = latest;
    if (pairing.displayName.isNotEmpty) return pairing.displayName;
    if (pairing.deviceName.isNotEmpty) return pairing.deviceName;
    return peerId;
  }

  String get deviceSummary {
    final labels = <String>[];
    final mobile = devices.any((pairing) {
      final platform = pairing.platform.toLowerCase();
      return platform.contains('android') ||
          platform.contains('ios') ||
          platform.contains('phone');
    });
    final desktop = devices.any((pairing) {
      final platform = pairing.platform.toLowerCase();
      return platform.contains('windows') ||
          platform.contains('linux') ||
          platform.contains('mac') ||
          platform.contains('desktop');
    });
    if (desktop) labels.add(translate('Desktop'));
    if (mobile) labels.add(translate('Mobile'));
    if (labels.isEmpty && devices.length > 1) {
      labels.add('${devices.length} ${translate('devices')}');
    }
    return labels.join(' · ');
  }

  void addDevice(DirectPairing pairing) {
    final fingerprint = pairing.fingerprint
        .toLowerCase()
        .replaceAll(':', '')
        .replaceAll(' ', '');
    final existingIndex = fingerprint.isEmpty
        ? devices.indexWhere((item) => item.peerId == pairing.peerId)
        : devices.indexWhere(
            (item) =>
                item.fingerprint
                    .toLowerCase()
                    .replaceAll(':', '')
                    .replaceAll(' ', '') ==
                fingerprint,
          );
    if (existingIndex < 0) {
      devices.add(pairing);
    } else if (pairing.updatedAt.isAfter(devices[existingIndex].updatedAt)) {
      devices[existingIndex] = pairing;
    }
  }
}

class _LocalContactsViewState extends State<LocalContactsView> {
  List<_LocalContact> _contacts = const <_LocalContact>[];

  @override
  void initState() {
    super.initState();
    DirectPairingStore.revision.addListener(_reload);
    gFFI.serverModel.addListener(_reload);
    // 先基于当前配对快照重建联系人列表。
    _rebuild();
    // 再异步过滤掉本机自身的配对。
    unawaited(_filterSelf());
  }

  @override
  void dispose() {
    DirectPairingStore.revision.removeListener(_reload);
    gFFI.serverModel.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(_rebuild);
  }

  void _rebuild() {
    final groups = <String, _LocalContact>{};
    final fingerprintKeys = <String, String>{};
    for (final pairing in DirectPairingStore.load().values) {
      if (pairing.companion) continue;
      final pid = pairing.peerId.trim();
      if (pid.isEmpty || pid == kFileHelperId) continue;
      final conversationId = pairing.conversationId.trim().isEmpty
          ? pid
          : pairing.conversationId.trim();
      final fingerprint = pairing.fingerprint
          .toLowerCase()
          .replaceAll(':', '')
          .replaceAll(' ', '');
      final knownKey =
          fingerprint.isEmpty ? null : fingerprintKeys[fingerprint];
      final key = knownKey ?? conversationId;
      final group = groups.putIfAbsent(
        key,
        () => _LocalContact(peerId: key),
      );
      group.addDevice(pairing);
      if (fingerprint.isNotEmpty) fingerprintKeys[fingerprint] = key;
    }
    final contacts = groups.values.toList(growable: false);
    contacts.sort((a, b) {
      return b.latest.updatedAt.compareTo(a.latest.updatedAt);
    });
    _contacts = contacts;
  }

  /// 从列表中过滤掉指向本机自身的配对。
  Future<void> _filterSelf() async {
    if (_contacts.isEmpty) return;
    try {
      final removeIds = <String>{};
      for (final contact in _contacts) {
        if (await DirectPairingStore.isSelfTarget(contact.peerId)) {
          removeIds.add(contact.peerId);
        }
      }
      if (removeIds.isEmpty || !mounted) return;
      setState(() {
        _contacts = _contacts
            .where((contact) => !removeIds.contains(contact.peerId))
            .toList();
      });
    } catch (_) {}
  }

  bool _isOnline(String peerId) {
    final ids = DirectPairingStore.conversationPeerIds(peerId);
    return gFFI.serverModel.clients.any((client) =>
        client.authorized &&
        !client.disconnected &&
        client.isChat &&
        ids.contains(client.peerId));
  }

  void _openChat(_LocalContact contact) {
    final peerId = contact.peerId;
    if (peerId == kFileHelperId) {
      gFFI.chatModel.changeCurrentKey(gFFI.chatModel.fileHelperKey);
      HomePage.homeKey.currentState?.selectChatPage();
      return;
    }
    final pairing = contact.latest;
    gFFI.chatModel.changeCurrentKey(MessageKey(peerId, ChatModel.clientModeID));
    gFFI.chatModel.updatePeerIdentity(
      peerId,
      displayName: pairing.displayName.isEmpty
          ? pairing.deviceName
          : pairing.displayName,
      avatar: pairing.avatar,
    );
    HomePage.homeKey.currentState?.selectChatPage();
    unawaited(gFFI.chatModel.ensureChatConnection?.call(peerId));
  }

  @override
  Widget build(BuildContext context) {
    if (_contacts.isEmpty) {
      return _buildEmpty(context);
    }
    DirectChatAccessController.instance.load();
    final friends = <_LocalContact>[];
    final strangers = <_LocalContact>[];
    for (final contact in _contacts) {
      if (DirectChatAccessController.instance.isFriend(contact.peerId)) {
        friends.add(contact);
      } else {
        strangers.add(contact);
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: <Widget>[
        if (friends.isNotEmpty) ...<Widget>[
          _buildGroupHeader(context, 'Friends', friends.length),
          for (final contact in friends) _buildRow(context, contact),
        ],
        if (strangers.isNotEmpty) ...<Widget>[
          _buildGroupHeader(context, 'Strangers', strangers.length),
          for (final contact in strangers) _buildRow(context, contact),
        ],
      ],
    );
  }

  Widget _buildGroupHeader(BuildContext context, String label, int count) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? MyTheme.mutedDark
        : MyTheme.mutedLight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: <Widget>[
          Text(
            translate(label),
            style: TextStyle(
              fontSize: MobileText.caption,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: MobileText.captionSm,
              color: muted.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.people_outline_rounded,
              size: 52, color: theme.colorScheme.outline.withOpacity(0.6)),
          const SizedBox(height: 12),
          Text(
            translate('No local contacts yet'),
            style: TextStyle(
              fontSize: MobileText.bodyLg,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            translate('Scan the other side\'s QR code or enter ID / IP to add'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: MobileText.caption,
              color: theme.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ScanPage(),
                  ),
                );
              },
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: Text(translate('Add contact')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, _LocalContact contact) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final online = _isOnline(contact.peerId);
    final isFriend =
        DirectChatAccessController.instance.isFriend(contact.peerId);
    final routeLabel = directConnectionRouteLabel(contact.peerId);
    final deviceSummary = contact.deviceSummary;
    final subtitle =
        deviceSummary.isEmpty ? routeLabel : '$deviceSummary · $routeLabel';
    // Material ancestor is required for InkWell's grey tap highlight to
    // actually render — this list sits on a bare ColoredBox, so without
    // this wrapper the WeChat-style press feedback never appears.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openChat(contact),
        highlightColor:
            dark ? const Color(0xFF34373D) : const Color(0xFFE5E8E6),
        splashColor: Colors.transparent,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
              child: Row(
                children: <Widget>[
                  _buildAvatar(context, contact, online),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                contact.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: MobileText.bodyLg + 1,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildCategoryBadge(context,
                                isFriend: isFriend, online: online),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: MobileText.caption,
                            color: dark
                                ? MyTheme.mutedDark.withOpacity(0.7)
                                : const Color(0xFF667085),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: translate('Connection & identity'),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => showDirectConnectionDetails(
                      context,
                      conversationId: contact.peerId,
                    ),
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurface.withOpacity(0.45),
                    ),
                  ),
                ],
              ),
            ),
            // WeChat-style hairline: starts at the avatar right edge so no
            // line crosses the avatar (avatar top/bottom stay clean).
            Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 76),
              color: dark ? const Color(0xFF3A3D43) : const Color(0x80E5E5E5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    _LocalContact contact,
    bool online,
  ) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final pairing = contact.latest;
    final initial = contact.name.trim().isEmpty
        ? '?'
        : contact.name.trim().characters.first.toUpperCase();
    final fallback = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: str2color(contact.name),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
    final avatar = buildAvatarWidget(
          avatar: pairing.avatar,
          size: 48,
          borderRadius: 8,
          fallback: fallback,
        ) ??
        fallback;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        avatarWithPlatformBadge(
          child: avatar,
          platform: pairing.platform,
          badgeSize: 15,
          // WeChat-style OS indicator on the avatar's top-right corner,
          // clear of the online dot at the bottom-right.
          topRight: true,
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online
                  ? const Color(0xFF2BB673)
                  : dark
                      ? const Color(0xFF6B7280)
                      : const Color(0xFFC6CBD4),
              border: Border.all(color: theme.colorScheme.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBadge(
    BuildContext context, {
    required bool isFriend,
    required bool online,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final Color bg;
    final Color fg;
    if (isFriend) {
      bg = dark ? const Color(0xFF123B27) : const Color(0xFFE6F7EE);
      fg = dark ? const Color(0xFF53D98A) : const Color(0xFF07A457);
    } else {
      bg = dark ? const Color(0xFF2A2F38) : const Color(0xFFF2F3F5);
      fg = dark ? MyTheme.mutedDark : const Color(0xFF6B7280);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? const Color(0xFF2BB673) : fg.withOpacity(0.6),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            translate(isFriend ? 'Friend' : 'Stranger'),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
