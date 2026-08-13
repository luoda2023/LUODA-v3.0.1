import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/mobile/pages/server_page.dart';
import 'package:luoda_flutter/mobile/pages/settings_page.dart';
import 'package:luoda_flutter/web/settings_page.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../common.dart';
import '../../consts.dart';
import '../../common/direct_chat_policy.dart';
import '../../common/direct_chat.dart';
import '../../common/direct_pairing.dart';
import '../../common/widgets/chat_page.dart';
import '../../common/widgets/direct_connection_details.dart';
import '../../common/widgets/location_picker_page.dart';
import '../../common/widgets/meeting_group_panel.dart';
import '../../common/widgets/meeting_members_dialog.dart';
import '../../common/widgets/online_status_text.dart';
import '../../models/chat_model.dart';
import '../../models/file_model.dart';
import '../../models/meeting_group_model.dart';
import '../../models/model.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'connection_page.dart';
import 'remote_meeting_page.dart';
import 'first_run_wizard.dart';

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

class _MobilePeopleGroupHeader {
  const _MobilePeopleGroupHeader(this.label, this.count);

  final String label;
  final int count;
}

/// Merged chat row: several device conversations of the same person
/// (e.g. one phone that was reinstalled and got a new ID) shown as one entry.
class _MobileChatGroup {
  const _MobileChatGroup(this.key, this.conversations);

  final String key;
  final List<MapEntry<MessageKey, MessageBody>> conversations;
}

