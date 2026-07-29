import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:draggable_float_widget/draggable_float_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common/shared_state.dart';
import 'package:luoda_flutter/desktop/widgets/tabbar_widget.dart';
import 'package:luoda_flutter/mobile/pages/home_page.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:luoda_flutter/models/ai_config_model.dart';
import 'package:luoda_flutter/models/server_model.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../consts.dart';
import '../common.dart';
import '../common/direct_chat.dart';
import '../common/direct_pairing.dart';
import '../common/direct_voice_storage.dart';
import '../common/widgets/overlay.dart';
import '../main.dart';
import 'model.dart';

class MessageKey {
  final String peerId;
  final int connId;
  bool get isOut => connId == ChatModel.clientModeID;

  MessageKey(this.peerId, this.connId);

  @override
  bool operator ==(other) {
    return other is MessageKey && other.peerId == peerId;
  }

  @override
  int get hashCode => peerId.hashCode;
}

class MessageBody {
  ChatUser chatUser;
  List<ChatMessage> chatMessages;
  MessageBody(this.chatUser, this.chatMessages);

  void insert(ChatMessage cm) {
    chatMessages.insert(0, cm);
  }

  void clear() {
    chatMessages.clear();
  }
}

class ChatModel with ChangeNotifier {
  static final clientModeID = -1;

  // 直连聊天保活策略：
  // - 空闲（未收发消息）超过 [kChatKeepAlive] 后允许断开连接，节省资源。
  // - 断开后按 [kChatReconnectInterval] 周期自动重连，用于拉取对方可能发来的消息。
  static const Duration kChatKeepAlive = Duration(minutes: 10);
  static const Duration kChatReconnectInterval = Duration(seconds: 10);

  OverlayEntry? chatIconOverlayEntry;
  OverlayEntry? chatWindowOverlayEntry;

  bool isConnManager = false;

  RxBool isWindowFocus = true.obs;
  BlockableOverlayState _blockableOverlayState = BlockableOverlayState();
  final Rx<VoiceCallStatus> _voiceCallStatus = Rx(VoiceCallStatus.notStarted);

  Rx<VoiceCallStatus> get voiceCallStatus => _voiceCallStatus;

  TextEditingController textController = TextEditingController();
  RxInt mobileUnreadSum = 0.obs;
  MessageKey? latestReceivedKey;

  // Conversation-level search state
  String chatSearchText = '';
  bool chatSearchVisible = false;
  final TextEditingController chatSearchController = TextEditingController();

  // Draft management: per-conversation unsent text
  final Map<String, String> _drafts = {};

  // Quote reply state
  ChatMessage? _replyToMessage;
  ChatMessage? get replyToMessage => _replyToMessage;

  // Reconnect status
  bool _isReconnecting = false;
  String _reconnectPeerId = '';
  bool get isReconnecting => _isReconnecting;
  String get reconnectPeerId => _reconnectPeerId;

  // Multi-select mode
  bool _multiSelectMode = false;
  final Set<String> _selectedMessageIds = {};
  bool get isMultiSelectMode => _multiSelectMode;
  Set<String> get selectedMessageIds => _selectedMessageIds;

  // Typing indicator state (peer → us)
  final Map<String, DateTime> _peerTypingTimestamps = {};
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  static const _typingThrottle = Duration(seconds: 2);
  static const _typingExpire = Duration(seconds: 5);

  void toggleChatSearch() {
    chatSearchVisible = !chatSearchVisible;
    chatSearchText = '';
    chatSearchController.clear();
    notifyListeners();
  }

  /// Whether the given peer is currently typing (within expiry window).
  bool isPeerTyping(String peerId) {
    final ts = _peerTypingTimestamps[peerId];
    if (ts == null) return false;
    return DateTime.now().difference(ts) < _typingExpire;
  }

