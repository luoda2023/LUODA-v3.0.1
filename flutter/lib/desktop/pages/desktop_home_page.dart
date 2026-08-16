import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:luoda_flutter/common.dart';
import '../../runtime_logger.dart';
import 'package:luoda_flutter/common/widgets/animated_rotation_widget.dart';
import 'package:luoda_flutter/common/widgets/ai_config_page.dart';
import 'package:luoda_flutter/common/widgets/chat_page.dart';
import 'package:luoda_flutter/common/widgets/direct_connection_details.dart';
import 'package:luoda_flutter/common/widgets/favorites_page.dart';
import 'package:luoda_flutter/common/widgets/friend_picker_dialog.dart';
import 'package:luoda_flutter/common/widgets/join_viewer_page.dart';
import 'package:luoda_flutter/common/widgets/custom_password.dart';
import 'package:luoda_flutter/common/widgets/dialog.dart';
import 'package:luoda_flutter/common/widgets/peer_tab_page.dart';
import 'package:luoda_flutter/common/widgets/vip_features_page.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/desktop/pages/connection_page.dart';
import 'package:luoda_flutter/desktop/pages/desktop_setting_page.dart';
import 'package:luoda_flutter/desktop/pages/desktop_tab_page.dart';
import 'package:luoda_flutter/desktop/widgets/update_progress.dart';
import 'package:luoda_flutter/desktop/widgets/screenshot_annotator.dart';
import 'package:luoda_flutter/desktop/widgets/desktop_primary_rail.dart';
import 'package:luoda_flutter/mobile/pages/bt_chat_page.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:luoda_flutter/models/meeting_group_model.dart';
import 'package:luoda_flutter/common/widgets/meeting_group_panel.dart';
import 'package:luoda_flutter/common/widgets/meeting_members_dialog.dart';
import 'package:luoda_flutter/models/contact_category_model.dart';
import 'package:luoda_flutter/models/file_model.dart';
import 'package:luoda_flutter/models/model.dart';
import 'package:luoda_flutter/models/peer_model.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:luoda_flutter/models/server_model.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:luoda_flutter/native/screen_capture.dart';
import 'package:luoda_flutter/plugin/ui_manager.dart';
import 'package:luoda_flutter/utils/multi_window_manager.dart';
import 'package:luoda_flutter/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../clipboard_image_probe.dart';
import '../widgets/button.dart';
import '../../common/direct_chat.dart';
import '../../common/join_meeting_session.dart';
import '../../common/direct_chat_policy.dart';
import '../../common/system_announcement.dart';
import '../../common/direct_pairing.dart';
import '../../common/direct_viewer_invite.dart';
import '../../common/wechat_ui_tokens.dart';

class DesktopHomePage extends StatefulWidget {
  /// 是否为纯客户端（仅控制端，不接收远程控制）
  final bool isClientOnly;
  static final GlobalKey<_DesktopHomePageState> _pageKey =
      GlobalKey<_DesktopHomePageState>();
  static Key get pageKey => _pageKey;

  const DesktopHomePage({Key? key, this.isClientOnly = false})
      : super(key: key);

  static Future<void> selectSection(String section) async {
    await _pageKey.currentState?._selectSection(section);
  }

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

enum _ConversationAction { fileTransfer, remoteAssist, camera, terminal, port, meetingManage, joinSession, copyInvite }

enum _WorkspaceNoticeTone { info, success, warning, error }

class _PeopleGroupHeader {
  const _PeopleGroupHeader(this.label, this.count);

  final String label;
  final int count;
}

String _normalizePeerFingerprint(String value) =>
    value.toLowerCase().replaceAll(':', '').replaceAll(' ', '').trim();

bool _isMobilePeerPlatform(String platform) {
  final p = platform.toLowerCase();
  return p.contains('android') || p.contains('ios') || p.contains('phone');
}

/// Normalize a mobile device name so that reinstalls of the same physical
/// phone (which generate a brand-new id) can be merged into one person.
String? _normalizeMobileDeviceName(String value) {
  final v = value.trim().toLowerCase();
  if (v.isEmpty) return null;
  if (v == 'android' || v == 'localhost' || v == 'unknown' || v == 'phone') {
    return null;
  }
  final sig = v.replaceAll(RegExp(r'[\s:._\-]+'), '');
  return sig.length < 4 ? null : sig;
}

String? _mobileDeviceSignatureFromPeer(Peer peer) {
  if (!_isMobilePeerPlatform(peer.platform)) return null;
  final raw =
      peer.hostname.trim().isNotEmpty ? peer.hostname : peer.displayName.trim();
  return _normalizeMobileDeviceName(raw);
}

String? _mobileDeviceSignatureFromPairing(DirectPairing pairing) {
  if (!_isMobilePeerPlatform(pairing.platform)) return null;
  return _normalizeMobileDeviceName(pairing.deviceName);
}

String _peerDeviceName(Peer peer) {
  final h = peer.hostname.trim();
  if (h.isNotEmpty) return h;
  final d = peer.displayName.trim();
  return (d.isNotEmpty && d != 'android') ? d : '';
}

/// Contact "person group": merges all devices of one person (PC, phone, and
/// reinstalled ids that share the same physical device) into a single row.
/// ????? ID ??????????/??????????ID ??????????
bool _isIdLikeDeviceName(String name, String personKey) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed.toLowerCase() == personKey.trim().toLowerCase()) return true;
  final compact = trimmed.replaceAll(RegExp(r'[\s:\-_.]'), '');
  return RegExp(r'^[0-9]{3,}$').hasMatch(compact);
}

/// ???????????/???????????ID ????????????
/// peerId?????????ID ??????????
String _resolveConversationDisplayName(
  String peerId, {
  String contactName = '',
  String chatName = '',
  String idFallback = '',
}) {
  final candidates = <String>[
    contactName.trim(),
    DirectPairingStore.findForConversation(peerId)?.displayName.trim() ?? '',
    chatName.trim(),
  ];
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    final compact = candidate.replaceAll(RegExp(r'[\s:\-_.]'), '');
    final isIdLike =
        compact == peerId.trim().replaceAll(RegExp(r'[\s:\-_.]'), '') ||
            RegExp(r'^[0-9]{3,}$').hasMatch(compact);
    if (!isIdLike) return candidate;
  }
  return idFallback.trim();
}

class _DesktopPersonGroup {
  _DesktopPersonGroup(this.key);

  /// Conversation identity: accountId when bound, otherwise the device id.
  final String key;
  final List<DirectPairing> devices = <DirectPairing>[];
  final List<Peer> peers = <Peer>[];
  final Map<String, int> _fingerprintIndex = <String, int>{};

  bool get isMobile =>
      devices.any((d) => _isMobilePeerPlatform(d.platform)) ||
      peers.any((p) => _isMobilePeerPlatform(p.platform));

  bool get isDesktop =>
      devices.any((d) => !_isMobilePeerPlatform(d.platform)) ||
      peers.any((p) => !_isMobilePeerPlatform(p.platform));

  void addPairing(DirectPairing pairing) {
    final fp = _normalizePeerFingerprint(pairing.fingerprint);
    if (fp.isNotEmpty) {
      final index = _fingerprintIndex[fp];
      if (index != null) {
        if (pairing.updatedAt.isAfter(devices[index].updatedAt)) {
          devices[index] = pairing;
        }
        return;
      }
      _fingerprintIndex[fp] = devices.length;
    }
    devices.add(pairing);
  }

  void addPeer(Peer peer) => peers.add(peer);

  DirectPairing? get primaryPairing {
    if (devices.isEmpty) return null;
    final sorted = List<DirectPairing>.of(devices)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted.first;
  }

  Peer? get primaryPeer {
    if (peers.isEmpty) return null;
    final sorted = List<Peer>.of(peers);
    sorted.sort((a, b) {
      final aOnline = a.online ? 1 : 0;
      final bOnline = b.online ? 1 : 0;
      if (aOnline != bOnline) return bOnline - aOnline;
      final aInfo = (a.hostname.isNotEmpty || a.displayName.isNotEmpty) ? 1 : 0;
      final bInfo = (b.hostname.isNotEmpty || b.displayName.isNotEmpty) ? 1 : 0;
      return bInfo - aInfo;
    });
    return sorted.first;
  }

  String get primaryPeerId => primaryPairing?.peerId ?? primaryPeer?.id ?? key;

  int get deviceCount => devices.length + peers.length;

  String get deviceSummary {
    final parts = <String>[];
    if (isMobile) parts.add(translate('Mobile'));
    if (isDesktop) parts.add(translate('Desktop'));
    final names = <String>{
      for (final d in devices)
        if (d.deviceName.trim().isNotEmpty &&
            !_isIdLikeDeviceName(d.deviceName, key))
          d.deviceName.trim(),
      for (final p in peers)
        if (_peerDeviceName(p).isNotEmpty &&
            !_isIdLikeDeviceName(_peerDeviceName(p), key))
          _peerDeviceName(p),
    }.toList();
    if (names.isNotEmpty) parts.addAll(names.take(2));
    if (parts.isEmpty && deviceCount > 1) {
      parts.add('${deviceCount} ${translate('devices')}');
    }
    return parts.join(' · ');
  }
}

/// Chat conversation "person group": one row for all device conversations of
/// the same person.
class _ChatPersonGroup {
  _ChatPersonGroup(this.key);

  final String key;
  final List<MapEntry<MessageKey, MessageBody>> conversations =
      <MapEntry<MessageKey, MessageBody>>[];

  /// 组内最新一条消息的时间，用于统一列表按时间排序。
  DateTime get lastMessageTime {
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final entry in conversations) {
      final t = _latestConversationTime(entry);
      if (t.isAfter(latest)) latest = t;
    }
    return latest;
  }
}