/// ???????????/???????????ID ????????????
/// peerId?????????ID ???????????
String _resolveConversationName(
  String peerId, {
  String contactName = '',
  String chatName = '',
  String idFallback = '',
}) {
  final localName = (gFFI.chatModel.me.firstName ?? '').trim();
  final candidates = <String>[
    contactName.trim(),
    DirectPairingStore.findForConversation(peerId)?.displayName.trim() ?? '',
    chatName.trim(),
  ];
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    // LUODA FIX: the local user's own name (or the default "LUODA" product
    // name) must never be shown as a peer conversation title. This prevents
    // the conversation from renaming itself after receiving messages whose
    // sender identity was empty or mis-resolved.
    if (localName.isNotEmpty && candidate == localName) continue;
    if (candidate.toLowerCase() == 'luoda') continue;
    final compact = candidate.replaceAll(RegExp(r'[\s:\-_.]'), '');
    final isIdLike =
        compact == peerId.trim().replaceAll(RegExp(r'[\s:\-_.]'), '') ||
            RegExp(r'^[0-9]{3,}$').hasMatch(compact);
    if (!isIdLike) return candidate;
  }
  final fallback = idFallback.trim();
  return fallback;
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;

  /// When true, periodic keep-alive / pairing-sync timers are paused because
  /// the app is backgrounded (Android). Continuing to dial or run rendezvous
  /// IPC while hidden wastes battery and CPU; on resume the tasks are run
  /// once immediately and the timers restarted.
  bool _lifecyclePaused = false;
  final List<PageShape> _pages = [];
  int _chatPageTabIndex = -1;
  int _contactsPageTabIndex = -1;

  /// Contacts tab index, used by ConnectionPage to skip its keep-alive when
  /// the contacts tab is not the visible page (HomePageState owns the
  /// always-on keep-alive fallback).
  int get contactsPageTabIndex => _contactsPageTabIndex;

  /// Messages tab index, used by the messages page to skip its online-state
  /// polling while a different tab is visible.
  int get chatPageTabIndex => _chatPageTabIndex;
  int _meetingPageTabIndex = -1;
  int _assistPageTabIndex = -1;
  PageController? _pageController;
  bool _chatDetailOpen = false;
  FFI? _directFileSession;
  String _directFilePeerId = '';
  FFI? _companionSyncSession;
  String _companionSyncPeerId = '';
  Timer? _directPairingSyncTimer;
  Timer? _chatKeepAliveTimer;
  bool get isChatPageCurrentTab => isMobile && _chatDetailOpen;

  void selectChatPage() {
    if (_chatPageTabIndex < 0) return;
    if (_selectedIndex != _chatPageTabIndex) {
      _goToPage(_chatPageTabIndex);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openCurrentConversation());
    });
  }

  void _selectContactsPage() {
    if (_contactsPageTabIndex < 0 || _selectedIndex == _contactsPageTabIndex) {
      return;
    }
    _goToPage(_contactsPageTabIndex);
  }

  /// Establishes (or restores) a direct chat session for [peerId] so that
  /// messages are actually transmitted. Mirrors ConnectionPage's chat
  /// connect flow without forcing a page switch.
  Future<void> _ensureChatConnection(String peerId,
      {bool force = false}) async {
    final trimmed = peerId.trim().replaceAll(' ', '');
    if (trimmed.isEmpty) return;

    final pairing = DirectPairingStore.find(trimmed) ??
        DirectPairingStore.findByEndpoint(trimmed) ??
        DirectPairingStore.findForConversation(trimmed);
    // A conversation may be keyed by a person account (the id the sender
    // addressed, e.g. the PC id) while the actual dialable device is one of
    // that person's linked devices. Resolve those ids so mobile replies dial
    // the right device (mirrors the desktop _startDirectChat flow).
    final personIds = DirectPairingStore.conversationPeerIds(trimmed);
    final targetPeerId = pairing?.peerId ?? trimmed;
    // The live incoming chat client may be keyed by a different device id of
    // the same person (e.g. the conversation is keyed by the PC id while the
    // phone's session peer is the phone id). Match through the person id set
    // so replies go back over the live channel instead of re-dialing.
    final incomingIndex = gFFI.serverModel.clients.lastIndexWhere((client) =>
        (client.peerId.trim() == targetPeerId ||
            personIds.contains(client.peerId.trim())) &&
        client.authorized &&
        client.isChat &&
        !client.disconnected);
    // A conversation keyed by our own account id (bound phone) is still a
    // real conversation with another device of the same person. Only treat
    // it as "self" when no linked device and no live session can carry it.
    if (await DirectPairingStore.isSelfTarget(trimmed) &&
        incomingIndex < 0 &&
        !personIds.any((candidate) =>
            candidate != trimmed && DirectPairingStore.isDeviceId(candidate))) {
      return;
    }
    final endpoint = DirectPairingStore.resolveConnectionTarget(trimmed);
    debugPrint('[ENSURE_CHAT] peer=' +
        trimmed +
        ' pairing=${pairing != null} endpoint=' +
        (endpoint ?? '<null>') +
        ' personIds=$personIds' +
        ' isDialing=' +
        ChatModel.isDialing(pairing?.peerId ?? trimmed).toString());
    var dialTarget = endpoint;
    var dialForceRelay = false;
    if (dialTarget == null || dialTarget.isEmpty) {
      // No direct endpoint: fall back to dialing by device ID through the
      // rendezvous server (ID route) so messaging works over any network.
      String? deviceTarget;
      for (final candidate in personIds) {
        if (candidate == trimmed) continue;
        if (await DirectPairingStore.isSelfTarget(candidate)) continue;
        if (DirectPairingStore.isDeviceId(candidate)) {
          deviceTarget = candidate;
          break;
        }
      }
      final idTarget = deviceTarget ??
          (DirectPairingStore.isDeviceId(trimmed) ? trimmed : null);
      if (idTarget == null) {
        debugPrint('[ENSURE_CHAT] no endpoint and no device id; return for ' +
            trimmed);
        return;
      }
      dialTarget = idTarget;
      dialForceRelay = true;
      debugPrint('[ENSURE_CHAT] no endpoint; dialing by ID ' + idTarget);
    }
    if (ChatModel.isDialing(targetPeerId)) return;
    if (incomingIndex >= 0) {
      ChatModel.clearDialing(targetPeerId);
      final incoming = gFFI.serverModel.clients[incomingIndex];
      // LUODA: keep the conversation the user is viewing; only attach the
      // peer identity and let _sendWire route through the live client.
      gFFI.chatModel.updatePeerIdentity(
        targetPeerId,
        displayName: incoming.name.trim().isNotEmpty
            ? incoming.name.trim()
            : pairing?.displayName ?? targetPeerId,
        avatar: incoming.avatar,
      );
      return;
    }
    final liveConversationPeer = gFFI.chatModel.currentKey.peerId;
    if (!force &&
        !gFFI.closed &&
        gFFI.connType == ConnType.chat &&
        gFFI.ffiModel.pi.isSet.isTrue &&
        (liveConversationPeer == targetPeerId ||
            liveConversationPeer == trimmed ||
            personIds.contains(liveConversationPeer))) {
      ChatModel.clearDialing(targetPeerId);
      return;
    }
    if (force) {
      debugPrint('[ENSURE_CHAT] force redial for ' + targetPeerId);
    }
    if (gFFI.ffiModel.pi.isSet.isTrue || gFFI.connType == ConnType.chat) {
      await gFFI.close();
    }
    ChatModel.markDialing(targetPeerId);
    // LUODA: never hijack the visible conversation while dialing; the caller
    // (e.g. _openConversation) already set the current key.
    if (pairing != null) {
      gFFI.chatModel.updatePeerIdentity(
        targetPeerId,
        displayName: pairing.displayName,
        avatar: pairing.avatar,
      );
    }
    gFFI.suppressConnectionDialogs = true;
    debugPrint('[ENSURE_CHAT] dialing target=' +
        targetPeerId +
        ' endpoint=' +
        dialTarget +
        ' forceRelay=$dialForceRelay');
    final cachedPassword = DirectPairingStore.cachedChatPassword(targetPeerId);
    gFFI.start(dialTarget,
        isChat: true, forceRelay: dialForceRelay, password: cachedPassword);
  }

  /// 维护聊天保活。
  Future<void> _maintainChatKeepAlive() async {
    if (!mounted) return;
    // 未连接、非默认连接或尚未初始化时无需保活，直接返回。

    if (!gFFI.closed &&
        gFFI.connType == ConnType.defaultConn &&
        gFFI.ffiModel.pi.isSet.isTrue) {
      return;
    }
    var watchPeer = gFFI.chatModel.lastActiveChatPeerId;
    if (watchPeer == null || watchPeer.isEmpty) {
      // 当前无活跃会话时，取第一条待处理会话。

      watchPeer = await gFFI.chatModel.firstPendingPeerId();
    }
    if (watchPeer == null || watchPeer.isEmpty) return;
    final access = DirectChatAccessController.instance..load();
    if (!access.shouldAutoReconnect(watchPeer)) return;
    if (DirectPairingStore.resolveConnectionTarget(watchPeer) == null) return;
    final hasStuck = await gFFI.chatModel.hasPendingOutgoing(watchPeer);
    if (!gFFI.closed &&
        gFFI.connType == ConnType.chat &&
        gFFI.chatModel.currentKey.peerId == watchPeer &&
        gFFI.ffiModel.pi.isSet.isTrue &&
        !hasStuck) {
      return;
    }
    await _ensureChatConnection(watchPeer, force: true);
    // 拨号完成后刷新该会话的待发消息。
    unawaited(_flushPendingAfterDial(watchPeer));
  }

  /// 拨号后刷新待发消息。
  Future<void> _flushPendingAfterDial(String peerId) async {
    /// 刷新该会话的待发消息。
    if (peerId.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    await gFFI.chatModel.flushPendingOutgoing(peerId);
  }

  /// 从会议群聊标题栏加入实时远程会话（观看演示/教学）。
  void _joinMeetingSessionFromChat(MeetingGroup group) {
    if (!group.hasActiveSession || group.activeSessionEndpoint.isEmpty) {
      showToast(translate('No active session yet'));
      return;
    }
    connect(context, group.activeSessionEndpoint,
        isFileTransfer: false, isViewCamera: false, isTerminal: false);
  }

  /// 会议群聊标题栏直接添加成员（群主入口）。
  Future<void> _showMobileAddMemberDialog(
    BuildContext dialogContext,
    MeetingGroup group,
  ) async {
    final theme = Theme.of(dialogContext);
    final controller = TextEditingController();
    final peerId = await showDialog<String>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    if (trimmed == group.hostPeerId || trimmed == gFFI.serverModel.id) {
      showToast(translate('Already a member'));
      return;
    }
    if ((group.members ?? []).any((m) => m.peerId == trimmed)) {
      showToast(translate('Already a member'));
      return;
    }
    final peer = gFFI.recentPeersModel.peers
        .firstWhereOrNull((p) => p.id == trimmed);
    final displayName = peer?.alias.isNotEmpty == true
        ? peer!.alias
        : peer?.username.isNotEmpty == true
            ? peer!.username
            : trimmed;
    MeetingGroupStore.addMember(group.meetingId, trimmed, displayName);
    if (mounted) setState(() {});
    showToast('$displayName ${translate('joined the group')}');
  }

  void _openConversation(MessageKey key) {
    gFFI.chatModel.changeCurrentKey(key);
    gFFI.chatModel.mobileClearClientUnread(key.connId);
    unawaited(_openCurrentConversation());
    // 会议群聊走群消息通道，不需要（也不应该）建立单聊 P2P 连接。
    if (key.peerId.isNotEmpty && !key.peerId.startsWith('meeting:')) {
      unawaited(_ensureChatConnection(key.peerId));
    }
  }

  Future<void> _openCurrentConversation() async {
    final key = gFFI.chatModel.currentKey;
    if (!mounted || _chatDetailOpen || key.peerId.isEmpty) return;
    _chatDetailOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AnimatedBuilder(
            animation: gFFI.chatModel,
            builder: (context, __) {
              final user = gFFI.chatModel.currentUser;
              final currentKey = gFFI.chatModel.currentKey;
              // 会议群聊：标题显示会议名 + 群成员徽标，点击打开成员查询窗口。
              final isMeetingChat = currentKey.peerId.startsWith('meeting:');
              final meetingGroup = isMeetingChat
                  ? MeetingGroupStore.find(
                      currentKey.peerId.substring('meeting:'.length),
                    )
                  : null;
              final meetingMemberCount =
                  (meetingGroup?.members?.length ?? 0) + 1;
              final name = meetingGroup != null
                  ? meetingGroup.title
                  : currentKey.peerId == kFileHelperId
                      ? translate('File Transfer Assistant')
                      : _resolveConversationName(
                          currentKey.peerId,
                          contactName: _findContactByPeerId(currentKey.peerId)
                                  ?.finalName() ??
                              '',
                          chatName: user?.firstName ?? '',
                        );
              final pairing = DirectPairingStore.findForConversation(
                currentKey.peerId,
              );
              return Scaffold(
                appBar: AppBar(
                  centerTitle: true,
                  toolbarHeight: 44,
                  elevation: 0,
                  title: InkWell(
                    onTap: meetingGroup != null
                        ? () => showMeetingMembersDialog(context, meetingGroup)
                              .then((dissolved) {
                              if (dissolved == true) {
                                Navigator.of(context).pop();
                              }
                            })
                        : pairing == null
                            ? null
                            : () => showDirectConnectionDetails(
                                  context,
                                  conversationId: currentKey.peerId,
                            ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          name.isEmpty ? currentKey.peerId : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: MobileText.bodyLg,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                        if (meetingGroup != null)
                          Text(
                            '${translate('Group chat')} · '
                            '$meetingMemberCount ${translate('Members')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: MobileText.badge,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF07C160),
                              letterSpacing: 0,
                            ),
                          )
                        else if (pairing != null)
                          Text(
                            directConnectionRouteLabel(currentKey.peerId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: MobileText.badge,
                              fontWeight: FontWeight.w400,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                              letterSpacing: 0,
                            ),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    if (meetingGroup != null) ...<Widget>[
                      if (meetingGroup.hasActiveSession)
                        IconButton(
                          icon: const Icon(Icons.sensors_rounded),
                          tooltip: translate('Join live session'),
                          onPressed: () =>
                              _joinMeetingSessionFromChat(meetingGroup),
                        ),
                      if (meetingGroup.isHost)
                        IconButton(
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          tooltip: translate('Add member'),
                          onPressed: () =>
                              _showMobileAddMemberDialog(context, meetingGroup),
                        ),
                    ],
                    IconButton(
                      icon: const Icon(Icons.search_rounded),
                      tooltip: translate('Search Messages'),
                      onPressed: () {
                        gFFI.chatModel.openChatSearch();
                      },
                    ),
                    PopupMenuButton<String>(
                      tooltip: translate('More'),
                      onSelected: (action) {
                        final peerId = gFFI.chatModel.currentKey.peerId;
                        if (action == 'meetingMembers') {
                          final group = MeetingGroupStore.find(
                            peerId.startsWith('meeting:')
                                ? peerId.substring('meeting:'.length)
                                : '',
                          );
                          if (group != null) {
                            unawaited(showMeetingMembersDialog(context, group)
                                .then((dissolved) {
                              if (dissolved == true && mounted) {
                                Navigator.of(context).pop();
                              }
                            }));
                          }
                        } else if (action == 'mute') {
                          gFFI.chatSettingsModel.toggleMute(peerId);
                        } else if (action == 'block') {
                          gFFI.chatSettingsModel.toggleBlock(peerId);
                        } else if (action == 'connectionDetails') {
                          showDirectConnectionDetails(
                            context,
                            conversationId: peerId,
                          );
                        }
                      },
                      itemBuilder: (context) {
                        final peerId = gFFI.chatModel.currentKey.peerId;
                        return [
                          if (meetingGroup != null)
                            PopupMenuItem(
                              value: 'meetingMembers',
                              child: Row(
                                children: <Widget>[
                                  const Icon(Icons.groups_rounded, size: 18),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${translate('Group chat')} · '
                                    '$meetingMemberCount ${translate('Members')}',
                                  ),
                                ],
                              ),
                            ),
                          if (pairing != null)
                            PopupMenuItem(
                              value: 'connectionDetails',
                              child: Row(
                                children: <Widget>[
                                  const Icon(Icons.hub_outlined, size: 18),
                                  const SizedBox(width: 10),
                                  Text(translate('P2P connection details')),
                                ],
                              ),
                            ),
                          PopupMenuItem(
                            value: 'mute',
                            child: Text(
                              gFFI.chatSettingsModel.isMuted(peerId)
                                  ? translate('Unmute')
                                  : translate('Mute'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'block',
                            child: Text(
                              gFFI.chatSettingsModel.isBlocked(peerId)
                                  ? translate('Unblock')
                                  : translate('Block'),
                            ),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
                body: ChatPage(
                  type: ChatPageType.mobileMain,
                  onAttachFile: _sendDirectChatFiles,
                  onRemoteAssist: _startRemoteFromChat,
                  onForwardMessages: _forwardConversationMessages,
                  onSendImage: _pickImageOrFile,
                  onTakePhoto: _takePhoto,
                  onSendLocation: _sendLocation,
                ),
              );
            },
          ),
        ),
      );
    } finally {
      _chatDetailOpen = false;
    }
  }

  Future<void> syncPairingsNow() => _syncLatestPairing();

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // LUODA: the chat page must be able to establish its own chat session.
    // Previously this callback was only registered by ConnectionPage, so
    // opening a conversation from the recent list sent into a dead session
    // (messages stuck at "sent" / "A rejects messages").
    gFFI.chatModel.ensureChatConnection = _ensureChatConnection;
    // 启动即加载会议群聊数据，点聊列表才能混排显示会议。
    MeetingGroupStore.load();
    initPages();
    final count = _pages.length;
    // Start in the middle of the infinite carousel so BOTH swipe
    // directions work from launch (an end-anchored start blocked the
    // forward/next swipe because the initial page was the last one).
    final base = count <= 0 ? 0 : (50000000 ~/ count) * count;
    _pageController = PageController(initialPage: base);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncLatestPairing());
      // Show one-time permission wizard on first install (Android only).
      // Once it finishes (or was already done), auto-start the service so the
      // device registers with the rendezvous server right away instead of
      // waiting for the user to open the manual toggle.
      if (isAndroid) {
        unawaited(FirstRunPermissionWizard.showIfNeeded(context).then((done) {
          if (done) {
            unawaited(gFFI.serverModel.maybeAutoStartService());
          }
        }));
      }
    });
    _directPairingSyncTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(_syncLatestPairing()),
    );
    // LUODA: keep the last active direct-chat session alive and re-dial it
    // when it drops, so messages are received / delivered even when the user
    // is on the Messages tab (ConnectionPage's own keep-alive only runs while
    // its tab is mounted).
    _chatKeepAliveTimer = Timer.periodic(
      ChatModel.kChatReconnectInterval,
      (_) => unawaited(_maintainChatKeepAlive()),
    );
    Future<void>.delayed(const Duration(milliseconds: 3000), () {
      unawaited(_maintainChatKeepAlive());
    });
  }

  final GlobalKey<_MobileMessagesPageState> _mobileMessagesKey =
      GlobalKey<_MobileMessagesPageState>();
  final GlobalKey<ConnectionPageState> _contactsPageKey =
      GlobalKey<ConnectionPageState>();

// DotChat v3.1.1 build marker: search box GlobalKey attached
  void initPages() {
    _pages.clear();
    // DotChat ?????? ? ???? ? ????????????
    // ?? / ???????? tab??? AppBar ??????????
    if (isMobile) {
      _chatPageTabIndex = _pages.length;
      _pages.add(_MobileMessagesPage(
        key: _mobileMessagesKey,
        onOpenConversation: _openConversation,
        onNewConversation: _selectContactsPage,
        onOpenMeetings: () {
          if (_meetingPageTabIndex >= 0) _goToPage(_meetingPageTabIndex);
        },
        searchKey: _mobileMessagesKey,
      ));
    }
    if (!bind.isIncomingOnly()) {
      _contactsPageTabIndex = _pages.length;
      _pages.add(ConnectionPage(
        key: _contactsPageKey,
        // 搜索图标上移至 AppBar，与点聊页一致（点击弹出悬浮搜索框）。
        appBarActions: <Widget>[
          IconButton(
            tooltip: translate('Search'),
            onPressed: () => _contactsPageKey.currentState?.openContactSearch(),
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ));
    } else {
      _contactsPageTabIndex = -1;
    }
    _assistPageTabIndex = _pages.length;
    _pages.add(ServerPage());
    _meetingPageTabIndex = _pages.length;
    _pages.add(const RemoteMeetingPage());
  }

  void _startRemoteFromChat() {
    final peerId = gFFI.chatModel.currentKey.peerId.trim();
    if (peerId.isEmpty) return;
    final endpoint = DirectPairingStore.resolveConnectionTarget(peerId);
    if (endpoint == null) {
      showToast(translate(
        'Direct endpoint required. Scan the PC QR code or enter IP:port.',
      ));
      return;
    }
    connect(context, endpoint, forceRelay: false);
  }

  void connectByInput(String value) {
    final trimmed = value.trim().replaceAll(' ', '');
    if (trimmed.isEmpty) return;
    final endpoint =
        DirectPairingStore.resolveConnectionTarget(trimmed) ?? trimmed;
    connect(context, endpoint, forceRelay: false);
  }

  Future<void> showMyIdentity() async {
    final id = gFFI.serverModel.id.trim();
    final fingerprint = await bind.mainGetFingerprint();
    if (!mounted) return;
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(translate('My identity')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              translate('ID'),
              style: TextStyle(
                fontSize: MobileText.caption,
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: SelectableText(
                    id,
                    style: TextStyle(
                      fontSize: MobileText.titleSm,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: translate('Copy'),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: id));
                    showToast(translate('Copied'));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              translate('Fingerprint'),
              style: TextStyle(
                fontSize: MobileText.caption,
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              fingerprint,
              style: TextStyle(
                fontSize: MobileText.captionSm,
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(translate('Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _syncLatestPairing() async {
    if (!mounted || !isMobile) return;
    final access = DirectChatAccessController.instance..load();
    if (!access.alwaysOn) return;
    await gFFI.serverModel.updateClientState();
    if (!mounted) return;
    final pairing = DirectPairingStore.latestCompanion();
    if (pairing == null) return;
    final existing = _companionSyncSession;
    if (existing != null &&
        !existing.closed &&
        _companionSyncPeerId == pairing.peerId &&
        existing.ffiModel.pi.isSet.isTrue &&
        existing.ffiModel.direct == true) {
      await existing.chatModel.requestCompanionSync(
        peerId: pairing.peerId,
        connId: ChatModel.clientModeID,
      );
      return;
    }
    if (existing != null) {
      await existing.close();
    }
    final ffi = FFI(const Uuid().v4obj());
    ffi.suppressConnectionDialogs = true;
    _companionSyncSession = ffi;
    _companionSyncPeerId = pairing.peerId;
    ffi.chatModel.changeCurrentKey(
      MessageKey(pairing.peerId, ChatModel.clientModeID),
    );
    ffi.chatModel.updatePeerIdentity(
      pairing.peerId,
      displayName: pairing.displayName,
      avatar: '',
    );
    ffi.start(
      pairing.connectionTarget,
      isChat: true,
      forceRelay: false,
    );
  }

  /// Show WeChat-style bottom sheet: Take Photo / Gallery / File
  Future<void> _pickImageOrFile() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: Text(translate('Take Photo')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(translate('Choose from Gallery')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_rounded),
              title: Text(translate('Send File')),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'file') {
      await _sendDirectChatFiles();
    } else {
      final type = action == 'camera' ? FileType.media : FileType.image;
      final picked =
          await FilePicker.platform.pickFiles(type: type, allowMultiple: true);
      final files = picked?.files.where((f) => f.path != null).toList() ?? [];
      if (files.isEmpty) return;
      await _sendPickedFiles(files);
    }
  }

  Future<void> _sendDirectChatFiles() async {
    final currentKey = gFFI.chatModel.currentKey;
    final peerId = currentKey.peerId.trim();
    final connected = currentKey.isOut
        ? gFFI.connType == ConnType.chat &&
            isDirectChatSessionReady(
              closed: gFFI.closed,
              peerInfoReady: gFFI.ffiModel.pi.isSet.isTrue,
              connectionError: gFFI.ffiModel.lastConnectionError,
            )
        : gFFI.serverModel.clients.any(
            (client) =>
                client.id == currentKey.connId &&
                client.authorized &&
                client.isChat &&
                !client.disconnected,
          );
    if (peerId.isEmpty || !connected) {
      showToast(translate('Connect to the contact before sending files.'));
      return;
    }

    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    final files = picked?.files.where((file) => file.path != null).toList() ??
        <PlatformFile>[];
    if (files.isEmpty || !mounted) return;
    await _sendPickedFiles(files);
  }

  Future<void> _sendPickedFiles(List<PlatformFile> files) async {
    final currentKey = gFFI.chatModel.currentKey;
    final peerId = currentKey.peerId.trim();
    final connected = currentKey.isOut
        ? gFFI.connType == ConnType.chat &&
            isDirectChatSessionReady(
              closed: gFFI.closed,
              peerInfoReady: gFFI.ffiModel.pi.isSet.isTrue,
              connectionError: gFFI.ffiModel.lastConnectionError,
            )
        : gFFI.serverModel.clients.any(
            (client) =>
                client.id == currentKey.connId &&
                client.authorized &&
                client.isChat &&
                !client.disconnected,
          );
    if (peerId.isEmpty || !connected) {
      showToast(translate('Connect to the contact before sending files.'));
      return;
    }
    // File size guard: reject individual files > 500 MB or total > 2 GB
    const kMaxSingleFileBytes = 500 * 1024 * 1024;
    const kMaxTotalBytes = 2 * 1024 * 1024 * 1024;
    var totalBytes = 0;
    for (final f in files) {
      if (f.size > kMaxSingleFileBytes) {
        showToast(
            translate('File too large') + ': ${f.name} (${_fmtSize(f.size)})');
        return;
      }
      totalBytes += f.size;
    }
    if (totalBytes > kMaxTotalBytes) {
      showToast(translate('Total size exceeds 2 GB limit'));
      return;
    }
    final inlineFiles = files
        .where((file) => canInlineDirectChatFile(file.size))
        .toList(growable: false);
    for (final file in inlineFiles) {
      await gFFI.chatModel.sendFileRecord(
        fileName: file.name,
        fileSize: file.size,
        localPath: file.path!,
      );
    }

    final transferFiles = files
        .where((file) => !canInlineDirectChatFile(file.size))
        .toList(growable: false);
    if (transferFiles.isNotEmpty) {
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
      if (gFFI.chatModel.currentKey.peerId.trim() == peerId) {
        for (final file in transferFiles) {
          await gFFI.chatModel.sendFileRecord(
            fileName: file.name,
            fileSize: file.size,
            localPath: file.path!,
          );
        }
      }
      showToast(translate('Direct file transfer started.'));
    } else {
      showToast(translate('Sent file'));
    }
  }

  /// 当前会话是否已建立直连（聊天/协助都能发送内容的前提）。
  bool _directChatConnected() {
    final currentKey = gFFI.chatModel.currentKey;
    final peerId = currentKey.peerId.trim();
    if (peerId.isEmpty) return false;
    if (currentKey.isOut) {
      return gFFI.connType == ConnType.chat &&
          isDirectChatSessionReady(
            closed: gFFI.closed,
            peerInfoReady: gFFI.ffiModel.pi.isSet.isTrue,
            connectionError: gFFI.ffiModel.lastConnectionError,
          );
    }
    return gFFI.serverModel.clients.any(
      (client) =>
          client.id == currentKey.connId &&
          client.authorized &&
          client.isChat &&
          !client.disconnected,
    );
  }

  /// 拍照并直接发送（image_picker 调起系统相机）。
  Future<void> _takePhoto() async {
    if (!_directChatConnected()) {
      showToast(translate('Connect to the contact before sending files.'));
      return;
    }
    XFile? shot;
    try {
      shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
    } catch (e) {
      debugPrint('_takePhoto failed: $e');
      if (mounted) showToast(translate('Failed to take photo'));
      return;
    }
    if (shot == null || !mounted) return;
    try {
      final length = await shot.length();
      await _sendPickedFiles(<PlatformFile>[
        PlatformFile(
          name: shot.name,
          size: length,
          path: shot.path,
        ),
      ]);
    } catch (e) {
      debugPrint('_takePhoto send failed: $e');
      if (mounted) showToast(translate('Failed to send photo'));
    }
  }

  /// 微信风格发送定位：先打开地图显示“我的位置”，用户确认/选点后发送。
  Future<void> _sendLocation() async {
    if (!_directChatConnected()) {
      showToast(translate('Connect to the contact before sending files.'));
      return;
    }
    Position? position;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        showToast(translate('Location service is disabled'));
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        showToast(translate('Location permission required'));
        return;
      }
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint('_sendLocation failed: $e');
      // 模拟器/无 GPS 环境常见超时，给出可理解提示。
      if (mounted) showToast(translate('Failed to get location'));
      return;
    }
    if (!mounted || position == null) return;
    // 打开地图选点页（微信风格），用户确认后拿到 GCJ-02 坐标再发送。
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute<PickedLocation>(
        builder: (_) => LocationPickerPage(
          gpsLat: position!.latitude,
          gpsLng: position!.longitude,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    gFFI.chatModel.sendText(
      DirectChatLocation(
        latitude: picked.latitude,
        longitude: picked.longitude,
        name: translate('My Location'),
      ).encode(),
    );
  }

  Future<bool> _forwardConversationMessages(
    String rawTargetPeerId,
    List<ChatForwardItem> items,
    bool merged,
  ) async {
    if (items.isEmpty) return false;
    final pairing = DirectPairingStore.find(rawTargetPeerId) ??
        DirectPairingStore.findByEndpoint(rawTargetPeerId);
    final peerId = pairing?.peerId ?? rawTargetPeerId.trim();
    final ensureConnection = gFFI.chatModel.ensureChatConnection;
    if (peerId.isEmpty ||
        ensureConnection == null ||
        await DirectPairingStore.isSelfTarget(peerId)) {
      return false;
    }
    await ensureConnection(peerId, force: false);
    if (gFFI.chatModel.currentKey.peerId != peerId) return false;

    if (merged) {
      final senders = items
          .map((item) => item.senderName)
          .where((name) => name.isNotEmpty)
          .toSet()
          .take(2)
          .join(', ');
      await gFFI.chatModel.sendForwardBundle(
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
    if (transferableFiles.isNotEmpty) {
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
          await gFFI.chatModel.sendFileRecord(
            fileName: item.fileName,
            fileSize: item.fileSize,
            localPath: item.localPath,
          );
        } else {
          await gFFI.chatModel.sendTextAndWait(
            '[${translate('File')}] ${item.fileName}',
          );
        }
      } else if (item.kind == DirectChatKind.voice) {
        await gFFI.chatModel.sendTextAndWait(
          '[${translate('Voice')}] '
          '${(item.voiceDurationMs / 1000).ceil()}s',
        );
      } else if (item.text.isNotEmpty) {
        await gFFI.chatModel.sendTextAndWait(item.text);
      }
    }
    return true;
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<FFI?> _ensureDirectFileSession(String peerId) async {
    final existing = _directFileSession;
    if (existing != null &&
        _directFilePeerId == peerId &&
        !existing.closed &&
        existing.ffiModel.pi.isSet.isTrue &&
        existing.ffiModel.direct == true) {
      return existing;
    }
    if (existing != null) {
      _directFileSession = null;
      _directFilePeerId = '';
      await _disposeDirectFileSession(existing);
    }

    final endpoint = DirectPairingStore.resolveConnectionTarget(peerId);
    if (endpoint == null) {
      showToast(translate(
        'Direct endpoint required. Scan the PC QR code or enter IP:port.',
      ));
      return null;
    }
    final ffi = FFI(const Uuid().v4obj());
    ffi.suppressConnectionDialogs = true;
    _directFileSession = ffi;
    _directFilePeerId = peerId;
    ffi.start(endpoint, isFileTransfer: true, forceRelay: false);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (ffi.ffiModel.pi.isSet.isTrue) {
        ffi.dialogManager.dismissAll();
        if (ffi.ffiModel.direct != true) {
          _directFileSession = null;
          _directFilePeerId = '';
          await _disposeDirectFileSession(ffi);
          showToast(
            translate('Direct connection failed. File relay is disabled.'),
          );
          return null;
        }
        if (await _waitForFileDirectories(ffi)) return ffi;
        break;
      }
      if (ffi.closed || (ffi.ffiModel.lastConnectionError ?? '').isNotEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    ffi.dialogManager.dismissAll();
    if (_directFileSession == ffi) {
      _directFileSession = null;
      _directFilePeerId = '';
    }
    final error = ffi.ffiModel.lastConnectionError;
    await _disposeDirectFileSession(ffi);
    showToast(
      translate(
        error?.isNotEmpty == true
            ? error!
            : 'Direct file transfer connection timed out.',
      ),
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

  Future<void> _disposeDirectFileSession(FFI ffi) async {
    if (ffi.closed) return;
    try {
      await ffi.fileModel.close();
    } finally {
      await ffi.close();
    }
  }

  @override
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (paused == _lifecyclePaused) return;
    _lifecyclePaused = paused;
    if (paused) {
      // Backgrounded: pause periodic IPC-heavy tasks to save battery/CPU.
      _chatKeepAliveTimer?.cancel();
      _chatKeepAliveTimer = null;
      _directPairingSyncTimer?.cancel();
      _directPairingSyncTimer = null;
    } else {
      // Resumed: catch up immediately, then restart the timers.
      unawaited(_maintainChatKeepAlive());
      unawaited(_syncLatestPairing());
      _chatKeepAliveTimer = Timer.periodic(
        ChatModel.kChatReconnectInterval,
        (_) => unawaited(_maintainChatKeepAlive()),
      );
      _directPairingSyncTimer = Timer.periodic(
        const Duration(minutes: 30),
        (_) => unawaited(_syncLatestPairing()),
      );
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (gFFI.chatModel.ensureChatConnection == _ensureChatConnection) {
      gFFI.chatModel.ensureChatConnection = null;
    }
    _chatKeepAliveTimer?.cancel();
    _pageController?.dispose();
    _pageController = null;
    _directPairingSyncTimer?.cancel();
    final fileSession = _directFileSession;
    _directFileSession = null;
    if (fileSession != null) {
      unawaited(_disposeDirectFileSession(fileSession));
    }
    final companionSession = _companionSyncSession;
    _companionSyncSession = null;
    if (companionSession != null && !companionSession.closed) {
      unawaited(companionSession.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _pages.length;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return WillPopScope(
        onWillPop: () async {
          if (_selectedIndex != _chatPageTabIndex) {
            _goToPage(_chatPageTabIndex);
          } else {
            return true;
          }
          return false;
        },
        child: Scaffold(
          backgroundColor: dark ? MyTheme.canvasDark : MyTheme.canvasLight,
          appBar: AppBar(
            centerTitle: true,
            toolbarHeight: 44,
            elevation: 0,
            backgroundColor: dark ? MyTheme.surfaceDark : MyTheme.canvasLight,
            // 点聊/联系人 tab：在线状态独立放到最左侧（leading），
            // 不与标题挤在一起；其余 tab 不占 leading，标题保持居中。
            leadingWidth: 116,
            leading: appLeading(),
            title: appTitle(),
            actions: <Widget>[
              ..._pages.elementAt(_selectedIndex).appBarActions,
              // ?? / ?????????? tab????????
              IconButton(
                tooltip: translate('Me'),
                icon: const Icon(Icons.person_outline_rounded),
                onPressed: () {
                  final settingsPage = SettingsPage();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => settingsPage,
                    ),
                  );
                },
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(context),
          body: count == 0
              ? const SizedBox.shrink()
              : PageView.builder(
                  controller: _pageController,
                  // ??????? ? ?? ? ?? ? ??
                  itemCount: 100000001,
                  onPageChanged: (index) {
                    final page = index % count;
                    if (page != _selectedIndex) {
                      setState(() => _selectedIndex = page);
                      if (page == _chatPageTabIndex) {
                        gFFI.chatModel.hideChatIconOverlay();
                        gFFI.chatModel.hideChatWindowOverlay();
                        gFFI.chatModel.mobileClearClientUnread(
                            gFFI.chatModel.currentKey.connId);
                      }
                    }
                  },
                  itemBuilder: (context, index) =>
                      _pages.elementAt(index % count),
                ),
        ));
  }

  void _goToPage(int index) {
    final count = _pages.length;
    if (count <= 0) return;
    final controller = _pageController;
    if (controller == null) {
      if (index != _selectedIndex) setState(() => _selectedIndex = index);
      return;
    }
    final base = (controller.initialPage ~/ count) * count;
    controller.animateToPage(
      base + index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: BottomNavigationBar(
        key: navigationBarKey,
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum),
            label: translate('DotChat'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.contacts_outlined),
            activeIcon: const Icon(Icons.contacts_rounded),
            label: translate('Contacts'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.support_agent_outlined),
            activeIcon: const Icon(Icons.support_agent_rounded),
            label: translate('Assist'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.videocam_outlined),
            activeIcon: const Icon(Icons.videocam_rounded),
            label: translate('Meeting'),
          ),
        ],
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: dark ? MyTheme.surfaceDark : const Color(0xFFF7F7F7),
        selectedItemColor: MyTheme.accent,
        unselectedItemColor: dark ? MyTheme.mutedDark : const Color(0xFF8A8D94),
        selectedFontSize: 12,
        unselectedFontSize: 12,
        selectedLabelStyle: const TextStyle(
          fontSize: MobileText.caption,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: MobileText.caption,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
        iconSize: 26,
        elevation: 0,
        onTap: _goToPage,
      ),
    );
  }

  /// AppBar leading：点聊/联系人 tab 时把在线状态放到最左侧（贴边），
  /// 其余 tab 返回 null，不占 leading 区域。
  Widget? appLeading() {
    final showOnline = _selectedIndex == _chatPageTabIndex ||
        _selectedIndex == _contactsPageTabIndex;
    if (!showOnline) return null;
    return const Padding(
      padding: EdgeInsets.only(left: 16),
      child: OnlineStatusText(),
    );
  }

  /// AppBar 标题：点聊/联系人 tab 时在线状态已移到最左侧（见 appLeading），
  /// 标题本身保持居中。
  Widget appTitle() {
    final title = _pages.elementAt(_selectedIndex).title;
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: MobileText.bodyLg,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

Peer? _findContactByPeerId(String peerId) {
  for (final model in <Peers>[
    gFFI.recentPeersModel,
    gFFI.favoritePeersModel,
    gFFI.lanPeersModel,
    gFFI.abModel.peersModel,
    gFFI.groupModel.peersModel,
  ]) {
    for (final peer in model.peers) {
      if (peer.id == peerId) {
        return peer;
      }
    }
  }
  return null;
}

class _MobileMessagesPage extends StatefulWidget implements PageShape {
  const _MobileMessagesPage({
    super.key,
    required this.onOpenConversation,
    required this.onNewConversation,
    this.onOpenMeetings,
    this.searchKey,
  });

  final ValueChanged<MessageKey> onOpenConversation;
  final VoidCallback onNewConversation;
  final VoidCallback? onOpenMeetings;
  final GlobalKey<_MobileMessagesPageState>? searchKey;

  @override
  String get title => translate('DotChat');

  @override
  Widget get icon => unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum);

  @override
  List<Widget> get appBarActions => <Widget>[
        // LUODA: the search icon sits in the top bar, left of the
        // "add friend" button, so the list area stays uncluttered.
        IconButton(
          tooltip: translate('Search'),
          onPressed: () => searchKey?.currentState?.openSearch(),
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: translate('New conversation'),
          onPressed: onNewConversation,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ];

  @override
  State<_MobileMessagesPage> createState() => _MobileMessagesPageState();
}

class _MobileMessagesPageState extends State<_MobileMessagesPage>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _query = ValueNotifier<String>('');
  bool _searchOpen = false;

  /// 会议群聊数据变化订阅（创建/加入/解散后刷新点聊列表）。
  StreamSubscription<List<MeetingGroup>>? _meetingsSub;
  Set<String> _selfTargets = const <String>{};
  String _selfDirectPort = '';
  // Rendezvous-driven online states, refreshed periodically so peers show
  // "online" without requiring an active chat connection (the old UI only
  // lit up the dot after a manual P2P poke).
  final Map<String, bool> _onlineByPeer = <String, bool>{};
  Timer? _onlineQueryTimer;
  static const String _onlineHandlerName = 'messages_online';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    platformFFI.registerEventHandler(
      'callback_query_onlines',
      _onlineHandlerName,
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
          if (_onlineByPeer[id] != true) {
            _onlineByPeer[id] = true;
            changed = true;
          }
        }
        for (final id in offlines) {
          if (_onlineByPeer[id] != false) {
            _onlineByPeer[id] = false;
            changed = true;
          }
        }
        if (changed && mounted) setState(() {});
      },
      replace: true,
    );
    _onlineQueryTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _queryOnlineStates());
    _queryOnlineStates();
    unawaited(_loadSelfTargets());
    // 会议群聊数据变化时刷新点聊列表（创建/加入/解散会议后立即反映）。
    _meetingsSub = MeetingGroupStore.reactive.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// True when this Messages tab is the visible page. PageView pre-builds
  /// adjacent pages, so without this guard a hidden tab keeps polling the
  /// rendezvous server every 10s for peers the user is not looking at.
  bool get _isCurrentTab {
    final home = HomePage.homeKey.currentState;
    if (home == null) return true;
    // Before tabs are laid out the index is -1: allow the initial query.
    if (home.chatPageTabIndex < 0) return true;
    return home.selectedIndex == home.chatPageTabIndex;
  }

  void _queryOnlineStates() {
    if (!mounted || !_isCurrentTab) return;
    final ids = <String>{
      for (final entry in gFFI.chatModel.messages.entries)
        if (entry.key.peerId.isNotEmpty &&
            entry.key.peerId != kFileHelperId &&
            !_isSelfEntry(entry.key))
          entry.key.peerId,
    }.toList(growable: false);
    if (ids.isNotEmpty) {
      bind.queryOnlines(ids: ids);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Messages persisted by the background service while the app was
      // suspended appear immediately instead of waiting for the poll timer.
      unawaited(gFFI.chatModel.refreshRecentFromStorage());
      if (_onlineQueryTimer == null) {
        _onlineQueryTimer = Timer.periodic(
            const Duration(seconds: 10), (_) => _queryOnlineStates());
        _queryOnlineStates();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Backgrounded: stop polling the rendezvous server until resumed.
      _onlineQueryTimer?.cancel();
      _onlineQueryTimer = null;
    }
  }

  /// Opens the search field from the top-bar search icon.
  void openSearch() {
    if (mounted && !_searchOpen) setState(() => _searchOpen = true);
  }

  Future<void> _loadSelfTargets() async {
    try {
      final myId = (await bind.mainGetMyId()).trim().replaceAll(' ', '');
      final lan = bind.mainGetOptionSync(key: 'lan-ip').trim();
      final pub = bind.mainGetOptionSync(key: 'public-ip').trim();
      _selfTargets = <String>{myId, lan, pub, 'localhost'};
      _selfDirectPort =
          bind.mainGetOptionSync(key: 'direct-access-port').trim();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  /// 判断是否为自身条目（按ID / IP / localhost）。
  bool _isSelfEntry(MessageKey key) {
    final peerId = key.peerId.trim();
    if (peerId.isEmpty || peerId == kFileHelperId) return false;
    final normalized = peerId.toLowerCase();
    if (normalized == 'localhost' ||
        normalized == '::1' ||
        normalized.startsWith('127.')) {
      return true;
    }
    for (final target in _selfTargets) {
      final t = target.trim().toLowerCase();
      if (t.isEmpty) continue;
      if (normalized == t) return true;
      // host:port endpoints are only "myself" when the port also matches this
      // device's own direct port. Peers behind the same public IP (e.g. NAT)
      // produce host:port conversations whose host may equal ours; filtering
      // them by host alone hides real contacts.
      final host = t.split(':').first;
      if (host.isNotEmpty && normalized.startsWith('$host:')) {
        final portPart = normalized.substring(host.length + 1);
        if (_selfDirectPort.isNotEmpty && portPart == _selfDirectPort) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onlineQueryTimer?.cancel();
    platformFFI.unregisterEventHandler(
        'callback_query_onlines', _onlineHandlerName);
    _meetingsSub?.cancel();
    _searchController.dispose();
    _query.dispose();
    super.dispose();
  }

  bool _isMobilePlatform(String? platform) {
    final value = (platform ?? '').toLowerCase();
    return value.contains('android') ||
        value.contains('ios') ||
        value.contains('phone');
  }

  String? _normalizeDeviceSig(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v == 'android' || v == 'localhost' || v == 'unknown' || v == 'phone') {
      return null;
    }
    final sig = v.replaceAll(RegExp(r'[\s:._\-]+'), '');
    return sig.length < 4 ? null : sig;
  }

  /// Signature used to merge multiple device IDs of the same person into one
  /// chat row. Mobile devices are keyed by normalized device name so a
  /// reinstalled phone (which generates a new ID) stays one person.
  String? _personSignatureForEntry(MapEntry<MessageKey, MessageBody> entry) {
    final peerId = entry.key.peerId;
    // LUODA: the same person can be reached through different endpoints
    // (ID / public IP / LAN IP / Bluetooth).  Resolve the pairing by any of
    // them so every conversation of that person collapses into one row.
    final pairing = DirectPairingStore.find(peerId) ??
        DirectPairingStore.findByEndpoint(peerId) ??
        DirectPairingStore.findForConversation(peerId);
    if (pairing != null) {
      if (_isMobilePlatform(pairing.platform)) {
        final sig = _normalizeDeviceSig(pairing.deviceName);
        if (sig != null) return 'm:$sig';
      }
      final account = pairing.accountId.trim();
      if (account.isNotEmpty) return 'a:$account';
    }
    final contact = _findContactByPeerId(peerId);
    if (contact != null && _isMobilePlatform(contact.platform)) {
      final sig = _normalizeDeviceSig(contact.hostname);
      if (sig != null) return 'm:$sig';
    }
    // LUODA: merge the same device reached through different conversation
    // keys. DotChat envelope messages are keyed by the sender's stable
    // device UUID while legacy/session messages are keyed by the dotchat ID;
    // both carry the same sender_id, so use it as the person signature.
    String? senderDeviceId;
    for (final message in entry.value.chatMessages) {
      if (message.user.id != gFFI.chatModel.me.id) {
        final sid = message.customProperties?['ldesk_sender_id'];
        if (sid is String && sid.isNotEmpty) {
          senderDeviceId = sid;
          break;
        }
      }
    }
    if (senderDeviceId != null) return 'd:$senderDeviceId';
    return null;
  }

  List<Object> _mergePersonEntries(
    List<MapEntry<MessageKey, MessageBody>> entries,
  ) {
    if (entries.length < 2) return entries;
    final groups = <String, List<MapEntry<MessageKey, MessageBody>>>{};
    final order = <String>[];
    for (final entry in entries) {
      final signature = _personSignatureForEntry(entry);
      final key = signature ?? entry.key.peerId;
      if (!groups.containsKey(key)) {
        groups[key] = <MapEntry<MessageKey, MessageBody>>[];
        order.add(key);
      }
      groups[key]!.add(entry);
    }
    final result = <Object>[];
    for (final key in order) {
      final list = groups[key]!;
      if (list.length == 1) {
        result.add(list.first);
      } else {
        result.add(_MobileChatGroup(key, list));
      }
    }
    return result;
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
  }

  void _closeSearch() {
    _searchController.clear();
    _query.value = '';
    setState(() => _searchOpen = false);
  }

  bool _peerPhoneEntry(MapEntry<MessageKey, MessageBody> entry) {
    final messages = entry.value.chatMessages;
    for (final message in messages) {
      if (message.user.id != gFFI.chatModel.me.id) {
        return message.customProperties?['ldesk_src_platform'] == 'mobile';
      }
    }
    return false;
  }

  /// True when the peer in this conversation is a mobile device, used to show
  /// the small OS badge at the avatar's top-right corner. Checks pairing,
  /// contact record and message source platform in that order.
  bool _peerIsMobileEntry(MapEntry<MessageKey, MessageBody> entry) {
    return _isMobilePlatform(_peerPlatformEntry(entry));
  }

  /// 解析会话对端的操作系统平台字符串（Windows/Android/iOS/…），
  /// 用于头像左下角的操作系统角标。优先取配对记录，其次联系人，
  /// 最后兜底消息来源平台。
  String _peerPlatformEntry(MapEntry<MessageKey, MessageBody> entry) {
    final pairing = DirectPairingStore.findForConversation(entry.key.peerId);
    if (pairing != null && pairing.platform.trim().isNotEmpty) {
      return pairing.platform;
    }
    final contact = _findContactByPeerId(entry.key.peerId);
    if (contact != null && contact.platform.trim().isNotEmpty) {
      return contact.platform;
    }
    final messages = entry.value.chatMessages;
    for (final message in messages) {
      if (message.user.id != gFFI.chatModel.me.id) {
        final src = message.customProperties?['ldesk_src_platform'];
        if (src == 'mobile') return 'Android';
        if (src == 'desktop') return 'Windows';
      }
    }
    return '';
  }

  DateTime _latestMessageTime(MapEntry<MessageKey, MessageBody> entry) {
    final messages = entry.value.chatMessages;
    if (messages.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return messages
        .map((message) => message.createdAt)
        .reduce((latest, value) => value.isAfter(latest) ? value : latest);
  }

  String _messagePreview(MapEntry<MessageKey, MessageBody> entry) {
    if (entry.value.chatMessages.isEmpty) {
      return translate('Start a conversation');
    }
    final message = entry.value.chatMessages.reduce(
      (latest, value) =>
          value.createdAt.isAfter(latest.createdAt) ? value : latest,
    );
    final properties = message.customProperties;
    if (properties?['ldesk_kind'] == 'file') {
      final fileName = (properties?['ldesk_file_name'] ?? '').toString();
      return fileName.isEmpty ? translate('File Transfer') : fileName;
    }
    final text = message.text.trim();
    final location = DirectChatLocation.tryParse(text);
    if (location != null) {
      final name =
          location.name.isNotEmpty ? location.name : translate('Location');
      return '[${translate('Location')}] $name';
    }
    return text.isEmpty ? translate('Message') : text;
  }

  IconData? _fileIconForEntry(MapEntry<MessageKey, MessageBody> entry) {
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

  String _timeLabel(DateTime value) {
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

  Widget _avatar(MapEntry<MessageKey, MessageBody> entry) {
    if (entry.key.peerId == kFileHelperId) {
      return Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MyTheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.folder_shared_rounded,
            color: Colors.white, size: 26),
      );
    }
    final user = entry.value.chatUser;
    final contact = _findContactByPeerId(entry.key.peerId);
    final name = _resolveConversationName(
      entry.key.peerId,
      contactName: contact?.finalName() ?? '',
      chatName: user.firstName ?? '',
      idFallback: user.id,
    );
    final initial = name.isEmpty ? '?' : name.characters.first;
    final fallback = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: str2color(name),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: MobileText.titleLg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final avatarWidget = buildAvatarWidget(
          avatar: user.profileImage ?? '',
          size: 48,
          borderRadius: 10,
          fallback: fallback,
        ) ??
        fallback;
    final muted = gFFI.chatSettingsModel.isMuted(entry.key.peerId);
    final blocked = gFFI.chatSettingsModel.isBlocked(entry.key.peerId);
    final peerPhone = _peerPhoneEntry(entry);
    if (!muted && !blocked && !peerPhone) {
      // WeChat-style: small OS badge at the avatar's top-right corner
      // (Windows/Android/iOS) — matches the contacts page.
      return avatarWithPlatformBadge(
        child: avatarWidget,
        platform: _peerPlatformEntry(entry),
        badgeSize: 15,
        topRight: true,
      );
    }

    Widget stateBadge(IconData icon, Color color, String tooltip) {
      return Tooltip(
        message: tooltip,
        child: Container(
          width: 21,
          height: 21,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.surface,
              width: 1.5,
            ),
          ),
          child: Icon(icon, size: 13, color: Colors.white),
        ),
      );
    }

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(child: avatarWidget),
          if (peerPhone)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.phone_android_rounded,
                    size: 11, color: Colors.white),
              ),
            ),
          if (muted)
            Positioned(
              left: -5,
              top: -5,
              child: stateBadge(
                Icons.volume_off_rounded,
                const Color(0xFF4B5563),
                translate('Mute'),
              ),
            ),
          if (blocked)
            Positioned(
              right: -5,
              top: -5,
              child: stateBadge(
                Icons.block_rounded,
                const Color(0xFFD92D20),
                translate('Blocked'),
              ),
            ),
        ],
      ),
    );
  }

  /// 点聊页标题条：会议已合并进消息列表（微信风格：会议群聊就是会话），
  /// 不再需要独立“会议”tab 切换。
  Widget _buildDotChatTabs(BuildContext context, bool dark) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dark ? MyTheme.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                dark ? Colors.white.withOpacity(0.08) : const Color(0xFFE5E5E5),
            width: 0.5,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF07C160).withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          translate('DotChat'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF07C160),
          ),
        ),
      ),
    );
  }

  /// 点聊列表里的会议群聊（按搜索词过滤，倒序排列）。
  List<MeetingGroup> _visibleMeetings(String query) {
    final meetings = MeetingGroupStore.all.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (query.isEmpty) return meetings;
    final q = query.trim().toLowerCase();
    return meetings
        .where((m) =>
            m.title.toLowerCase().contains(q) ||
            m.meetingId.toLowerCase().contains(q) ||
            m.hostDisplayName.toLowerCase().contains(q))
        .toList();
  }

  String _formatMeetingTimeMobile(DateTime time) {
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

  Widget _buildMessageGroupHeader(
    BuildContext context,
    _MobilePeopleGroupHeader group,
    bool dark,
  ) {
    final muted = dark ? MyTheme.mutedDark : MyTheme.mutedLight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: <Widget>[
          Text(
            translate(group.label),
            style: TextStyle(
              fontSize: MobileText.caption,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${group.count}',
            style: TextStyle(
              fontSize: MobileText.captionSm,
              color: muted.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMergedEntry(
    BuildContext context,
    _MobileChatGroup group,
    bool dark,
    Color muted,
  ) {
    var primary = group.conversations.first;
    for (final entry in group.conversations) {
      if (_latestMessageTime(entry).isAfter(_latestMessageTime(primary))) {
        primary = entry;
      }
    }
    final entry = primary;
    final user = entry.value.chatUser;
    final contact = _findContactByPeerId(entry.key.peerId);
    final name = _resolveConversationName(
      entry.key.peerId,
      contactName: contact?.finalName() ?? '',
      chatName: user.firstName ?? '',
    );
    final client = gFFI.serverModel.clients.firstWhereOrNull(
      (client) => group.conversations.any((e) =>
          e.key.peerId == client.peerId &&
          client.isChat &&
          !client.disconnected),
    );
    final peerOnline = client != null ||
        group.conversations.any((e) => _onlineByPeer[e.key.peerId] == true);
    final isBlocked = gFFI.chatSettingsModel.isBlocked(entry.key.peerId);
    return _buildConversationRow(
      context,
      entry: entry,
      name: name,
      muted: muted,
      isBlocked: isBlocked,
      peerOnline: peerOnline,
      unreadCount: client?.unreadChatMessageCount,
    );
  }

  /// WeChat-style conversation row shared by merged and single-person entries:
  /// no divider, 48px rounded avatar, 17px name + online dot + gray time on
  /// the first line, 14px gray preview + unread badge on the second line.
  /// 会议群聊行（混排在点聊列表）：点击进入会议群聊聊天窗口。
  Widget _buildMeetingListRow(
    BuildContext context,
    MeetingGroup meeting,
    bool dark,
  ) {
    final theme = Theme.of(context);
    final memberCount = (meeting.members?.length ?? 0) + 1;
    final when = _formatMeetingTimeMobile(meeting.createdAt);
    final hostLabel = '${translate('Host')}: '
        '${meeting.hostDisplayName.isNotEmpty ? meeting.hostDisplayName : meeting.hostPeerId}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onOpenConversation(MessageKey(
          meeting.conversationId,
          ChatModel.clientModeID,
        )),
        highlightColor: dark
            ? const Color(0xFF34373D)
            : const Color(0xFFE5E8E6),
        splashColor: Colors.transparent,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF07C160).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.videocam_rounded,
                        color: Color(0xFF07C160), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                meeting.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: MobileText.bodyLg,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF07C160)
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                translate('Group chat'),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF07C160),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$hostLabel · $memberCount ${translate('Members')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: MobileText.caption,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    when,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 76),
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF3A3D43)
                  : const Color(0x80E5E5E5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationRow(
    BuildContext context, {
    required MapEntry<MessageKey, MessageBody> entry,
    required String name,
    required Color muted,
    required bool isBlocked,
    required bool peerOnline,
    RxInt? unreadCount,
  }) {
    final theme = Theme.of(context);
    final fileIcon = _fileIconForEntry(entry);
    // Material ancestor is required for InkWell's grey tap highlight to
    // actually render — the chat list sits on a bare ColoredBox, so without
    // this wrapper the WeChat-style press feedback never appears.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onOpenConversation(entry.key),
        highlightColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF34373D)
            : const Color(0xFFE5E8E6),
        splashColor: Colors.transparent,
        onLongPress: () => _showPeerPolicySheet(
          context,
          entry.key.peerId,
          DirectChatAccessController.instance..load(),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _avatar(entry),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                name.isEmpty ? entry.key.peerId : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: MobileText.bodyLg,
                                  fontWeight: FontWeight.w600,
                                  color: isBlocked
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (peerOnline) ...<Widget>[
                              const SizedBox(width: 6),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF238A57),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              _timeLabel(_latestMessageTime(entry)),
                              style: TextStyle(
                                fontSize: MobileText.captionSm,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: <Widget>[
                            if (fileIcon != null) ...<Widget>[
                              Icon(fileIcon, size: 15, color: muted),
                              const SizedBox(width: 4),
                            ],
                            if (isBlocked)
                              Text(
                                translate('Blocked'),
                                style: TextStyle(
                                  fontSize: MobileText.caption,
                                  color: theme.colorScheme.error,
                                ),
                              )
                            else
                              Expanded(
                                child: Text(
                                  _messagePreview(entry),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: MobileText.caption,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.5),
                                  ),
                                ),
                              ),
                            if (!isBlocked &&
                                unreadCount != null &&
                                unreadCount.value > 0) ...<Widget>[
                              const SizedBox(width: 8),
                              unreadMessageCountBuilder(unreadCount),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // WeChat-style hairline: starts at the avatar right edge, so no
            // line crosses the avatar (avatar top/bottom stay clean).
            Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 76),
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF3A3D43)
                  : const Color(0x80E5E5E5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPeerPolicySheet(
    BuildContext context,
    String peerId,
    DirectChatAccessController access,
  ) async {
    final isFriend = access.isFriend(peerId);
    final isBlocked = gFFI.chatSettingsModel.isBlocked(peerId);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(
                isFriend
                    ? Icons.person_remove_outlined
                    : Icons.person_add_alt_1_outlined,
              ),
              title: Text(
                translate(isFriend ? 'Move to strangers' : 'Add as friend'),
              ),
              onTap: () => Navigator.pop(
                sheetContext,
                isFriend ? 'stranger' : 'friend',
              ),
            ),
            ListTile(
              leading: Icon(
                isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
              ),
              title: Text(translate(isBlocked ? 'Unblock' : 'Block')),
              onTap: () => Navigator.pop(sheetContext, 'block'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'friend':
        if (isBlocked) await gFFI.chatSettingsModel.toggleBlock(peerId);
        await access.setPeerPolicy(peerId, 'allow');
        break;
      case 'stranger':
        await access.setPeerPolicy(peerId, 'ask');
        break;
      case 'block':
        await gFFI.chatSettingsModel.toggleBlock(peerId);
        await access.setPeerPolicy(peerId, isBlocked ? 'ask' : 'deny');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = DirectChatAccessController.instance..load();
    return ChangeNotifierProvider.value(
      value: gFFI.chatModel,
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          gFFI.chatModel,
          gFFI.chatSettingsModel,
          access,
          _query,
          DirectPairingStore.revision,
        ]),
        builder: (context, _) {
          final model = gFFI.chatModel;
          final dark = Theme.of(context).brightness == Brightness.dark;
          final muted = dark ? MyTheme.mutedDark : MyTheme.mutedLight;
          final query = _query.value.trim().toLowerCase();
          // 手机端"文件传输助手"只在扫码绑定 PC 后才出现（类似微信：绑定后
          // PC/手机两端才启用该内置会话），未绑定时手机端不显示。
          final boundToPc = DirectPairingStore.companionDevice() != null;
          if (boundToPc) model.ensureFileHelperEntry();
          final entries = model.messages.entries.where((entry) {
            if (entry.key.peerId.isEmpty) return false;
            // ???? has its own pinned row; it must not also appear in
            // the Friends/Strangers groups below.
            if (entry.key.peerId == kFileHelperId) return false;
            if (_isSelfEntry(entry.key)) return false;
            if (query.isEmpty) return true;
            final user = entry.value.chatUser;
            return entry.key.peerId.toLowerCase().contains(query) ||
                (user.firstName ?? '').toLowerCase().contains(query) ||
                _messagePreview(entry).toLowerCase().contains(query);
          }).toList(growable: false)
            ..sort(
              (a, b) => _latestMessageTime(b).compareTo(_latestMessageTime(a)),
            );
          final friends = _mergePersonEntries(entries
              .where((entry) => access.isFriend(entry.key.peerId))
              .toList(growable: false));
          final strangers = _mergePersonEntries(entries
              .where((entry) => !access.isFriend(entry.key.peerId))
              .toList(growable: false));
          final fileHelperRow =
              boundToPc ? model.messages[model.fileHelperKey] : null;
          final rows = <Object>[
            if (fileHelperRow != null &&
                (query.isEmpty ||
                    kFileHelperId.contains(query) ||
                    translate('File Transfer Assistant')
                        .toLowerCase()
                        .contains(query)))
              MapEntry<MessageKey, MessageBody>(
                  model.fileHelperKey, fileHelperRow),
            // 会议群聊混排：一次会议就是一个群聊会话，直接出现在点聊列表里
            // （已与独立“会议”tab 合并，微信风格）。
            if (_visibleMeetings(query).isNotEmpty) ...<Object>[
              _MobilePeopleGroupHeader('Meeting', _visibleMeetings(query).length),
              ..._visibleMeetings(query),
            ],
            if (friends.isNotEmpty) ...<Object>[
              _MobilePeopleGroupHeader('Friends', friends.length),
              ...friends,
            ],
            if (strangers.isNotEmpty) ...<Object>[
              _MobilePeopleGroupHeader('Strangers', strangers.length),
              ...strangers,
            ],
          ];
          return ColoredBox(
            color: dark ? MyTheme.canvasDark : MyTheme.canvasLight,
            child: Stack(
              children: <Widget>[
                Column(
                  children: <Widget>[
                    _buildDotChatTabs(context, dark),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                        child: rows.isEmpty
                            ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(28),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF07C160)
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: const Icon(
                                                Icons.forum_outlined,
                                                size: 30,
                                                color: Color(0xFF07C160),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              translate('No conversations yet'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              translate(
                                                  'Chats you start will show up here'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withOpacity(0.5)),
                                            ),
                                            const SizedBox(height: 14),
                                            FilledButton.icon(
                                              onPressed:
                                                  widget.onNewConversation,
                                              icon: const Icon(
                                                Icons.person_add_alt_1_rounded,
                                                size: 18,
                                              ),
                                              label:
                                                  Text(translate('Contacts')),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: rows.length,
                                      itemBuilder: (context, index) {
                                        final row = rows[index];
                                        if (row is _MobilePeopleGroupHeader) {
                                          return _buildMessageGroupHeader(
                                            context,
                                            row,
                                            dark,
                                          );
                                        }
                                        if (row is _MobileChatGroup) {
                                          return _buildMergedEntry(
                                            context,
                                            row,
                                            dark,
                                            muted,
                                          );
                                        }
                                        if (row is MeetingGroup) {
                                          return _buildMeetingListRow(
                                            context,
                                            row,
                                            dark,
                                          );
                                        }
                                        final entry = row as MapEntry<
                                            MessageKey, MessageBody>;
                                        final user = entry.value.chatUser;
                                        final contact = _findContactByPeerId(
                                            entry.key.peerId);
                                        final name = entry.key.peerId ==
                                                kFileHelperId
                                            ? translate(
                                                'File Transfer Assistant')
                                            : _resolveConversationName(
                                                entry.key.peerId,
                                                contactName:
                                                    contact?.finalName() ?? '',
                                                chatName: user.firstName ?? '',
                                              );
                                        final client = gFFI.serverModel.clients
                                            .firstWhereOrNull(
                                          (client) =>
                                              client.peerId ==
                                                  entry.key.peerId &&
                                              client.isChat &&
                                              !client.disconnected,
                                        );
                                        final isBlocked = gFFI.chatSettingsModel
                                            .isBlocked(entry.key.peerId);
                                        final peerOnline = client != null ||
                                            _onlineByPeer[entry.key.peerId] ==
                                                true;
                                        return _buildConversationRow(
                                          context,
                                          entry: entry,
                                          name: name,
                                          muted: muted,
                                          isBlocked: isBlocked,
                                          peerOnline: peerOnline,
                                          unreadCount:
                                              client?.unreadChatMessageCount,
                                        );
                                      },
                                    ),
                      ),
                    ),
                  ],
                ),
                if (_searchOpen)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: dark ? MyTheme.surfaceDark : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withOpacity(0.16),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        height: 38,
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (value) => _query.value = value,
                          decoration: InputDecoration(
                            hintText: translate('Search'),
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 19),
                            suffixIcon: IconButton(
                              tooltip: translate('Close'),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: _closeSearch,
                            ),
                            filled: true,
                            fillColor:
                                dark ? MyTheme.surfaceDark : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          bind.mainGetAppNameSync(),
          style: const TextStyle(
              fontSize: MobileText.titleLg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0),
        ),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "luoda://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTerminal: isTerminal,
          password: password);
    }
  }
}