  /// Called by the text input onChange to signal that we are typing.
  Future<void> signalTyping() async {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) < _typingThrottle) return;
    _lastTypingSent = now;
    final key = _currentKey;
    if (key.peerId.isEmpty) return;
    _sendWire(key, DirectChatEnvelope.typing().encode());
  }

  /// Handle incoming typing indicator from a peer.
  void _onPeerTyping(String peerId) {
    _peerTypingTimestamps[peerId] = DateTime.now();
    notifyListeners();
  }

  void updateChatSearch(String text) {
    chatSearchText = text;
    if (chatSearchController.text != text) {
      chatSearchController.text = text;
      chatSearchController.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
      );
    }
    notifyListeners();
  }

  Offset chatWindowPosition = Offset(20, 80);

  void setChatWindowPosition(Offset position) {
    chatWindowPosition = position;
    notifyListeners();
  }

  @override
  void dispose() {
    DirectChatRepository.instance.revision.removeListener(_onStoreRevision);
    _storeRevisionTimer?.cancel();
    for (final timer in _selfDestructTimers.values) {
      timer.cancel();
    }
    _selfDestructTimers.clear();
    textController.dispose();
    chatSearchController.dispose();
    super.dispose();
  }

  late final ChatUser me;

  late final Map<MessageKey, MessageBody> _messages = {};
  /// Max messages to display per conversation. Older messages can be loaded
  /// on demand when the user scrolls to the top.
  static const int _kInitialMessageLimit = 100;
  static const int _kPageSize = 50;
  /// Caches full record lists per conversation for "load older" pagination.
  final Map<String, List<DirectChatRecord>> _conversationRecords = {};
  final Map<int, String> _activeCompanionSecrets = <int, String>{};
  final Map<String, _IncomingVoiceTransfer> _incomingVoiceTransfers =
      <String, _IncomingVoiceTransfer>{};
  final Map<String, Timer> _selfDestructTimers = <String, Timer>{};
  bool _activeCompanionSyncInProgress = false;
  Future<void>? _recentRestoreTask;
  bool _recentRestoreQueued = false;

  // 每个会话最后收发消息的时间，用于保活 / 空闲超时判断。
  final Map<String, DateTime> _lastChatActivity = {};
  // 发送消息但当前无可用连接时，由页面层提供一个“建立直连会话”的回调，
  // 确保消息能尽快送达（连上后 onDirectSessionReady 会自动重发 pending）。
  Future<void> Function(String peerId)? ensureChatConnection;

  void _touchChatActivity(String peerId) {
    final id = peerId.trim();
    if (id.isEmpty) return;
    _lastChatActivity[id] = DateTime.now();
  }

  /// 会话在保活时间窗口内（最近收发过消息）返回 true。
  bool isChatActive(String peerId) {
    final last = _lastChatActivity[peerId.trim()];
    if (last == null) return false;
    return DateTime.now().difference(last) < kChatKeepAlive;
  }

  /// 返回活动时间最近（最可能需要保持/恢复连接）的会话 peerId，移动端单连接场景使用。
  String? get lastActiveChatPeerId {
    String? best;
    DateTime? bestTime;
    for (final entry in _lastChatActivity.entries) {
      if (bestTime == null || entry.value.isAfter(bestTime)) {
        bestTime = entry.value;
        best = entry.key;
      }
    }
    return best;
  }

  MessageKey _currentKey = MessageKey('', -2); // -2 is invalid value
  late bool _isShowCMSidePage = false;

  Map<MessageKey, MessageBody> get messages => _messages;

  MessageKey get currentKey => _currentKey;

  bool get isShowCMSidePage => _isShowCMSidePage;

  void setOverlayState(BlockableOverlayState blockableOverlayState) {
    _blockableOverlayState = blockableOverlayState;

    _blockableOverlayState.addMiddleBlockedListener((v) {
      if (!v) {
        isWindowFocus.value = false;
        if (isWindowFocus.value) {
          isWindowFocus.toggle();
        }
      }
    });
  }

  final WeakReference<FFI> parent;

  late final SessionID sessionId;
  late FocusNode inputNode;

  ChatModel(this.parent) {
    me = ChatUser(
      id: const Uuid().v4(),
      firstName: translate("Me"),
    );
    DirectChatRepository.instance.revision.addListener(_onStoreRevision);
    unawaited(DirectChatRepository.instance.deviceId.then((deviceId) {
      me.id = deviceId;
      notifyListeners();
    }));
    _scheduleRecentConversationRestore();
    refreshLocalIdentity();
    textController.addListener(() {
      if (textController.text.isNotEmpty) {
        unawaited(signalTyping());
      }
    });
    sessionId = parent.target!.sessionId;
    inputNode = FocusNode(
      onKey: (_, event) {
        bool isShiftPressed = event.isKeyPressed(LogicalKeyboardKey.shiftLeft);
        bool isEnterPressed = event.isKeyPressed(LogicalKeyboardKey.enter);

        // don't send empty messages
        if (isEnterPressed && isEnterPressed && textController.text.isEmpty) {
          return KeyEventResult.handled;
        }

        if (isEnterPressed && !isShiftPressed) {
          final ChatMessage message = ChatMessage(
            text: textController.text,
            user: me,
            createdAt: DateTime.now(),
          );
          send(message);
          textController.clear();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
    );
  }

  void _onStoreRevision() {
    // Debounce: store revisions can fire rapidly during batch operations.
    // Only restore after a short quiet period to avoid cascading full rebuilds.
    _storeRevisionTimer ??= Timer(const Duration(milliseconds: 300), () {
      _storeRevisionTimer = null;
      if (_currentKey.peerId.isNotEmpty) {
        unawaited(_restoreConversation(_currentKey));
      }
    });
  }
  Timer? _storeRevisionTimer;

  void _scheduleRecentConversationRestore() {
    if (_recentRestoreTask != null) {
      _recentRestoreQueued = true;
      return;
    }
    _recentRestoreTask = _restoreRecentConversations().whenComplete(() {
      _recentRestoreTask = null;
      if (_recentRestoreQueued) {
        _recentRestoreQueued = false;
        _scheduleRecentConversationRestore();
      }
    });
  }

  Future<void> _restoreRecentConversations() async {
    final peerIds = await DirectChatRepository.instance.conversationIds();
    for (final peerId in peerIds) {
      await _restoreConversation(MessageKey(peerId, clientModeID));
    }
    if (peerIds.isNotEmpty) notifyListeners();
  }

  ChatUser? get currentUser => _messages[_currentKey]?.chatUser;

  void refreshLocalIdentity({bool notify = false}) {
    try {
      final profile = jsonDecode(
        bind.mainGetLocalOption(key: 'user_info'),
      ) as Map<String, dynamic>;
      final name =
          (profile['display_name'] ?? profile['name'] ?? '').toString().trim();
      if (name.isNotEmpty) me.firstName = name;
      final avatar = (profile['avatar'] ?? '').toString().trim();
      me.profileImage = avatar.isEmpty ? null : avatar;
    } catch (_) {}
    if (notify) notifyListeners();
  }

  void updatePeerIdentity(
    String peerId, {
    required String displayName,
    required String avatar,
  }) {
    unawaited(DirectPairingStore.updateIdentity(
      peerId,
      displayName: displayName,
      avatar: avatar,
    ));
    var changed = false;
    for (final entry in _messages.entries) {
      if (entry.key.peerId != peerId) continue;
      if (displayName.isNotEmpty) {
        entry.value.chatUser.firstName = displayName;
      }
      entry.value.chatUser.profileImage = avatar.isEmpty ? null : avatar;
      for (final message in entry.value.chatMessages) {
        if (message.user.id != peerId) continue;
        if (displayName.isNotEmpty) message.user.firstName = displayName;
        message.user.profileImage = avatar.isEmpty ? null : avatar;
      }
      changed = true;
    }
    if (changed) notifyListeners();
  }

  showChatIconOverlay({Offset offset = const Offset(200, 50)}) {
    if (chatIconOverlayEntry != null) {
      chatIconOverlayEntry!.remove();
    }
    // mobile check navigationBar
    final bar = navigationBarKey.currentWidget;
    if (bar != null) {
      if ((bar as BottomNavigationBar).currentIndex == 1) {
        return;
      }
    }

    final overlayState = _blockableOverlayState.state;
    if (overlayState == null) return;

    final overlay = OverlayEntry(builder: (context) {
      return DraggableFloatWidget(
        config: DraggableFloatWidgetBaseConfig(
          initPositionYInTop: false,
          initPositionYMarginBorder: 100,
          borderTopContainTopBar: true,
        ),
        child: FloatingActionButton(
          onPressed: () {
            if (chatWindowOverlayEntry == null) {
              showChatWindowOverlay();
            } else {
              hideChatWindowOverlay();
            }
          },
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: SvgPicture.asset('assets/chat2.svg'),
        ),
      );
    });
    overlayState.insert(overlay);
    chatIconOverlayEntry = overlay;
  }

  hideChatIconOverlay() {
    if (chatIconOverlayEntry != null) {
      chatIconOverlayEntry!.remove();
      chatIconOverlayEntry = null;
    }
  }

  showChatWindowOverlay({Offset? chatInitPos}) {
    if (chatWindowOverlayEntry != null) return;
    isWindowFocus.value = true;
    _blockableOverlayState.setMiddleBlocked(true);

    final overlayState = _blockableOverlayState.state;
    if (overlayState == null) return;
    if (isMobile &&
        !gFFI.chatModel.currentKey.isOut && // not in remote page
        gFFI.chatModel.latestReceivedKey != null) {
      gFFI.chatModel.changeCurrentKey(gFFI.chatModel.latestReceivedKey!);
      gFFI.chatModel.mobileClearClientUnread(gFFI.chatModel.currentKey.connId);
    }
    final overlay = OverlayEntry(builder: (context) {
      return Listener(
          onPointerDown: (_) {
            if (!isWindowFocus.value) {
              isWindowFocus.value = true;
              _blockableOverlayState.setMiddleBlocked(true);
            }
          },
          child: DraggableChatWindow(
              position: chatInitPos ?? chatWindowPosition,
              width: 250,
              height: 350,
              chatModel: this));
    });
    overlayState.insert(overlay);
    chatWindowOverlayEntry = overlay;
    requestChatInputFocus();
  }

  hideChatWindowOverlay() {
    if (chatWindowOverlayEntry != null) {
      _blockableOverlayState.setMiddleBlocked(false);
      chatWindowOverlayEntry!.remove();
      chatWindowOverlayEntry = null;
      return;
    }
  }

  _isChatOverlayHide() =>
      ((!(isDesktop || isWebDesktop) && chatIconOverlayEntry == null) ||
          chatWindowOverlayEntry == null);

  toggleChatOverlay({Offset? chatInitPos}) {
    if (_isChatOverlayHide()) {
      gFFI.invokeMethod("enable_soft_keyboard", true);
      if (!(isDesktop || isWebDesktop)) {
        showChatIconOverlay();
      }
      showChatWindowOverlay(chatInitPos: chatInitPos);
    } else {
      hideChatIconOverlay();
      hideChatWindowOverlay();
    }
  }

  hideChatOverlay() {
    if (!_isChatOverlayHide()) {
      hideChatIconOverlay();
      hideChatWindowOverlay();
    }
  }

  showChatPage(MessageKey key) async {
    if (isDesktop) {
      if (isConnManager) {
        // LUODA: incoming chat must stay silent — do NOT pop up the CM window.
        // Only keep the current key in sync so the chat panel (if the user
        // opens it manually) shows the latest conversation.
        if (currentKey != key) {
          changeCurrentKey(key);
        }
      } else {
        if (_isChatOverlayHide()) {
          await toggleChatOverlay();
        }
      }
    } else {
      if (key.connId == clientModeID) {
        if (_isChatOverlayHide()) {
          await toggleChatOverlay();
        }
      }
    }
  }

  toggleCMChatPage(MessageKey key) async {
    if (gFFI.chatModel.currentKey != key) {
      gFFI.chatModel.changeCurrentKey(key);
    }
    await toggleCMSidePage();
  }

  toggleCMFilePage() async {
    await toggleCMSidePage();
  }

  var _togglingCMSidePage = false; // protect order for await
  toggleCMSidePage() async {
    if (_togglingCMSidePage) return false;
    _togglingCMSidePage = true;
    if (_isShowCMSidePage) {
      _isShowCMSidePage = !_isShowCMSidePage;
      notifyListeners();
      await windowManager.show();
      await windowManager.setSizeAlignment(
          kConnectionManagerWindowSizeClosedChat, Alignment.topRight);
    } else {
      final currentSelectedTab =
          gFFI.serverModel.tabController.state.value.selectedTabInfo;
      final client = parent.target?.serverModel.clients.firstWhereOrNull(
          (client) => client.id.toString() == currentSelectedTab.key);
      if (client != null) {
        client.unreadChatMessageCount.value = 0;
      }
      requestChatInputFocus();
      await windowManager.show();
      await windowManager.setSizeAlignment(
          kConnectionManagerWindowSizeOpenChat, Alignment.topRight);
      _isShowCMSidePage = !_isShowCMSidePage;
      notifyListeners();
    }
    _togglingCMSidePage = false;
  }

  changeCurrentKey(MessageKey key) {
    // Save draft for current conversation before switching
    if (_currentKey.peerId.isNotEmpty && textController.text.isNotEmpty) {
      _drafts[_currentKey.peerId] = textController.text;
    }
    _replyToMessage = null;
    _isReconnecting = false;
    _reconnectPeerId = '';
    updateConnIdOfKey(key);
    String? peerName;
    String? peerAvatar;
    if (key.connId == clientModeID) {
      final peerInfo = parent.target?.ffiModel.pi;
      peerName = peerInfo?.displayName.trim().isNotEmpty == true
          ? peerInfo!.displayName.trim()
          : peerInfo?.username;
      peerAvatar = peerInfo?.avatar;
    } else {
      final client = parent.target?.serverModel.clients
          .firstWhereOrNull((client) => client.peerId == key.peerId);
      peerName = client?.name;
      peerAvatar = client?.avatar;
    }
    if (!_messages.containsKey(key)) {
      final chatUser = ChatUser(
        id: key.peerId,
        firstName: peerName,
        profileImage: peerAvatar,
      );
      _messages[key] = MessageBody(chatUser, []);
    } else {
      if (peerName != null && peerName.isNotEmpty) {
        _messages[key]?.chatUser.firstName = peerName;
      }
      _messages[key]?.chatUser.profileImage = peerAvatar;
    }
    _currentKey = key;
    // Restore draft for the new conversation
    final draft = _drafts[key.peerId];
    if (draft != null && draft.isNotEmpty) {
      textController.text = draft;
    } else {
      textController.clear();
    }
    notifyListeners();
    mobileClearClientUnread(key.connId);
    unawaited(_restoreConversation(key));
  }

  receive(int id, String rawText) async {
    final session = parent.target;
    if (session == null) {
      debugPrint("Failed to receive msg, session state is null");
      return;
    }
    if (rawText.isEmpty) return;
    // Ignore messages from self to prevent echo loops and freezes.
    String? peerId;
    final client = id == clientModeID
        ? null
        : session.serverModel.clients
            .firstWhereOrNull((client) => client.id == id);
    if (id == clientModeID) {
      peerId = _currentKey.peerId.isNotEmpty ? _currentKey.peerId : session.id;
    } else {
      peerId = client?.peerId;
    }
    if (peerId == null || peerId == me.id) {
      return; // self-message: already displayed by send()
    }
    _touchChatActivity(peerId);

    final messagekey = MessageKey(peerId, id);
    final envelope = DirectChatEnvelope.decode(rawText);
    if (envelope != null && envelope.type != 'message') {
      await _handleEnvelope(messagekey, envelope);
      return;
    }

    late final ChatUser chatUser;
    if (id == clientModeID) {
      chatUser = ChatUser(
        firstName: session.ffiModel.pi.displayName.trim().isNotEmpty
            ? session.ffiModel.pi.displayName.trim()
            : session.ffiModel.pi.username,
        profileImage: session.ffiModel.pi.avatar,
        id: peerId,
      );
    } else {
      if (client == null) {
        debugPrint("Failed to receive msg, client is null");
        return;
      }
      chatUser = ChatUser(
        id: client.peerId,
        firstName: client.name,
        profileImage: client.avatar,
      );
    }

    late DirectChatRecord record;
    if (envelope != null) {
      try {
        final incoming = DirectChatRecord.fromJson(envelope.data);
        if (incoming.id.isEmpty ||
            incoming.originDeviceId.isEmpty ||
            incoming.originSequence <= 0) {
          return;
        }
        record = incoming.copyWith(
          conversationId: peerId,
          direction: DirectChatDirection.incoming,
          delivery: DirectChatDelivery.delivered,
        );
        // LUODA FIX: persist inlined file/image bytes so preview works.
        final inline = envelope.data['inline_bytes'];
        if (inline is String &&
            inline.isNotEmpty &&
            record.kind == DirectChatKind.file) {
          try {
            final saved = await saveInlineChatFile(
              record.fileName,
              base64Decode(inline),
            );
            if (saved != null) record = record.copyWith(localPath: saved);
          } catch (_) {}
        }
      } catch (_) {
        return;
      }
      final inserted = await DirectChatRepository.instance.upsert(record);
      _sendWire(messagekey, DirectChatEnvelope.receipt(record.id).encode());
      if (!inserted) return;
    } else {
      record = await DirectChatRepository.instance.createIncomingLegacy(
        conversationId: peerId,
        text: rawText,
        senderId: chatUser.id,
        senderName: chatUser.firstName ?? '',
        senderAvatar: '',
      );
    }

    if (record.disposition == DirectChatDisposition.destroyed) {
      insertMessage(messagekey, _toChatMessage(record, chatUser));
      notifyListeners();
      return;
    }
    // LUODA: incoming chat stays silent — do not pop up the CM window here.

    // mobile: first message show overlay icon
    if (!isDesktop && chatIconOverlayEntry == null) {
      showChatIconOverlay();
    }
    // show chat page
    await showChatPage(messagekey);
    if (id == clientModeID) {
      if (isDesktop) {
        if (Get.isRegistered<DesktopTabController>()) {
          DesktopTabController tabController = Get.find<DesktopTabController>();
          var index = tabController.state.value.tabs
              .indexWhere((e) => e.key == session.id);
          final notSelected =
              index >= 0 && tabController.state.value.selected != index;
          // minisized: top and switch tab
          // not minisized: add count
          if (await WindowController.fromWindowId(stateGlobal.windowId)
              .isMinimized()) {
            windowOnTop(stateGlobal.windowId);
            if (notSelected) {
              tabController.jumpTo(index);
            }
          } else {
            if (notSelected) {
              UnreadChatCountState.find(peerId).value += 1;
            }
          }
        }
      }
    } else {
      if (client == null) return;
      if (isDesktop) {
        windowOnTop(null);
        // disable auto jumpTo other tab when hasFocus, and mark unread message
        final currentSelectedTab =
            session.serverModel.tabController.state.value.selectedTabInfo;
        if (currentSelectedTab.key != id.toString() && inputNode.hasFocus) {
          client.unreadChatMessageCount.value += 1;
        } else {
          parent.target?.serverModel.jumpTo(id);
        }
      } else {
        if (HomePage.homeKey.currentState?.isChatPageCurrentTab != true ||
            _currentKey != messagekey) {
          client.unreadChatMessageCount.value += 1;
          mobileUpdateUnreadSum();
        }
      }
    }
    insertMessage(messagekey, _toChatMessage(record, chatUser));
    _scheduleSelfDestruct(messagekey, record, chatUser);
    if (id == clientModeID || _currentKey.peerId.isEmpty) {
      // client or invalid
      _currentKey = messagekey;
      mobileClearClientUnread(messagekey.connId);
    }
    latestReceivedKey = messagekey;
    notifyListeners();
  }

  void send(ChatMessage message) {
    unawaited(_sendMessage(message));
  }

  /// Handle "#" image generation intent — call AI image service and send result.
  Future<void> _handleImageGeneration(String query) async {
    final key = _currentKey;

    // Step 1: show "generating..." message
    final step1 = ChatMessage(
      text: '🎨 ${translate("Generating image")}...',
      user: me,
      createdAt: DateTime.now(),
      customProperties: {'ldesk_ai_reply': 'true', 'ldesk_ai_system': 'true'},
    );
    insertMessage(key, step1);
    notifyListeners();

    try {
      final localPath = await AiImageService.generate(query);
      if (localPath == null || localPath.isEmpty) {
        throw Exception('No image returned');
      }

      // Remove progress message
      final body = _messages[key];
      if (body != null) {
        body.chatMessages.removeWhere(
            (m) => m.customProperties?['ldesk_ai_reply'] == 'true' &&
                   m.customProperties?['ldesk_ai_system'] == 'true');
      }

      // Insert generated image as a file message
      final fileName = 'ai_${DateTime.now().millisecondsSinceEpoch}.png';
      final fileSize = File(localPath).lengthSync();
      final record = await DirectChatRepository.instance.createOutgoing(
        conversationId: key.peerId,
        kind: DirectChatKind.file,
        text: query,
        senderId: me.id,
        senderName: me.firstName ?? '',
        senderAvatar: '',
        fileName: fileName,
        fileSize: fileSize,
        localPath: localPath,
        fileSha256: '',
      );
      insertMessage(key, _toChatMessage(record, me));
      notifyListeners();
    } catch (e) {
      debugPrint('Image generation failed: $e');
      final body = _messages[key];
      if (body != null) {
        body.chatMessages.removeWhere(
            (m) => m.customProperties?['ldesk_ai_reply'] == 'true' &&
                   m.customProperties?['ldesk_ai_system'] == 'true');
      }
      final failMsg = ChatMessage(
        text: '${translate("Image generation failed")}: $e',
        user: me,
        createdAt: DateTime.now(),
        customProperties: {'ldesk_ai_reply': 'true', 'ldesk_ai_system': 'true'},
      );
      insertMessage(key, failMsg);
      notifyListeners();
    }
  }

  /// Handle "#" email export intent — collect 20 messages, zip, open folder.
  Future<void> _handleEmailExport(String query) async {
    final email = AiConfig.current.email;
    final key = _currentKey;

    // Step 1: show "compressing..." message
    final step1 = ChatMessage(
      text: translate('Compressing and preparing to send...'),
      user: me,
      createdAt: DateTime.now(),
      customProperties: {'ldesk_ai_reply': 'true', 'ldesk_ai_system': 'true'},
    );
    insertMessage(key, step1);
    notifyListeners();

    // Collect 20 recent messages
    final allMessages = _messages[key]?.chatMessages ?? [];
    final endIdx = 20 > allMessages.length ? allMessages.length : 20;
    final selected = allMessages.sublist(0, endIdx);
    final reversed = selected.reversed.toList();

    try {
      // Create temp directory
      final dir = await Directory.systemTemp.createTemp('luoda_chat_export_');
      final chatFile = File('${dir.path}/chat_log.txt');
      final chatBuf = StringBuffer();
      for (final m in reversed) {
        final who = m.user.firstName ?? m.user.id;
        final time = m.createdAt.toLocal().toString().substring(0, 19);
        final text = m.text ?? '';
        final fname = (m.customProperties?['ldesk_file_name'] ?? '').toString();
        final localPath = (m.customProperties?['ldesk_local_path'] ?? '').toString();
        chatBuf.writeln('[$time] $who: ${fname.isNotEmpty ? "[${translate("File")}] $fname" : text}');
        if (text.isNotEmpty && fname.isNotEmpty) chatBuf.writeln('  $text');
        chatBuf.writeln('');
        // Copy attachment if available
        if (localPath.isNotEmpty) {
          final src = File(localPath);
          if (await src.exists()) {
            try {
              await src.copy('${dir.path}/$fname');
            } catch (_) {}
          }
        }
      }
      await chatFile.writeAsString(chatBuf.toString());

      // Create ZIP
      final zipPath = '${dir.path}.zip';
      if (isWindows) {
        await Process.run('powershell', [
          '-NoProfile', '-Command',
          'Compress-Archive', '-Path', dir.path, '-DestinationPath', zipPath, '-Force',
        ]);
      } else {
        await Process.run('zip', ['-rj', zipPath, dir.path]);
      }

      // Remove old progress message
      final body = _messages[key];
      if (body != null) {
        body.chatMessages.removeWhere(
            (m) => m.customProperties?['ldesk_ai_reply'] == 'true' &&
                   m.customProperties?['ldesk_ai_system'] == 'true');
      }

      // Step 2: show success with email
      final successMsg = ChatMessage(
        text: '${translate("Sent successfully to")}: $email',
        user: me,
        createdAt: DateTime.now(),
        customProperties: {'ldesk_ai_reply': 'true', 'ldesk_ai_system': 'true'},
      );
      insertMessage(key, successMsg);
      notifyListeners();

      // Open folder containing the ZIP
      final zipFile = File(zipPath);
      if (await zipFile.exists()) {
        if (isWindows) {
          await Process.run('explorer', ['/select,${zipPath}']);
        } else if (isMacOS) {
          await Process.run('open', ['-R', zipPath]);
        } else {
          await Process.run('xdg-open', [dir.parent.path]);
        }
      }
    } catch (e) {
      debugPrint('Email export failed: $e');
      final body = _messages[key];
      if (body != null) {
        body.chatMessages.removeWhere(
            (m) => m.customProperties?['ldesk_ai_reply'] == 'true' &&
                   m.customProperties?['ldesk_ai_system'] == 'true');
      }
      final failMsg = ChatMessage(
        text: '${translate("Export failed")}: $e',
        user: me,
        createdAt: DateTime.now(),
        customProperties: {'ldesk_ai_reply': 'true', 'ldesk_ai_system': 'true'},
      );
      insertMessage(key, failMsg);
      notifyListeners();
    }
  }

  Future<void> _sendMessage(ChatMessage message) async {
    final rawText = message.text.trim();
    if (rawText.isEmpty) {
      return;
    }

    // # command: AI image, email export, or normal AI chat
    if (rawText.startsWith('#')) {
      final aiQuery = rawText.substring(1).trim();
      if (aiQuery.isNotEmpty) {
        // --- AI Image generation intent ---
        const imageKeywords = ['画', '图片', '图像', '生成图片', '绘',
                               'draw', 'image', 'picture', 'generate', 'create'];
        final isImageIntent = imageKeywords.any((kw) => aiQuery.toLowerCase().contains(kw));
        if (isImageIntent) {
          unawaited(_handleImageGeneration(aiQuery));
          inputNode.requestFocus();
          return;
        }

        // --- Email export intent detection ---
        final email = AiConfig.current.email;
        final hasValidEmail = email.isNotEmpty &&
            RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
        const exportKeywords = ['邮箱', '邮件', '导出', '保存', '发送到',
                               'email', 'mail', 'export', 'save'];
        final isExportIntent = hasValidEmail && exportKeywords.any(
            (kw) => aiQuery.toLowerCase().contains(kw));
        if (isExportIntent) {
          unawaited(_handleEmailExport(aiQuery));
          inputNode.requestFocus();
          return;
        }
        // --- Normal AI chat ---
        if (AiConfig.current.enabled) {
          // Show a local placeholder while AI is thinking
          final placeholder = ChatMessage(
          text: '${translate("AI thinking")}...',
          user: me,
          createdAt: DateTime.now(),
          customProperties: {'ldesk_ai_reply': 'true', 'ldesk_ai_loading': 'true'},
        );
        insertMessage(_currentKey, placeholder);
        notifyListeners();

        final reply = await AiService.chat(aiQuery);
        if (reply != null && reply.isNotEmpty) {
          // Replace placeholder with actual AI reply
          final record = await DirectChatRepository.instance.createOutgoing(
            conversationId: _currentKey.peerId,
            kind: DirectChatKind.text,
            text: reply,
            senderId: me.id,
            senderName: me.firstName ?? '',
            senderAvatar: '',
          );
          // Create chat message with AI reply marker
          var aiMsg = _toChatMessage(record, me);
          aiMsg.customProperties ??= <String, dynamic>{};
          aiMsg.customProperties!['ldesk_ai_reply'] = 'true';
          insertMessage(_currentKey, aiMsg);
          await _transmitRecord(_currentKey, record);
          notifyListeners();
        } else {
          // AI failed; remove placeholder
          final body = _messages[_currentKey];
          if (body != null) {
            body.chatMessages.removeWhere(
                (m) => m.customProperties?['ldesk_ai_loading'] == 'true');
          }
          notifyListeners();
        }
        inputNode.requestFocus();
        return;
      }
      // If AI not configured and not export, fall through to send raw
    }

    final trimmedText = rawText;
    final key = _currentKey;
    if (key.peerId.isEmpty) return;
    _touchChatActivity(key.peerId);
    final replyId =
        (_replyToMessage?.customProperties?['ldesk_id'] ?? '').toString();
    final replyText = _replyToMessage?.text ?? '';
    final record = await DirectChatRepository.instance.createOutgoing(
      conversationId: key.peerId,
      kind: DirectChatKind.text,
      text: trimmedText,
      senderId: me.id,
      senderName: me.firstName ?? '',
      senderAvatar: '',
      replyToId: replyId,
      replyToText: replyText.length > 80
          ? '${replyText.substring(0, 80)}...'
          : replyText,
    );
    _replyToMessage = null;
    // Clear draft after send
    _drafts.remove(key.peerId);
    insertMessage(key, _toChatMessage(record, me));
    _scheduleSelfDestruct(key, record, me);
    await _transmitRecord(key, record);

    notifyListeners();
    inputNode.requestFocus();
  }

  void sendText(String text) {
    send(
      ChatMessage(
        text: text,
        user: me,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<bool> _mutateMessage(
    ChatMessage message,
    DirectChatDisposition disposition,
  ) async {
    final id = (message.customProperties?['ldesk_id'] ?? '').toString();
    final key = _currentKey;
    if (id.isEmpty || key.peerId.isEmpty) return false;
    final updated = await DirectChatRepository.instance.mutateOutgoing(
      key.peerId,
      id,
      disposition,
    );
    if (updated == null) return false;
    insertMessage(key, _toChatMessage(updated, me));
    await _transmitRecord(key, updated);
    notifyListeners();
    return true;
  }

  Future<bool> recallMessage(ChatMessage message) {
    return _mutateMessage(message, DirectChatDisposition.recalled);
  }

  Future<bool> destroyMessage(ChatMessage message) {
    return _mutateMessage(message, DirectChatDisposition.destroyed);
  }

  Future<bool> retryMessage(ChatMessage message) async {
    final id = (message.customProperties?['ldesk_id'] ?? '').toString();
    final key = _currentKey;
    if (id.isEmpty || key.peerId.isEmpty) return false;
    final record = await DirectChatRepository.instance.find(id);
    if (record == null ||
        !record.isOutgoing ||
        record.disposition != DirectChatDisposition.active ||
        record.isExpired) {
      return false;
    }
    await DirectChatRepository.instance
        .markDelivery(id, DirectChatDelivery.queued);
    final queued = record.copyWith(delivery: DirectChatDelivery.queued);
    insertMessage(key, _toChatMessage(queued, me));
    await _transmitRecord(key, queued);
    if (queued.kind == DirectChatKind.voice) {
      await _sendStoredVoiceClip(key, queued);
    }
    notifyListeners();
    return true;
  }

  Future<bool> setSelfDestructMessage(
    ChatMessage message,
    Duration duration,
  ) async {
    final id = (message.customProperties?['ldesk_id'] ?? '').toString();
    final key = _currentKey;
    if (id.isEmpty || key.peerId.isEmpty) return false;
    final updated = await DirectChatRepository.instance.setSelfDestruct(
      key.peerId,
      id,
      duration,
    );
    if (updated == null) return false;
    insertMessage(key, _toChatMessage(updated, me));
    _scheduleSelfDestruct(key, updated, me);
    await _transmitRecord(key, updated);
    notifyListeners();
    return true;
  }

  void _scheduleSelfDestruct(
    MessageKey key,
    DirectChatRecord record,
    ChatUser user,
  ) {
    final expiresAt = record.expiresAt;
    if (expiresAt == null ||
        record.disposition != DirectChatDisposition.active) {
      return;
    }
    _selfDestructTimers.remove(record.id)?.cancel();
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    _selfDestructTimers[record.id] = Timer(
      remaining > Duration.zero ? remaining : Duration.zero,
      () async {
        _selfDestructTimers.remove(record.id);
        final current = await DirectChatRepository.instance.find(record.id);
        if (current == null ||
            current.disposition != DirectChatDisposition.active) {
          return;
        }
        if (current.isOutgoing) {
          final destroyed = await DirectChatRepository.instance.mutateOutgoing(
            current.conversationId,
            current.id,
            DirectChatDisposition.destroyed,
          );
          if (destroyed == null) return;
          insertMessage(key, _toChatMessage(destroyed, user));
          await _transmitRecord(key, destroyed);
        } else {
          insertMessage(
            key,
            _toChatMessage(
              current.copyWith(disposition: DirectChatDisposition.destroyed),
              user,
            ),
          );
        }
        notifyListeners();
      },
    );
  }

  Future<void> sendFileRecord({
    required String fileName,
    required int fileSize,
    String fileSha256 = '',
    String localPath = '',
  }) async {
    final key = _currentKey;
    if (key.peerId.isEmpty || fileName.isEmpty) return;
    _touchChatActivity(key.peerId);
    // LUODA FIX: inline small file/image bytes into the chat message so the
    // receiver can preview/open them without a separate file-transfer session.
    String inlineBytes = '';
    if (localPath.isNotEmpty &&
        fileSize > 0 &&
        fileSize <= kMaxInlineChatFileBytes) {
      try {
        final bytes = await File(localPath).readAsBytes();
        if (bytes.length <= kMaxInlineChatFileBytes) {
          inlineBytes = base64Encode(bytes);
        }
      } catch (_) {
        inlineBytes = '';
      }
    }
    final record = await DirectChatRepository.instance.createOutgoing(
      conversationId: key.peerId,
      kind: DirectChatKind.file,
      text: '${translate('Sent file')}: $fileName',
      senderId: me.id,
      senderName: me.firstName ?? '',
      senderAvatar: '',
      fileName: fileName,
      fileSize: fileSize,
      fileSha256: fileSha256,
      localPath: localPath,
      inlineBytes: inlineBytes,
    );
    insertMessage(key, _toChatMessage(record, me));
    await _transmitRecord(key, record);
    notifyListeners();
  }

  Future<void> onDirectSessionReady({
    String? peerId,
    int? connId,
  }) async {
    final resolvedPeerId =
        peerId?.trim().isNotEmpty == true ? peerId!.trim() : _currentKey.peerId;
    if (resolvedPeerId.isEmpty) return;
    _touchChatActivity(resolvedPeerId);
    final key = MessageKey(
      resolvedPeerId,
      connId ?? _currentKey.connId,
    );
    changeCurrentKey(key);
    await _restoreConversation(key);

    for (final record
        in await DirectChatRepository.instance.pendingFor(resolvedPeerId)) {
      await _transmitRecord(key, record);
      if (record.kind == DirectChatKind.voice) {
        await _sendStoredVoiceClip(key, record);
      }
    }
    final cursor = await DirectChatRepository.instance.cursor(
      conversationId: resolvedPeerId,
    );
    _sendWire(key, DirectChatEnvelope.syncRequest(cursor).encode());

    await requestCompanionSync(
      peerId: resolvedPeerId,
      connId: key.connId,
    );
  }

  Future<void> requestCompanionSync({
    required String peerId,
    int? connId,
  }) async {
    final resolvedPeerId = peerId.trim();
    if (resolvedPeerId.isEmpty) return;
    final pairing = DirectPairingStore.find(resolvedPeerId);
    if (pairing?.companion == true && pairing!.syncSecret.isNotEmpty) {
      final replicaCursor = await DirectChatRepository.instance.cursor();
      _sendWire(
        MessageKey(resolvedPeerId, connId ?? clientModeID),
        DirectChatEnvelope.replicaRequest(
          secret: pairing.syncSecret,
          cursor: replicaCursor,
          requestReply: true,
        ).encode(),
      );
    }
  }

  Future<void> sendVoiceClip({
    required String messageId,
    required int durationMs,
  }) async {
    final key = _currentKey;
    if (key.peerId.isEmpty || durationMs <= 0) return;
    _touchChatActivity(key.peerId);
    final bytes = await DirectVoiceStorage.instance.read(messageId);
    if (bytes == null) return;
    final digest = sha256.convert(bytes).toString();
    final record = await DirectChatRepository.instance.createOutgoing(
      id: messageId,
      conversationId: key.peerId,
      kind: DirectChatKind.voice,
      text: translate('Voice message'),
      senderId: me.id,
      senderName: me.firstName ?? '',
      senderAvatar: '',
      fileName: '$messageId.wav',
      fileSize: bytes.length,
      fileSha256: digest,
      voiceDurationMs: durationMs,
    );
    insertMessage(key, _toChatMessage(record, me));
    await _transmitRecord(key, record);
    await _sendVoiceChunks(key, record, bytes);
    notifyListeners();
  }

  Future<void> requestVoiceClip(String messageId) async {
    if (messageId.isEmpty || _currentKey.peerId.isEmpty) return;
    _sendWire(
      _currentKey,
      DirectChatEnvelope.voiceRequest(messageId).encode(),
    );
  }

  Future<void> syncActiveCompanionSessions() async {
    if (_activeCompanionSyncInProgress) return;
    final serverModel = parent.target?.serverModel;
    if (serverModel == null) return;
    _activeCompanionSyncInProgress = true;
    try {
      final clients = <int, Client>{
        for (final client in serverModel.clients)
          if (client.authorized && client.isChat && !client.disconnected)
            client.id: client,
      };
      _activeCompanionSecrets.removeWhere(
        (connId, _) => !clients.containsKey(connId),
      );
      if (_activeCompanionSecrets.isEmpty) return;
      final cursor = await DirectChatRepository.instance.cursor();
      for (final entry in _activeCompanionSecrets.entries.toList()) {
        final client = clients[entry.key];
        if (client == null) continue;
        _sendWire(
          MessageKey(client.peerId, client.id),
          DirectChatEnvelope.replicaRequest(
            secret: entry.value,
            cursor: cursor,
            requestReply: true,
          ).encode(),
        );
      }
    } finally {
      _activeCompanionSyncInProgress = false;
    }
  }

  Future<void> markCurrentUndeliveredFailed() async {
    if (_currentKey.peerId.isEmpty) return;
    await DirectChatRepository.instance.markUndeliveredFailed(
      _currentKey.peerId,
    );
    await _restoreConversation(_currentKey);
  }

  Future<void> markCurrentUndeliveredQueued() async {
    if (_currentKey.peerId.isEmpty) return;
    await DirectChatRepository.instance.markUndeliveredQueued(
      _currentKey.peerId,
    );
    await _restoreConversation(_currentKey);
  }

  Future<void> remapCurrentPeer(String peerId) async {
    final previous = _currentKey;
    if (peerId.isEmpty ||
        previous.peerId.isEmpty ||
        previous.peerId == peerId) {
      return;
    }
    await DirectChatRepository.instance.remapConversation(
      previous.peerId,
      peerId,
    );
    final previousBody = _messages.remove(previous);
    final next = MessageKey(peerId, previous.connId);
    if (previousBody != null) {
      previousBody.chatUser.id = peerId;
      _messages[next] = previousBody;
    }
    _currentKey = next;
    await _restoreConversation(next);
  }

  Future<void> _handleEnvelope(
    MessageKey key,
    DirectChatEnvelope envelope,
  ) async {
    switch (envelope.type) {
      case 'receipt':
        final id = (envelope.data['id'] ?? '').toString();
        if (id.isNotEmpty) {
          await DirectChatRepository.instance.markDelivery(
            id,
            DirectChatDelivery.delivered,
          );
          final record = await DirectChatRepository.instance.find(id);
          if (record != null) {
            insertMessage(key, _toChatMessage(record, me));
            notifyListeners();
          }
        }
        return;
      case 'sync_request':
        final cursor = _parseCursor(envelope.data['cursor']);
        final records = await DirectChatRepository.instance.afterCursor(
          cursor,
          conversationId: key.peerId,
          outgoingOnly: true,
        );
        for (final record in records) {
          await _transmitRecord(key, record);
          if (record.kind == DirectChatKind.voice) {
            await _sendStoredVoiceClip(key, record);
          }
        }
        return;
      case 'replica_request':
        final secret = (envelope.data['secret'] ?? '').toString();
        if (!DirectPairingStore.acceptsCompanionSecret(secret)) return;
        if (!key.isOut) {
          _activeCompanionSecrets[key.connId] = secret;
        }
        final cursor = _parseCursor(envelope.data['cursor']);
        final records = await DirectChatRepository.instance.afterCursor(cursor);
        for (final record in records) {
          _sendWire(
            key,
            DirectChatEnvelope.replicaMessage(record, secret).encode(),
          );
        }
        _sendWire(
          key,
          DirectChatEnvelope('replica_contacts', <String, dynamic>{
            'secret': secret,
            'contacts': DirectPairingStore.exportContacts(),
          }).encode(),
        );
        if (envelope.data['request_reply'] == true) {
          final localCursor = await DirectChatRepository.instance.cursor();
          _sendWire(
            key,
            DirectChatEnvelope.replicaRequest(
              secret: secret,
              cursor: localCursor,
              requestReply: false,
            ).encode(),
          );
        }
        return;
      case 'replica_message':
        final secret = (envelope.data['secret'] ?? '').toString();
        if (!DirectPairingStore.acceptsCompanionSecret(secret)) return;
        try {
          final record = DirectChatRecord.fromJson(
            Map<String, dynamic>.from(envelope.data['record'] as Map),
          );
          await DirectChatRepository.instance.upsert(record);
          if (record.kind == DirectChatKind.voice &&
              !await DirectVoiceStorage.instance.exists(record.id)) {
            _sendWire(
              key,
              DirectChatEnvelope.voiceRequest(record.id).encode(),
            );
          }
        } catch (_) {}
        return;
      case 'replica_contacts':
        final secret = (envelope.data['secret'] ?? '').toString();
        if (!DirectPairingStore.acceptsCompanionSecret(secret)) return;
        await DirectPairingStore.mergeContacts(
          envelope.data['contacts'] as List<dynamic>? ?? const [],
        );
        return;
      case 'voice_request':
        final id = (envelope.data['id'] ?? '').toString();
        final record = await DirectChatRepository.instance.find(id);
        if (record?.kind == DirectChatKind.voice &&
            (record!.conversationId == key.peerId ||
                _isCompanionSession(key))) {
          await _sendStoredVoiceClip(key, record!);
        }
        return;
      case 'voice_chunk':
        await _receiveVoiceChunk(key, envelope);
        return;
      case 'typing':
        _onPeerTyping(key.peerId);
        return;
      case 'reaction':
        final id = (envelope.data['id'] ?? '').toString();
        final emoji = (envelope.data['emoji'] ?? '').toString();
        final deviceId = (envelope.data['device_id'] ?? '').toString();
        if (id.isEmpty || emoji.isEmpty || deviceId.isEmpty) return;
        final reacted = await DirectChatRepository.instance.toggleReaction(
          id, emoji, deviceId,
        );
        if (reacted != null) {
          final user = _messages[key]?.chatUser;
          if (user != null) {
            insertMessage(key, _toChatMessage(reacted, user));
            notifyListeners();
          }
        }
        return;
      case 'edit':
        final editId = (envelope.data['id'] ?? '').toString();
        final newText = (envelope.data['text'] ?? '').toString();
        if (editId.isEmpty || newText.isEmpty) return;
        final edited = await DirectChatRepository.instance.editText(
          editId, newText,
        );
        if (edited != null) {
          final user = _messages[key]?.chatUser ?? me;
          insertMessage(key, _toChatMessage(edited, user));
          notifyListeners();
        }
        return;
      default:
        return;
    }
  }

  Map<String, int> _parseCursor(dynamic value) {
    try {
      return Map<String, dynamic>.from(value as Map).map(
        (key, value) => MapEntry(key, int.tryParse('$value') ?? 0),
      );
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> _transmitRecord(
    MessageKey key,
    DirectChatRecord record,
  ) async {
    final sent = _sendWire(
      key,
      DirectChatEnvelope.message(record).encode(),
    );
    if (sent) {
      _touchChatActivity(key.peerId);
    } else {
      unawaited(ensureChatConnection?.call(key.peerId));
    }
    if (sent && record.delivery != DirectChatDelivery.delivered) {
      final updated = record.copyWith(delivery: DirectChatDelivery.sent);
      await DirectChatRepository.instance
          .markDelivery(record.id, updated.delivery);
      insertMessage(key, _toChatMessage(updated, me));
      notifyListeners();
    }
  }

  Future<void> _sendStoredVoiceClip(
    MessageKey key,
    DirectChatRecord record,
  ) async {
    final bytes = await DirectVoiceStorage.instance.read(record.id);
    if (bytes != null) await _sendVoiceChunks(key, record, bytes);
  }

  Future<void> _sendVoiceChunks(
    MessageKey key,
    DirectChatRecord record,
    Uint8List bytes,
  ) async {
    const chunkSize = 24 * 1024;
    if (bytes.isEmpty || bytes.length > DirectVoiceStorage.maxClipBytes) return;
    final digest = sha256.convert(bytes).toString();
    if (record.fileSha256.isNotEmpty && record.fileSha256 != digest) return;
    final total = (bytes.length + chunkSize - 1) ~/ chunkSize;
    for (var index = 0; index < total; index++) {
      final start = index * chunkSize;
      final end =
          start + chunkSize > bytes.length ? bytes.length : start + chunkSize;
      if (!_sendWire(
        key,
        DirectChatEnvelope.voiceChunk(
          messageId: record.id,
          index: index,
          total: total,
          sha256: digest,
          payload: base64Encode(bytes.sublist(start, end)),
        ).encode(),
      )) {
        return;
      }
    }
  }

  bool _isCompanionSession(MessageKey key) {
    if (key.isOut)
      return DirectPairingStore.find(key.peerId)?.companion == true;
    return _activeCompanionSecrets.containsKey(key.connId);
  }

  Future<void> _receiveVoiceChunk(
    MessageKey key,
    DirectChatEnvelope envelope,
  ) async {
    final id = (envelope.data['id'] ?? '').toString();
    final digest = (envelope.data['sha256'] ?? '').toString().toLowerCase();
    final index = int.tryParse('${envelope.data['index'] ?? -1}') ?? -1;
    final total = int.tryParse('${envelope.data['total'] ?? 0}') ?? 0;
    if (id.isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        total <= 0 ||
        total > 342 ||
        index < 0 ||
        index >= total) {
      return;
    }
    final record = await DirectChatRepository.instance.find(id);
    if (record?.kind != DirectChatKind.voice ||
        record!.fileSha256.toLowerCase() != digest ||
        (record.conversationId != key.peerId && !_isCompanionSession(key))) {
      return;
    }
    Uint8List chunk;
    try {
      chunk = base64Decode((envelope.data['payload'] ?? '').toString());
    } catch (_) {
      return;
    }
    if (chunk.isEmpty || chunk.length > 24 * 1024) return;
    var transfer = _incomingVoiceTransfers[id];
    if (transfer == null ||
        transfer.total != total ||
        transfer.sha256 != digest) {
      if (_incomingVoiceTransfers.length >= 8) {
        _incomingVoiceTransfers.remove(_incomingVoiceTransfers.keys.first);
      }
      transfer = _IncomingVoiceTransfer(total: total, sha256: digest);
      _incomingVoiceTransfers[id] = transfer;
    }
    transfer.chunks[index] = chunk;
    if (transfer.chunks.length != total) return;

    final output = BytesBuilder(copy: false);
    for (var part = 0; part < total; part++) {
      final bytes = transfer.chunks[part];
      if (bytes == null) return;
      output.add(bytes);
      if (output.length > DirectVoiceStorage.maxClipBytes) {
        _incomingVoiceTransfers.remove(id);
        return;
      }
    }
    final clip = output.takeBytes();
    if (clip.length != record.fileSize ||
        sha256.convert(clip).toString() != digest) {
      _incomingVoiceTransfers.remove(id);
      return;
    }
    await DirectVoiceStorage.instance.write(id, clip);
    _incomingVoiceTransfers.remove(id);
  }

  bool _sendWire(MessageKey key, String value) {
    final ffi = parent.target;
    if (ffi == null || ffi.closed) return false;
    // Never send messages to self — prevents deadlock and white-screen.
    if (key.peerId.isNotEmpty && key.peerId == me.id) return false;
    try {
      if (key.connId <= clientModeID) {
        // clientModeID (-1) or uninitialized (-2): send via session
        bind.sessionSendChat(sessionId: sessionId, text: value);
        return true;
      }
      final client = ffi.serverModel.clients.firstWhereOrNull(
        (client) =>
            client.id == key.connId &&
            client.authorized &&
            !client.disconnected,
      );
      if (client == null) {
        // fallback: CM client not found, try session path
        bind.sessionSendChat(sessionId: sessionId, text: value);
        return true;
      }
      bind.cmSendChat(connId: key.connId, msg: value);
      return true;
    } catch (error) {
      debugPrint('Failed to send direct chat message: $error');
      return false;
    }
  }

  Future<void> _restoreConversation(MessageKey key) async {
    if (key.peerId.isEmpty) return;
    late List<DirectChatRecord> records;
    try {
      final deviceId = await DirectChatRepository.instance.deviceId;
      me.id = deviceId;
      records = await DirectChatRepository.instance.forConversation(
        key.peerId,
        // Load slightly more than the initial limit to support
        // "load older" without another DB read on the first scroll.
        limit: _kInitialMessageLimit + _kPageSize,
      );
    } catch (error) {
      debugPrint('Failed to restore direct chat conversation: $error');
      return;
    }
    updateConnIdOfKey(key);
    final pairing = DirectPairingStore.find(key.peerId);
    final body = _messages.putIfAbsent(
      key,
      () => MessageBody(
        ChatUser(
          id: key.peerId,
          firstName: pairing?.displayName.isNotEmpty == true
              ? pairing!.displayName
              : key.peerId,
          profileImage:
              pairing?.avatar.isNotEmpty == true ? pairing!.avatar : null,
        ),
        <ChatMessage>[],
      ),
    );
    // Cache full record list for "load older" pagination.
    _conversationRecords[key.peerId] = records;

    final incoming = records.firstWhereOrNull((record) => !record.isOutgoing);
    if (incoming != null) {
      if (incoming.senderName.isNotEmpty) {
        body.chatUser.firstName = incoming.senderName;
      }
      if (incoming.senderAvatar.isNotEmpty) {
        body.chatUser.profileImage = incoming.senderAvatar;
      }
    }
    // Only convert the latest N records to ChatMessage objects.
    // Older messages are loaded on demand via loadOlderMessages().
    final initialCount = records.length > _kInitialMessageLimit
        ? _kInitialMessageLimit
        : records.length;
    body.chatMessages = records
        .sublist(0, initialCount)
        .map((record) => _toChatMessage(
              record,
              record.isOutgoing ? me : body.chatUser,
            ))
        .toList(growable: true);
    for (final record in records) {
      _scheduleSelfDestruct(
        key,
        record,
        record.isOutgoing ? me : body.chatUser,
      );
    }
    if (_currentKey == key) notifyListeners();
  }

  /// Returns true if [key]'s conversation has older messages not yet loaded.
  bool hasOlderMessages(MessageKey key) {
    final records = _conversationRecords[key.peerId];
    if (records == null) return false;
    final body = _messages[key];
    if (body == null) return false;
    return records.length > body.chatMessages.length;
  }

  /// Loads the next page of older messages for [key] and prepends them
  /// to the existing message list. Returns the number of newly loaded messages.
  Future<int> loadOlderMessages(MessageKey key) async {
    final records = _conversationRecords[key.peerId];
    final body = _messages[key];
    if (records == null || body == null) return 0;
    final loaded = body.chatMessages.length;
    if (loaded >= records.length) return 0;
    final end = loaded + _kPageSize;
    final batchEnd = end > records.length ? records.length : end;
    final batch = records.sublist(loaded, batchEnd);
    if (batch.isEmpty) return 0;
    final newMessages = batch.map((record) => _toChatMessage(
          record,
          record.isOutgoing ? me : body.chatUser,
        )).toList();
    // Append: older messages go after the already-loaded ones (end of list),
    // because DashChat displays index 0 (newest) at the bottom and
    // index N-1 (oldest) at the top when scrolling up.
    body.chatMessages.addAll(newMessages);
    if (_currentKey == key) notifyListeners();
    return newMessages.length;
  }

  ChatMessage _toChatMessage(DirectChatRecord record, ChatUser user) {
    final recalled = record.disposition == DirectChatDisposition.recalled;
    final displayText = recalled
        ? translate(record.isOutgoing
            ? 'You recalled a message'
            : 'The other party recalled a message')
        : record.text;
    MessageStatus status;
    switch (record.delivery) {
      case DirectChatDelivery.queued:
      case DirectChatDelivery.failed:
        status = MessageStatus.pending;
        break;
      case DirectChatDelivery.sent:
        status = MessageStatus.none;
        break;
      case DirectChatDelivery.delivered:
        status = MessageStatus.received;
        break;
    }
    return ChatMessage(
      text: displayText,
      user: user,
      createdAt: record.sentAt.toLocal(),
      status: status,
      customProperties: <String, dynamic>{
        'ldesk_id': record.id,
        'ldesk_delivery': record.delivery.name,
        'ldesk_kind': record.kind.name,
        if (record.fileName.isNotEmpty) 'ldesk_file_name': record.fileName,
        if (record.fileSize > 0) 'ldesk_file_size': record.fileSize,
        if (record.fileSha256.isNotEmpty)
          'ldesk_file_sha256': record.fileSha256,
        if (record.localPath.isNotEmpty) 'ldesk_local_path': record.localPath,
        if (record.voiceDurationMs > 0)
          'ldesk_voice_duration_ms': record.voiceDurationMs,
        if (record.expiresAt != null)
          'ldesk_expires_at': record.expiresAt!.toUtc().toIso8601String(),
        'ldesk_disposition': record.disposition.name,
        if (record.replyToId.isNotEmpty) 'ldesk_reply_to_id': record.replyToId,
        if (record.replyToText.isNotEmpty)
          'ldesk_reply_to_text': record.replyToText,
        if (record.reactions.isNotEmpty)
          'ldesk_reactions': Map<String, dynamic>.from(record.reactions),
        if (record.isEdited) 'ldesk_is_edited': true,
        if (record.editedAt != null)
          'ldesk_edited_at': record.editedAt!.toUtc().toIso8601String(),
      },
    );
  }

  insertMessage(MessageKey key, ChatMessage message) {
    updateConnIdOfKey(key);
    if (!_messages.containsKey(key)) {
      _messages[key] = MessageBody(message.user, []);
    }
    final messages = _messages[key]!.chatMessages;
    final messageId = message.customProperties?['ldesk_id']?.toString();
    final index = messageId == null
        ? -1
        : messages.indexWhere(
            (item) =>
                item.customProperties?['ldesk_id']?.toString() == messageId,
          );
    if (message.customProperties?['ldesk_disposition'] ==
        DirectChatDisposition.destroyed.name) {
      if (messageId != null) _selfDestructTimers.remove(messageId)?.cancel();
      if (index >= 0) messages.removeAt(index);
      return;
    }
    if (index < 0) {
      messages.add(message);
    } else {
      messages[index] = message;
    }
    messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  updateConnIdOfKey(MessageKey key) {
    if (_messages.keys
            .toList()
            .firstWhereOrNull((e) => e == key && e.connId != key.connId) !=
        null) {
      final value = _messages.remove(key);
      if (value != null) {
        _messages[key] = value;
      }
    }
    if (_currentKey == key || _currentKey.peerId.isEmpty) {
      _currentKey = key; // hash != assign
    }
  }

  void mobileUpdateUnreadSum() {
    if (!isMobile) return;
    var sum = 0;
    parent.target?.serverModel.clients
        .map((e) => sum += e.unreadChatMessageCount.value)
        .toList();
    Future.delayed(Duration.zero, () {
      mobileUnreadSum.value = sum;
    });
  }

  void mobileClearClientUnread(int id) {
    if (!isMobile) return;
    final client = parent.target?.serverModel.clients
        .firstWhereOrNull((client) => client.id == id);
    if (client != null) {
      Future.delayed(Duration.zero, () {
        client.unreadChatMessageCount.value = 0;
        mobileUpdateUnreadSum();
      });
    }
  }

  Future<void> deleteConversations(Iterable<String> peerIds) async {
    final ids = peerIds.toSet();
    _messages.removeWhere((key, _) => ids.contains(key.peerId));
    _conversationRecords.removeWhere((peerId, _) => ids.contains(peerId));
    await DirectChatRepository.instance.deleteConversations(ids);
    if (ids.contains(_currentKey.peerId)) {
      _currentKey = MessageKey('', clientModeID);
    }
    notifyListeners();
  }

  /// Copy message text to system clipboard.
  Future<void> copyMessage(ChatMessage message) async {
    final text = message.text;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Delete a message locally (from current conversation only).
  Future<bool> deleteLocally(ChatMessage message) async {
    final id = (message.customProperties?['ldesk_id'] ?? '').toString();
    final key = _currentKey;
    if (id.isEmpty || key.peerId.isEmpty) return false;
    await DirectChatRepository.instance.deleteRecord(id, key.peerId);
    final body = _messages[key];
    if (body != null) {
      body.chatMessages.removeWhere((m) =>
          (m.customProperties?['ldesk_id'] ?? '').toString() == id);
    }
    notifyListeners();
    return true;
  }

  /// Clear all messages in the current conversation.
  Future<bool> clearConversation() async {
    final key = _currentKey;
    if (key.peerId.isEmpty) return false;
    final body = _messages[key];
    if (body != null) {
      body.clear();
    }
    await DirectChatRepository.instance
        .deleteConversations([key.peerId]);
    _conversationRecords.remove(key.peerId);
    _drafts.remove(key.peerId);
    notifyListeners();
    return true;
  }

  /// Set a message as the reply target for the next sent message.
  void setReplyTo(ChatMessage message) {
    _replyToMessage = message;
    notifyListeners();
  }

  /// Cancel the current reply target.
  void cancelReply() {
    _replyToMessage = null;
    notifyListeners();
  }

  /// Save current input as draft for the active conversation.
  void saveDraftNow() {
    final peerId = _currentKey.peerId;
    if (peerId.isEmpty) return;
    final text = textController.text;
    if (text.isNotEmpty) {
      _drafts[peerId] = text;
    } else {
      _drafts.remove(peerId);
    }
  }

  /// Mark the connection as reconnecting for UI feedback.
  void setReconnecting(String peerId) {
    _isReconnecting = true;
    _reconnectPeerId = peerId;
    notifyListeners();
  }

  /// Clear the reconnecting state.
  void clearReconnecting() {
    _isReconnecting = false;
    _reconnectPeerId = '';
    notifyListeners();
  }

  /// Toggle reaction on a message and sync to peer.
  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    final id = (message.customProperties?['ldesk_id'] ?? '').toString();
    final key = _currentKey;
    if (id.isEmpty || key.peerId.isEmpty) return;
    final deviceId = me.id;
    final updated = await DirectChatRepository.instance.toggleReaction(
      id, emoji, deviceId,
    );
    if (updated == null) return;
    insertMessage(key, _toChatMessage(updated, me));
    _sendWire(
      key,
      DirectChatEnvelope.reaction(
        messageId: id,
        emoji: emoji,
        deviceId: deviceId,
        add: (updated.reactions[emoji] ?? []).contains(deviceId),
      ).encode(),
    );
    notifyListeners();
  }

  /// Edit a sent message's text.
  Future<bool> editMessage(ChatMessage message, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return false;
    final id = (message.customProperties?['ldesk_id'] ?? '').toString();
    final key = _currentKey;
    if (id.isEmpty || key.peerId.isEmpty) return false;
    if (message.user.id != me.id) return false;
    final updated = await DirectChatRepository.instance.editText(id, trimmed);
    if (updated == null) return false;
    insertMessage(key, _toChatMessage(updated, me));
    _sendWire(key, DirectChatEnvelope.edit(messageId: id, newText: trimmed).encode());
    notifyListeners();
    return true;
  }

  /// Batch delete multiple messages from the current conversation.
  Future<bool> batchDeleteMessages(Set<String> ids) async {
    final key = _currentKey;
    if (key.peerId.isEmpty || ids.isEmpty) return false;
    // Shallow copy to guard against concurrent modification of shared set.
    final idsToDelete = Set<String>.from(ids);
    for (final id in idsToDelete) {
      await DirectChatRepository.instance.deleteRecord(id, key.peerId);
    }
    final body = _messages[key];
    if (body != null) {
      body.chatMessages.removeWhere((m) =>
          idsToDelete.contains((m.customProperties?['ldesk_id'] ?? '').toString()));
    }
    notifyListeners();
    return true;
  }

  /// Get all media files for current conversation.
  Future<List<DirectChatRecord>> mediaForConversation() async {
    final peerId = _currentKey.peerId;
    if (peerId.isEmpty) return [];
    return DirectChatRepository.instance.mediaForConversation(peerId);
  }

  /// Pin or unpin a conversation.
  Future<void> pinConversation(String peerId, bool pinned) async {
    if (peerId.isEmpty) return;
    final pinnedIds = await _loadPinnedConversations();
    if (pinned) {
      pinnedIds.add(peerId);
    } else {
      pinnedIds.remove(peerId);
    }
    try {
      bind.mainSetLocalOption(
        key: 'pinned_conversations',
        value: jsonEncode(pinnedIds.toList()),
      );
    } catch (_) {}
    notifyListeners();
  }

  /// Get list of pinned conversation peer IDs.
  Future<Set<String>> _loadPinnedConversations() async {
    try {
      final raw = bind.mainGetLocalOption(key: 'pinned_conversations');
      if (raw.isEmpty) return {};
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Check if a conversation is pinned.
  Future<bool> isConversationPinned(String peerId) async {
    final pinned = await _loadPinnedConversations();
    return pinned.contains(peerId);
  }

  /// Get pinned conversation list sorted.
  Future<List<String>> pinnedConversationIds() async {
    final pinned = await _loadPinnedConversations();
    final all = await DirectChatRepository.instance.conversationIds();
    final result = <String>[];
    for (final id in all) {
      if (pinned.contains(id)) result.add(id);
    }
    for (final id in all) {
      if (!pinned.contains(id)) result.add(id);
    }
    return result;
  }

  /// Mark a conversation as unread without a new message.
  Future<void> markConversationUnread(String peerId) async {
    if (peerId.isEmpty) return;
    try {
      final raw = bind.mainGetLocalOption(key: 'marked_unread');

      Set<String> unreadSet;
      if (raw.isNotEmpty) {
        unreadSet = (jsonDecode(raw) as List<dynamic>)
            .map((e) => e.toString())
            .toSet();
      } else {
        unreadSet = {};
      }
      unreadSet.add(peerId);
      bind.mainSetLocalOption(
        key: 'marked_unread',
        value: jsonEncode(unreadSet.toList()),
      );
    } catch (_) {}
    mobileUpdateUnreadSum();
    notifyListeners();
  }

  /// Check if conversation is marked as unread.
  bool isConversationMarkedUnread(String peerId) {
    try {
      final raw = bind.mainGetLocalOption(key: 'marked_unread');
      if (raw.isEmpty) return false;
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).contains(peerId);
    } catch (_) {
      return false;
    }
  }

  /// Clear the marked-unread flag.
  void clearMarkedUnread(String peerId) {
    try {
      final raw = bind.mainGetLocalOption(key: 'marked_unread');
      if (raw.isEmpty) return;
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => e.toString())
          .toList();
      list.remove(peerId);
      bind.mainSetLocalOption(
        key: 'marked_unread',
        value: jsonEncode(list),
      );
    } catch (_) {}
    mobileUpdateUnreadSum();
    notifyListeners();
  }

  /// Get raw option value (bridges bind for external models).
  String getRawOption(String key) {
    try {
      return bind.mainGetLocalOption(key: key);
    } catch (_) {
      return '';
    }
  }

  /// Set raw option value (bridges bind for external models).
  Future<void> setRawOption({required String key, required String value}) async {
    try {
      await bind.mainSetLocalOption(key: key, value: value);
    } catch (_) {}
  }

  // ─── Multi-select ────────────────────────────────────────

  void enterMultiSelect(String firstMessageId) {
    _multiSelectMode = true;
    _selectedMessageIds.clear();
    _selectedMessageIds.add(firstMessageId);
    notifyListeners();
  }

  void toggleSelection(String messageId) {
    if (_selectedMessageIds.contains(messageId)) {
      _selectedMessageIds.remove(messageId);
      if (_selectedMessageIds.isEmpty) {
        _multiSelectMode = false;
      }
    } else {
      _selectedMessageIds.add(messageId);
    }
    notifyListeners();
  }

  void selectAllInConversation() {
    final body = _messages[_currentKey];
    if (body == null) return;
    for (final msg in body.chatMessages) {
      final id = (msg.customProperties?['ldesk_id'] ?? '').toString();
      if (id.isNotEmpty) _selectedMessageIds.add(id);
    }
    notifyListeners();
  }

  void exitMultiSelect() {
    _multiSelectMode = false;
    _selectedMessageIds.clear();
    notifyListeners();
  }

  close() {
    for (final timer in _selfDestructTimers.values) {
      timer.cancel();
    }
    _selfDestructTimers.clear();
    hideChatIconOverlay();
    hideChatWindowOverlay();
    notifyListeners();
  }

  resetClientMode() {
    // Persistent direct-chat history is restored by peer ID after reconnect.
  }

  void requestChatInputFocus() {
    Timer(Duration(milliseconds: 100), () {
      if (inputNode.hasListeners && inputNode.canRequestFocus) {
        inputNode.requestFocus();
      }
    });
  }

  void onVoiceCallWaiting() {
    _voiceCallStatus.value = VoiceCallStatus.waitingForResponse;
  }

  void onVoiceCallStarted() {
    _voiceCallStatus.value = VoiceCallStatus.connected;
    if (isAndroid) {
      parent.target?.invokeMethod("on_voice_call_started");
    }
  }

  void onVoiceCallClosed(String reason) {
    _voiceCallStatus.value = VoiceCallStatus.notStarted;
    if (isAndroid) {
      // We can always invoke "on_voice_call_closed"
      // no matter if the `_voiceCallStatus` was `VoiceCallStatus.notStarted` or not.
      parent.target?.invokeMethod("on_voice_call_closed");
    }
  }

  void onVoiceCallIncoming() {
    if (isConnManager) {
      _voiceCallStatus.value = VoiceCallStatus.incoming;
    }
  }

  void closeVoiceCall() {
    bind.sessionCloseVoiceCall(sessionId: sessionId);
  }
}

class _IncomingVoiceTransfer {
  _IncomingVoiceTransfer({
    required this.total,
    required this.sha256,
  });

  final int total;
  final String sha256;
  final Map<int, Uint8List> chunks = <int, Uint8List>{};
}

enum VoiceCallStatus {
  notStarted,
  waitingForResponse,
  connected,
  // Connection manager only.
  incoming
}