DateTime _latestConversationTime(MapEntry<MessageKey, MessageBody> entry) {
  final messages = entry.value.chatMessages;
  if (messages.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
  return messages
      .map((message) => message.createdAt)
      .reduce((latest, value) => value.isAfter(latest) ? value : latest);
}

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  Timer? _directChatKeepAliveTimer;
  static const List<Duration> _backgroundChatRetryDelays = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];
  final Map<String, int> _backgroundChatFailures = <String, int>{};
  final Map<String, DateTime> _backgroundChatRetryAfter = <String, DateTime>{};
  bool _refreshingDirectSessions = false;
  bool isCardClosed = false;
  String _lastIp = '';
  String _lastLanIp = '';
  String _lastPort = '';
  bool _passwordVisible = false;
  final ValueNotifier<String> _selectedRail = ValueNotifier<String>('chat');
  String get _selectedRailId => _selectedRail.value;
  Peer? _selectedContact;
  String? _selectedConversationPeerId;

  /// PC 端聊天输入框控制器：截图标注完成后把图片放入输入框
  /// （待发送状态），由用户点发送按钮再真正发出（微信式流程）。
  final DesktopChatComposerController _composerController =
      DesktopChatComposerController();

  bool _openingViewerInvite = false;

  /// 系统通知分栏面板是否打开（嵌入右侧内容区，不遮挡左侧列表）。
  /// 用 ValueNotifier 驱动，避免整页 setState 重建。
  final ValueNotifier<bool> _noticesOpen = ValueNotifier<bool>(false);

  /// 收藏夹分栏面板是否打开（同样嵌入右侧内容区，左侧列表保持原样）。
  final ValueNotifier<bool> _favoritesOpen = ValueNotifier<bool>(false);

  final Map<String, FFI> _directChatSessions = <String, FFI>{};
  final Map<String, DateTime> _directChatAttemptedAt = <String, DateTime>{};
  final Set<String> _openingDirectChatPeers = <String>{};
  static const Duration _directChatConnectionGracePeriod = Duration(seconds: 8);
  final Map<String, FFI> _directFileSessions = <String, FFI>{};
  final Set<String> _openingDirectConnections = <String>{};
  final Map<String, DateTime> _lastDirectConnectionAttempt =
      <String, DateTime>{};
  static const Duration _directConnectionClickCooldown = Duration(seconds: 2);
  final Map<String, bool> _knownPeerOnline = <String, bool>{};
  // Rendezvous-driven online states for direct-pairing contacts that are not
  // part of the classic Peers models, so standalone pairings also show the
  // real online status without needing an active chat connection.
  final Map<String, bool> _rendezvousOnlineByPeer = <String, bool>{};
  Timer? _peerOnlineQueryTimer;
  static const String _peerOnlineHandlerName = 'desktop_contacts_online';
  final Set<String> _notifiedChatConnections = <String>{};
  static const Duration _contactSectionRefreshInterval = Duration(seconds: 30);
  final Map<String, DateTime> _lastContactSectionLoad = <String, DateTime>{};
  Timer? _workspaceNoticeTimer;
  Timer? _announceTimer;
  String? _workspaceNotice;
  _WorkspaceNoticeTone _workspaceNoticeTone = _WorkspaceNoticeTone.info;
  int _workspaceNoticeRevision = 0;
  String? _activeDirectChatPeerId;
  bool _contactSelectionMode = false;
  final Set<String> _selectedManagedEntries = <String>{};
  final RxBool _settingsHover = false.obs;
  final RxBool _relayHover = false.obs;
  final RxBool _block = false.obs;
  final ContactCategoryModel _categoryModel = ContactCategoryModel();
  final DirectChatAccessController _directChatAccess =
      DirectChatAccessController.instance;
  String? _draggingPeerId; // 当前拖拽中的会话 ID
  String? _selectedCategoryFilter; // 当前选中的分类筛选
  final GlobalKey _childKey = GlobalKey();

  // ---- 客户端连接相关控件 ----
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _contactSearchController =
      TextEditingController();
  final ValueNotifier<String> _contactQuery = ValueNotifier<String>('');
  final FocusNode _clientIdFocusNode = FocusNode();

  void _onClientConnect(String id, BuildContext buildCtx) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    _connectDirect(buildCtx, trimmed);
  }

  void _toggleManagedEntry(String id) {
    setState(() {
      _contactSelectionMode = true;
      if (!_selectedManagedEntries.add(id)) {
        _selectedManagedEntries.remove(id);
      }
      if (_selectedManagedEntries.isEmpty) _contactSelectionMode = false;
    });
  }

  Future<void> _addManagedEntriesToFavorites(Iterable<String> ids) async {
    final favorites = (await bind.mainGetFav()).toList();
    for (final id in ids) {
      if (!favorites.contains(id)) favorites.add(id);
    }
    await bind.mainStoreFav(favs: favorites);
    bind.mainLoadFavPeers();
    showToast(translate('Successful'));
  }

  List<Peer> _selectedAddressBookPeers(Iterable<String> ids) => ids
      .map(gFFI.abModel.find)
      .whereType<Peer>()
      .map(Peer.copy)
      .toList(growable: false);

  void _moveAddressBookPeers(Iterable<String> ids) {
    final peers = _selectedAddressBookPeers(ids);
    if (peers.isEmpty) return;
    addPeersToAbDialog(peers, moveFromCurrent: true);
  }

  Future<void> _deleteManagedEntries(Iterable<String> ids) async {
    final selected = ids.toSet();
    if (selected.isEmpty) return;
    switch (_selectedRailId) {
      case 'chat':
        await gFFI.chatModel.deleteConversations(selected);
        break;
      case 'favorites':
        final favorites = (await bind.mainGetFav()).toList()
          ..removeWhere(selected.contains);
        await bind.mainStoreFav(favs: favorites);
        bind.mainLoadFavPeers();
        break;
      case 'discovered':
        for (final id in selected) {
          await bind.mainRemoveDiscovered(id: id);
        }
        bind.mainLoadLanPeers();
        break;
      case 'contacts':
        await gFFI.abModel.deletePeers(selected.toList());
        await DirectPairingStore.removeAll(selected);
        break;
      default:
        for (final id in selected) {
          await bind.mainRemovePeer(id: id);
        }
        bind.mainLoadRecentPeers();
    }
    if (!mounted) return;
    setState(() {
      _selectedManagedEntries.clear();
      _contactSelectionMode = false;
      if (selected.contains(_selectedConversationPeerId)) {
        _selectedConversationPeerId = null;
        _selectedContact = null;
      }
    });
    showToast(translate('Successful'));
  }

  void _confirmDeleteManagedEntries(Iterable<String> ids) {
    final selected = ids.toSet();
    if (selected.isEmpty) return;
    deleteConfirmDialog(
      () => _deleteManagedEntries(selected),
      '${translate('Delete')} ${selected.length} ${translate('Selected')}?',
    );
  }

  Future<void> _showManagedEntryMenu(
    BuildContext context,
    String id,
    Offset position, {
    Peer? peer,
  }) async {
    final overlayObj = Overlay.of(context).context.findRenderObject();
    if (overlayObj is! RenderBox) return;
    final overlayBox = overlayObj as RenderBox;
    final localPosition = overlayBox.globalToLocal(position);
    final anchor = Rect.fromLTWH(localPosition.dx, localPosition.dy, 1, 1);
    final compactMenuTextStyle =
        (Theme.of(context).textTheme.labelMedium ?? const TextStyle()).copyWith(
      fontSize: 13,
      height: 1,
      letterSpacing: 0,
    );
    Text menuText(String text, {Color? color}) => Text(
          text,
          maxLines: 1,
          style: compactMenuTextStyle.copyWith(color: color),
        );
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        anchor,
        Offset.zero & overlayBox.size,
      ),
      constraints: const BoxConstraints.tightFor(width: 176),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'select',
          height: 36,
          child: menuText(translate('Select')),
        ),
        PopupMenuItem<String>(
          value: 'favorite',
          height: 36,
          child: menuText(translate('Add to Favorites')),
        ),
        PopupMenuItem<String>(
          value: _directChatAccess.isFriend(id) ? 'stranger' : 'friend',
          height: 36,
          child: menuText(
            translate(
              _directChatAccess.isFriend(id)
                  ? 'Move to strangers'
                  : 'Add as friend',
            ),
          ),
        ),
        if (peer != null && _selectedRailId == 'contacts')
          PopupMenuItem<String>(
            value: 'tags',
            height: 36,
            child: menuText(translate('Edit Tag')),
          ),
        if (peer != null && _selectedRailId == 'contacts')
          PopupMenuItem<String>(
            value: 'move',
            height: 36,
            child: menuText(translate('Move')),
          ),
        PopupMenuItem<String>(
          value: 'mute',
          height: 36,
          child: menuText(
            gFFI.chatSettingsModel.isMuted(id)
                ? translate('Unmute')
                : translate('Mute'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'block',
          height: 36,
          child: menuText(
            gFFI.chatSettingsModel.isBlocked(id)
                ? translate('Unblock')
                : translate('Block'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 36,
          child: menuText(translate('Delete'), color: Colors.red),
        ),
      ],
    );
    switch (action) {
      case 'select':
        _toggleManagedEntry(id);
        break;
      case 'favorite':
        await _addManagedEntriesToFavorites(<String>[id]);
        break;
      case 'friend':
        if (gFFI.chatSettingsModel.isBlocked(id)) {
          await gFFI.chatSettingsModel.toggleBlock(id);
        }
        await _directChatAccess.setPeerPolicy(id, 'allow');
        break;
      case 'stranger':
        await _directChatAccess.setPeerPolicy(id, 'ask');
        break;
      case 'tags':
        editAbTagDialog(gFFI.abModel.getPeerTags(id), (tags) async {
          await gFFI.abModel.changeTagForPeers(<String>[id], tags);
        });
        break;
      case 'move':
        _moveAddressBookPeers(<String>[id]);
        break;
      case 'delete':
        _confirmDeleteManagedEntries(<String>[id]);
        break;
      case 'mute':
        await gFFI.chatSettingsModel.toggleMute(id);
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                gFFI.chatSettingsModel.isMuted(id)
                    ? translate('Notifications muted for this chat')
                    : translate('Notifications enabled'),
              ),
            ),
          );
        }
        break;
      case 'block':
        final willBlock = !gFFI.chatSettingsModel.isBlocked(id);
        await gFFI.chatSettingsModel.toggleBlock(id);
        await _directChatAccess.setPeerPolicy(
          id,
          willBlock ? 'deny' : 'ask',
        );
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                gFFI.chatSettingsModel.isBlocked(id)
                    ? translate('Contact blocked')
                    : translate('Contact unblocked'),
              ),
            ),
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
// 纯客户端模式：仅显示控制端面板，不接收远程控制。
    if (widget.isClientOnly) {
      return _buildBlock(
        child: SizedBox.expand(
          child: buildLeftPane(context),
        ),
      );
    }
    if (!isIncomingOnly) {
      return _buildBlock(child: _buildRemoteCenter(context));
    }
    return _buildBlock(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildLeftPane(context),
          if (!isIncomingOnly) const VerticalDivider(width: 1),
          if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
        ],
      ),
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
      block: _block,
      mask: true,
      use: canBeBlocked,
      child: child,
    );
  }

  Widget _buildRemoteCenter(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail = weChatShowDesktopRail(constraints.maxWidth);
        final contactsWidth = weChatConversationListWidth(constraints.maxWidth);
        final dark = Theme.of(context).brightness == Brightness.dark;
        return ColoredBox(
          color: dark ? const Color(0xFF191B20) : kWeChatChromeColor,
          child: Stack(
            children: <Widget>[
              Row(
                children: [
                  if (showRail)
                    ValueListenableBuilder<String>(
                      valueListenable: _selectedRail,
                      builder: (context, _, __) => _buildPrimaryRail(context),
                    ),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: _selectedRail,
                      child: _buildConversationWorkspace(context),
                      builder: (context, section, workspace) {
                        if (section == 'vip') {
                          return const VipFeaturesPage();
                        }
                        return Row(
                          children: <Widget>[
                            SizedBox(
                              width: contactsWidth,
                              child: _buildContactsPane(context),
                            ),
                            Expanded(
                              child: AnimatedBuilder(
                                animation: Listenable.merge(<Listenable>[
                                  _noticesOpen,
                                  _favoritesOpen,
                                ]),
                                builder: (context, _) => AnimatedSwitcher(
                                  duration:
                                      const Duration(milliseconds: 260),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    return SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0.06, 0),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _noticesOpen.value
                                      ? _SystemNoticePanel(
                                          key: const ValueKey(
                                              'notice-panel'),
                                          lastReadId:
                                              SystemAnnouncementStore
                                                  .instance
                                                  .lastReadId,
                                          onClose: _closeNoticesPanel,
                                        )
                                      : _favoritesOpen.value
                                          ? FavoritesPage(
                                              key: const ValueKey(
                                                  'favorites-panel'),
                                              detailPane: true,
                                              onClose: _closeFavoritesPane,
                                            )
                                          : KeyedSubtree(
                                              key: const ValueKey(
                                                  'workspace'),
                                              child: workspace!,
                                            ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 60,
                right: 16,
                width: constraints.maxWidth < 392
                    ? constraints.maxWidth - 32
                    : 360,
                child: _buildWorkspaceNotice(context),
              ),
              // Incoming voice call overlay
              Obx(() {
                final status = gFFI.chatModel.voiceCallStatus.value;
                if (status == VoiceCallStatus.incoming) {
                  final caller = gFFI.serverModel.clients.firstWhereOrNull(
                      (c) => c.incomingVoiceCall && !c.disconnected);
                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _IncomingVoiceCallOverlay(
                      callerName: caller?.name ?? '',
                      onAccept: () => _handleIncomingVoiceCall(true),
                      onReject: () => _handleIncomingVoiceCall(false),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrimaryRail(BuildContext context) {
    const destinations = <DesktopRailDestination>[
      DesktopRailDestination(
        id: 'chat',
        label: 'Messages',
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_bubble_rounded,
      ),
      DesktopRailDestination(
        id: 'recent',
        label: 'Recent sessions',
        icon: Icons.history_rounded,
      ),
      DesktopRailDestination(
        id: 'favorites',
        label: 'Favorites',
        icon: Icons.star_outline_rounded,
        selectedIcon: Icons.star_rounded,
      ),
      DesktopRailDestination(
        id: 'discovered',
        label: 'LAN discovery',
        icon: Icons.radar_rounded,
      ),
      DesktopRailDestination(
        id: 'contacts',
        label: 'Contacts',
        icon: Icons.contacts_outlined,
        selectedIcon: Icons.contacts_rounded,
      ),
      DesktopRailDestination(
        id: 'vip',
        label: 'VIP',
        icon: Icons.workspace_premium_outlined,
        selectedIcon: Icons.workspace_premium_rounded,
      ),
    ];
    // 监听绑定状态：未绑定时在左下角手机图标上显示绿色“未绑定”气泡。
    return ValueListenableBuilder<int>(
      valueListenable: DirectPairingStore.revision,
      builder: (context, _, __) {
        final bound =
            (DirectPairingStore.boundPhone()['peerId'] ?? '').trim().isNotEmpty;
        return DesktopPrimaryRail(
          destinations: destinations,
          selectedId: _selectedRailId,
          avatar: _buildLocalAvatar(44),
          onAvatarPressed: () => DesktopTabPage.onAddSetting(
            initialPage: SettingsTabKey.account,
          ),
          onSelected: _selectSection,
          onSettings: DesktopTabPage.onAddSetting,
          onPairPhone: () => _showPairingQrDialog(context),
          pairPhoneBound: bound,
        );
      },
    );
  }

  Future<void> _selectSection(String section) async {
    // 收藏：不再弹窗，改为嵌入右侧内容区的分栏面板
    // （左侧列表栏保持原样，右侧分两列：分类列表 + 详情）。
    if (section == 'favorites') {
      if (!mounted) return;
      _noticesOpen.value = false;
      _favoritesOpen.value = true;
      return;
    }
    const sections = <String>{
      'chat',
      'recent',
      'favorites',
      'discovered',
      'contacts',
      'vip',
    };
    if (!sections.contains(section) || !mounted) return;
    if (_selectedRailId != section) {
      _selectedRail.value = section;
      _contactSearchController.clear();
      _contactQuery.value = '';
    }
    if (mounted) {
      _noticesOpen.value = false;
      _favoritesOpen.value = false;
    }
    await _loadContactSection(section);
  }

  /// 关闭收藏夹分栏面板（返回按钮触发）。
  void _closeFavoritesPane() {
    if (!mounted) return;
    _favoritesOpen.value = false;
  }

  /// 微信 PC 风格收藏面板：分类查看收藏的图片 / 文件 / 位置 / 聊天内容等。
  Future<void> _showFavoritesPage() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => Center(
        child: Container(
          width: 860,
          height: 600,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1C1E23)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          // 桌面端：左右分栏（左侧列表 + 右侧详情）。
          child: const FavoritesPage(detailPane: true),
        ),
      ),
    );
  }

  void _openBluetoothScan(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BluetoothChatPage(),
      ),
    );
  }

  /// 列表顶部“手机绑定”状态条（微信电脑版风格）：
  /// 未绑定时提示扫码，已绑定显示“已绑定 手机 + IP:端口”。
  Widget _buildPhoneBindingStrip(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<int>(
      valueListenable: DirectPairingStore.revision,
      builder: (context, _, __) {
        final bound = DirectPairingStore.boundPhone();
        final phoneId = (bound['peerId'] ?? '').trim();
        if (phoneId.isEmpty) {
          // 未绑定手机：不再显示顶部文字提示条
          // （改为左下角手机图标的绿色“未绑定”气泡）。
          return const SizedBox.shrink();
        }
        final pairing = DirectPairingStore.load().values.toList().firstWhereOrNull(
          (p) => p.peerId == phoneId,
        );
        final endpoint = (pairing != null &&
                pairing.preferredEndpoint.isNotEmpty)
            ? pairing.preferredEndpoint
            : phoneId;
        final phoneName =
            (bound['displayName'] ?? '').trim().isNotEmpty
                ? (bound['displayName'] ?? '').trim()
                : translate('Phone');
        return Container(
          height: 28,
          width: double.infinity,
          color: dark ? const Color(0xFF1E3A28) : const Color(0xFFE6F4EA),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.phone_android_rounded,
                size: 14,
                color: dark
                    ? const Color(0xFF7ED9A0)
                    : const Color(0xFF1E8E3E),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  '${translate('Bound to phone')}  $phoneName · $endpoint',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: dark
                        ? const Color(0xFF7ED9A0)
                        : const Color(0xFF1E8E3E),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContactsPane(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final sectionTitle = switch (_selectedRailId) {
      'chat' => translate('Messages'),
      'recent' => translate('Recent sessions'),
      'favorites' => translate('Favorites'),
      'discovered' => translate('LAN discovery'),
      'contacts' => translate('Contacts'),
      _ => translate('Contacts'),
    };
    return ColoredBox(
      color: dark ? const Color(0xFF25272C) : kWeChatListSurfaceColor,
      child: Column(
        children: <Widget>[
          _buildPhoneBindingStrip(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _contactSearchController,
                      onChanged: (value) => _contactQuery.value = value,
                      onSubmitted: (value) {
                        if (DirectPairingStore.resolveConnectionTarget(value) !=
                            null) {
                          _startDirectChat(value);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: _selectedRailId == 'chat'
                            ? translate('Search conversations')
                            : translate('Search'),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        filled: true,
                        fillColor:
                            dark ? const Color(0xFF32343A) : kWeChatCanvasColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: translate('Bluetooth scan'),
                  constraints:
                      const BoxConstraints.tightFor(width: 40, height: 40),
                  icon: const Icon(
                    Icons.bluetooth_searching_rounded,
                    size: 22,
                  ),
                  onPressed: () => _openBluetoothScan(context),
                ),
                const SizedBox(width: 2),
                PopupMenuButton<String>(
                  tooltip: translate('Add'),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
                  onSelected: (value) {
                    switch (value) {
                      case 'connect':
                        _showDirectConnectDialog(context);
                        return;
                      case 'viewer':
                        _showJoinViewerPage(context);
                        return;
                      case 'pair-phone':
                        _showPairingQrDialog(context);
                        return;
                      case 'identity':
                        _showIdentityDialog(context);
                        return;
                      case 'bluetooth':
                        _openBluetoothScan(context);
                        return;
                      case 'create-meeting':
                        _showCreateMeetingDialog(context);
                        return;
                      case 'join-meeting':
                        _joinMeetingByCode();
                        return;
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'connect',
                      child: Text(translate('Connect by ID / IP')),
                    ),
                    PopupMenuItem<String>(
                      value: 'viewer',
                      child: Text(translate('Join as Viewer')),
                    ),
                    PopupMenuItem<String>(
                      value: 'pair-phone',
                      child: Text(translate('Pair phone')),
                    ),
                    PopupMenuItem<String>(
                      value: 'identity',
                      child: Text(translate('My Identity')),
                    ),
                    PopupMenuItem<String>(
                      value: 'bluetooth',
                      child: Text(translate('Bluetooth scan')),
                    ),
                    if (_selectedRailId == 'chat' ||
                        _selectedRailId == 'contacts')
                      PopupMenuItem<String>(
                        value: 'create-meeting',
                        child: Text(translate('Create Meeting')),
                      ),
                    if (_selectedRailId == 'chat' ||
                        _selectedRailId == 'contacts')
                      PopupMenuItem<String>(
                        value: 'join-meeting',
                        child: Text(translate('Join meeting')),
                      ),
                  ],
                ),
                if (_selectedRailId == 'contacts')
                  IconButton(
                    tooltip: translate('Add Category'),
                    icon:
                        const Icon(Icons.create_new_folder_outlined, size: 22),
                    onPressed: () => _showAddCategoryDialog(context),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 20),
                Icon(
                  _selectedRailId == 'chat'
                      ? Icons.format_list_bulleted_rounded
                      : Icons.contacts_outlined,
                  size: 19,
                  color: theme.colorScheme.onSurface.withOpacity(0.56),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    sectionTitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.64),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_contactSelectionMode) ...[
                  Text(
                    '${_selectedManagedEntries.length} ${translate('Selected')}',
                    style: theme.textTheme.labelMedium,
                  ),
                  IconButton(
                    tooltip: translate('Add to Favorites'),
                    icon: const Icon(Icons.star_outline_rounded, size: 20),
                    onPressed: _selectedManagedEntries.isEmpty
                        ? null
                        : () => _addManagedEntriesToFavorites(
                              _selectedManagedEntries,
                            ),
                  ),
                  if (_selectedRailId == 'contacts') ...[
                    IconButton(
                      tooltip: translate('Edit Tag'),
                      icon: const Icon(Icons.tag_outlined, size: 20),
                      onPressed: _selectedManagedEntries.isEmpty
                          ? null
                          : () => editAbTagDialog(<dynamic>[], (tags) async {
                                await gFFI.abModel.changeTagForPeers(
                                  _selectedManagedEntries.toList(),
                                  tags,
                                );
                              }),
                    ),
                    IconButton(
                      tooltip: translate('Move'),
                      icon: const Icon(
                        Icons.drive_file_move_outline,
                        size: 20,
                      ),
                      onPressed: _selectedManagedEntries.isEmpty
                          ? null
                          : () => _moveAddressBookPeers(
                                _selectedManagedEntries,
                              ),
                    ),
                  ],
                  IconButton(
                    tooltip: translate('Delete'),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: Colors.red,
                    onPressed: _selectedManagedEntries.isEmpty
                        ? null
                        : () => _confirmDeleteManagedEntries(
                              _selectedManagedEntries,
                            ),
                  ),
                  IconButton(
                    tooltip: translate('Cancel'),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => setState(() {
                      _selectedManagedEntries.clear();
                      _contactSelectionMode = false;
                    }),
                  ),
                ] else
                  IconButton(
                    tooltip: translate('Select multiple'),
                    icon: const Icon(Icons.checklist_rounded, size: 20),
                    onPressed: () => setState(() {
                      _contactSelectionMode = true;
                    }),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: dark
                ? const Color(0xFF3A3D43)
                : kWeChatDividerColor.withOpacity(0.5),
          ),
          AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              gFFI.serverModel,
              gFFI.recentPeersModel,
              gFFI.favoritePeersModel,
              gFFI.lanPeersModel,
              _directChatAccess,
            ]),
            builder: (context, _) => _buildPresenceStatusStrip(context),
          ),
          if (_selectedRailId == 'contacts') _buildCategoryFilterBar(context),
          if (_selectedRailId == 'chat') _buildSystemNoticeEntryStrip(context),
          if (_selectedRailId == 'chat') _buildMeetingEntryStrip(context),
          Expanded(child: _buildContactSection(context)),
        ],
      ),
    );
  }

  /// 点聊列表顶部的“系统通知”入口条（会议中心上方）。
  Widget _buildSystemNoticeEntryStrip(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final store = SystemAnnouncementStore.instance;
    return ValueListenableBuilder<int>(
      valueListenable: store.revision,
      builder: (context, _, __) {
        final count = store.unreadCount;
        final latest = store.items.isEmpty ? null : store.items.first;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Material(
            color: dark ? const Color(0xFF23272F) : const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openNoticesPanel(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: kWeChatPrimaryColor.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.campaign_rounded,
                          size: 19, color: kWeChatPrimaryColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            translate('System notices'),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            latest == null
                                ? translate('No system notices')
                                : latest.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: dark
                                  ? const Color(0xFF8A8F98)
                                  : const Color(0xFF6B7076),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (count > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFA5151),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded,
                        size: 18,
                        color: dark
                            ? const Color(0xFF8A8F98)
                            : const Color(0xFF6B7076)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 点聊列表顶部的“会议中心”入口条：让会议入口足够明显，
  /// 点击直接创建会议（可随后邀请成员、多人观看演示/远程协助）。
  Widget _buildMeetingEntryStrip(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final meetingCount = MeetingGroupStore.all.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Material(
        color: dark ? const Color(0xFF1C3A2A) : const Color(0xFFE7F5EC),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showCreateMeetingDialog(context),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: kWeChatPrimaryColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.groups_rounded,
                      size: 20, color: kWeChatPrimaryColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        translate('Meeting Center'),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: dark
                              ? const Color(0xFFDDF3E4)
                              : const Color(0xFF1B5E2F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meetingCount > 0
                            ? '${translate('Meeting')} · $meetingCount'
                            : translate('Create a meeting to chat and share screen'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: dark
                              ? const Color(0xFF8FBF9D)
                              : const Color(0xFF4C7A58),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _buildEntryChip(
                  context,
                  label: translate('Create'),
                  onTap: () => _showCreateMeetingDialog(context),
                ),
                const SizedBox(width: 6),
                _buildEntryChip(
                  context,
                  label: translate('Join'),
                  onTap: _joinMeetingByCode,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntryChip(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: kWeChatPrimaryColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }

  /// 打开系统通知面板：不弹窗、不加遮罩，直接在右侧内容区切换显示——
  /// 左侧列表保持不动，右侧滑入分栏面板（第 1 列通知列表、第 2 列详情）。
  Future<void> _openNoticesPanel() async {
    final store = SystemAnnouncementStore.instance;
    store.load();
    await store.refresh();
    if (!mounted) return;
    _noticesOpen.value = true;
  }

  /// 关闭系统通知面板并标记全部已读。
  Future<void> _closeNoticesPanel() async {
    if (!mounted) return;
    _noticesOpen.value = false;
    await SystemAnnouncementStore.instance.markAllRead();
  }

  /// 构建分类筛选相关控件：按分类过滤会话列表。
  Widget _buildCategoryFilterBar(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Obx(() {
      final categories = _categoryModel.categories;
      if (categories.isEmpty && _selectedCategoryFilter == null) {
        return const SizedBox.shrink();
      }
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: categories.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              final isSelected = _selectedCategoryFilter == null;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildCategoryChip(
                  label: translate('All'),
                  count: null,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedCategoryFilter = null),
                  color: isSelected
                      ? theme.colorScheme.primary
                      : (dark
                          ? const Color(0xFF3A3D43)
                          : const Color(0xFFE0E5EA)),
                  onAcceptPeer: (_) {},
                ),
              );
            }
            final category = categories[index - 1];
            final isSelected = _selectedCategoryFilter == category.name;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildCategoryChip(
                label: category.name,
                count: _categoryModel.getCategoryCount(category.name),
                isSelected: isSelected,
                onTap: () => setState(() => _selectedCategoryFilter =
                    isSelected ? null : category.name),
                color: isSelected
                    ? theme.colorScheme.primary
                    : (dark
                        ? const Color(0xFF3A3D43)
                        : const Color(0xFFE0E5EA)),
                onAcceptPeer: (peerId) {
                  _categoryModel.setPeerCategory(peerId, category.name);
                  showToast(translate('Moved to {name}')
                      .replaceAll('{name}', category.name));
                },
              ),
            );
          },
        ),
      );
    });
  }

  /// 显示分类筛选栏
  Widget _buildCategoryChip({
    required String label,
    required int? count,
    required bool isSelected,
    required VoidCallback onTap,
    required Color color,
    required void Function(String peerId) onAcceptPeer,
  }) {
    final theme = Theme.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) {
        final peerId = details.data;
        if (peerId.isNotEmpty) onAcceptPeer(peerId);
      },
      builder: (context, candidateData, rejectedData) {
        final isHover = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isHover
                  ? color.withOpacity(0.4)
                  : isSelected
                      ? color
                      : color.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isHover ? theme.colorScheme.primary : color,
                width: isHover ? 2 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.folder_outlined,
                  size: 14,
                  color: (isSelected || isHover)
                      ? Colors.white
                      : theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: (isSelected || isHover)
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (count != null && count > 0) ...<Widget>[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      color: (isSelected || isHover)
                          ? Colors.white70
                          : theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示添加分类对话框
  void _showAddCategoryDialog(BuildContext context) {
    final controller = TextEditingController();
    gFFI.dialogManager.show((setState, close, ctx) {
      return CustomAlertDialog(
        title: Text(translate('Add Category')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: translate('Category Name'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          dialogButton('Cancel', onPressed: close),
          dialogButton(
            'OK',
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) _categoryModel.addCategory(name);
              close();
            },
          ),
        ],
        onSubmit: () {
          final name = controller.text.trim();
          if (name.isNotEmpty) _categoryModel.addCategory(name);
          close();
        },
        onCancel: close,
      );
    });
  }

  /// 显示创建会议对话框
  void _showCreateMeetingDialog(BuildContext context) {
    /// 创建会议页面输入框
    final controller = TextEditingController();
    // 演示人：默认发起人自己，可改为其他联系人（单选）。
    Peer? presenter;
    gFFI.dialogManager.show((setState, close, ctx) {
      final presenterLabel = presenter != null
          ? presenter!.finalName()
          : gFFI.serverModel.serverId.text;
      return CustomAlertDialog(
        title: Text(translate('Create Meeting')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: translate('Meeting Title'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showFriendPickerDialog(
                  context,
                  peers: gFFI.recentPeersModel.peers,
                  title: translate('Choose presenter'),
                  maxSelections: 1,
                );
                if (picked != null && picked.isNotEmpty) {
                  setState(() => presenter = picked.first);
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withOpacity(0.6),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.present_to_all_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${translate('Presenter')}: $presenterLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Icon(Icons.unfold_more_rounded,
                        size: 16,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              translate('Members can watch your session and chat in group'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          dialogButton('Cancel', onPressed: close),
          dialogButton(
            'Create',
            onPressed: () {
              final title = controller.text.trim();
              if (title.isEmpty) return;
              final group = MeetingGroupStore.create(
                title: title,
                hostPeerId: gFFI.serverModel.id,
                hostDisplayName: gFFI.serverModel.serverId.text,
                presenterPeerId:
                    presenter?.id ?? gFFI.serverModel.id,
                presenterDisplayName:
                    presenter?.finalName() ?? gFFI.serverModel.serverId.text,
              );
              close();
              // 发送邀请链接到聊天，方便邀请其他人
              if (group.meetingId.isNotEmpty) {
                showToast(translate('Meeting created'));
                // 自动生成邀请链接并复制
                final link = 'luoda://meeting/${group.meetingId}';
                _copyToClipboard(link);
                showToast(translate('Invite link copied'));
              }
            },
          ),
        ],
        onSubmit: () {
          final title = controller.text.trim();
          if (title.isEmpty) return;
          MeetingGroupStore.create(
            title: title,
            hostPeerId: gFFI.serverModel.id,
            hostDisplayName: gFFI.serverModel.serverId.text,
            presenterPeerId: presenter?.id ?? gFFI.serverModel.id,
            presenterDisplayName:
                presenter?.finalName() ?? gFFI.serverModel.serverId.text,
          );
          close();
        },
        onCancel: close,
      );
    });
  }

  void _copyToClipboard(String text) {
    // Clipboard copy is async, fire-and-forget
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  void _showMeetingGroupSettings(BuildContext context, MeetingGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MeetingGroupPanel(group: group),
      ),
    );
  }

  Widget _buildPresenceStatusStrip(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final networkStatus = gFFI.serverModel.connectStatus;
    final directListenerReady =
        bind.mainGetOptionSync(key: kOptionDirectListenerStatus) == 'ready';
    final localLabel = networkStatus > 0
        ? translate('Online')
        : directListenerReady
            ? translate('Direct listening')
            : networkStatus == 0
                ? translate('Connecting')
                : translate('Offline');
    final localColor = networkStatus > 0 || directListenerReady
        ? const Color(0xFF238A57)
        : networkStatus == 0
            ? const Color(0xFFE39128)
            : const Color(0xFF667085);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1D2025) : const Color(0xFFF1F4F7),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: dark ? const Color(0xFF353941) : const Color(0xFFE0E5EA),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _presenceStatusCell(
              context,
              label: translate('My status'),
              value: localLabel,
              color: localColor,
              icon: Icons.person_outline_rounded,
            ),
          ),
          SizedBox(
            height: 26,
            child: VerticalDivider(
              width: 18,
              color: dark ? const Color(0xFF454951) : const Color(0xFFD5DADF),
            ),
          ),
          Expanded(
            child: _messageAudienceCell(context),
          ),
        ],
      ),
    );
  }

  Widget _presenceStatusCell(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final muted = Theme.of(context).colorScheme.onSurface.withOpacity(0.56);
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontSize: 11,
                    ),
              ),
              const SizedBox(height: 1),
              Row(
                children: <Widget>[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _messageAudienceCell(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(0.56);
    return Row(
      children: <Widget>[
        Icon(Icons.shield_outlined, size: 16, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                translate('Message permissions'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontSize: 11,
                ),
              ),
              SizedBox(
                height: 24,
                child: PopupMenuButton<DirectChatAudience>(
                  tooltip: translate('Message permissions'),
                  padding: EdgeInsets.zero,
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 8),
                  constraints: const BoxConstraints.tightFor(width: 288),
                  onSelected: (value) =>
                      unawaited(_directChatAccess.setAudience(value)),
                  itemBuilder: (context) =>
                      <PopupMenuEntry<DirectChatAudience>>[
                    PopupMenuItem<DirectChatAudience>(
                      value: DirectChatAudience.friendsOnly,
                      height: 36,
                      child: Text(
                        translate('Only friends can contact me anytime'),
                        maxLines: 1,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 13,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    PopupMenuItem<DirectChatAudience>(
                      value: DirectChatAudience.everyone,
                      height: 36,
                      child: Text(
                        translate('Strangers can also chat with me directly'),
                        maxLines: 1,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 13,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _directChatAccess.audience ==
                                  DirectChatAudience.friendsOnly
                              ? translate(
                                  'Only friends can contact me anytime',
                                )
                              : translate(
                                  'Strangers can also chat with me directly',
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.expand_more_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDirectConnectDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        void startChat() {
          final target = _clientIdController.text.trim();
          if (target.isEmpty) return;
          Navigator.of(dialogContext).pop();
          _startDirectChat(target);
        }

        void startRemote() {
          final target = _clientIdController.text.trim();
          if (target.isEmpty) return;
          Navigator.of(dialogContext).pop();
          _connectDirect(context, target);
        }

        return AlertDialog(
          title: Text(translate('Connect by ID / IP')),
          content: SizedBox(
            width: 360,
            child: TextField(
              key: const ValueKey('direct-chat-address-field'),
              controller: _clientIdController,
              focusNode: _clientIdFocusNode,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => startRemote(),
              decoration: InputDecoration(
                labelText: translate('ID or IP:port'),
                helperText: translate('Enter Remote ID'),
                prefixIcon: const Icon(Icons.link_rounded, size: 20),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(translate('Cancel')),
            ),
            OutlinedButton.icon(
              onPressed: startChat,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: Text(translate('Start a direct conversation')),
            ),
            FilledButton.icon(
              onPressed: startRemote,
              icon: const Icon(Icons.desktop_windows_outlined, size: 18),
              label: Text(translate('Remote assistance')),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConversationWorkspace(BuildContext context) {
    final configuredFfi = _activeDirectChatPeerId == null
        ? null
        : _directChatSessionFor(_activeDirectChatPeerId!);
    Widget workspace(ChatModel activeModel) => ChangeNotifierProvider.value(
          value: activeModel,
          child: Consumer<ChatModel>(
            builder: (context, model, _) {
              final user = model.currentUser;
              final rawSelectedPeerId =
                  _selectedConversationPeerId ?? _selectedContact?.id ?? '';
              final modelPeerId = user?.id.trim() ?? '';
              final selectedPairing =
                  DirectPairingStore.findForConversation(rawSelectedPeerId);
              final selectedPeerId = DirectPairingStore.canonicalConversationId(
                rawSelectedPeerId,
              );
              final modelConversationId =
                  DirectPairingStore.canonicalConversationId(modelPeerId);
              final userMatchesSelection = selectedPeerId.isEmpty ||
                  selectedPeerId == modelConversationId ||
                  selectedPairing?.conversationId == modelConversationId;
              final peerId = userMatchesSelection && modelPeerId.isNotEmpty
                  ? modelPeerId
                  : selectedPeerId;
              RuntimeLogger.instance.info('WSCOPE',
                  'sel=${rawSelectedPeerId} model=${modelPeerId} canon=${modelConversationId} match=${userMatchesSelection} peer=${peerId} activeD=${_activeDirectChatPeerId}');
              final selectedName = _selectedContact == null
                  ? ''
                  : _contactName(_selectedContact!);
              final modelDisplayName = (user?.firstName ?? '').trim();
              final hasConversation =
                  user != null && userMatchesSelection && peerId.isNotEmpty;
              final canStartDirectSession =
                  DirectPairingStore.resolveConnectionTarget(peerId) != null;
              return ColoredBox(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1C1E23)
                    : kWeChatCanvasColor,
                child: Column(
                  children: <Widget>[
                    _buildConversationHeader(
                      context,
                      chatModel: model,
                      title: selectedName.isNotEmpty
                          ? selectedName
                          : hasConversation && modelDisplayName.isNotEmpty
                              ? modelDisplayName
                              : translate('Direct chat'),
                      peerId: peerId,
                      hasConversation: hasConversation,
                      canStartDirectSession: canStartDirectSession,
                    ),
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    if (hasConversation)
                      _buildActiveTransferStrip(context, peerId),
                    Expanded(
                      child: hasConversation
                          ? ChatPage(
                              chatModel: model,
                              type: ChatPageType.desktopHome,
                              peerOffline: _selectedContact?.online != true,
                              onAttachFile: () =>
                                  _sendFilesFromConversation(peerId),
                              // 会议群聊：+ 面板的入口是“进入观看”（只读观看演示）；
                              // 普通会话才是“远程桌面”（可操控）。观看权限由服务端
                              // viewer 模型保证（viewer 天然只读，无法输入）。
                              isMeetingChat: peerId.startsWith('meeting:'),
                              onRemoteAssist: peerId.startsWith('meeting:')
                                  ? () {
                                      final group = MeetingGroupStore.find(
                                        peerId.substring('meeting:'.length),
                                      );
                                      if (group != null) {
                                        _joinGroupSession(context, group);
                                      }
                                    }
                                  : () => _connectDirect(context, peerId),
                              onSendImage: () =>
                                  _pickImagesForConversation(peerId),
                              onScreenshot: () =>
                                  _screenshotForConversation(peerId),
                              onPasteImage: (notifyIfEmpty) =>
                                  _pasteImageToConversation(
                                peerId,
                                notifyIfEmpty: notifyIfEmpty,
                              ),
                              onForwardMessages: _forwardConversationMessages,
                              composerController: _composerController,
                              onSendPendingImage: (path) =>
                                  _sendStagedImage(peerId, path),
                            )
                          : _buildEmptyConversation(
                              context,
                              contact: _selectedContact,
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
    return AnimatedBuilder(
      animation: configuredFfi == null
          ? gFFI.serverModel
          : Listenable.merge(<Listenable>[
              configuredFfi.ffiModel,
              gFFI.serverModel,
            ]),
      builder: (context, _) {
        final peerId = DirectPairingStore.canonicalConversationId(
          _activeDirectChatPeerId ??
              _selectedConversationPeerId ??
              _selectedContact?.id ??
              '',
        );
        final incoming = _incomingDirectChatClientFor(peerId);
        final activeFfi = incoming == null ? configuredFfi : null;
        return workspace(activeFfi?.chatModel ?? gFFI.chatModel);
      },
    );
  }

  Future<void> _setConversationAlias(
    String peerId,
    String alias,
  ) async {
    final pairing = DirectPairingStore.findForConversation(peerId);
    final storagePeerId = pairing?.peerId.trim().isNotEmpty == true
        ? pairing!.peerId.trim()
        : peerId.trim();
    if (storagePeerId.isEmpty) return;
    await bind.mainSetPeerAlias(id: storagePeerId, alias: alias.trim());
    final contact = _findContact(peerId);
    if (contact != null) contact.alias = alias.trim();
    bind.mainLoadRecentPeers();
    if (mounted) setState(() {});
  }

  Widget _buildConversationHeader(
    BuildContext context, {
    required ChatModel chatModel,
    required String title,
    required String peerId,
    required bool hasConversation,
    required bool canStartDirectSession,
  }) {
    final theme = Theme.of(context);
    // 会议群聊（meeting:xxx）：标题栏显示成员入口，点击打开成员查询窗口。
    final isMeetingChat = peerId.startsWith('meeting:');
    final meetingGroup = isMeetingChat
        ? MeetingGroupStore.find(peerId.substring('meeting:'.length))
        : null;
    final meetingMemberCount = (meetingGroup?.members?.length ?? 0) + 1;
    final status = _directDeliveryStatus(peerId, contact: _selectedContact);
    final routeLabel = peerId.isEmpty ? '' : directConnectionRouteLabel(peerId);
    final avatar =
        chatModel.currentUser?.profileImage ?? _selectedContact?.avatar ?? '';
    final initial = title.trim().isEmpty ? '#' : title.trim()[0].toUpperCase();
    void showDetails() {
      if (peerId.isEmpty) return;
      if (meetingGroup != null) {
        unawaited(
          showMeetingMembersDialog(context, meetingGroup).then((dissolved) {
            if (dissolved == true && mounted) {
              setState(() {
                _selectedConversationPeerId = null;
                _selectedContact = null;
                _activeDirectChatPeerId = null;
              });
            }
          }),
        );
        return;
      }
      unawaited(showDirectConnectionDetails(
        context,
        conversationId: peerId,
        initialAlias: _selectedContact?.alias.trim() ?? '',
        onRename: (alias) => _setConversationAlias(peerId, alias),
      ));
    }

    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                onTap: peerId.isEmpty ? null : showDetails,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: <Widget>[
                      if (peerId.isNotEmpty) ...<Widget>[
                        _buildConversationAvatar(
                          avatar: avatar,
                          name: title,
                          initial: initial,
                          size: 36,
                          peerId: peerId,
                          platform: _contactPlatformFor(peerId),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ),
                                if (isMeetingChat && meetingGroup != null) ...<Widget>[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: MyTheme.primarySoft,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${translate('Group chat')} ($meetingMemberCount)',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: MyTheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ] else if (peerId.isNotEmpty) ...<Widget>[
                                  const SizedBox(width: 10),
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: status.$2,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    translate(status.$1),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: status.$2,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (peerId.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 2, right: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      isMeetingChat
                                          ? Icons.groups_rounded
                                          : Icons.hub_outlined,
                                      size: 12,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        isMeetingChat
                                            ? '${translate('Group chat')} · '
                                                '${translate('Host')}: '
                                                '${meetingGroup?.hostDisplayName.isNotEmpty == true ? meetingGroup!.hostDisplayName : ''}'
                                            : routeLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.62),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _conversationActionButton(
              context,
              tooltip: translate('Search Messages'),
              icon: Icons.search_rounded,
              onPressed: hasConversation ? chatModel.openChatSearch : null,
            ),
            if (isMeetingChat && meetingGroup != null) ...<Widget>[
              // 进入观看：突出的绿色按钮（仅只读观看演示，无法操控）。
              Tooltip(
                message: meetingGroup.hasActiveSession
                    ? translate('Enter to Watch')
                    : translate('No active session yet'),
                child: IconButton(
                  onPressed: meetingGroup.hasActiveSession
                      ? () => _joinGroupSession(context, meetingGroup)
                      : null,
                  style: IconButton.styleFrom(
                    backgroundColor: meetingGroup.hasActiveSession
                        ? MyTheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.08),
                    foregroundColor: meetingGroup.hasActiveSession
                        ? Colors.white
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.3),
                    disabledBackgroundColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.06),
                    disabledForegroundColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.25),
                    minimumSize: const Size(40, 40),
                    padding: const EdgeInsets.all(8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.visibility_rounded, size: 21),
                ),
              ),
              if (meetingGroup.isHost)
                _conversationActionButton(
                  context,
                  tooltip: translate('Add member'),
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: () =>
                      _showMeetingAddMemberDialog(context, meetingGroup),
                ),
            ] else ...<Widget>[
              _conversationActionButton(
                context,
                tooltip: translate('Remote Desktop'),
                icon: Icons.desktop_windows_outlined,
                onPressed: canStartDirectSession
                    ? () => _connectDirect(context, peerId)
                    : null,
              ),
            ],
            PopupMenuButton<_ConversationAction>(
              tooltip: translate('More'),
              enabled: isMeetingChat ? true : canStartDirectSession,
              onSelected: (action) {
                if (isMeetingChat && meetingGroup != null) {
                  switch (action) {
                    case _ConversationAction.meetingManage:
                      _showMeetingGroupSettings(context, meetingGroup);
                    case _ConversationAction.joinSession:
                      _joinGroupSession(context, meetingGroup);
                    case _ConversationAction.copyInvite:
                      _copyMeetingInvite(meetingGroup);
                    case _ConversationAction.fileTransfer:
                    case _ConversationAction.remoteAssist:
                    case _ConversationAction.camera:
                    case _ConversationAction.terminal:
                    case _ConversationAction.port:
                      break;
                  }
                  return;
                }
                _handleConversationAction(context, action, peerId);
              },
              itemBuilder: (context) => isMeetingChat && meetingGroup != null
                  ? <PopupMenuEntry<_ConversationAction>>[
                      PopupMenuItem(
                        value: _ConversationAction.meetingManage,
                        child: Text(translate('Meeting management')),
                      ),
                      if (meetingGroup.hasActiveSession)
                        PopupMenuItem(
                          value: _ConversationAction.joinSession,
                          child: Text(translate('Join live session')),
                        ),
                      if (meetingGroup.inviteShortCode.isNotEmpty)
                        PopupMenuItem(
                          value: _ConversationAction.copyInvite,
                          child: Text(translate('Copy invite link')),
                        ),
                    ]
                  : <PopupMenuEntry<_ConversationAction>>[
                      PopupMenuItem(
                        value: _ConversationAction.camera,
                        child: Text(translate('View camera')),
                      ),
                      PopupMenuItem(
                        value: _ConversationAction.terminal,
                        child: Text(translate('Terminal')),
                      ),
                      PopupMenuItem(
                        value: _ConversationAction.port,
                        child: Text(translate('TCP tunneling')),
                      ),
                    ],
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ],
        ),
      ),
    );
  }

  /// 加入会议群聊的实时远程会话（观看演示/教学）。
  void _joinGroupSession(BuildContext context, MeetingGroup group) {
    // 发起人/演示人可控制，其他成员只读观看（进入观看）。
    unawaited(joinMeetingSession(context, group));
  }

  /// 复制会议邀请链接到剪贴板。
  void _copyMeetingInvite(MeetingGroup group) {
    if (group.inviteShortCode.isEmpty) {
      showToast(translate('Generate an invite link first'));
      return;
    }
    final link =
        'luoda://meeting/${group.meetingId}?code=${group.inviteShortCode}'
        '&host=${group.hostPeerId}';
    Clipboard.setData(ClipboardData(text: link));
    showToast(translate('Link copied'));
  }

  /// 会议群聊窗口内直接添加成员（群主入口）。
  Future<void> _showMeetingAddMemberDialog(
    BuildContext context,
    MeetingGroup group,
  ) async {
    final theme = Theme.of(context);
    final controller = TextEditingController();
    final peerId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(translate('Add member')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: translate('Peer ID / ID / IP'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(translate('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(translate('Add')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (peerId == null || peerId.isEmpty || !mounted) return;
    final trimmed = peerId.replaceAll(' ', '');
    final members = (group.members ?? [])
        .where((m) => m.peerId != group.hostPeerId)
        .toList();
    if (trimmed == group.hostPeerId || trimmed == gFFI.serverModel.id) {
      showToast(translate('Already a member'));
      return;
    }
    if (members.any((m) => m.peerId == trimmed)) {
      showToast(translate('Already a member'));
      return;
    }
    final peer =
        gFFI.recentPeersModel.peers.firstWhereOrNull((p) => p.id == trimmed);
    final displayName = peer?.alias.isNotEmpty == true
        ? peer!.alias
        : peer?.username.isNotEmpty == true
            ? peer!.username
            : trimmed;
    MeetingGroupStore.addMember(group.meetingId, trimmed, displayName);
    showToast('$displayName ${translate('joined the group')}');
  }

  Widget _conversationActionButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 21),
      ),
    );
  }

  Widget _buildWorkspaceNotice(BuildContext context) {
    final message = _workspaceNotice;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final (background, foreground, icon) = switch (_workspaceNoticeTone) {
      _WorkspaceNoticeTone.success => (
          const Color(0xFFF0F8F3),
          const Color(0xFF166A42),
          Icons.check_circle_outline_rounded,
        ),
      _WorkspaceNoticeTone.warning => (
          const Color(0xFFFFF7E8),
          const Color(0xFF8A5A12),
          Icons.wifi_tethering_error_rounded,
        ),
      _WorkspaceNoticeTone.error => (
          const Color(0xFFFFF1F1),
          const Color(0xFFA83B3B),
          Icons.error_outline_rounded,
        ),
      _WorkspaceNoticeTone.info => (
          const Color(0xFFF1F6FB),
          const Color(0xFF315C86),
          Icons.info_outline_rounded,
        ),
    };
    return AnimatedSwitcher(
      duration: Duration(milliseconds: reduceMotion ? 0 : 180),
      reverseDuration: Duration(milliseconds: reduceMotion ? 0 : 120),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.12),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
      child: message == null
          ? const SizedBox.shrink(key: ValueKey<String>('notice-empty'))
          : Container(
              key: ValueKey<int>(_workspaceNoticeRevision),
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: translate('Close'),
                    onPressed: _dismissWorkspaceNotice,
                    icon:
                        Icon(Icons.close_rounded, size: 17, color: foreground),
                    constraints:
                        const BoxConstraints.tightFor(width: 36, height: 36),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildActiveTransferStrip(BuildContext context, String peerId) {
    final ffi = _directFileSessions[peerId];
    if (ffi == null) return const SizedBox.shrink();
    return Obx(() {
      final jobs = ffi.fileModel.jobController.jobTable;
      if (jobs.isEmpty) return const SizedBox.shrink();
      final job = jobs.last;
      final color = switch (job.state) {
        JobState.done => const Color(0xFF238A57),
        JobState.error => const Color(0xFFD84A4A),
        _ => Theme.of(context).colorScheme.primary,
      };
      final cancellable = job.state != JobState.done &&
          job.state != JobState.error &&
          job.state != JobState.none;
      return Container(
        height: 46,
        padding: const EdgeInsets.only(left: 22, right: 12),
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          children: <Widget>[
            Icon(
              job.state == JobState.done
                  ? Icons.check_circle_outline_rounded
                  : job.state == JobState.error
                      ? Icons.error_outline_rounded
                      : Icons.upload_file_outlined,
              size: 19,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                job.fileName.isEmpty
                    ? translate('File Transfer')
                    : job.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 104,
              child: job.state == JobState.inProgress
                  ? LinearProgressIndicator(
                      value: job.totalSize > 0 ? job.percent : null,
                      minHeight: 3,
                      color: color,
                    )
                  : Text(
                      job.state.display(),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: color,
                          ),
                    ),
            ),
            const SizedBox(width: 8),
            if (cancellable)
              Tooltip(
                message: translate('Cancel'),
                child: IconButton(
                  onPressed: () => unawaited(
                    ffi.fileModel.jobController.cancelJob(job.id),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildEmptyConversation(BuildContext context, {Peer? contact}) {
    if (contact == null) {
      return _buildLocalIdentityWorkspace(context);
    }
    final theme = Theme.of(context);
    final contactName = _contactName(contact);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.person_rounded,
                size: 70,
                color: str2color(contactName),
              ),
              const SizedBox(height: 20),
              Text(
                contactName,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${contact.id}\n${translate(contact.online ? 'Online' : 'Offline')}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.56),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _startDirectChat(contact.id),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                label: Text(translate('Connect and chat')),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => _sendFilesFromConversation(contact.id),
                    icon: const Icon(Icons.attach_file_rounded, size: 18),
                    label: Text(translate('File Transfer')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _connectDirect(context, contact.id),
                    icon: const Icon(
                      Icons.desktop_windows_outlined,
                      size: 18,
                    ),
                    label: Text(translate('Remote assistance')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalIdentityWorkspace(BuildContext context) {
    final theme = Theme.of(context);
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, _) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    translate('My Identity'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: kWeChatHeadingFontSize,
                      height: kWeChatTextHeight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    translate(
                        'Tell the other device your ID or IP to connect.'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: kWeChatBodyFontSize,
                      height: kWeChatTextHeight,
                      color: theme.colorScheme.onSurface.withOpacity(0.62),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildIdentityCard(context, model),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _showDirectConnectDialog(context),
                          icon: const Icon(Icons.add_link_rounded, size: 19),
                          label: Text(translate('Connect by ID / IP')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: model.serverId.text.isEmpty
                            ? null
                            : () => _copyValue(model.serverId.text),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: Text(translate('Copy device ID')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactSection(BuildContext context) {
    if (_selectedRailId == 'chat') {
      return _buildConversationList(context);
    }
    final model = _contactModelFor(_selectedRailId);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        model,
        gFFI.serverModel,
        DirectPairingStore.revision,
        gFFI.chatSettingsModel,
        _directChatAccess,
        _contactQuery,
      ]),
      builder: (context, _) {
        final query = _contactQuery.value.trim().toLowerCase();
        final directPairings = DirectPairingStore.load();
        final friendsOnly = _selectedRailId == 'contacts';
        final peers = <Peer>[];
        final seenPeerKeys = <String>{};
        for (final peer in model.peers) {
          if (_selectedRailId == 'recent' && _isLoopbackPeer(peer)) {
            continue;
          }
          if (query.isNotEmpty &&
              !_contactName(peer).toLowerCase().contains(query) &&
              !peer.id.toLowerCase().contains(query)) {
            continue;
          }
// 联系人分类筛选：跳过不属于当前分类的会话。
          if (_selectedCategoryFilter != null &&
              _selectedRailId == 'contacts' &&
              _categoryModel.getPeerCategory(peer.id) !=
                  _selectedCategoryFilter) {
            continue;
          }
          if (friendsOnly &&
              !_directChatAccess.isFriend(
                _conversationPeerId(peer.id, pairings: directPairings),
              )) {
            continue;
          }
          final identity = _historyIdentity(peer);
          if (_selectedRailId == 'recent' && !seenPeerKeys.add(identity)) {
            continue;
          }
          peers.add(peer);
        }
        final peerIds = peers.map((peer) => peer.id).toSet();
        final standalonePairings = (_selectedRailId == 'contacts'
                ? directPairings.values
                : const <DirectPairing>[])
            .where((pairing) {
          if (peerIds.contains(pairing.peerId)) return false;
          if (friendsOnly && !_directChatAccess.isFriend(pairing.peerId)) {
            return false;
          }
// 分类筛选：跳过不属于当前分类的配对。
          if (_selectedCategoryFilter != null &&
              _selectedRailId == 'contacts' &&
              _categoryModel.getPeerCategory(pairing.peerId) !=
                  _selectedCategoryFilter) {
            return false;
          }
          if (query.isEmpty) return true;
          return pairing.peerId.toLowerCase().contains(query) ||
              pairing.displayName.toLowerCase().contains(query) ||
              pairing.endpoints.any(
                (endpoint) => endpoint.toLowerCase().contains(query),
              );
        }).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (peers.isEmpty && standalonePairings.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    _selectedRailId == 'discovered'
                        ? Icons.radar_rounded
                        : Icons.people_outline_rounded,
                    size: 42,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.22),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    translate('No contacts yet'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (_selectedRailId == 'contacts') ...<Widget>[
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => _showDirectConnectDialog(context),
                      icon:
                          const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: Text(translate('Add contact')),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        final personGroups = _buildPersonGroups(
          peers: peers,
          pairings: standalonePairings,
          allPairings: directPairings,
          myId: gFFI.serverModel.id,
        );
        final rows = <Object>[];
        void addGroup(String label, bool friends) {
          final grouped = personGroups
              .where(
                  (group) => _directChatAccess.isFriend(group.key) == friends)
              .toList(growable: false);
          if (grouped.isEmpty) return;
          rows.add(_PeopleGroupHeader(label, grouped.length));
          rows.addAll(grouped);
        }

        if (friendsOnly) {
          rows.addAll(personGroups);
        } else {
          addGroup('Friends', true);
          addGroup('Strangers', false);
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 1),
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is _PeopleGroupHeader) {
              return _buildPeopleGroupHeader(context, row);
            }
            return _buildPersonContactItem(
              context,
              row as _DesktopPersonGroup,
              directPairings,
            );
          },
        );
      },
    );
  }

  String _formatMeetingTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (diff == 0) return '$hh:$mm';
    if (diff == 1) return '${translate('Yesterday')} $hh:$mm';
    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  Future<void> _joinMeetingByCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(translate('Join meeting')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: translate('Enter meeting code'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(translate('Cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(translate('Join')),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final normalized = code.toLowerCase();
    MeetingGroup? group;
    for (final m in MeetingGroupStore.all) {
      if (m.inviteShortCode.toLowerCase() == normalized ||
          m.meetingId.toLowerCase() == normalized) {
        group = m;
        break;
      }
    }
    if (group == null) {
      showToast(translate('Meeting not found'));
      return;
    }
    final target = group;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MeetingGroupPanel(group: target),
      ),
    );
  }

  Widget _buildPeopleGroupHeader(
    BuildContext context,
    _PeopleGroupHeader group,
  ) {
    final theme = Theme.of(context);
    Widget header({bool highlighted = false}) => Container(
          height: 32,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: highlighted
              ? theme.colorScheme.primary.withOpacity(0.18)
              : theme.brightness == Brightness.dark
                  ? const Color(0xFF202227)
                  : const Color(0xFFF1F3F5),
          child: Text(
            '${translate(group.label)} (${group.count})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.62),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    return header();
  }

  String _historyIdentity(Peer peer) {
    final identity = peer.displayName.trim().isNotEmpty
        ? peer.displayName
        : peer.hostname.trim().isNotEmpty
            ? peer.hostname
            : peer.id;
    return identity.trim().toLowerCase();
  }

  bool _isLoopbackPeer(Peer peer) {
    final value = peer.id.trim().replaceAll(' ', '');
    if (value.isEmpty) return false;
    final host = value.startsWith('[')
        ? value.substring(1, value.indexOf(']'))
        : value.contains(':')
            ? value.substring(0, value.lastIndexOf(':'))
            : value;
    return host == 'localhost' || host == '::1' || host.startsWith('127.');
  }

  DateTime _conversationTime(MapEntry<MessageKey, MessageBody> entry) {
    final messages = entry.value.chatMessages;
    if (messages.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return messages
        .map((message) => message.createdAt)
        .reduce((latest, value) => value.isAfter(latest) ? value : latest);
  }

  String _conversationPreview(MapEntry<MessageKey, MessageBody> entry) {
    final messages = entry.value.chatMessages;
    if (messages.isEmpty) return translate('Start a conversation');
    final message = messages.reduce(
      (latest, value) =>
          value.createdAt.isAfter(latest.createdAt) ? value : latest,
    );
    final properties = message.customProperties;
    if (properties?['ldesk_kind'] == 'file') {
      final fileName = (properties?['ldesk_file_name'] ?? '').toString();
      return fileName.isEmpty ? translate('File Transfer') : fileName;
    }
    if (properties?['ldesk_kind'] == 'voice') {
      return translate('Voice message');
    }
    return message.text.trim().isEmpty
        ? translate('Message')
        : message.text.trim();
  }

  /// Returns null if the last message is not a file.
  IconData? _conversationFileIcon(MapEntry<MessageKey, MessageBody> entry) {
    final messages = entry.value.chatMessages;
    if (messages.isEmpty) return null;
    final message = messages.reduce(
      (latest, value) =>
          value.createdAt.isAfter(latest.createdAt) ? value : latest,
    );
    final properties = message.customProperties;
    if (properties?['ldesk_kind'] != 'file') return null;
    final fileName = (properties?['ldesk_file_name'] ?? '').toString();
    if (fileName.isEmpty) return null;
    return _chatFileTypeIcon(fileName);
  }

  IconData _chatFileTypeIcon(String fileName) {
    final ext =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
      case 'svg':
        return Icons.image_outlined;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case 'wmv':
      case 'flv':
        return Icons.movie_outlined;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
        return Icons.audiotrack_outlined;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_outlined;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_outlined;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_outlined;
      case 'txt':
      case 'md':
      case 'log':
        return Icons.article_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _conversationTimeLabel(DateTime value) {
    if (value.millisecondsSinceEpoch == 0) return '';
    final now = DateTime.now();
    if (value.year == now.year &&
        value.month == now.month &&
        value.day == now.day) {
      return '${value.hour.toString().padLeft(2, '0')}:'
          '${value.minute.toString().padLeft(2, '0')}';
    }
    if (value.year == now.year) return '${value.month}/${value.day}';
    return '${value.year}/${value.month}/${value.day}';
  }

  void _openConversation(MapEntry<MessageKey, MessageBody> entry) {
    final peerId = entry.key.peerId.trim();
    RuntimeLogger.instance.info('OPENCONV',
        'peerId=${peerId} name=${entry.value.chatUser.firstName} msgs=${entry.value.chatMessages.length}');
    if (peerId.isEmpty) return;
    if (peerId == kFileHelperId) {
      setState(() {
        _selectedContact = null;
        _selectedConversationPeerId = peerId;
        _activeDirectChatPeerId = null;
      });
      gFFI.chatModel.changeCurrentKey(entry.key);
      return;
    }
    if (gFFI.chatSettingsModel.isBlocked(peerId)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(translate('This contact is blocked'))),
      );
      return;
    }
    final registered = _directChatSessionFor(peerId);
    final active = registered != null &&
            !registered.closed &&
            (registered.ffiModel.lastConnectionError ?? '').isEmpty
        ? registered
        : null;
    final incoming =
        active == null ? _incomingDirectChatClientFor(peerId) : null;
    final model = active?.chatModel ?? gFFI.chatModel;
    final contact = gFFI.recentPeersModel.peers.firstWhereOrNull(
      (peer) => peer.id == peerId,
    );
    setState(() {
      _selectedContact = contact;
      _selectedConversationPeerId = peerId;
      _activeDirectChatPeerId = active == null ? null : peerId;
    });
    model.changeCurrentKey(
      MessageKey(peerId, incoming?.id ?? ChatModel.clientModeID),
    );
    model.updatePeerIdentity(
      peerId,
      displayName: entry.value.chatUser.firstName ?? peerId,
      avatar: entry.value.chatUser.profileImage ?? '',
    );
    if (active == null && incoming == null) {
      unawaited(_startDirectChat(peerId));
    }
  }

  Widget _buildConversationList(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        gFFI.chatModel,
        gFFI.serverModel,
        DirectPairingStore.revision,
        gFFI.chatSettingsModel,
        _directChatAccess,
        _contactQuery,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final conversationHoverColor = theme.brightness == Brightness.dark
            ? const Color(0xFF34373D)
            : kWeChatConversationHoverColor;
        final query = _contactQuery.value.trim().toLowerCase();
        final entries = gFFI.chatModel.messages.entries.where((entry) {
          final peerId = entry.key.peerId.trim();
          if (peerId.isEmpty ||
              peerId == gFFI.chatModel.me.id ||
              peerId == kFileHelperId) {
            return false;
          }
          if (query.isEmpty) return true;
          final name = (entry.value.chatUser.firstName ?? '').toLowerCase();
          return peerId.toLowerCase().contains(query) ||
              name.contains(query) ||
              _conversationPreview(entry).toLowerCase().contains(query);
        }).toList(growable: false)
          ..sort(
            (a, b) => _conversationTime(b).compareTo(_conversationTime(a)),
          );
        final meetings = MeetingGroupStore.all;
        final meetingEntries = meetings.where((m) {
          if (query.isEmpty) return true;
          return m.title.toLowerCase().contains(query);
        }).toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        // ?????????PC/???????? ID?????????
        final chatGroups = <String, _ChatPersonGroup>{};
        final chatSignatureKeys = <String, String>{};
        for (final entry in entries) {
          final peerId = entry.key.peerId.trim();
          final conversationId = _conversationPeerId(peerId);
          final contact = _findContact(peerId);
          var signature =
              contact == null ? null : _mobileDeviceSignatureFromPeer(contact);
          if (signature == null) {
            final pairing = DirectPairingStore.find(peerId) ??
                DirectPairingStore.findByEndpoint(peerId) ??
                DirectPairingStore.findForConversation(peerId);
            if (pairing != null) {
              signature = _mobileDeviceSignatureFromPairing(pairing);
            }
          }
          var key = conversationId.isEmpty ? peerId : conversationId;
          if (signature != null && chatSignatureKeys.containsKey(signature)) {
            key = chatSignatureKeys[signature]!;
          }
          final group =
              chatGroups.putIfAbsent(key, () => _ChatPersonGroup(key));
          if (signature != null) {
            chatSignatureKeys.putIfAbsent(signature, () => group.key);
          }
          group.conversations.add(entry);
        }
        final chatGroupList = chatGroups.values.toList();
        final rows = <Object>[];
        // PC 端不显示“文件传输助手”（那是手机扫码/绑定入口的替代品，
        // PC 端已有扫码绑定弹窗，不应混入会话列表）。
        // 会议与普通会话先合并为统一列表，再按 会议/好友/陌生 三大类分组：
        // 每个分组带灰色小标题，组内按最近活动时间排序。
        // 去重：会议一旦有聊天记录（meeting:xxx 会话已进 chatGroups），
        // 就不再重复显示“会议条目”，只显示带消息预览的会话行。
        final unified = <Object>[];
        final chatKeys = <String>{
          for (final g in chatGroupList) g.key,
        };
        for (final group in chatGroupList) {
          if (group.conversations.length == 1) {
            unified.add(group.conversations.first);
          } else {
            unified.add(group);
          }
        }
        unified.addAll(
          meetingEntries.where((m) => !chatKeys.contains(m.conversationId)),
        );
        unified.sort((a, b) {
          final ta = a is MapEntry<MessageKey, MessageBody>
              ? _conversationTime(a as MapEntry<MessageKey, MessageBody>)
              : a is _ChatPersonGroup
                  ? (a as _ChatPersonGroup).lastMessageTime
                  : (a as MeetingGroup).createdAt;
          final tb = b is MapEntry<MessageKey, MessageBody>
              ? _conversationTime(b as MapEntry<MessageKey, MessageBody>)
              : b is _ChatPersonGroup
                  ? (b as _ChatPersonGroup).lastMessageTime
                  : (b as MeetingGroup).createdAt;
          return tb.compareTo(ta);
        });
        // 三大类分组：会议 / 好友 / 陌生。
        String? _peerIdOf(Object item) {
          if (item is MapEntry<MessageKey, MessageBody>) {
            return item.key.peerId;
          }
          if (item is _ChatPersonGroup) {
            return item.conversations.isNotEmpty
                ? item.conversations.first.key.peerId
                : null;
          }
          return null;
        }

        bool _isMeetingItem(Object item) {
          if (item is MeetingGroup) return true;
          final pid = _peerIdOf(item);
          return pid != null && pid.startsWith('meeting:');
        }

        final meetingRows = <Object>[];
        final friendRows = <Object>[];
        final strangerRows = <Object>[];
        for (final item in unified) {
          if (_isMeetingItem(item)) {
            meetingRows.add(item);
            continue;
          }
          final pid = _peerIdOf(item);
          final isFriend =
              pid != null && _directChatAccess.isFriend(pid);
          (isFriend ? friendRows : strangerRows).add(item);
        }
        if (meetingRows.isNotEmpty) {
          rows.add(_PeopleGroupHeader(
              translate('Meeting'), meetingRows.length));
          rows.addAll(meetingRows);
        }
        if (friendRows.isNotEmpty) {
          rows.add(
              _PeopleGroupHeader(translate('Friends'), friendRows.length));
          rows.addAll(friendRows);
        }
        if (strangerRows.isNotEmpty) {
          rows.add(_PeopleGroupHeader(
              translate('Strangers'), strangerRows.length));
          rows.addAll(strangerRows);
        }
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.forum_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurface.withOpacity(0.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    translate('No conversations yet'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _clientIdFocusNode.requestFocus,
                    icon: const Icon(Icons.add_comment_outlined, size: 18),
                    label: Text(translate('New conversation')),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: rows.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 65,
            endIndent: 12,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF3A3D43)
                : const Color(0xFFE5E5E7),
          ),
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is _PeopleGroupHeader) {
              return _buildPeopleGroupHeader(context, row);
            }
            if (row is _ChatPersonGroup) {
              return _buildMergedChatRow(context, row);
            }
            if (row is MeetingGroup) {
              final meeting = row;
              final isSelected =
                  _selectedConversationPeerId == 'meeting:${meeting.meetingId}';
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedConversationPeerId =
                        'meeting:${meeting.meetingId}';
                    _selectedContact = null;
                    _activeDirectChatPeerId = null;
                  });
                  gFFI.chatModel.changeCurrentKey(
                    MessageKey(
                        'meeting:${meeting.meetingId}', ChatModel.clientModeID),
                  );
                },
                onSecondaryTapUp: (details) {
                  _showMeetingGroupSettings(context, meeting);
                },
                child: Material(
                  color: isSelected
                      ? Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF087A4E)
                          : kWeChatSelectedConversationColor
                      : Colors.transparent,
                  child: InkWell(
                    hoverColor: conversationHoverColor,
                    child: SizedBox(
                      height: 68,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF1A8E1A).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.groups_rounded,
                                  size: 22, color: Color(0xFF1A8E1A)),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    meeting.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: isSelected ? Colors.white : null,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${(meeting.members?.length ?? 0) + 1} ${translate('members')} · ${meeting.isHost ? translate('Host') : translate('Member')}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isSelected
                                          ? Colors.white.withOpacity(0.82)
                                          : theme.colorScheme.onSurface
                                              .withOpacity(0.48),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            final entry = row as MapEntry<MessageKey, MessageBody>;
            final peerId = entry.key.peerId;
            final user = entry.value.chatUser;
            final name = (user.firstName ?? '').trim();
            final contact = _findContact(peerId);
            final displayName = peerId == kFileHelperId
                ? translate('File Transfer Assistant')
                : _resolveConversationDisplayName(
                    peerId,
                    contactName: contact?.finalName() ?? '',
                    chatName: name,
                    idFallback: peerId,
                  );
            final selected = _selectedConversationPeerId == peerId;
            final isFriend = _directChatAccess.isFriend(peerId);
            final targetGroup = isFriend ? 'Strangers' : 'Friends';
            final client = gFFI.serverModel.clients.firstWhereOrNull(
              (client) =>
                  client.peerId == peerId &&
                  client.isChat &&
                  !client.disconnected,
            );
            final conversationRow = GestureDetector(
              onSecondaryTapDown: (details) => _showManagedEntryMenu(
                context,
                peerId,
                details.globalPosition,
              ),
              onDoubleTap: _contactSelectionMode
                  ? null
                  : () => _connectDirect(context, peerId),
              child: Material(
                color: selected
                    ? Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF087A4E)
                        : kWeChatSelectedConversationColor
                    : Colors.transparent,
                child: InkWell(
                  hoverColor: conversationHoverColor,
                  onTap: _contactSelectionMode
                      ? () => _toggleManagedEntry(peerId)
                      : () => _openConversation(entry),
                  child: SizedBox(
                    height: 80,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: <Widget>[
                          if (_contactSelectionMode) ...[
                            Checkbox(
                              value: _selectedManagedEntries.contains(peerId),
                              onChanged: (_) => _toggleManagedEntry(peerId),
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (peerId == kFileHelperId)
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF1A8E1A).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.folder_shared_rounded,
                                  size: 22, color: Color(0xFF1A8E1A)),
                            )
                          else
                            _buildConversationAvatar(
                              avatar: user.profileImage ?? '',
                              name: displayName,
                              initial: displayName.characters.first,
                              size: 40,
                              peerId: peerId,
                              platform: contact?.platform ?? '',
                            ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodyLarge?.copyWith(
                                          color: selected
                                              ? Colors.white
                                              : theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 15,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _conversationTimeLabel(
                                        _conversationTime(entry),
                                      ),
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: selected
                                            ? Colors.white.withOpacity(0.82)
                                            : theme.colorScheme.onSurface
                                                .withOpacity(0.46),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: <Widget>[
                                    if (_conversationFileIcon(entry)
                                        case final icon?)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 5),
                                        child: Icon(
                                          icon,
                                          size: 14,
                                          color: selected
                                              ? Colors.white.withOpacity(0.82)
                                              : theme.colorScheme.onSurface
                                                  .withOpacity(0.46),
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        _conversationPreview(entry),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: selected
                                              ? Colors.white.withOpacity(0.88)
                                              : theme.colorScheme.onSurface
                                                  .withOpacity(0.52),
                                          fontSize: 12,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ),
                                    if (client != null)
                                      unreadMessageCountBuilder(
                                        client.unreadChatMessageCount,
                                      ).marginOnly(left: 8),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            return Dismissible(
              key: ValueKey<String>('conversation-$peerId-$targetGroup'),
              direction: DismissDirection.startToEnd,
              dismissThresholds: const <DismissDirection, double>{
                DismissDirection.startToEnd: 0.34,
              },
              confirmDismiss: (_) async {
                if (!isFriend && gFFI.chatSettingsModel.isBlocked(peerId)) {
                  await gFFI.chatSettingsModel.toggleBlock(peerId);
                }
                await _directChatAccess.setPeerPolicy(
                  peerId,
                  isFriend ? 'ask' : 'allow',
                );
                return false;
              },
              background: ColoredBox(
                color: isFriend
                    ? theme.colorScheme.onSurface.withOpacity(0.1)
                    : theme.colorScheme.primary,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          isFriend
                              ? Icons.person_outline_rounded
                              : Icons.person_add_alt_1_rounded,
                          size: 20,
                          color: isFriend
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          translate(targetGroup),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: isFriend
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: conversationRow,
            );
          },
        );
      },
    );
  }

  Widget _buildPairedContactItem(
    BuildContext context,
    DirectPairing pairing,
  ) {
    final ffi = _directChatSessionFor(pairing.peerId);
    if (ffi != null) {
      return AnimatedBuilder(
        animation: ffi.ffiModel,
        builder: (context, _) => _buildPairedContactItemBody(context, pairing),
      );
    }
    return _buildPairedContactItemBody(context, pairing);
  }

  Widget _buildPairedContactItemBody(
    BuildContext context,
    DirectPairing pairing,
  ) {
    final theme = Theme.of(context);
    final conversationHoverColor = theme.brightness == Brightness.dark
        ? const Color(0xFF34373D)
        : kWeChatConversationHoverColor;
    final contact = _findContact(pairing.peerId);
    final name = contact != null
        ? contact.finalName()
        : (pairing.displayName.isEmpty ? pairing.peerId : pairing.displayName);
    final selected = _selectedConversationPeerId == pairing.peerId;
    final delivery = _directDeliveryStatus(pairing.peerId);
    return GestureDetector(
      onSecondaryTapDown: (details) => _showManagedEntryMenu(
        context,
        pairing.peerId,
        details.globalPosition,
      ),
      onDoubleTap: _contactSelectionMode
          ? null
          : () => _connectDirect(context, pairing.peerId),
      child: Material(
        color: selected
            ? theme.colorScheme.onSurface.withOpacity(0.08)
            : Colors.transparent,
        child: InkWell(
          hoverColor: conversationHoverColor,
          onTap: _contactSelectionMode
              ? () => _toggleManagedEntry(pairing.peerId)
              : () => _startDirectChat(pairing.peerId),
          child: SizedBox(
            height: 66,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: <Widget>[
                  if (_contactSelectionMode) ...[
                    Checkbox(
                      value: _selectedManagedEntries.contains(pairing.peerId),
                      onChanged: (_) => _toggleManagedEntry(pairing.peerId),
                    ),
                    const SizedBox(width: 4),
                  ],
                  _buildConversationAvatar(
                    avatar: pairing.avatar,
                    name: name,
                    initial: name.characters.first,
                    size: 42,
                    peerId: pairing.peerId,
                    platform: pairing.platform,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                pairing.peerId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.48),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              translate(delivery.$1),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: delivery.$2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactItem(
    BuildContext context,
    Peer peer,
    Map<String, DirectPairing> pairings,
  ) {
    final conversationPeerId = _conversationPeerId(peer.id, pairings: pairings);
    final ffi = _directChatSessionFor(conversationPeerId);
    final body = ffi != null
        ? AnimatedBuilder(
            animation: ffi.ffiModel,
            builder: (context, _) => _buildContactItemBody(
              context,
              peer,
              conversationPeerId,
            ),
          )
        : _buildContactItemBody(context, peer, conversationPeerId);
// 联系人页支持拖拽排序。
    if (_selectedRailId != 'contacts') return body;
    return LongPressDraggable<String>(
      data: peer.id,
      delay: const Duration(milliseconds: 200),
      feedback: _buildDragFeedback(context, peer),
      childWhenDragging: Opacity(opacity: 0.3, child: body),
      onDragStarted: () => setState(() => _draggingPeerId = peer.id),
      onDragEnd: (_) => setState(() => _draggingPeerId = null),
      child: body,
    );
  }

  Widget _buildDragFeedback(BuildContext context, Peer peer) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 240,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.person_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _contactName(peer),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactItemBody(
    BuildContext context,
    Peer peer,
    String conversationPeerId,
  ) {
    final theme = Theme.of(context);
    final conversationHoverColor = theme.brightness == Brightness.dark
        ? const Color(0xFF34373D)
        : kWeChatConversationHoverColor;
    final name = _contactName(peer);
    final selected = _selectedConversationPeerId == conversationPeerId;
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;
    final delivery =
        _contactDeliveryStatus(peer, conversationPeerId: conversationPeerId);
    return GestureDetector(
      onSecondaryTapDown: (details) => _showManagedEntryMenu(
        context,
        peer.id,
        details.globalPosition,
        peer: peer,
      ),
      onDoubleTap: _contactSelectionMode
          ? null
          : () => _connectDirect(context, conversationPeerId),
      child: Material(
        color: selected
            ? theme.colorScheme.onSurface.withOpacity(0.08)
            : Colors.transparent,
        child: InkWell(
          hoverColor: conversationHoverColor,
          onTap: _contactSelectionMode
              ? () => _toggleManagedEntry(peer.id)
              : () => _openContactConversation(peer),
          child: SizedBox(
            height: 66,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: <Widget>[
                  if (_contactSelectionMode) ...[
                    Checkbox(
                      value: _selectedManagedEntries.contains(peer.id),
                      onChanged: (_) => _toggleManagedEntry(peer.id),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      _buildConversationAvatar(
                        avatar: peer.avatar,
                        name: name,
                        initial: initial,
                        size: 42,
                        peerId: conversationPeerId,
                        platform: peer.platform,
                        badgeTopLeft: true,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: peer.online
                                ? const Color(0xFF2BB673)
                                : const Color(0xFFA7A9AF),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            const Expanded(child: SizedBox.shrink()),
                            const SizedBox(width: 6),
                            Text(
                              translate(delivery.$1),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: delivery.$2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ????/????? peer ?????????????????????
  /// ??????? ID ???????????????????
  List<_DesktopPersonGroup> _buildPersonGroups({
    required Iterable<Peer> peers,
    required Iterable<DirectPairing> pairings,
    required Map<String, DirectPairing> allPairings,
    required String myId,
  }) {
    final groups = <String, _DesktopPersonGroup>{};
    final signatureKeys = <String, String>{};

    void rememberSignature(String? signature, String key) {
      if (signature == null || signature.isEmpty) return;
      signatureKeys.putIfAbsent(signature, () => key);
    }

    _DesktopPersonGroup groupForPairing(DirectPairing pairing) {
      final key = pairing.conversationId;
      var group = groups[key];
      if (group == null) {
        final signature = _mobileDeviceSignatureFromPairing(pairing);
        if (signature != null && signatureKeys.containsKey(signature)) {
          group = groups[signatureKeys[signature]];
        }
      }
      group ??= groups[key] = _DesktopPersonGroup(key);
      rememberSignature(_mobileDeviceSignatureFromPairing(pairing), group.key);
      return group;
    }

    _DesktopPersonGroup groupForPeer(Peer peer) {
      final conversationId =
          _conversationPeerId(peer.id, pairings: allPairings);
      var group = groups[conversationId];
      if (group == null) {
        final signature = _mobileDeviceSignatureFromPeer(peer);
        if (signature != null && signatureKeys.containsKey(signature)) {
          group = groups[signatureKeys[signature]];
        }
      }
      group ??= groups[conversationId] = _DesktopPersonGroup(conversationId);
      rememberSignature(_mobileDeviceSignatureFromPeer(peer), group.key);
      return group;
    }

    for (final pairing in pairings) {
      if (pairing.peerId.isEmpty || pairing.peerId == myId) continue;
      groupForPairing(pairing).addPairing(pairing);
    }
    for (final peer in peers) {
      if (peer.id.isEmpty || peer.id == myId) continue;
      groupForPeer(peer).addPeer(peer);
    }
    final list = groups.values.toList();
    list.sort((a, b) {
      final aTime =
          a.primaryPairing?.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          b.primaryPairing?.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return list;
  }

  Widget _buildPersonContactItem(
    BuildContext context,
    _DesktopPersonGroup group,
    Map<String, DirectPairing> pairings,
  ) {
    final theme = Theme.of(context);
    final conversationHoverColor = theme.brightness == Brightness.dark
        ? const Color(0xFF34373D)
        : kWeChatConversationHoverColor;
    final pairing = group.primaryPairing;
    final peer = group.primaryPeer;
    final primaryPeerId = group.primaryPeerId;
    final contact = _findContact(primaryPeerId);
    final conversationContact = contact ?? peer;
    final name = contact != null
        ? (_isMobilePeerPlatform(contact.platform) &&
                _peerDeviceName(contact).isNotEmpty
            ? _peerDeviceName(contact)
            : contact.finalName())
        : (pairing != null
            ? (pairing.displayName.isEmpty
                ? primaryPeerId
                : pairing.displayName)
            : (peer != null ? _contactName(peer) : primaryPeerId));
    final selected = _selectedConversationPeerId == primaryPeerId;
    final delivery = _directDeliveryStatus(primaryPeerId, contact: peer);
    final deviceSummary = group.deviceSummary;
    final platform = pairing?.platform ?? peer?.platform ?? '';
    final muted = theme.colorScheme.onSurface.withOpacity(0.48);
    final subtitle = deviceSummary;
    return GestureDetector(
      onSecondaryTapDown: (details) => _showManagedEntryMenu(
        context,
        primaryPeerId,
        details.globalPosition,
        peer: peer,
      ),
      onDoubleTap: _contactSelectionMode
          ? null
          : () => _connectDirect(context, primaryPeerId),
      child: Material(
        color: selected
            ? theme.colorScheme.onSurface.withOpacity(0.08)
            : Colors.transparent,
        child: InkWell(
          hoverColor: conversationHoverColor,
          onTap: _contactSelectionMode
              ? () => _toggleManagedEntry(primaryPeerId)
              : () {
                  if (conversationContact != null) {
                    _openContactConversation(conversationContact);
                  } else if (pairing != null) {
                    _startDirectChat(pairing.peerId);
                  }
                },
          child: SizedBox(
            height: 66,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: <Widget>[
                  if (_contactSelectionMode) ...[
                    Checkbox(
                      value: _selectedManagedEntries.contains(primaryPeerId),
                      onChanged: (_) => _toggleManagedEntry(primaryPeerId),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      _buildConversationAvatar(
                        avatar: pairing?.avatar ?? peer?.avatar ?? '',
                        name: name,
                        initial: name.trim().isEmpty
                            ? '?'
                            : name.trim().characters.first,
                        size: 42,
                        peerId: primaryPeerId,
                        platform: platform,
                        badgeTopLeft: true,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: (peer?.online == true) ||
                                    _rendezvousOnlineByPeer[primaryPeerId] ==
                                        true ||
                                    group.devices.any((d) =>
                                        _rendezvousOnlineByPeer[d.peerId] ==
                                        true) ||
                                    group.peers.any((p) =>
                                        _rendezvousOnlineByPeer[p.id] == true)
                                ? const Color(0xFF2BB673)
                                : const Color(0xFFA7A9AF),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (group.deviceCount > 1) ...<Widget>[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: deviceSummary,
                                child: Icon(
                                  Icons.devices_rounded,
                                  size: 14,
                                  color: muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              translate(delivery.$1),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: delivery.$2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ????????????????????????????/??/???
  Widget _buildMergedChatRow(
    BuildContext context,
    _ChatPersonGroup group,
  ) {
    final theme = Theme.of(context);
    final conversationHoverColor = theme.brightness == Brightness.dark
        ? const Color(0xFF34373D)
        : kWeChatConversationHoverColor;
    final primary = group.conversations.reduce(
      (a, b) => _conversationTime(b).isAfter(_conversationTime(a)) ? b : a,
    );
    final peerId = primary.key.peerId.trim();
    final user = primary.value.chatUser;
    final contact = _findContact(peerId);
    final name = contact != null
        ? (_isMobilePeerPlatform(contact.platform) &&
                _peerDeviceName(contact).isNotEmpty
            ? _peerDeviceName(contact)
            : contact.finalName())
        : ((user.firstName ?? '').trim().isEmpty
            ? peerId
            : (user.firstName ?? '').trim());
    final selected = _selectedConversationPeerId == peerId;
    final isFriend = _directChatAccess.isFriend(group.key);
    final targetGroup = isFriend ? 'Strangers' : 'Friends';
    final unread = group.conversations.fold<int>(0, (sum, entry) {
      final client = gFFI.serverModel.clients.firstWhereOrNull(
        (candidate) =>
            candidate.peerId == entry.key.peerId &&
            candidate.isChat &&
            !candidate.disconnected,
      );
      return sum + (client?.unreadChatMessageCount.value ?? 0);
    });
    final deviceNames = group.conversations
        .map((entry) => _findContact(entry.key.peerId.trim()))
        .whereType<Peer>()
        .map(_peerDeviceName)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final subtitle = deviceNames.length > 1
        ? '${translate('Mobile')} ? ${deviceNames.take(2).join(' / ')}'
        : (deviceNames.isNotEmpty ? deviceNames.first : '');
    final conversationRow = GestureDetector(
      onSecondaryTapDown: (details) => _showManagedEntryMenu(
        context,
        peerId,
        details.globalPosition,
      ),
      child: Material(
        color: selected
            ? Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF087A4E)
                : kWeChatSelectedConversationColor
            : Colors.transparent,
        child: InkWell(
          hoverColor: conversationHoverColor,
          onTap: _contactSelectionMode
              ? () => _toggleManagedEntry(peerId)
              : () => _openConversation(primary),
          child: SizedBox(
            height: 80,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: <Widget>[
                  if (_contactSelectionMode) ...[
                    Checkbox(
                      value: _selectedManagedEntries.contains(peerId),
                      onChanged: (_) => _toggleManagedEntry(peerId),
                    ),
                    const SizedBox(width: 4),
                  ],
                  _buildConversationAvatar(
                    avatar: user.profileImage ?? '',
                    name: name,
                    initial: name.isEmpty ? '?' : name.characters.first,
                    size: 40,
                    peerId: peerId,
                    platform: contact?.platform ?? '',
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: selected
                                      ? Colors.white
                                      : theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _conversationTimeLabel(
                                  _conversationTime(primary)),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: selected
                                    ? Colors.white.withOpacity(0.82)
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.46),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: selected
                                  ? Colors.white.withOpacity(0.7)
                                  : theme.colorScheme.onSurface
                                      .withOpacity(0.42),
                              fontSize: 11,
                            ),
                          ),
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            if (_conversationFileIcon(primary) case final icon?)
                              Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: Icon(
                                  icon,
                                  size: 14,
                                  color: selected
                                      ? Colors.white.withOpacity(0.82)
                                      : theme.colorScheme.onSurface
                                          .withOpacity(0.46),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                _conversationPreview(primary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: selected
                                      ? Colors.white.withOpacity(0.88)
                                      : theme.colorScheme.onSurface
                                          .withOpacity(0.52),
                                  fontSize: 12,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            if (unread > 0)
                              unreadMessageCountBuilder(RxInt(unread))
                                  .marginOnly(left: 8),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Dismissible(
      key: ValueKey<String>('conversation-merged-${group.key}'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const <DismissDirection, double>{
        DismissDirection.startToEnd: 0.34,
      },
      confirmDismiss: (_) async {
        if (!isFriend && gFFI.chatSettingsModel.isBlocked(peerId)) {
          await gFFI.chatSettingsModel.toggleBlock(peerId);
        }
        await _directChatAccess.setPeerPolicy(
          peerId,
          isFriend ? 'ask' : 'allow',
        );
        return false;
      },
      background: ColoredBox(
        color: isFriend
            ? theme.colorScheme.onSurface.withOpacity(0.1)
            : theme.colorScheme.primary,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  isFriend
                      ? Icons.person_outline_rounded
                      : Icons.person_add_alt_1_rounded,
                  size: 20,
                  color: isFriend
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  translate(targetGroup),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isFriend
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: conversationRow,
    );
  }

  String _conversationPeerId(
    String rawPeerId, {
    Map<String, DirectPairing>? pairings,
  }) {
    final requestedId = rawPeerId.trim().replaceAll(' ', '');
    if (requestedId.isEmpty) return '';
    final availablePairings = pairings ?? DirectPairingStore.load();
    return DirectPairingStore.canonicalConversationIdValue(
      requestedId,
      pairings: availablePairings,
    );
  }

  void _openContactConversation(Peer peer) {
    final requestedId = peer.id.trim();
    // A contact row may still carry a previously discovered IP. Once that
    // endpoint is paired, use the canonical device ID so a changed LAN IP
    // does not keep the chat pinned to a stale direct socket.
    final pairingForEndpoint = DirectPairingStore.findByEndpoint(requestedId);
    final connectTarget = pairingForEndpoint?.peerId ?? requestedId;
    final peerId = _conversationPeerId(requestedId);
    if (peerId.isEmpty) return;
    final registered = _directChatSessionFor(peerId);
    final active = registered != null &&
            !registered.closed &&
            (registered.ffiModel.lastConnectionError ?? '').isEmpty
        ? registered
        : null;
    final incoming =
        active == null ? _incomingDirectChatClientFor(peerId) : null;
    setState(() {
      _selectedContact = peer;
      _selectedConversationPeerId = peerId;
      _activeDirectChatPeerId = active == null ? null : peerId;
    });
    final model = active?.chatModel ?? gFFI.chatModel;
    model.changeCurrentKey(
      MessageKey(peerId, incoming?.id ?? ChatModel.clientModeID),
    );
    model.updatePeerIdentity(
      peerId,
      displayName: normalizeDirectPeerName(
        _contactName(peer),
        fallback: peerId,
      ),
      avatar: peer.avatar,
    );
    if (active == null && incoming == null) {
      unawaited(_startDirectChat(connectTarget));
    }
  }

  (String, Color) _contactDeliveryStatus(
    Peer peer, {
    String? conversationPeerId,
  }) {
    return _directDeliveryStatus(
      conversationPeerId ?? _conversationPeerId(peer.id),
      contact: peer,
    );
  }

  (String, Color) _directDeliveryStatus(String peerId, {Peer? contact}) {
    final ffi = _directChatSessionFor(peerId);
    final incoming = _incomingDirectChatClientFor(peerId);
    final error = ffi?.ffiModel.lastConnectionError ?? '';
    if ((ffi != null &&
            isDirectChatSessionReady(
              closed: ffi.closed,
              peerInfoReady: ffi.ffiModel.pi.isSet.isTrue,
              connectionError: error,
            )) ||
        incoming != null) {
      return ('Messages allowed', const Color(0xFF238A57));
    }
    if (isDirectChatPermissionDenied(error)) {
      return ('Messages rejected', const Color(0xFFD84A4A));
    }
    if (error.trim().isNotEmpty) {
      return ('Offline', const Color(0xFF8A8D94));
    }
    if (ffi == null) {
      final rendezvousOnline = _rendezvousOnlineByPeer[peerId] == true;
      return (contact?.online == true || rendezvousOnline)
          ? ('Online', const Color(0xFF238A57))
          : ('Offline', const Color(0xFF8A8D94));
    }
    if (ffi.closed) {
      return ('Offline', const Color(0xFF8A8D94));
    }
    return ('Connecting', const Color(0xFF07C160));
  }

  String _contactName(Peer peer) => peer.finalName();

  String _contactPlatformFor(String peerId) {
    if (peerId.trim().isEmpty) return '';
    final contact = _findContact(peerId);
    if (contact != null && contact.platform.trim().isNotEmpty) {
      return contact.platform;
    }
    for (final ffi in _directChatSessions.values) {
      if (!ffi.closed &&
          ffi.chatModel.currentKey.peerId == peerId &&
          ffi.ffiModel.pi.platform.trim().isNotEmpty) {
        return ffi.ffiModel.pi.platform;
      }
    }
    return '';
  }

  Widget _buildConversationAvatar({
    required String avatar,
    required String name,
    required String initial,
    required double size,
    String peerId = '',
    String platform = '',
    bool badgeTopLeft = false,
  }) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: str2color(name),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
        ),
      ),
    );
    final avatarWidget = buildAvatarWidget(
          avatar: avatar,
          size: size,
          borderRadius: 8,
          fallback: fallback,
        ) ??
        fallback;
    final muted = peerId.isNotEmpty && gFFI.chatSettingsModel.isMuted(peerId);
    final blocked =
        peerId.isNotEmpty && gFFI.chatSettingsModel.isBlocked(peerId);
    if (!muted && !blocked) {
      return avatarWithPlatformBadge(
        child: avatarWidget,
        platform: platform,
        badgeSize: size >= 40 ? 15 : 13,
        topLeft: badgeTopLeft,
      );
    }

    Widget stateBadge({
      required IconData icon,
      required String tooltip,
      required Color color,
    }) {
      return Tooltip(
        message: tooltip,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.surface,
              width: 1.5,
            ),
          ),
          child: Icon(icon, size: 12, color: Colors.white),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(child: avatarWidget),
          if (platformOsIcon(platform) != null)
            Positioned(
              left: -2,
              bottom: -2,
              top: null,
              right: null,
              child: buildPlatformBadge(
                platform: platform,
                size: size >= 40 ? 15 : 13,
              ),
            ),
          if (muted)
            Positioned(
              left: -5,
              top: -5,
              child: stateBadge(
                icon: Icons.volume_off_rounded,
                tooltip: translate('Mute'),
                color: const Color(0xFF4B5563),
              ),
            ),
          if (blocked)
            Positioned(
              right: -5,
              top: -5,
              child: stateBadge(
                icon: Icons.block_rounded,
                tooltip: translate('Blocked'),
                color: const Color(0xFFD92D20),
              ),
            ),
        ],
      ),
    );
  }

  Peers _contactModelFor(String section) {
    switch (section) {
      case 'favorites':
        return gFFI.favoritePeersModel;
      case 'discovered':
        return gFFI.lanPeersModel;
      case 'contacts':
        return gFFI.abModel.peersModel;
      case 'chat':
      case 'recent':
      default:
        return gFFI.recentPeersModel;
    }
  }

  Future<void> _loadContactSection(String section) async {
    final now = DateTime.now();
    final lastLoad = _lastContactSectionLoad[section];
    if (lastLoad != null &&
        now.difference(lastLoad) < _contactSectionRefreshInterval) {
      return;
    }
    _lastContactSectionLoad[section] = now;
    try {
      switch (section) {
        case 'favorites':
          bind.mainLoadFavPeers();
          break;
        case 'discovered':
          bind.mainLoadLanPeers();
          bind.mainDiscover();
          break;
        case 'contacts':
          await gFFI.abModel.pullAb(force: null, quiet: true);
          break;
        case 'vip':
          break;
        case 'chat':
        case 'recent':
        default:
          bind.mainLoadRecentPeers();
          break;
      }
    } catch (_) {
      _lastContactSectionLoad.remove(section);
      rethrow;
    }
  }

  Future<void> _startDirectChat(
    String rawPeerId, {
    bool activate = true,
  }) async {
    final requestedId = rawPeerId.trim().replaceAll(' ', '');
    if (requestedId.isEmpty) return;

    if (await DirectPairingStore.isSelfTarget(requestedId)) {
      if (activate) {
        _showConversationNotice(
          translate(
              'This is the current device. You cannot connect to or message yourself.'),
          tone: _WorkspaceNoticeTone.error,
        );
      }
      return;
    }
    final pairing = DirectPairingStore.find(requestedId) ??
        DirectPairingStore.findByEndpoint(requestedId) ??
        DirectPairingStore.findForConversation(requestedId);
    final peerId = DirectPairingStore.canonicalConversationId(requestedId);
    final endpoint = DirectPairingStore.resolveConnectionTarget(requestedId);
    if (endpoint == null) {
      if (activate) {
        _showConversationNotice(
          translate(
              'Direct endpoint required. Scan the PC QR code or enter IP:port.'),
          tone: _WorkspaceNoticeTone.warning,
        );
      }
      return;
    }
    if (activate) {
      unawaited(_releaseInactiveDirectChatSessions(peerId));
    }
    final contact = _findContact(peerId);
    final existing = _directChatSessionFor(peerId);
    if (existing != null && !existing.closed) {
      final attemptedAt = _directChatAttemptedAt[peerId];
      final connecting = !existing.ffiModel.pi.isSet.isTrue &&
          existing.ffiModel.lastConnectionError?.isNotEmpty != true &&
          attemptedAt != null &&
          DateTime.now().difference(attemptedAt) <
              _directChatConnectionGracePeriod;
      final ready = isDirectChatSessionReady(
        closed: existing.closed,
        peerInfoReady: existing.ffiModel.pi.isSet.isTrue,
        connectionError: existing.ffiModel.lastConnectionError,
      );
      if (ready || connecting) {
        if (activate) {
          existing.suppressConnectionDialogs = true;
          setState(() {
            _activeDirectChatPeerId = peerId;
            _selectedContact = contact;
            _selectedConversationPeerId = peerId;
          });
          existing.chatModel.requestChatInputFocus();
        }
        return;
      }
      _removeDirectChatSession(existing);
      await existing.close();
    } else if (existing != null) {
      _removeDirectChatSession(existing);
    }
    final incoming = _incomingDirectChatClientFor(peerId);
    if (incoming != null) {
      if (activate) {
        final fallbackName = normalizeDirectPeerName(
          contact == null ? '' : _contactName(contact),
          fallback: peerId,
        );
        gFFI.chatModel.changeCurrentKey(MessageKey(peerId, incoming.id));
        gFFI.chatModel.updatePeerIdentity(
          peerId,
          displayName: normalizeDirectPeerName(
            incoming.name,
            fallback: normalizeDirectPeerName(
              pairing?.displayName ?? '',
              fallback: fallbackName,
            ),
          ),
          avatar: incoming.avatar.isNotEmpty
              ? incoming.avatar
              : contact?.avatar ?? '',
        );
        setState(() {
          _activeDirectChatPeerId = null;
          _selectedContact = contact;
          _selectedConversationPeerId = peerId;
        });
        gFFI.chatModel.requestChatInputFocus();
      }
      return;
    }

    if (!_openingDirectChatPeers.add(peerId)) return;

    try {
      final ffi = FFI(null);
      ffi.suppressConnectionDialogs = true;
      final fallbackName = normalizeDirectPeerName(
        contact == null ? '' : _contactName(contact),
        fallback: peerId,
      );
      ffi.chatModel
          .changeCurrentKey(MessageKey(peerId, ChatModel.clientModeID));
      ffi.chatModel.updatePeerIdentity(
        peerId,
        displayName: normalizeDirectPeerName(
          pairing?.displayName ?? '',
          fallback: fallbackName,
        ),
        avatar: contact?.avatar ?? '',
      );
      ffi.start(endpoint,
          isChat: true,
          forceRelay: false,
          password: DirectPairingStore.cachedChatPassword(peerId));
      _directChatSessions[peerId] = ffi;
      _directChatAttemptedAt[peerId] = DateTime.now();
      if (mounted && activate) {
        setState(() {
          _activeDirectChatPeerId = peerId;
          _selectedContact = contact;
          _selectedConversationPeerId = peerId;
        });
      }
    } finally {
      _openingDirectChatPeers.remove(peerId);
    }
  }

  Peer? _findContact(String peerId) {
    for (final model in <Peers>[
      gFFI.recentPeersModel,
      gFFI.favoritePeersModel,
      gFFI.lanPeersModel,
      gFFI.abModel.peersModel,
      gFFI.groupModel.peersModel,
    ]) {
      for (final peer in model.peers) {
        if (peer.id == peerId || _conversationPeerId(peer.id) == peerId) {
          return peer;
        }
      }
    }
    // Account conversations: the person's contact is one of its devices
    // (e.g. the phone with id 372849 bound to account 423156).
    final devices = DirectPairingStore.loadPersonDevices()[
        DirectPairingStore.canonicalConversationId(peerId)];
    if (devices != null && devices.isNotEmpty) {
      for (final model in <Peers>[
        gFFI.recentPeersModel,
        gFFI.favoritePeersModel,
        gFFI.lanPeersModel,
        gFFI.abModel.peersModel,
        gFFI.groupModel.peersModel,
      ]) {
        for (final peer in model.peers) {
          if (devices.contains(peer.id)) return peer;
        }
      }
    }
    return null;
  }

  void _canonicalizeDirectChatSessions() {
    var selectionChanged = false;
    for (final entry in _directChatSessions.entries.toList(growable: false)) {
      final storagePeerId = entry.key;
      final ffi = entry.value;
      final canonicalPeerId = DirectPairingStore.canonicalConversationId(
        ffi.chatModel.currentKey.peerId,
      );
      if (canonicalPeerId.isEmpty || canonicalPeerId == storagePeerId) continue;

      final existing = _directChatSessions[canonicalPeerId];
      _directChatSessions.remove(storagePeerId);
      if (existing == null || existing.closed || identical(existing, ffi)) {
        _directChatSessions[canonicalPeerId] = ffi;
      } else {
        unawaited(ffi.close());
      }
      if (_notifiedChatConnections.remove(storagePeerId)) {
        _notifiedChatConnections.add(canonicalPeerId);
      }
      if (_selectedConversationPeerId == storagePeerId) {
        _selectedConversationPeerId = canonicalPeerId;
        selectionChanged = true;
      }
      if (_activeDirectChatPeerId == storagePeerId) {
        _activeDirectChatPeerId = canonicalPeerId;
        selectionChanged = true;
      }
    }
    if (selectionChanged && mounted) setState(() {});
  }

  FFI? _directChatSessionFor(String peerId) {
    final requestedIds = DirectPairingStore.conversationPeerIds(peerId);
    final canonicalPeerId = DirectPairingStore.canonicalConversationId(peerId);
    final direct = _directChatSessions[canonicalPeerId];
    if (direct != null) return direct;
    for (final entry in _directChatSessions.entries) {
      final sessionPeerId = entry.value.chatModel.currentKey.peerId;
      final sessionIds = <String>{
        ...DirectPairingStore.conversationPeerIds(entry.key),
        ...DirectPairingStore.conversationPeerIds(sessionPeerId),
      };
      if (requestedIds.any(sessionIds.contains)) {
        return entry.value;
      }
    }
    return null;
  }

  void _removeDirectChatSession(FFI session) {
    final keys = _directChatSessions.entries
        .where((entry) => identical(entry.value, session))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in keys) {
      _directChatSessions.remove(key);
      _directChatAttemptedAt.remove(key);
      _notifiedChatConnections.remove(key);
    }
  }

  Future<void> _releaseInactiveDirectChatSessions(String activePeerId) async {
    final staleChatPeers = _directChatSessions.entries
        .where((entry) {
          final ffi = entry.value;
          final sessionPeerId = ffi.chatModel.currentKey.peerId.trim();
          final canonicalPeerId =
              sessionPeerId.isEmpty ? entry.key : sessionPeerId;
          return canonicalPeerId != activePeerId &&
              !_directChatAccess.shouldAutoReconnect(canonicalPeerId);
        })
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final peerId in staleChatPeers) {
      final ffi = _directChatSessions.remove(peerId);
      _notifiedChatConnections.remove(peerId);
      _clearBackgroundChatRetry(peerId);
      if (ffi != null) await ffi.close();
    }

    final staleFilePeers = _directFileSessions.keys
        .where((peerId) => peerId != activePeerId)
        .toList(growable: false);
    for (final peerId in staleFilePeers) {
      final ffi = _directFileSessions.remove(peerId);
      if (ffi != null) await _disposeFileSession(ffi);
    }
  }

  Client? _incomingDirectChatClientFor(String peerId) {
    final requestedIds = DirectPairingStore.conversationPeerIds(peerId);
    for (final client in gFFI.serverModel.clients.reversed) {
      final clientIds = DirectPairingStore.conversationPeerIds(client.peerId);
      if (requestedIds.any(clientIds.contains) &&
          client.authorized &&
          client.isChat &&
          !client.disconnected) {
        return client;
      }
    }
    return null;
  }

  Future<void> _maintainTrustedChatSessions() async {
    _directChatAccess.load();
    if (!mounted ||
        !_directChatAccess.alwaysOn ||
        !_directChatAccess.autoReconnect) {
      return;
    }
    final latestPairingByConversation = <String, DirectPairing>{};
    for (final pairing in DirectPairingStore.load().values) {
      final conversationId = pairing.conversationId;
      final current = latestPairingByConversation[conversationId];
      if (current == null || pairing.updatedAt.isAfter(current.updatedAt)) {
        latestPairingByConversation[conversationId] = pairing;
      }
    }
    for (final pairing in latestPairingByConversation.values) {
      final conversationId = pairing.conversationId;
      if (!mounted ||
          pairing.companion ||
          !_directChatAccess.shouldAutoReconnect(conversationId)) {
        continue;
      }
      if (!await _canMaintainBackgroundChat(conversationId)) continue;
      final existing = _directChatSessionFor(conversationId);
      if (isDirectChatPermissionDenied(
        existing?.ffiModel.lastConnectionError,
      )) {
        _clearBackgroundChatRetry(conversationId);
        continue;
      }
      final hasError =
          existing?.ffiModel.lastConnectionError?.isNotEmpty == true;
      final connected = existing != null &&
          isDirectChatSessionReady(
            closed: existing.closed,
            peerInfoReady: existing.ffiModel.pi.isSet.isTrue,
            connectionError: existing.ffiModel.lastConnectionError,
          );
      if (connected) {
        _clearBackgroundChatRetry(conversationId);
        continue;
      }
      final attemptedAt = _directChatAttemptedAt[conversationId];
      final connecting = existing != null &&
          !existing.closed &&
          !hasError &&
          attemptedAt != null &&
          DateTime.now().difference(attemptedAt) <
              _directChatConnectionGracePeriod;
      if (connecting) continue;
      if (!_backgroundChatRetryDue(conversationId)) continue;
      if (existing != null) {
        _removeDirectChatSession(existing);
        if (!existing.closed) await existing.close();
      }
      await _startDirectChat(conversationId, activate: false);
      _recordBackgroundChatAttempt(conversationId);
    }
  }

  Future<void> _maintainPendingChatSessions() async {
    for (final peerId in _directChatAccess.autoReconnectPeerIds) {
      if (!mounted) return;
      if (!_directChatAccess.shouldAutoReconnect(peerId)) continue;
      final pending = await DirectChatRepository.instance.pendingFor(peerId);
      if (pending.isEmpty) {
        continue;
      }
      if (!await _canMaintainBackgroundChat(peerId)) continue;
      final existing = _directChatSessionFor(peerId);
      if (isDirectChatPermissionDenied(
        existing?.ffiModel.lastConnectionError,
      )) {
        _clearBackgroundChatRetry(peerId);
        continue;
      }
      final hasError =
          existing?.ffiModel.lastConnectionError?.isNotEmpty == true;
      final connected = existing != null &&
          isDirectChatSessionReady(
            closed: existing.closed,
            peerInfoReady: existing.ffiModel.pi.isSet.isTrue,
            connectionError: existing.ffiModel.lastConnectionError,
          );
      if (connected) {
        _clearBackgroundChatRetry(peerId);
        continue;
      }
      final attemptedAt = _directChatAttemptedAt[peerId];
      final connecting = existing != null &&
          !existing.closed &&
          !hasError &&
          attemptedAt != null &&
          DateTime.now().difference(attemptedAt) <
              _directChatConnectionGracePeriod;
      if (connecting) continue;
      if (!_backgroundChatRetryDue(peerId)) continue;
      if (existing != null) {
        _removeDirectChatSession(existing);
        if (!existing.closed) await existing.close();
      }
      await _startDirectChat(peerId, activate: false);
      _recordBackgroundChatAttempt(peerId);
    }
  }

  Future<void> _refreshDirectSessions() async {
    if (_refreshingDirectSessions || !mounted) return;
    _refreshingDirectSessions = true;
    try {
      await _maintainTrustedChatSessions();
      await _maintainPendingChatSessions();
      await gFFI.chatModel.syncActiveCompanionSessions();
    } finally {
      _refreshingDirectSessions = false;
    }
  }

  Future<bool> _canMaintainBackgroundChat(String peerId) async {
    if (peerId.trim().isEmpty ||
        await DirectPairingStore.isSelfTarget(peerId)) {
      _clearBackgroundChatRetry(peerId);
      return false;
    }
    return DirectPairingStore.resolveConnectionTarget(peerId) != null;
  }

  bool _backgroundChatRetryDue(String peerId) {
    final retryAfter = _backgroundChatRetryAfter[peerId];
    return retryAfter == null || !DateTime.now().isBefore(retryAfter);
  }

  void _recordBackgroundChatAttempt(String peerId) {
    final failures = (_backgroundChatFailures[peerId] ?? 0) + 1;
    _backgroundChatFailures[peerId] = failures;
    final delayIndex =
        (failures - 1).clamp(0, _backgroundChatRetryDelays.length - 1);
    _backgroundChatRetryAfter[peerId] =
        DateTime.now().add(_backgroundChatRetryDelays[delayIndex]);
  }

  void _clearBackgroundChatRetry(String peerId) {
    _backgroundChatFailures.remove(peerId);
    _backgroundChatRetryAfter.remove(peerId);
  }

  Future<void> _sendFilesFromConversation(String peerId) async {
    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    final files = picked?.files.where((file) => file.path != null).toList() ??
        <PlatformFile>[];
    if (files.isEmpty || !mounted) return;

    await _startDirectChat(peerId, activate: false);
    final chatFfi = _directChatSessionFor(peerId);
    final incoming = _incomingDirectChatClientFor(peerId);
    final hasSession =
        (chatFfi != null && !chatFfi.closed) || incoming != null;

    final chatModel =
        chatFfi != null && !chatFfi.closed ? chatFfi.chatModel : gFFI.chatModel;
    if (hasSession) {
      chatModel.changeCurrentKey(
        MessageKey(
          peerId,
          chatFfi != null && !chatFfi.closed
              ? ChatModel.clientModeID
              : incoming!.id,
        ),
      );
    }

    final transferFiles = files
        .where((file) => !canInlineDirectChatFile(file.size))
        .toList(growable: false);
    // 小文件/图片走消息队列：对方离线时自动排队，连接建立后补发。
    for (final file in files.where(
      (file) => canInlineDirectChatFile(file.size),
    )) {
      await chatModel.sendFileRecord(
        fileName: file.name,
        fileSize: file.size,
        localPath: file.path!,
      );
    }
    if (transferFiles.isNotEmpty) {
      // 超大文件需要独立文件传输会话（双向分块协议），要求对方在线。
      if (!hasSession) {
        _showConversationNotice(
          translate('Large file needs an active connection first'),
          tone: _WorkspaceNoticeTone.warning,
        );
        return;
      }
      final ffi = await _ensureDirectFileSession(peerId);
      if (ffi == null || !mounted) return;
      final items = SelectedItems(isLocal: true);
      for (final file in transferFiles) {
        items.add(
          Entry()
            ..path = file.path!
            ..name = file.name
            ..size = file.size,
        );
      }
      await ffi.fileModel.localController.sendFiles(
        items,
        ffi.fileModel.remoteController.directoryData(),
      );
      for (final file in transferFiles) {
        await chatModel.sendFileRecord(
          fileName: file.name,
          fileSize: file.size,
          localPath: file.path!,
        );
      }
    }
    _showConversationNotice(
      translate('Direct file transfer started.'),
      tone: _WorkspaceNoticeTone.success,
    );
  }

  Future<bool> _forwardConversationMessages(
    String rawTargetPeerId,
    List<ChatForwardItem> items,
    bool merged,
  ) async {
    if (items.isEmpty) return false;
    final peerId =
        DirectPairingStore.canonicalConversationId(rawTargetPeerId.trim());
    if (peerId.isEmpty || await DirectPairingStore.isSelfTarget(peerId)) {
      return false;
    }

    final isMeeting = peerId.startsWith('meeting:');
    late final ChatModel targetModel;
    if (isMeeting) {
      // 会议群聊无需建立 P2P 会话：切换到群聊会话即可发送（与在群聊
      // 窗口里直接发消息走同一路径，消息会广播给所有成员）。
      targetModel = gFFI.chatModel;
      targetModel.changeCurrentKey(
        MessageKey(peerId, ChatModel.clientModeID),
      );
    } else {
      await _startDirectChat(peerId, activate: false);
      final direct = _directChatSessionFor(peerId);
      final incoming = _incomingDirectChatClientFor(peerId);
      if (direct != null && !direct.closed) {
        targetModel = direct.chatModel;
        targetModel.changeCurrentKey(
          MessageKey(peerId, ChatModel.clientModeID),
        );
      } else if (incoming != null) {
        targetModel = gFFI.chatModel;
        targetModel.changeCurrentKey(MessageKey(peerId, incoming.id));
      } else {
        _showConversationNotice(
          translate('Unable to connect to forwarding target.'),
          tone: _WorkspaceNoticeTone.error,
        );
        return false;
      }
    }

    if (merged) {
      final senders = items
          .map((item) => item.senderName)
          .where((name) => name.isNotEmpty)
          .toSet()
          .take(2)
          .join(', ');
      await targetModel.sendForwardBundle(
        title: senders.isEmpty ? translate('Chat history') : senders,
        items: items.map((item) => item.toSummary()).toList(growable: false),
      );
      return true;
    }

    final transferableFiles = items
        .where(
          (item) =>
              item.kind == DirectChatKind.file &&
              item.localPath.isNotEmpty &&
              File(item.localPath).existsSync(),
        )
        .toList(growable: false);
    // 会议群聊不走 P2P 文件会话，只发文件记录（聊天记录卡片）。
    if (transferableFiles.isNotEmpty && !isMeeting) {
      final fileSession = await _ensureDirectFileSession(peerId);
      if (fileSession == null) return false;
      final selected = SelectedItems(isLocal: true);
      for (final item in transferableFiles) {
        selected.add(
          Entry()
            ..path = item.localPath
            ..name = item.fileName
            ..size = item.fileSize,
        );
      }
      await fileSession.fileModel.localController.sendFiles(
        selected,
        fileSession.fileModel.remoteController.directoryData(),
      );
    }

    for (final item in items) {
      if (item.kind == DirectChatKind.file) {
        if (item.localPath.isNotEmpty && File(item.localPath).existsSync()) {
          await targetModel.sendFileRecord(
            fileName: item.fileName,
            fileSize: item.fileSize,
            localPath: item.localPath,
          );
        } else {
          await targetModel.sendTextAndWait(
            '[${translate('File')}] ${item.fileName}',
          );
        }
      } else if (item.kind == DirectChatKind.voice) {
        await targetModel.sendTextAndWait(
          '[${translate('Voice')}] '
          '${(item.voiceDurationMs / 1000).ceil()}s',
        );
      } else if (item.text.isNotEmpty) {
        await targetModel.sendTextAndWait(item.text);
      }
    }
    return true;
  }

  Future<void> _pickImagesForConversation(String peerId) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    final files = picked?.files.where((file) => file.path != null).toList() ??
        <PlatformFile>[];
    if (files.isEmpty || !mounted) return;
    for (final file in files) {
      await _sendImageFile(peerId, file.path!, file.name, file.size);
    }
  }

  /// Read a clipboard image into persistent chat storage so its thumbnail and
  /// full-screen preview remain available after the transfer completes.
  Future<Map<String, dynamic>?> _readClipboardImage() async {
    try {
      String? filePath;
      String ext = 'png';
      final supportDir = await getApplicationSupportDirectory();
      final imageDir = Directory(
        '${supportDir.path}${Platform.pathSeparator}chat_images',
      );
      await imageDir.create(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final imageFile = File(
        '${imageDir.path}${Platform.pathSeparator}clipboard_image_$stamp.$ext',
      );

      if (Platform.isWindows) {
        final hasBitmap = isWindowsClipboardImageAvailable();
        if (!hasBitmap) return null;
        final tempFile = imageFile;
        final script = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'luoda_clip_$stamp.ps1',
        );
        final safePath = tempFile.path.replaceAll('\\', '\\\\');
        await script.writeAsString(
          'Add-Type -AssemblyName System.Windows.Forms;\n'
          'if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) { exit 1 }\n'
          '\$img = [System.Windows.Forms.Clipboard]::GetImage();\n'
          '\$img.Save("$safePath", [System.Drawing.Imaging.ImageFormat]::Png);\n'
          '\$img.Dispose()\n',
        );
        final result = await Process.run(
          'powershell',
          ['-NoProfile', '-NonInteractive', '-File', script.path],
        );
        try {
          await script.delete();
        } catch (_) {}
        if (result.exitCode == 0 && await tempFile.exists()) {
          filePath = tempFile.path;
        }
      } else if (Platform.isMacOS) {
        final tempFile = imageFile;
        final result = await Process.run('osascript', [
          '-e',
          'try\n'
              'set f to (open for access POSIX file "${tempFile.path}" with write permission)\n'
              'set eof f to 0\n'
              'write (the clipboard as «class PNGf» to f\n'
              'close access f\n'
              'return "ok"\n'
              'on error errMsg\n'
              'return "NO_IMAGE"\n'
              'end try',
        ]);
        final out = (result.stdout as String).trim();
        if (out == 'ok' && await tempFile.exists()) {
          filePath = tempFile.path;
        }
      } else if (Platform.isLinux) {
        final result = await Process.run('xclip', [
          '-selection',
          'clipboard',
          '-t',
          'image/png',
          '-o',
        ]);
        if (result.exitCode == 0) {
          final stdout = result.stdout;
          Uint8List bytes;
          if (stdout is Uint8List) {
            bytes = stdout;
          } else {
            bytes = Uint8List.fromList(
              (stdout as String).codeUnits,
            );
          }
          if (bytes.isNotEmpty) {
            final tempFile = imageFile;
            await tempFile.writeAsBytes(bytes);
            if (await tempFile.exists()) {
              filePath = tempFile.path;
            }
          }
        }
      }

      if (filePath == null) return null;

      final file = File(filePath);
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      return {
        'path': filePath,
        'name': 'clipboard_image_$stamp.$ext',
        'size': bytes.length,
      };
    } catch (_) {
      return null;
    }
  }

  Future<bool> _pasteImageToConversation(
    String peerId, {
    required bool notifyIfEmpty,
  }) async {
    final clipboard = await _readClipboardImage();
    if (clipboard == null) {
      if (!notifyIfEmpty || !mounted) return false;
      _showConversationNotice(
        translate('Clipboard has no image'),
        tone: _WorkspaceNoticeTone.warning,
      );
      return false;
    }
    await _sendImageFile(
      peerId,
      clipboard['path']! as String,
      clipboard['name']! as String,
      clipboard['size']! as int,
    );
    return true;
  }

  /// 发送输入框内“待发送图片”（截图标注完成后由用户点发送触发）。
  Future<void> _sendStagedImage(String peerId, String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final size = await file.length();
      final name = path.split(Platform.pathSeparator).last;
      await _sendImageFile(peerId, path, name, size);
    } catch (_) {
      if (mounted) {
        _showConversationNotice(
          translate('Failed to send image'),
          tone: _WorkspaceNoticeTone.warning,
        );
      }
    }
  }

  /// Captures the screen, lets the user select a region and annotate it
  /// (pen / rectangle / arrow / text), then stages the composed image into
  /// the input box of the current conversation (user presses Send to send).
  Future<void> _screenshotForConversation(String peerId) async {
    if (!mounted) return;
    // 剪刀右侧下拉箭头设置的“隐藏本窗口/不隐藏”偏好。
    final hideWindow =
        bind.mainGetLocalOption(key: 'screenshot_hide_window') != '0';
    // 截图前把主窗口移出屏幕（而不是 hide），截图后移回原位。
    // 之前用 windowManager.hide() 在部分机器上恢复失败，导致整个应用
    // 从屏幕上消失（用户反馈“不能截图”的直接根因之一）。移出屏幕是
    // 纯位置操作，即使截图异常中断窗口也仍在任务栏/屏幕外，恢复可靠。
    Offset? savedPos;
    var windowMoved = false;
    if (hideWindow) {
      try {
        savedPos = await windowManager.getPosition();
        await windowManager.setPosition(const Offset(-32000, -32000));
        windowMoved = true;
        await Future<void>.delayed(const Duration(milliseconds: 360));
      } catch (_) {
        windowMoved = false;
      }
    }
    String? path;
    try {
      if (Platform.isWindows) {
        // Windows：先框选、后截取区域（微信式截图）。用户直接在实时
        // 屏幕上拖拽框选（或按住 Ctrl 自动选窗口），确认后只截取选中
        // 区域。返回 null = 用户按 Esc 取消。
        path = await captureRegionToFile();
      } else {
        // 其它平台：全屏截图后在图上框选。
        path = await captureScreenToFile();
      }
      if (path == null && mounted) {
        _showConversationNotice(
          translate('Screenshot cancelled'),
          tone: _WorkspaceNoticeTone.warning,
        );
      }
    } finally {
      // Restore the window BEFORE showing the annotation overlay so the
      // editor is visible.
      //
      // 关键：窗口被移到屏幕外后，Windows 可能自动把它标记为“最小化”
      // 或“隐藏”状态（DWM/任务栏行为），此时仅 setPosition/show/focus
      // 不足以让窗口回到可视状态（表现为点击剪刀后整个应用“消失”，
      // annotator 弹在不可见的窗口里）。必须先用 restore() 把窗口恢复到
      // 普通状态，再移回原位，最后 show+focus 确保可见并可交互。
      if (windowMoved && savedPos != null) {
        try {
          await windowManager.restore();
          await windowManager.setPosition(savedPos);
          await windowManager.show();
          await windowManager.focus();
          // 恢复后兜底验证：若窗口仍在屏幕外（极少数极端情况），
          // 直接居中到当前显示器，保证 annotator 一定可见。
          final checkPos = await windowManager.getPosition();
          final maxDim = 100000.0;
          if (checkPos.dx.abs() > maxDim || checkPos.dy.abs() > maxDim) {
            await windowManager.center();
            await windowManager.show();
            await windowManager.focus();
          }
        } catch (_) {
          // 恢复失败时兜底：居中 + 显示 + 聚焦，避免窗口永远停留在屏幕外。
          try {
            await windowManager.center();
            await windowManager.show();
            await windowManager.focus();
          } catch (_) {}
        }
      }
    }
    if (!mounted || path == null) return;
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      // The raw full-screen capture is only the editor source; the annotator
      // writes its own composed PNG.
      try {
        await file.delete();
      } catch (_) {}
      if (!mounted || bytes.isEmpty) return;
      final annotatedPath = await showScreenshotAnnotator(
        context,
        imageBytes: bytes,
        // Windows 新流程传入的是已框选好的区域图，annotator 直接进入
        // 标注阶段（工具条立即可用）；其它平台仍是全屏图，需要先框选。
        preselected: Platform.isWindows,
      );
      if (annotatedPath == null || !mounted) return;
      // 标注完成的截图先放入消息输入框（待发送状态），用户点输入框里的
      // “发送”按钮再真正发出——与微信截图流程一致。
      _composerController.stageImage(annotatedPath);
      // 同时复制到系统剪贴板：可在输入框 Ctrl+V 粘贴再次发送，
      // 或粘贴到微信/QQ 等其他应用。
      if (Platform.isWindows) {
        unawaited(_copyImageToClipboard(annotatedPath));
      }
    } catch (_) {
      if (mounted) {
        _showConversationNotice(
          translate('Failed to annotate screenshot'),
          tone: _WorkspaceNoticeTone.warning,
        );
      }
    }
  }

  /// 把一张 PNG 图片写入系统剪贴板（Windows：System.Drawing SetImage）。
  /// 与 _readClipboardImage 对称，供截图标注完成后“发送 + 复制”使用。
  Future<void> _copyImageToClipboard(String pngPath) async {
    try {
      if (!Platform.isWindows) return;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final script = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'luoda_clip_set_$stamp.ps1',
      );
      final safePath = pngPath.replaceAll('\\', '\\\\');
      await script.writeAsString(
        'Add-Type -AssemblyName System.Drawing;\n'
        'Add-Type -AssemblyName System.Windows.Forms;\n'
        '\$img = [System.Drawing.Image]::FromFile("$safePath");\n'
        '[System.Windows.Forms.Clipboard]::SetImage(\$img);\n'
        '\$img.Dispose()\n',
      );
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-File', script.path],
      );
      try {
        await script.delete();
      } catch (_) {}
      if (result.exitCode != 0) {
        RuntimeLogger.instance.warn(
            'CLIP', 'copy image to clipboard failed: ${result.stderr}');
      }
    } catch (e) {
      RuntimeLogger.instance.warn('CLIP', 'copy image failed: $e');
    }
  }

  /// Common send-image-to-peer routine extracted from _pasteImageToConversation.
  Future<void> _sendImageFile(
      String peerId, String path, String name, int size) async {
    await _startDirectChat(peerId, activate: false);
    final chatFfi = _directChatSessionFor(peerId);
    final incoming = _incomingDirectChatClientFor(peerId);
    final hasSession =
        (chatFfi != null && !chatFfi.closed) || incoming != null;
    // 对方离线也允许发送：小图片走消息队列（离线自动排队，连接后补发）。
    // 仅超大图片（需独立文件传输会话）要求对方在线。
    if (!canInlineDirectChatFile(size)) {
      if (!hasSession) {
        _showConversationNotice(
          translate('Large file needs an active connection first'),
          tone: _WorkspaceNoticeTone.warning,
        );
        return;
      }
      final ffi = await _ensureDirectFileSession(peerId);
      if (ffi == null || !mounted) return;
      final items = SelectedItems(isLocal: true);
      items.add(
        Entry()
          ..path = path
          ..name = name
          ..size = size,
      );
      await ffi.fileModel.localController.sendFiles(
        items,
        ffi.fileModel.remoteController.directoryData(),
      );
    }
    final chatModel =
        chatFfi != null && !chatFfi.closed ? chatFfi.chatModel : gFFI.chatModel;
    if (hasSession) {
      chatModel.changeCurrentKey(
        MessageKey(
          peerId,
          chatFfi != null && !chatFfi.closed
              ? ChatModel.clientModeID
              : incoming!.id,
        ),
      );
    }
    await chatModel.sendFileRecord(
      fileName: name,
      fileSize: size,
      localPath: path,
    );
    _showConversationNotice(
      translate(hasSession ? 'Image sent.' : 'Image queued for offline send'),
      tone: _WorkspaceNoticeTone.success,
    );
  }

  Future<FFI?> _ensureDirectFileSession(String peerId) async {
    final existing = _directFileSessions[peerId];
    if (existing != null &&
        !existing.closed &&
        existing.ffiModel.pi.isSet.isTrue &&
        existing.ffiModel.direct == true) {
      return existing;
    }
    if (existing != null) {
      _directFileSessions.remove(peerId);
      await _disposeFileSession(existing);
    }

    final ffi = FFI(null);
    ffi.suppressConnectionDialogs = true;
    _directFileSessions[peerId] = ffi;
    final endpoint = DirectPairingStore.resolveConnectionTarget(peerId);
    if (endpoint == null) {
      _directFileSessions.remove(peerId);
      _showConversationNotice(
        translate(
            'Direct endpoint required. Scan the PC QR code or enter IP:port.'),
        tone: _WorkspaceNoticeTone.warning,
      );
      return null;
    }
    ffi.start(endpoint, isFileTransfer: true, forceRelay: false);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (ffi.ffiModel.pi.isSet.isTrue) {
        ffi.dialogManager.dismissAll();
        if (ffi.ffiModel.direct != true) {
          _directFileSessions.remove(peerId);
          await _disposeFileSession(ffi);
          _showConversationNotice(
            translate('Direct connection failed. File relay is disabled.'),
            tone: _WorkspaceNoticeTone.error,
          );
          return null;
        }
        final ready = await _waitForFileDirectories(ffi);
        if (ready) return ffi;
        break;
      }
      if (ffi.closed || (ffi.ffiModel.lastConnectionError ?? '').isNotEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    ffi.dialogManager.dismissAll();
    _directFileSessions.remove(peerId);
    final error = ffi.ffiModel.lastConnectionError;
    await _disposeFileSession(ffi);
    _showConversationNotice(
      translate(
        error?.isNotEmpty == true
            ? error!
            : 'Direct file transfer connection timed out.',
      ),
      tone: _WorkspaceNoticeTone.error,
    );
    return null;
  }

  Future<bool> _waitForFileDirectories(FFI ffi) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (ffi.closed) return false;
      final local = ffi.fileModel.localController.directory.value.path;
      final remote = ffi.fileModel.remoteController.directory.value.path;
      if (local.isNotEmpty && remote.isNotEmpty) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<void> _disposeFileSession(FFI ffi) async {
    if (ffi.closed) return;
    try {
      await ffi.fileModel.close();
    } finally {
      await ffi.close();
    }
  }

  void _showConversationNotice(
    String message, {
    _WorkspaceNoticeTone tone = _WorkspaceNoticeTone.info,
  }) {
    if (!mounted) return;
    _workspaceNoticeTimer?.cancel();
    setState(() {
      _workspaceNotice = message;
      _workspaceNoticeTone = tone;
      _workspaceNoticeRevision++;
    });
    final duration = switch (tone) {
      _WorkspaceNoticeTone.success => const Duration(milliseconds: 3200),
      _WorkspaceNoticeTone.info => const Duration(seconds: 4),
      _WorkspaceNoticeTone.warning => const Duration(seconds: 5),
      _WorkspaceNoticeTone.error => const Duration(seconds: 6),
    };
    _workspaceNoticeTimer = Timer(duration, _dismissWorkspaceNotice);
  }

  void _dismissWorkspaceNotice() {
    _workspaceNoticeTimer?.cancel();
    _workspaceNoticeTimer = null;
    if (!mounted || _workspaceNotice == null) return;
    setState(() => _workspaceNotice = null);
  }

  Widget _buildLocalAvatar(double size) {
    var avatar = '';
    try {
      final userInfo = jsonDecode(
        bind.mainGetLocalOption(key: 'user_info'),
      ) as Map<String, dynamic>;
      avatar = (userInfo['avatar'] ?? '').toString();
    } catch (_) {}
    return buildAvatarWidget(
          avatar: avatar,
          size: size,
          borderRadius: 8,
          fallback: Image.asset('assets/avatar.png', fit: BoxFit.cover),
        ) ??
        Image.asset('assets/avatar.png', fit: BoxFit.cover);
  }

  Future<void> _showIdentityDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext2, setDialogState) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 420,
            height: 620,
            child: _buildIdentityPane(dialogContext2, setDialogState),
          ),
        ),
      ),
    );
  }

  Future<void> _showJoinViewerPage(
    BuildContext context, {
    ViewerInviteLink? invite,
  }) async {
    if (_openingViewerInvite) return;
    _openingViewerInvite = true;
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => JoinViewerPage(
            initialEndpoint: invite?.endpoint ?? _clientIdController.text,
            initialToken: invite?.token,
            initialDisplayName: gFFI.chatModel.me.firstName,
            onJoinRequested: ({
              required endpoint,
              required token,
              required viewerId,
              required displayName,
            }) async {
              await luodaWinManager.newRemoteDesktop(
                endpoint,
                viewerToken: token,
                viewerId: viewerId,
                viewerDisplayName: displayName,
              );
            },
          ),
        ),
      );
    } finally {
      _openingViewerInvite = false;
    }
  }

  void _handlePendingViewerInvite() {
    final invite = takePendingViewerInvite();
    if (invite == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showJoinViewerPage(context, invite: invite);
    });
  }

  /// Handle incoming voice call: accept or reject.
  void _handleIncomingVoiceCall(bool accept) {
    final caller = gFFI.serverModel.clients
        .firstWhereOrNull((c) => c.incomingVoiceCall && !c.disconnected);
    if (caller == null) return;
    if (accept) {
      bind.cmHandleIncomingVoiceCall(id: caller.id, accept: true);
    } else {
      bind.cmCloseVoiceCall(id: caller.id);
    }
  }

  Future<void> _showPairingQrDialog(BuildContext context) async {
    // 获取已绑定的手机号码。
    final boundPhone = DirectPairingStore.boundPhone();
    if (boundPhone.isNotEmpty) {
      await _showBoundPhoneDialog(context, boundPhone);
      return;
    }
    await bind.mainCheckConnectStatus();
    final listenerStatus =
        bind.mainGetOptionSync(key: kOptionDirectListenerStatus).trim();
    if (listenerStatus != 'ready') {
      _showConversationNotice(
        translate(
            'Direct listener is not ready. Check the LAN address and port.'),
        tone: _WorkspaceNoticeTone.warning,
      );
      return;
    }
    final payload = await DirectPairingStore.buildLocalPayload();
    final pairing = DirectPairingStore.parsePayload(payload);
    if (!mounted || pairing == null) {
      _showConversationNotice(
        translate(
            'Direct listener is not ready. Check the LAN address and port.'),
        tone: _WorkspaceNoticeTone.warning,
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.24),
      builder: (dialogContext) => AlertDialog(
        title: Text(translate('Pair phone directly')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  translate(
                    'Scan with DotChat on the phone. Pairing data stays on both devices.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      size: 184,
                      gapless: true,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  pairing.endpoints.join('\n'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  translate(
                      'Direct endpoint only. Same LAN or forwarded port required.'),
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                        color: MyTheme.mutedLight,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  translate('Direct listener ready'),
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                        color: MyTheme.accent,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(translate('Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showBoundPhoneDialog(
    BuildContext context,
    Map<String, String> bound,
  ) async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = bound['displayName'] ?? '';
    final peerId = bound['peerId'] ?? '';
    final platform = bound['platform'] ?? '';
    final boundAt = bound['boundAt'] ?? '';
    DateTime? time;
    try {
      time = DateTime.tryParse(boundAt)?.toLocal();
    } catch (_) {}
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(translate('Bound phone')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _boundInfoRow(translate('Device'), name.isEmpty ? peerId : name),
              if (platform.isNotEmpty)
                _boundInfoRow(translate('Platform'), platform),
              if (peerId.isNotEmpty) _boundInfoRow(translate('ID'), peerId),
              if (time != null)
                _boundInfoRow(
                  translate('Bound at'),
                  '${time.year}-${time.month.toString().padLeft(2, '0')}-'
                  '${time.day.toString().padLeft(2, '0')} '
                  '${time.hour.toString().padLeft(2, '0')}:'
                  '${time.minute.toString().padLeft(2, '0')}',
                ),
              const SizedBox(height: 10),
              Text(
                translate(
                    'A phone is already bound. Unbind before pairing another.'),
                style: TextStyle(
                  fontSize: 13,
                  color: dark ? Colors.orangeAccent : Colors.deepOrange,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(translate('Close')),
          ),
          TextButton(
            onPressed: () async {
              await DirectPairingStore.clearBoundPhone();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _showConversationNotice(
                translate('Bound phone unbound'),
                tone: _WorkspaceNoticeTone.success,
              );
            },
            child: Text(
              translate('Unbind'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _boundInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: MyTheme.mutedLight,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectDirect(
    BuildContext context,
    String peerIdOrEndpoint, {
    bool isFileTransfer = false,
    bool isViewCamera = false,
    bool isTerminal = false,
    bool isTcpTunneling = false,
  }) async {
    if (await DirectPairingStore.isSelfTarget(peerIdOrEndpoint)) {
      _showConversationNotice(
        translate(
            'This is the current device. You cannot connect to or message yourself.'),
        tone: _WorkspaceNoticeTone.error,
      );
      return;
    }
    final endpoint =
        DirectPairingStore.resolveConnectionTarget(peerIdOrEndpoint);
    if (endpoint == null) {
      _showConversationNotice(
        translate(
            'Direct endpoint required. Scan the PC QR code or enter IP:port.'),
        tone: _WorkspaceNoticeTone.warning,
      );
      return;
    }
    final mode = isFileTransfer
        ? 'file'
        : isViewCamera
            ? 'camera'
            : isTerminal
                ? 'terminal'
                : isTcpTunneling
                    ? 'tunnel'
                    : 'desktop';
    final requestKey = '$mode|$endpoint';
    final now = DateTime.now();
    final lastAttempt = _lastDirectConnectionAttempt[requestKey];
    if (_openingDirectConnections.contains(requestKey) ||
        lastAttempt != null &&
            now.difference(lastAttempt) < _directConnectionClickCooldown) {
      return;
    }
    _openingDirectConnections.add(requestKey);
    _lastDirectConnectionAttempt[requestKey] = now;
    _lastDirectConnectionAttempt.removeWhere(
      (_, attemptedAt) =>
          now.difference(attemptedAt) > const Duration(minutes: 5),
    );
    try {
      await connect(
        context,
        endpoint,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal,
        isTcpTunneling: isTcpTunneling,
        forceRelay: false,
      );
    } on TimeoutException catch (error) {
      debugPrint('Direct connection window timed out: $error');
      _showConversationNotice(
        translate('Connection window timed out. Please try again.'),
        tone: _WorkspaceNoticeTone.error,
      );
    } catch (error) {
      debugPrint('Failed to open direct connection window: $error');
      _showConversationNotice(
        translate('Unable to open the connection window.'),
        tone: _WorkspaceNoticeTone.error,
      );
    } finally {
      _openingDirectConnections.remove(requestKey);
    }
  }

  void _handleConversationAction(
    BuildContext context,
    _ConversationAction action,
    String peerId,
  ) {
    switch (action) {
      case _ConversationAction.fileTransfer:
        _sendFilesFromConversation(peerId);
        break;
      case _ConversationAction.remoteAssist:
        _connectDirect(context, peerId);
        break;
      case _ConversationAction.camera:
        _connectDirect(context, peerId, isViewCamera: true);
        break;
      case _ConversationAction.terminal:
        _connectDirect(context, peerId, isTerminal: true);
        break;
      case _ConversationAction.port:
        _connectDirect(context, peerId, isTcpTunneling: true);
        break;
      // 会议群聊动作不经过此分发（在标题栏 PopupMenu 内处理），
      // 这里给出安全兜底。
      case _ConversationAction.meetingManage:
      case _ConversationAction.joinSession:
      case _ConversationAction.copyInvite:
        break;
    }
  }

  Widget _buildDeviceNav(BuildContext context, {required bool expanded}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = <int, (IconData, String)>{
      0: (Icons.history_rounded, 'Recent sessions'),
      1: (Icons.star_outline_rounded, 'Favorites'),
      2: (Icons.radar_rounded, 'Discovered'),
      3: (Icons.contact_page_outlined, 'Address book'),
      4: (Icons.devices_rounded, 'Access history devices'),
    };
    final model = gFFI.peerTabModel;
    final tabsFixed = isOptionFixed(kOptionPeerTabVisible);
    return Container(
      width: expanded ? 264 : 72,
      color: dark ? const Color(0xFF20252E) : Colors.white,
      padding: EdgeInsets.fromLTRB(
        expanded ? 16 : 10,
        18,
        expanded ? 16 : 10,
        12,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: MyTheme.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.public_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              if (expanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'LUODA',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 26),
          Expanded(
            child: AnimatedBuilder(
              animation: model,
              builder: (context, _) {
                final visibleIndexes = model.visibleEnabledOrderedIndexs;
                return ReorderableListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: visibleIndexes.length,
                  buildDefaultDragHandles: false,
                  onReorder: tabsFixed ? (_, __) {} : model.reorder,
                  itemBuilder: (context, index) {
                    final tabIndex = visibleIndexes[index];
                    final item = items[tabIndex]!;
                    final selected = model.currentTab == tabIndex;
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey('device-nav-$tabIndex'),
                      index: index,
                      enabled: !tabsFixed,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Tooltip(
                          message: expanded ? '' : translate(item.$2),
                          child: Material(
                            color: selected
                                ? MyTheme.accent.withOpacity(.10)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () =>
                                  PeerTabPage.selectDesktopTab(tabIndex),
                              child: SizedBox(
                                height: 44,
                                child: Row(
                                  mainAxisAlignment: expanded
                                      ? MainAxisAlignment.start
                                      : MainAxisAlignment.center,
                                  children: [
                                    if (expanded) const SizedBox(width: 12),
                                    Icon(
                                      item.$1,
                                      size: 20,
                                      color: selected
                                          ? MyTheme.accent
                                          : Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color
                                              ?.withOpacity(.72),
                                    ),
                                    if (expanded) ...[
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          translate(item.$2),
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: selected
                                                ? MyTheme.accent
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          AnimatedBuilder(
            animation: model,
            builder: (context, _) => PopupMenuButton<int>(
              tooltip: translate('More'),
              enabled: !tabsFixed,
              onSelected: (tabIndex) => model.setTabVisible(
                tabIndex,
                !model.isVisibleEnabled[tabIndex],
              ),
              itemBuilder: (context) => [
                for (var tabIndex = 0; tabIndex < items.length; tabIndex++)
                  if (model.isEnabled[tabIndex])
                    CheckedPopupMenuItem<int>(
                      value: tabIndex,
                      checked: model.isVisibleEnabled[tabIndex],
                      child: Text(translate(items[tabIndex]!.$2)),
                    ),
              ],
              child: SizedBox(
                height: 40,
                child: Row(
                  mainAxisAlignment: expanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    if (expanded) const SizedBox(width: 12),
                    const Icon(Icons.tune_rounded, size: 20),
                    if (expanded) ...[
                      const SizedBox(width: 12),
                      Expanded(child: Text(translate('More'))),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 20),
          Tooltip(
            message: expanded ? '' : translate('Settings'),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: expanded ? 12 : 8,
              ),
              leading: const Icon(Icons.settings_outlined, size: 20),
              title: expanded ? Text(translate('Settings')) : null,
              onTap: DesktopTabPage.onAddSetting,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityPane(BuildContext context,
      [void Function(void Function())? setDialogState]) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final outgoingOnly = bind.isOutgoingOnly();
    return ColoredBox(
      color: dark ? const Color(0xFF20252E) : Colors.white,
      child: ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, _) {
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!outgoingOnly) ...[
                          Text(
                            translate('My Identity'),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontSize: kWeChatHeadingFontSize,
                                  height: kWeChatTextHeight,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 12),
                          _buildIdentityCard(context, model,
                              setDialogState: setDialogState),
                          const SizedBox(height: 22),
                        ],
                        Text(
                          translate('Quick Actions'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: () => _showDirectConnectDialog(context),
                            icon: const Icon(
                              Icons.add_rounded,
                              size: 20,
                            ),
                            label: Text(translate('Connect by ID / IP')),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: OutlinedButton.icon(
                            onPressed: () => DesktopTabPage.onAddSetting(
                              initialPage: SettingsTabKey.safety,
                            ),
                            icon: const Icon(Icons.security_outlined, size: 19),
                            label: Text(translate('Security settings')),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AiConfigPage(),
                              ),
                            ),
                            icon: const Icon(Icons.auto_awesome_outlined,
                                size: 19),
                            label: Text(translate('AI Settings')),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (!outgoingOnly) buildPresetPasswordWarning(),
                        if (bind.isCustomClient())
                          Align(
                            alignment: Alignment.center,
                            child: loadPowered(context),
                          ),
                        Obx(() => buildHelpCards(stateGlobal.updateUrl.value)),
                        buildPluginEntry(),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 52, child: OnlineStatusWidget()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildIdentityCard(
    BuildContext context,
    ServerModel model, {
    bool compact = false,
    void Function(void Function())? setDialogState,
  }) {
    final publicIP = bind.mainGetOptionSync(key: 'public-ip');
    final lanIP = bind.mainGetOptionSync(key: 'lan-ip');
    final port = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    final upnpStatus = bind.mainGetOptionSync(key: 'upnp-status');
    String address(String ip) {
      if (ip.isEmpty || port.isEmpty) return ip;
      final host = ip.contains(':') && !ip.startsWith('[') ? '[$ip]' : ip;
      return host + ':' + port;
    }

    final temporary = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF181C23) : const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _identityValue(
            context,
            translate('ID'),
            model.serverId.text,
            prominent: true,
            icon: Icons.copy_rounded,
            onTap: () => _copyValue(model.serverId.text),
          ),
          SizedBox(height: compact ? 8 : 12),
          _identityValue(
            context,
            translate('One-time Password'),
            model.serverPasswd.text,
            icon:
                temporary ? Icons.refresh_rounded : Icons.lock_outline_rounded,
            onTap: temporary ? () => bind.mainUpdateTemporaryPassword() : null,
            onCopy: () => _copyValue(model.serverPasswd.text),
            obscure: true,
            revealed: _passwordVisible,
            onToggleVisibility: () {
              final updater = setDialogState ?? setState;
              updater(() => _passwordVisible = !_passwordVisible);
            },
          ),
          Divider(height: compact ? 16 : 22),
          _addressValue(
            context,
            translate('Public IP:port'),
            address(publicIP),
            status: upnpStatus,
            statusColor: _directStatusColor(upnpStatus),
            statusTooltip: translate(_directStatusTip(upnpStatus)),
          ),
          SizedBox(height: compact ? 6 : 10),
          _addressValue(
            context,
            translate('LAN IP:port'),
            address(lanIP),
          ),
        ],
      ),
    );
  }

  Widget _identityValue(
    BuildContext context,
    String label,
    String value, {
    required IconData icon,
    VoidCallback? onTap,
    VoidCallback? onCopy,
    VoidCallback? onToggleVisibility,
    bool obscure = false,
    bool revealed = true,
    bool prominent = false,
  }) {
    final available = value.isNotEmpty;
    final displayValue = !available
        ? translate('Not available')
        : obscure && !revealed
            ? List.filled(value.runes.length, '\u2022').join()
            : value;
    final copyAction = onCopy ?? (prominent ? onTap : null);
    final unavailableColor =
        Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(.68);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: kWeChatMetaFontSize,
            height: kWeChatTextHeight,
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withOpacity(.65),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: GestureDetector(
                onDoubleTap: available ? copyAction : null,
                child: Tooltip(
                  message: displayValue,
                  child: Text(
                    displayValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: prominent ? 18 : kWeChatBodyFontSize,
                      height: kWeChatTextHeight,
                      fontWeight: FontWeight.w700,
                      color: available ? null : unavailableColor,
                    ),
                  ),
                ),
              ),
            ),
            if (onToggleVisibility != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip:
                    translate(revealed ? 'Hide Password' : 'Show Password'),
                onPressed: onToggleVisibility,
                icon: Icon(
                  revealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
              ),
            if (onCopy != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: translate('Copy to clipboard'),
                onPressed: available ? onCopy : null,
                icon: const Icon(Icons.copy_rounded, size: 17),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: translate(
                prominent
                    ? 'Copy to clipboard'
                    : onTap == null
                        ? 'Use permanent password'
                        : 'Refresh Password',
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  Widget _addressValue(
    BuildContext context,
    String label,
    String value, {
    String? status,
    Color? statusColor,
    String? statusTooltip,
  }) {
    final available = value.isNotEmpty;
    final displayValue = available ? value : translate('Not available');
    final unavailableColor =
        Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(.68);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: kWeChatMetaFontSize,
                  height: kWeChatTextHeight,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withOpacity(.65),
                ),
              ),
            ),
            if (available && statusColor != null)
              Tooltip(
                message: statusTooltip ?? '',
                child: Semantics(
                  label: statusTooltip,
                  child: Icon(
                    _directStatusIcon(status ?? ''),
                    size: 15,
                    color: statusColor,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onDoubleTap: available ? () => _copyValue(value) : null,
                child: Tooltip(
                  message: displayValue,
                  child: Text(
                    displayValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: kWeChatBodyFontSize,
                      height: kWeChatTextHeight,
                      fontWeight: FontWeight.w600,
                      color: available ? null : unavailableColor,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: translate('Copy to clipboard'),
              onPressed: available ? () => _copyValue(value) : null,
              icon: const Icon(Icons.copy_rounded, size: 16),
            ),
          ],
        ),
      ],
    );
  }

  void _copyValue(String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    showToast(translate('Copied'));
  }

  Color _directStatusColor(String status) {
    if (status == 'ok') return Colors.green;
    if (status == 'fail') return Colors.orange;
    if (status == 'unsupported') return Colors.blueGrey;
    return Colors.grey;
  }

  IconData _directStatusIcon(String status) {
    if (status == 'ok') return Icons.check_circle_outline_rounded;
    if (status == 'fail') return Icons.error_outline_rounded;
    if (status == 'disabled') return Icons.pause_circle_outline_rounded;
    if (status == 'unsupported') return Icons.info_outline_rounded;
    return Icons.help_outline_rounded;
  }

  String _directStatusTip(String status) {
    if (status == 'ok') return 'upnp_mapping_ready_tip';
    if (status == 'fail') return 'upnp_mapping_failed_tip';
    if (status == 'disabled') return 'direct_listener_disabled_tip';
    if (status == 'unsupported') return 'upnp_mapping_unsupported_tip';
    return 'upnp_mapping_unknown_tip';
  }

  Widget _buildClientHeader(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/icon.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.desktop_windows_rounded,
                    size: 30,
                    color: MyTheme.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              translate('LUODA Remote Assistance'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kWeChatHeadingFontSize,
                height: kWeChatTextHeight,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 4),
            const OnlineStatusWidget(compact: true),
          ],
        ),
      ),
    );
  }

  Widget _buildClientIdentityCard(BuildContext context) {
    return Consumer<ServerModel>(
      builder: (context, model, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          child: _buildIdentityCard(context, model, compact: true),
        ),
      ),
    );
  }

  Widget buildLeftPane(BuildContext context) {
    if (widget.isClientOnly) {
      return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: SizedBox.expand(
          child: ColoredBox(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1C1E22)
                : kWeChatCanvasColor,
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    key: _childKey,
                    children: [
                      _buildClientHeader(context),
                      _buildClientIdentityCard(context),
                      const Spacer(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      if (bind.isCustomClient())
        Align(alignment: Alignment.center, child: loadPowered(context)),
      // 底部“由 LUODA 驱动”标识。
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 20, bottom: 8),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: MyTheme.accent, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/avatar.png',
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, error, stackTrace) =>
                      Icon(Icons.computer, size: 40, color: MyTheme.accent),
                ),
              ),
            ),
            Text(
              "DotChat ${translate('Remote assistance')}",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            SizedBox(height: 10),
          ],
        ),
      ),
      if (!isOutgoingOnly) buildIDBoard(context),
      if (!isOutgoingOnly) buildPasswordBoard(context),
      if (!isOutgoingOnly) buildDirectAccessBoard(context),
      FutureBuilder<Widget>(
        future: Future.value(
          Obx(() => buildHelpCards(stateGlobal.updateUrl.value)),
        ),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
      buildPluginEntry(),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6),
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;

    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: isIncomingOnly ? 300.0 : 220.0,
        color: Theme.of(context).colorScheme.background,
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(key: _childKey, children: children),
                ),
                Expanded(child: Container()),
              ],
            ),
            Positioned(
              bottom: 6,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  // 会话列表。
                  Expanded(
                    child: Obx(
                      () => InkWell(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.settings_outlined,
                              color: _settingsHover.value
                                  ? textColor
                                  : Colors.grey.withOpacity(0.5),
                              size: 18,
                            ),
                            Text(
                              translate("Settings"),
                              style: TextStyle(
                                fontSize: 11,
                                color: _settingsHover.value
                                    ? textColor
                                    : Colors.grey.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          if (DesktopSettingPage.tabKeys.isNotEmpty) {
                            DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0],
                            );
                          }
                        },
                        onHover: (value) => _settingsHover.value = value,
                      ),
                    ),
                  ),
                  // 会话列表。
                  Expanded(
                    child: Obx(
                      () => InkWell(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_outlined,
                              color: _relayHover.value
                                  ? textColor
                                  : Colors.grey.withOpacity(0.5),
                              size: 18,
                            ),
                            Text(
                              translate("Network"),
                              style: TextStyle(
                                fontSize: 11,
                                color: _relayHover.value
                                    ? textColor
                                    : Colors.grey.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          DesktopSettingPage.switch2page(
                            SettingsTabKey.network,
                          );
                        },
                        onHover: (value) => _relayHover.value = value,
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

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(key: ConnectionPage.pageKey),
    );
  }

  /// ??? ID ????????????
  /// ??????? ID ???
  Widget _buildClientIDField() {
    return Container(
      child: TextFormField(
        controller: _clientIdController,
        focusNode: _clientIdFocusNode,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          filled: true,
          fillColor: Theme.of(context).colorScheme.background.withOpacity(0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Theme.of(context).dividerColor),
          ),
          hintText: translate('Enter Remote ID'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
        onFieldSubmitted: (value) {
          _onClientConnect(value, context);
        },
      ),
    );
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      height: 62,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: MyTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ).marginOnly(top: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translate("ID"),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(
                            context,
                          ).textTheme.titleLarge?.color?.withOpacity(0.45),
                        ),
                      ).marginOnly(top: 8),
                    ],
                  ),
                  GestureDetector(
                    onDoubleTap: () {
                      Clipboard.setData(
                        ClipboardData(text: model.serverId.text),
                      );
                      showToast(translate("Copied"));
                    },
                    child: TextFormField(
                      controller: model.serverId,
                      readOnly: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        isDense: true,
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 0,
                      ),
                    ).workaroundFreezeLinuxMint(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, child) {
          return buildPasswordBoard2(context, model);
        },
      ),
    );
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 13, bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: MyTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor?.withOpacity(0.45),
                    ),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              Clipboard.setData(
                                ClipboardData(text: model.serverPasswd.text),
                              );
                              showToast(translate("Copied"));
                            }
                          },
                          child: TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).colorScheme.background.withOpacity(0.5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              isDense: true,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              letterSpacing: 0,
                            ),
                          ).workaroundFreezeLinuxMint(),
                        ),
                      ),
                      if (showOneTime)
                        AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Tooltip(
                            message: translate('Refresh Password'),
                            child: Obx(
                              () => RotatedBox(
                                quarterTurns: 2,
                                child: Icon(
                                  Icons.refresh,
                                  color: refreshHover.value
                                      ? textColor
                                      : Color(0xFFDDDDDD),
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          onHover: (value) => refreshHover.value = value,
                        ).marginOnly(right: 8, top: 4),
                      // 设置按钮。f (!bind.isDisableSettings() && !bind.isCustomClient())
                      InkWell(
                        child: Tooltip(
                          message: translate('Change Password'),
                          child: Obx(
                            () => Icon(
                              Icons.edit,
                              color: editHover.value
                                  ? textColor
                                  : Color(0xFFDDDDDD),
                              size: 22,
                            ).marginOnly(right: 8, top: 4),
                          ),
                        ),
                        onTap: () => DesktopSettingPage.switch2page(
                          SettingsTabKey.safety,
                        ),
                        onHover: (value) => editHover.value = value,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  buildDirectAccessBoard(BuildContext context) {
    final publicIP = bind.mainGetOptionSync(key: 'public-ip');
    final lanIP = bind.mainGetOptionSync(key: 'lan-ip');
    final directPort = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    // UPnP 状态：通过 option "upnp-status" 读取（在 rust 侧 direct_server 启动后设置）
    final upnpStatus = bind.mainGetOptionSync(key: 'upnp-status');
    final textColor = Theme.of(context).textTheme.titleLarge?.color;

    // 显示用："地址:端口"，没有则只显示地址，再没有则"Not available"
    String address(String ip) {
      if (ip.isEmpty || directPort.isEmpty) return ip;
      final host = ip.contains(':') && !ip.startsWith('[') ? '[$ip]' : ip;
      return host + ':' + directPort;
    }

    final publicAddr = address(publicIP);
    final lanAddr = address(lanIP);

    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
// 直连 IP 访问说明。
          Text(
            translate('Direct IP Access'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor?.withOpacity(0.45),
            ),
          ),
          SizedBox(height: 6),
          // 公网 IP 卡片 —— 独立蓝色竖线
          _ipCard(
            context: context,
            label: translate('Public network'),
            addr: publicAddr,
            hasAddr: publicAddr.isNotEmpty,
            textColor: textColor,
            upnpStatus: upnpStatus,
            showUpnp: true,
          ),
          SizedBox(height: 6),
          // 内网 IP 卡片 —— 独立蓝色竖线
          _ipCard(
            context: context,
            label: translate('Local network'),
            addr: lanAddr,
            hasAddr: lanAddr.isNotEmpty,
            textColor: textColor,
            upnpStatus: '',
            showUpnp: false,
          ),
        ],
      ),
    );
  }

  // 一行 IP 显示：左侧独立蓝色竖线 + 标签 + IP:端口
  // 鼠标移到 IP 上时，Tooltip 弹窗显示完整地址（防止因宽度不够被截断）
  Widget _ipCard({
    required BuildContext context,
    required String label,
    required String addr,
    required bool hasAddr,
    required Color? textColor,
    required String upnpStatus,
    required bool showUpnp,
  }) {
    final naText = translate('Not available');
    final displayText = addr.isNotEmpty ? addr : naText;
// Tooltip 显示 IP 与 UPnP 状态提示。
    final tooltipText = showUpnp && addr.isNotEmpty
        ? '$addr\n${translate(_directStatusTip(upnpStatus))}'
        : (addr.isNotEmpty ? addr : naText);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 30,
          decoration: BoxDecoration(
            color: MyTheme.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor?.withOpacity(0.5),
            ),
          ),
        ),
        Expanded(
          child: Tooltip(
            message: tooltipText,
            preferBelow: false,
            waitDuration: Duration(milliseconds: 200),
            child: GestureDetector(
              onDoubleTap: () {
                if (addr.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: addr));
                  showToast(translate("Copied"));
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.background.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          letterSpacing: 0,
                          color:
                              hasAddr ? textColor : textColor?.withOpacity(0.4),
                        ),
                      ),
                    ),
                    if (showUpnp && addr.isNotEmpty) ...[
                      SizedBox(width: 4),
                      Semantics(
                        label: translate(_directStatusTip(upnpStatus)),
                        child: Icon(
                          _directStatusIcon(upnpStatus),
                          size: 13,
                          color: _directStatusColor(upnpStatus),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('luoda')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://www.dotchat.app/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
        "Status",
        "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
        btnText,
        onPressed,
        closeButton: true,
        help: isToUpdate ? 'Changelog' : null,
        link: isToUpdate
            ? 'https://github.com/luoda/luoda/releases/tag/${bind.mainGetNewVersion()}'
            : null,
      );
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      // Installation prompt removed for LUODA
      if (false && !bind.mainIsInstalled()) {
        return buildInstallCard(
          "",
          bind.isOutgoingOnly() ? "" : "install_tip",
          "Install",
          () async {
            await luodaWinManager.closeAllSubWindows();
            bind.mainGotoInstall();
          },
        );
      } else if (false && bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
          "Status",
          "Your installation is lower version.",
          "Click to upgrade",
          () async {
            await luodaWinManager.closeAllSubWindows();
            bind.mainUpdateMe();
          },
        );
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard(
          "Permissions",
          "config_screen",
          "Configure",
          () async {
            bind.mainIsCanScreenRecording(prompt: true);
            watchIsCanScreenRecording = true;
          },
          help: 'Help',
          link: translate("doc_mac_permission"),
        );
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard(
          "Permissions",
          "config_acc",
          "Configure",
          () async {
            bind.mainIsProcessTrusted(prompt: true);
            watchIsProcessTrust = true;
          },
          help: 'Help',
          link: translate("doc_mac_permission"),
        );
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard(
          "Permissions",
          "config_input",
          "Configure",
          () async {
            bind.mainIsCanInputMonitoring(prompt: true);
            watchIsInputMonitoring = true;
          },
          help: 'Help',
          link: translate("doc_mac_permission"),
        );
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(
            buildInstallCard(
              "Warning",
              "selinux_tip",
              "",
              () async {},
              marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
              help: 'Help',
              link: 'https://www.dotchat.app/docs/client/linux/',
              closeButton: true,
              closeOption: keyShowSelinuxHelpTip,
            ),
          );
        }
      }
      // Wayland warnings removed per user request
      if (LinuxCards.isNotEmpty) {
        return Column(children: LinuxCards);
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(
    String title,
    String content,
    String btnText,
    GestureTapCallback onPressed, {
    double marginTop = 20.0,
    String? help,
    String? link,
    bool? closeButton,
    String? closeOption,
  }) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
            0,
            marginTop,
            0,
            bind.isIncomingOnly() ? marginTop : 0,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              ),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: (title.isNotEmpty
                      ? <Widget>[
                          Center(
                            child: Text(
                              translate(title),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ).marginOnly(bottom: 6),
                          ),
                        ]
                      : <Widget>[]) +
                  <Widget>[
                    if (content.isNotEmpty)
                      Text(
                        translate(content),
                        style: TextStyle(
                          height: 1.5,
                          color: Colors.white,
                          fontWeight: FontWeight.normal,
                          fontSize: 13,
                        ),
                      ).marginOnly(bottom: 20),
                  ] +
                  (btnText.isNotEmpty
                      ? <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FixedWidthButton(
                                width: 150,
                                padding: 8,
                                isOutline: true,
                                text: translate(btnText),
                                textColor: Colors.white,
                                borderColor: Colors.white,
                                textSize: 20,
                                radius: 10,
                                onTap: onPressed,
                                icon: btnText == 'Download'
                                    ? Icons.download
                                    : Icons.system_update,
                              ),
                            ],
                          ),
                        ]
                      : <Widget>[]) +
                  (help != null
                      ? <Widget>[
                          Center(
                            child: InkWell(
                              onTap: () async =>
                                  await launchUrl(Uri.parse(link!)),
                              child: Text(
                                translate(help),
                                style: TextStyle(
                                  decoration: TextDecoration.underline,
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ).marginOnly(top: 6),
                          ),
                        ]
                      : <Widget>[]),
            ),
          ),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _directChatAccess.load();
    _categoryModel.load();
    MeetingGroupStore.load();
    // 系统通知：启动即拉取，之后每 5 分钟刷新一次（未读红点）。
    SystemAnnouncementStore.instance.load();
    unawaited(SystemAnnouncementStore.instance.refresh());
    _announceTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(SystemAnnouncementStore.instance.refresh());
    });
    platformFFI.registerEventHandler(
      'callback_query_onlines',
      _peerOnlineHandlerName,
      (evt) async {
        final onlines = (evt['onlines'] as String? ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toSet();
        final offlines = (evt['offlines'] as String? ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toSet();
        if (onlines.isEmpty && offlines.isEmpty) return;
        var changed = false;
        for (final id in onlines) {
          if (_rendezvousOnlineByPeer[id] != true) {
            _rendezvousOnlineByPeer[id] = true;
            changed = true;
          }
        }
        for (final id in offlines) {
          if (_rendezvousOnlineByPeer[id] != false) {
            _rendezvousOnlineByPeer[id] = false;
            changed = true;
          }
        }
        if (changed && mounted) setState(() {});
      },
      replace: true,
    );
    _peerOnlineQueryTimer = Timer.periodic(
        const Duration(seconds: 8), (_) => _queryPeerOnlineStates());
    _queryPeerOnlineStates();
    gFFI.chatModel.ensureChatConnection = (peerId, {bool force = false}) async {
      // LUODA: never try to connect to self (causes freeze / white screen.
      if (await DirectPairingStore.isSelfTarget(peerId)) return;
      if (DirectPairingStore.resolveConnectionTarget(peerId) == null) return;
      await _startDirectChat(peerId, activate: false);
    };
    pendingViewerInvite.addListener(_handlePendingViewerInvite);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingViewerInvite();
    });
    bind.mainLoadRecentPeers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshDirectSessions());
    });
    // Direct-chat keep-alive is irrelevant in incoming-only client mode.
    if (!bind.isIncomingOnly()) {
      _directChatKeepAliveTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(_refreshDirectSessions()),
      );
    }
    // LUODA 3.1.1 performance fix: desktop full mode polled at 1s, firing
    // several synchronous IPC reads (fetchID, mainGetError, stop-service,
    // public-ip, lan-ip, direct-access-port) on the UI thread every second.
    // Synchronous IPC blocks the Flutter isolate until Rust replies, which is
    // what made the whole PC feel sluggish. 5s is plenty (IP/port changes are
    // rare (network switch) and the values are re-read on any reconnect.
    final pollInterval = bind.isIncomingOnly()
        ? const Duration(seconds: 10)
        : const Duration(seconds: 5);
    _updateTimer = periodic_immediate(pollInterval, () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        // When service starts (v becomes false), refresh the temporary password
        if (!v) {
          bind.mainGetTemporaryPassword();
        }
        setState(() {});
      }
      _checkConnectionTransitions();
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // luodaWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
// 定时刷新 IP 显示。
      _refreshIpDisplay();
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    luodaWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse:
          return true;
      }

      return false;
    }

    luodaWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId",
        );
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
          (await window_size.getScreenList()).map(screenToMap).toList(),
        );
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await luodaWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await luodaWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowEventOpenDirectChat) {
        await windowOnTop(null);
        final peerId = call.arguments['id']?.toString() ?? '';
        if (peerId.isNotEmpty) {
          await _startDirectChat(peerId);
        }
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
          viewerToken: call.arguments['viewerToken'],
          viewerId: call.arguments['viewerId'],
          viewerDisplayName: call.arguments['viewerDisplayName'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy'],
        );
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await luodaWinManager.moveTabToNewWindow(
            windowId,
            args[1],
            args[2],
            windowType,
          );
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await luodaWinManager.openMonitorSession(
          windowId,
          peerId,
          display,
          displayCount,
          screenRect,
          windowType,
        );
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
            await luodaWinManager.getOtherRemoteWindowCoords(windowId),
          );
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  void _queryPeerOnlineStates() {
    if (!mounted) return;
    final ids = <String>{
      for (final pairing in DirectPairingStore.load().values)
        ...DirectPairingStore.conversationPeerIds(pairing.conversationId),
      for (final p in <Peer>[
        ...gFFI.recentPeersModel.peers,
        ...gFFI.favoritePeersModel.peers,
        ...gFFI.lanPeersModel.peers,
      ])
        p.id,
    }.toList(growable: false);
    if (ids.isNotEmpty) {
      bind.queryOnlines(ids: ids);
    }
  }

  void _checkConnectionTransitions() {
    _canonicalizeDirectChatSessions();
    final peers = <Peer>{
      ...gFFI.recentPeersModel.peers,
      ...gFFI.favoritePeersModel.peers,
      ...gFFI.lanPeersModel.peers,
    };
    for (final peer in peers) {
      final previous = _knownPeerOnline[peer.id];
      _knownPeerOnline[peer.id] = peer.online;
      if (previous != null && previous != peer.online) {
        _showConversationNotice(
          '${_contactName(peer)}: ${translate(peer.online ? 'Online' : 'Offline')}',
          tone: peer.online
              ? _WorkspaceNoticeTone.success
              : _WorkspaceNoticeTone.info,
        );
      }
    }

    for (final entry in _directChatSessions.entries) {
      if (entry.value.ffiModel.pi.isSet.isTrue &&
          _notifiedChatConnections.add(entry.key)) {
        _showConversationNotice(
          '${entry.key}: ${translate('Connected')}',
          tone: _WorkspaceNoticeTone.success,
        );
      }
    }
    _notifiedChatConnections.removeWhere(
      (peerId) => _directChatSessions[peerId]?.closed != false,
    );
  }

  _updateWindowSize() {
    if (widget.isClientOnly) return;
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  _refreshIpDisplay() {
    final ip = bind.mainGetOptionSync(key: 'public-ip');
    final lanIp = bind.mainGetOptionSync(key: 'lan-ip');
    final port = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    if (ip != _lastIp || lanIp != _lastLanIp || port != _lastPort) {
      _lastIp = ip;
      _lastLanIp = lanIp;
      _lastPort = port;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    pendingViewerInvite.removeListener(_handlePendingViewerInvite);
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    _directChatKeepAliveTimer?.cancel();
    _backgroundChatFailures.clear();
    _backgroundChatRetryAfter.clear();
    _directChatAttemptedAt.clear();
    _openingDirectChatPeers.clear();
    _workspaceNoticeTimer?.cancel();
    _announceTimer?.cancel();
    _peerOnlineQueryTimer?.cancel();
    platformFFI.unregisterEventHandler(
        'callback_query_onlines', _peerOnlineHandlerName);
    for (final ffi in _directChatSessions.values) {
      unawaited(ffi.close());
    }
    _directChatSessions.clear();
    for (final ffi in _directFileSessions.values) {
      unawaited(_disposeFileSession(ffi));
    }
    _directFileSessions.clear();
    _clientIdController.dispose();
    _contactSearchController.dispose();
    _contactQuery.dispose();
    _selectedRail.dispose();
    _clientIdFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          }),
        ],
      ),
    );
  }
}

/// Full-screen overlay shown when a remote peer requests a voice call.
/// Displays caller name with accept / reject buttons + pulse animation.
class _IncomingVoiceCallOverlay extends StatefulWidget {
  const _IncomingVoiceCallOverlay({
    required this.callerName,
    required this.onAccept,
    required this.onReject,
  });

  final String callerName;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  State<_IncomingVoiceCallOverlay> createState() =>
      _IncomingVoiceCallOverlayState();
}

class _IncomingVoiceCallOverlayState extends State<_IncomingVoiceCallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final displayName = widget.callerName.isNotEmpty
        ? widget.callerName
        : translate('Unknown peer');
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 48),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2B2D32) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Pulsing avatar with ring animation
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, child) {
                final scale = 1.0 + _pulseController.value * 0.15;
                final opacity = 1.0 - _pulseController.value * 0.6;
                return Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Transform.scale(
                      scale: scale * 1.4,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50)
                              .withOpacity(opacity * 0.3),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: scale * 1.15,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50)
                              .withOpacity(opacity * 0.15),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    child!,
                  ],
                );
              },
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color:
                      dark ? const Color(0xFF3D8C40) : const Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.call_rounded,
                    size: 32, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              translate('Incoming voice call'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              displayName,
              style: TextStyle(
                fontSize: 14,
                color: dark ? Colors.white60 : Colors.black45,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _CallActionButton(
                  icon: Icons.phone_disabled_rounded,
                  label: translate('Decline'),
                  color: Colors.red,
                  onPressed: widget.onReject,
                ),
                const SizedBox(width: 32),
                _CallActionButton(
                  icon: Icons.call_rounded,
                  label: translate('Accept'),
                  color: const Color(0xFF4CAF50),
                  onPressed: widget.onAccept,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatefulWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  State<_CallActionButton> createState() => _CallActionButtonState();
}

class _CallActionButtonState extends State<_CallActionButton> {
  bool _hovering = false;
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressing ? 0.92 : (_hovering ? 1.08 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressing = true),
        onTapUp: (_) {
          setState(() => _pressing = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _pressing = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Material(
                color: widget.color,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                elevation: _hovering ? 6 : 2,
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  child: Icon(widget.icon, color: Colors.white, size: 26),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: showStatusTipOnMobile ? 0.0 : 6.0),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: translate('Password'),
                      errorText: errMsg0.isNotEmpty ? errMsg0 : null,
                    ),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(height: showStatusTipOnMobile ? 0.0 : 8.0),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: translate('Confirmation'),
                      errorText: errMsg1.isNotEmpty ? errMsg1 : null,
                    ),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(
                    Icons.info,
                    color: Colors.amber,
                    size: 18,
                  ).marginOnly(right: 6),
                  Expanded(
                    child: Text(
                      statusTip,
                      style: const TextStyle(fontSize: 13, height: 1.1),
                    ),
                  ),
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(height: showStatusTipOnMobile ? 0.0 : 8.0),
            Obx(
              () => Wrap(
                runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                spacing: 4,
                children: rules.map((e) {
                  var checked = e.validate(rxPass.value.trim());
                  return Chip(
                    label: Text(
                      e.name,
                      style: TextStyle(
                        color: checked
                            ? const Color(0xFF0A9471)
                            : Color.fromARGB(255, 198, 86, 157),
                      ),
                    ),
                    backgroundColor: checked
                        ? const Color(0xFFD0F7ED)
                        : Color.fromARGB(255, 247, 205, 232),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok = await bind.mainSetPermanentPasswordWithResult(
              password: "",
            );
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
            backgroundColor: MaterialStatePropertyAll(Colors.red),
          ),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [cancelButton, if (localPasswordSet) removeButton, okButton];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}
/// 系统通知分栏面板：左侧通知列表 + 右侧详情。
/// 嵌入右侧内容区（不遮挡左侧列表），占满内容区宽度；
/// 拖动左右分隔条可调整列表列宽，拖大主窗口时详情列自动变宽。
class _SystemNoticePanel extends StatefulWidget {
  const _SystemNoticePanel({
    super.key,
    required this.lastReadId,
    required this.onClose,
  });

  final int lastReadId;
  final VoidCallback onClose;

  @override
  State<_SystemNoticePanel> createState() => _SystemNoticePanelState();
}

class _SystemNoticePanelState extends State<_SystemNoticePanel> {
  SystemAnnouncement? _selected;
  double _listWidth = 280;

  @override
  void initState() {
    super.initState();
    final items = SystemAnnouncementStore.instance.items;
    if (items.isNotEmpty) _selected = items.first;
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final d = DateTime(local.year, local.month, local.day);
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final diff = day.difference(d).inDays;
    if (diff == 0) return '$hh:$mm';
    if (diff == 1) return '${translate('Yesterday')} $hh:$mm';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final store = SystemAnnouncementStore.instance;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? MyTheme.mutedDark : MyTheme.mutedLight;
    final surface = dark ? MyTheme.surfaceDark : Colors.white;
    return ColoredBox(
      color: surface,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: <Widget>[
                const Icon(Icons.campaign_rounded,
                    size: 20, color: kWeChatPrimaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    translate('System notices'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: translate('Refresh'),
                  onPressed: () => store.refresh(),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
                IconButton(
                  tooltip: translate('Close'),
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: store.revision,
                  builder: (context, _, __) {
                    if (store.items.isEmpty) {
                      return Center(
                        child: Text(
                          translate('No system notices'),
                          style: TextStyle(color: muted),
                        ),
                      );
                    }
                    if (_selected == null ||
                        !store.items.contains(_selected)) {
                      _selected = store.items.first;
                    }
                    return Row(
                      children: <Widget>[
                        SizedBox(
                          width: _listWidth,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: store.items.length,
                            itemBuilder: (context, index) {
                              final a = store.items[index];
                              return _buildListItem(
                                  context, store, a, dark, muted);
                            },
                          ),
                        ),
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                _listWidth = (_listWidth + details.delta.dx)
                                    .clamp(220.0, 420.0);
                              });
                            },
                            child: Container(
                              width: 6,
                              color: dark
                                  ? const Color(0xFF2A2D33)
                                  : const Color(0xFFEDEDED),
                            ),
                          ),
                        ),
                        Expanded(
                          child:
                              _buildDetail(context, _selected!, dark, muted),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
  }

  Widget _buildListItem(
    BuildContext context,
    SystemAnnouncementStore store,
    SystemAnnouncement a,
    bool dark,
    Color muted,
  ) {
    final isSelected = _selected?.id == a.id;
    final unread = a.id > widget.lastReadId;
    final bg = isSelected
        ? (dark
            ? const Color(0xFF2E5B3F)
            : const Color(0xFFE7F5EC))
        : Colors.transparent;
    return InkWell(
      onTap: () => setState(() => _selected = a),
      child: Container(
        color: bg,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (unread)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFA5151),
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  const SizedBox(width: 14),
                if (a.important)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFA5151).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      translate('Important'),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFFA5151),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (a.important) const SizedBox(width: 5),
                if (a.pinned)
                  Icon(Icons.push_pin_rounded, size: 13, color: muted),
                Expanded(
                  child: Text(
                    a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTime(a.createdAt),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              a.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: dark ? const Color(0xFFAEB4BC) : const Color(0xFF6B7076),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    SystemAnnouncement a,
    bool dark,
    Color muted,
  ) {
    return Container(
      color: dark ? const Color(0xFF1E2024) : const Color(0xFFF5F6F7),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.campaign_rounded,
                  size: 22,
                  color: a.important
                      ? const Color(0xFFFA5151)
                      : kWeChatPrimaryColor,
                ),
                const SizedBox(width: 10),
                if (a.important)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFA5151).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      translate('Important'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFFA5151),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (a.important) const SizedBox(width: 8),
                if (a.pinned)
                  Icon(Icons.push_pin_rounded, size: 16, color: muted),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              a.title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: dark ? Colors.white : const Color(0xFF1B1D21),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${translate('Time')} · ${_formatTime(a.createdAt)}',
              style: TextStyle(fontSize: 12.5, color: muted),
            ),
            const SizedBox(height: 22),
            const Divider(height: 1),
            const SizedBox(height: 18),
            Text(
              a.content,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.8,
                color: dark ? const Color(0xFFC8CCD3) : const Color(0xFF3B3F45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
