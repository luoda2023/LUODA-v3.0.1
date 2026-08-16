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
import '../runtime_logger.dart';
import '../common/direct_chat.dart';
import '../common/relay_bridge.dart';
import '../common/email_draft_service.dart';
import '../common/string_utils.dart';
import '../common/direct_pairing.dart';
import '../common/direct_chat_policy.dart';
import '../common/backup_restore.dart';
import '../common/direct_voice_storage.dart';
import '../common/chat_notifier.dart';
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
  final FocusNode chatSearchFocusNode = FocusNode(debugLabel: 'chat-search');
  int _chatSearchMatchIndex = 0;
  final Map<String, GlobalKey> _chatSearchMessageKeys = <String, GlobalKey>{};

  List<ChatMessage> get chatSearchMatches {
    if (chatSearchText.trim().isEmpty) return const <ChatMessage>[];
    final messages = _messages[_currentKey]?.chatMessages ?? <ChatMessage>[];
    return messages.where(isChatSearchMatch).toList(growable: false);
  }

  bool isChatSearchMatch(ChatMessage message) {
    final query = chatSearchText.trim().toLowerCase();
    if (query.isEmpty) return false;
    final fileName =
        (message.customProperties?['ldesk_file_name'] ?? '').toString();
    return message.text.toLowerCase().contains(query) ||
        fileName.toLowerCase().contains(query);
  }

  int get chatSearchMatchIndex => _chatSearchMatchIndex;

  ChatMessage? get currentChatSearchMatch {
    final matches = chatSearchMatches;
    if (matches.isEmpty) return null;
    final index = _chatSearchMatchIndex.clamp(0, matches.length - 1);
    return matches[index];
  }

  bool get canSelectPreviousChatSearchResult =>
      _chatSearchMatchIndex > 0 && chatSearchMatches.isNotEmpty;

  bool get canSelectNextChatSearchResult {
    final matches = chatSearchMatches;
    return matches.isNotEmpty && _chatSearchMatchIndex < matches.length - 1;
  }

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
  // Shift+点击连续多选的锚点（上一次点击/选中的消息 id）。
  String? _anchorMessageId;
  bool get isMultiSelectMode => _multiSelectMode;
  Set<String> get selectedMessageIds => _selectedMessageIds;

  static const int _maxCachedTranslations = 500;
  final Map<String, String> _messageTranslations = <String, String>{};
  final Set<String> _pendingMessageTranslations = <String>{};

  String? messageTranslation(String messageId) =>
      _messageTranslations[messageId];

  bool isMessageTranslationPending(String messageId) =>
      _pendingMessageTranslations.contains(messageId);

  bool beginMessageTranslation(String messageId) {
    if (messageId.isEmpty || !_pendingMessageTranslations.add(messageId)) {
      return false;
    }
    notifyListeners();
    return true;
  }

  void completeMessageTranslation(String messageId, String translated) {
    _pendingMessageTranslations.remove(messageId);
    final value = sanitizeInvalidUtf16(translated).trim();
    if (messageId.isNotEmpty && value.isNotEmpty) {
      _messageTranslations[messageId] = value;
      while (_messageTranslations.length > _maxCachedTranslations) {
        _messageTranslations.remove(_messageTranslations.keys.first);
      }
    }
    notifyListeners();
  }

  void failMessageTranslation(String messageId) {
    if (_pendingMessageTranslations.remove(messageId)) notifyListeners();
  }

  // Typing indicator state (peer → us)
  final Map<String, DateTime> _peerTypingTimestamps = {};
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  static const _typingThrottle = Duration(seconds: 2);
  static const _typingExpire = Duration(seconds: 5);

  void openChatSearch() {
    if (chatSearchVisible) {
      _requestChatSearchFocus();
      return;
    }
    chatSearchVisible = true;
    chatSearchText = '';
    _chatSearchMatchIndex = 0;
    _chatSearchMessageKeys.clear();
    chatSearchController.clear();
    notifyListeners();
    _requestChatSearchFocus();
  }

  void closeChatSearch() {
    if (!chatSearchVisible) return;
    chatSearchVisible = false;
    chatSearchText = '';
    _chatSearchMatchIndex = 0;
    _chatSearchMessageKeys.clear();
    chatSearchController.clear();
    chatSearchFocusNode.unfocus();
    notifyListeners();
  }

  void toggleChatSearch() {
    if (chatSearchVisible) {
      closeChatSearch();
    } else {
      openChatSearch();
    }
  }

  void _requestChatSearchFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (chatSearchVisible && chatSearchFocusNode.canRequestFocus) {
        chatSearchFocusNode.requestFocus();
      }
    });
  }

  void selectPreviousChatSearchResult() {
    if (!canSelectPreviousChatSearchResult) return;
    _chatSearchMatchIndex -= 1;
    notifyListeners();
    _focusCurrentChatSearchResult();
  }

  void selectNextChatSearchResult() {
    if (!canSelectNextChatSearchResult) return;
    _chatSearchMatchIndex += 1;
    notifyListeners();
    _focusCurrentChatSearchResult();
  }

  GlobalKey chatSearchKeyFor(ChatMessage message) {
    return _chatSearchMessageKeys.putIfAbsent(
      _chatSearchIdentity(message),
      GlobalKey.new,
    );
  }

  bool isCurrentChatSearchResult(ChatMessage message) {
    final current = currentChatSearchMatch;
    return current != null &&
        _chatSearchIdentity(current) == _chatSearchIdentity(message);
  }

  String _chatSearchIdentity(ChatMessage message) {
    final storedId =
        (message.customProperties?['ldesk_id'] ?? '').toString().trim();
    if (storedId.isNotEmpty) return storedId;
    return '${message.createdAt.microsecondsSinceEpoch}:${message.user.id}:${message.text.hashCode}';
  }

  void _focusCurrentChatSearchResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = currentChatSearchMatch;
      if (message == null) return;
      final targetContext =
          _chatSearchMessageKeys[_chatSearchIdentity(message)]?.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
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
    _chatSearchMatchIndex = 0;
    if (chatSearchController.text != text) {
      chatSearchController.text = text;
      chatSearchController.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
      );
    }
    notifyListeners();
    _focusCurrentChatSearchResult();
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
    _externalChatPollTimer?.cancel();
    for (final timer in _selfDestructTimers.values) {
      timer.cancel();
    }
    _selfDestructTimers.clear();
    textController.dispose();
    chatSearchController.dispose();
    chatSearchFocusNode.dispose();
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
  // 送达看门狗：发出后一段时间未收到回执则强制重建连接并重发。
  final Map<String, Timer> _deliveryWatchdogs = <String, Timer>{};
  final Map<String, int> _deliveryWatchdogRetries = <String, int>{};
  final Set<String> _flushingPeers = <String>{};

  /// 拨号中防重入：短时间内对同一会话只允许一次建连操作，
  /// 避免保活 / 看门狗互相打断正在建立的会话。
  static final Map<String, DateTime> _dialingAt = <String, DateTime>{};

  static bool isDialing(String peerId) {
    final at = _dialingAt[peerId];
    if (at == null) return false;
    if (DateTime.now().difference(at) > const Duration(seconds: 25)) {
      _dialingAt.remove(peerId);
      return false;
    }
    return true;
  }

  static void markDialing(String peerId) => _dialingAt[peerId] = DateTime.now();

  static void clearDialing(String peerId) => _dialingAt.remove(peerId);
  bool _activeCompanionSyncInProgress = false;
  Future<void>? _recentRestoreTask;
  bool _recentRestoreQueued = false;

  // 每个会话最后收发消息的时间，用于保活 / 空闲超时判断。
  final Map<String, DateTime> _lastChatActivity = {};
  // 发送消息但当前无可用连接时，由页面层提供一个“建立直连会话”的回调，
  // 确保消息能尽快送达（连上后 onDirectSessionReady 会自动重发 pending）。
  Future<void> Function(String peerId, {bool force})? ensureChatConnection;

  // Cached live incoming chat client (hosted by the connection-manager
  // process on Windows) that can carry replies to [peerId]. Refreshed before
  // every send so a reply to an incoming message is routed over the peer's
  // existing connection instead of staying queued forever.
  String _cmLiveChatPeerId = '';
  int _cmLiveChatConnId = 0;

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
    // Restore contacts + chat history from the public backup folder after a
    // reinstall (app-private data is wiped on uninstall).
    unawaited(DotChatBackup.tryRestore());
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
        if (isEnterPressed && !isShiftPressed && textController.text.isEmpty) {
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
    _startExternalChatPolling();
  }

  /// Host-side incoming messages are written by the connection-manager
  /// process into the shared chat store; the main window has no in-memory
  /// notification for those writes. Poll the store file mtime every few
  /// seconds (a cheap stat) and refresh the conversation UI when a change is
  /// detected, so incoming messages appear without a manual tab switch.
  void _startExternalChatPolling() {
    final desktopMain = isDesktop && desktopType == DesktopType.main;
    if (!desktopMain && !isMobile) return;
    _externalChatPollTimer?.cancel();
    // Mobile has no separate writer process (the store is only touched by
    // this isolate, which bumps `revision`), so the file poll is just a cheap
    // safety net — 8s is plenty and the mtime fast-path keeps it to a stat.
    _externalChatPollTimer = Timer.periodic(
      isMobile ? const Duration(seconds: 8) : const Duration(seconds: 4),
      (_) async {
        try {
          // 低频清理阅后即焚到期消息（每 60 秒最多一次），防止历史
          // 存储无限累积过期垃圾。O(n) 扫描仅发生在轮询节拍上。
          final now = DateTime.now();
          if (_lastExpiredPurge == null ||
              now.difference(_lastExpiredPurge!) >
                  const Duration(minutes: 1)) {
            _lastExpiredPurge = now;
            unawaited(DirectChatRepository.instance.purgeExpired());
          }
          if (!await DirectChatRepository.instance
              .hasExternalStorageChanges()) {
            return;
          }
          _scheduleRecentConversationRestore();
          final peerId = _currentKey.peerId;
          if (peerId.isNotEmpty) {
            await _restoreConversation(_currentKey);
          }
          notifyListeners();
        } catch (_) {}
      },
    );
  }

  void _onStoreRevision() {
    // Keep a recent copy of contacts + chat history in the public folder so
    // a reinstall can restore them.
    DotChatBackup.schedule();
    // Debounce: store revisions can fire rapidly during batch operations.
    // Cancel any pending timer and restart — only the last revision in a
    // 300ms window triggers a restore. This prevents cascading full rebuilds.
    _storeRevisionTimer?.cancel();
    _storeRevisionTimer = Timer(const Duration(milliseconds: 300), () {
      _storeRevisionTimer = null;
      if (_currentKey.peerId.isNotEmpty) {
        unawaited(_restoreConversation(_currentKey));
      }
    });
  }

  Timer? _storeRevisionTimer;
  Timer? _externalChatPollTimer;
  /// 上次执行阅后即焚过期清理的时间（60 秒节流）。
  DateTime? _lastExpiredPurge;

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
    ensureFileHelperEntry();
    // Merge conversations that belong to the same person before building the
    // list so a reinstalled phone never appears as several entries.
    try {
      await DirectChatRepository.instance.mergeSamePersonConversations();
    } catch (_) {}
    final latest = await DirectChatRepository.instance.latestConversations();
    final pairings = DirectPairingStore.load();
    for (final entry in latest.entries) {
      final peerId = entry.key;
      final record = entry.value;
      final pairing = pairings[peerId];
      final key = MessageKey(peerId, clientModeID);
      final body = _messages.putIfAbsent(
        key,
        () => MessageBody(
          ChatUser(
            id: peerId,
            firstName: normalizeDirectPeerName(
              pairing?.displayName ?? '',
              fallback: peerId,
            ),
            profileImage:
                pairing?.avatar.isNotEmpty == true ? pairing!.avatar : null,
          ),
          <ChatMessage>[],
        ),
      );
      if (!record.isOutgoing) {
        final restoredName = normalizeDirectPeerName(
          record.senderName,
          fallback: body.chatUser.firstName ?? peerId,
        );
        // LUODA FIX: never let a corrupted/self-like sender name (e.g. the
        // local username "LUODA") become the conversation title.
        body.chatUser.firstName = _isSelfLikePeerName(restoredName)
            ? (body.chatUser.firstName ?? peerId)
            : restoredName;
        if (record.senderAvatar.isNotEmpty) {
          body.chatUser.profileImage = record.senderAvatar;
        }
      }
      final chatMessage =
          _taggedChatMessage(record, record.isOutgoing ? me : body.chatUser);
      final messageId = chatMessage.customProperties?['ldesk_id']?.toString();
      final existingIndex = messageId == null
          ? -1
          : body.chatMessages.indexWhere(
              (item) =>
                  item.customProperties?['ldesk_id']?.toString() == messageId,
            );
      if (existingIndex < 0) {
        body.chatMessages.add(chatMessage);
        body.chatMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      _scheduleSelfDestruct(
        key,
        record,
        record.isOutgoing ? me : body.chatUser,
      );
    }
    if (latest.isNotEmpty) notifyListeners();
  }

  ChatUser? get currentUser => _messages[_currentKey]?.chatUser;

  /// Built-in 文件助手 conversation key (like WeChat's file helper).
  MessageKey get fileHelperKey => MessageKey(kFileHelperId, clientModeID);

  bool get isFileHelperConversation => _currentKey.peerId == kFileHelperId;

  String _messageSourceTarget(MessageKey key) {
    if (key.peerId.toLowerCase().startsWith('bt:')) return key.peerId;
    final sessionTarget = parent.target?.id.trim() ?? '';
    if (sessionTarget.isNotEmpty) return sessionTarget;
    return DirectPairingStore.resolveConnectionTarget(key.peerId) ?? key.peerId;
  }

  /// Ensures the built-in File Transfer Assistant always exists so it can be
  /// pinned at the top of the conversation list even before the first send.
  void ensureFileHelperEntry() {
    final key = fileHelperKey;
    _messages.putIfAbsent(
      key,
      () => MessageBody(
        ChatUser(
          id: kFileHelperId,
          firstName: translate('File Transfer Assistant'),
        ),
        <ChatMessage>[],
      ),
    );
  }

  /// Local-only send used by the built-in File Transfer Assistant: messages
  /// are persisted and shown in the conversation but never transmitted.
  Future<void> _sendToFileHelper(
    DirectChatKind kind, {
    String text = '',
    String fileName = '',
    int fileSize = 0,
    String fileSha256 = '',
    String localPath = '',
    String inlineBytes = '',
  }) async {
    final key = _currentKey;
    if (key.peerId != kFileHelperId) return;
    _touchChatActivity(kFileHelperId);
    try {
      final record = await DirectChatRepository.instance.createOutgoing(
        conversationId: kFileHelperId,
        recordSource: false,
        kind: kind,
        text: text.isEmpty && kind == DirectChatKind.file
            ? '${translate('Sent file')}: $fileName'
            : text,
        senderId: me.id,
        senderName: me.firstName ?? '',
        senderAvatar: '',
        fileName: fileName,
        fileSize: fileSize,
        fileSha256: fileSha256,
        localPath: localPath,
        inlineBytes: inlineBytes,
      );
      if (record == null) return;
      // 文件助手是本地会话：写入即视为“已送达”，避免一直显示“待发送”。
      await DirectChatRepository.instance
          .markDelivery(record.id, DirectChatDelivery.delivered);
      final delivered = record.copyWith(delivery: DirectChatDelivery.delivered);
      ensureFileHelperEntry();
      insertMessage(fileHelperKey, _taggedChatMessage(delivered, me));
      _scheduleSelfDestruct(fileHelperKey, delivered, me);
      notifyListeners();
      // LUODA: 把文件助手消息同步到已绑定的伴生设备（如手机<->PC），
      // 让对端的文件助手会话也能收到。
      unawaited(syncActiveCompanionSessions());
    } catch (e, st) {
      debugPrint('Failed to persist file-helper message: $e\n$st');
    }
  }

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
    final normalizedName = sanitizeInvalidUtf16(displayName).trim();
    final normalizedAvatar = sanitizeInvalidUtf16(avatar).trim();
    // LUODA FIX: a self-like name (the local username or default "LUODA")
    // must never overwrite a peer's identity.
    final usableName = _isSelfLikePeerName(normalizedName) ? '' : normalizedName;
    final pairing = DirectPairingStore.find(peerId);
    if (pairing != null &&
        (usableName.isNotEmpty && usableName != pairing.displayName ||
            normalizedAvatar.isNotEmpty &&
                normalizedAvatar != pairing.avatar)) {
      unawaited(DirectPairingStore.updateIdentity(
        peerId,
        displayName: normalizedName,
        avatar: normalizedAvatar,
      ));
    }
    var changed = false;
    final body = _messages[MessageKey(peerId, clientModeID)];
    if (body != null) {
      if (usableName.isNotEmpty && body.chatUser.firstName != usableName) {
        body.chatUser.firstName = usableName;
        changed = true;
      }
      final nextProfileImage = normalizedAvatar.isEmpty
          ? body.chatUser.profileImage
          : normalizedAvatar;
      if (body.chatUser.profileImage != nextProfileImage) {
        body.chatUser.profileImage = nextProfileImage;
        changed = true;
      }
      for (final message in body.chatMessages) {
        if (message.user.id != peerId) continue;
        if (usableName.isNotEmpty &&
            message.user.firstName != usableName) {
          message.user.firstName = usableName;
          changed = true;
        }
        if (message.user.profileImage != nextProfileImage) {
          message.user.profileImage = nextProfileImage;
          changed = true;
        }
      }
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
    // Only switch the active conversation key. Never pop up the floating chat
    // window automatically: incoming messages show up in the conversation list
    // with unread badges (mobile) or the chat side panel (desktop) instead.
    if (currentKey != key) {
      changeCurrentKey(key);
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

  /// Returns true when [name] is the local user's own identity or a raw ID
  /// string ? such a name must never be shown as a peer conversation title
  /// (a mis-resolved sender identity used to rename the chat to the local
  /// username "LUODA" after receiving messages).
  bool _isSelfLikePeerName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return true;
    final compact = trimmed.replaceAll(RegExp(r'[\s:\-_.]'), '');
    if (RegExp(r'^[0-9]{3,}$').hasMatch(compact)) return true;
    final localName = me.firstName?.trim() ?? '';
    if (localName.isNotEmpty && trimmed == localName) return true;
    if (trimmed.toLowerCase() == 'luoda') return true;
    return false;
  }

  changeCurrentKey(MessageKey key) {
    if (key.peerId.isNotEmpty) {
      // LUODA FIX: only canonicalize keys that are not already in the
      // in-memory conversation map. List rows hand us the exact key their
      // messages are stored under (canonicalized when each message was
      // received). Re-canonicalizing at open time can map the peer to a
      // different account id after a pairing later gains an account_id
      // (e.g. "980031" -> "423156"), so the chat window reads an empty
      // body ("No messages yet") even though the list shows the preview.
      // Manual id/endpoint entry still canonicalizes because the key is
      // absent from the map (new conversation).
      if (!_messages.containsKey(key)) {
        final conversationId =
            DirectPairingStore.canonicalConversationId(key.peerId);
        if (conversationId != key.peerId) {
          key = MessageKey(conversationId, key.connId);
        }
      }
    }
    if (_currentKey.peerId == key.peerId && _currentKey.connId == key.connId) {
      return;
    }
    // Save draft for current conversation before switching
    if (_currentKey.peerId.isNotEmpty && textController.text.isNotEmpty) {
      _drafts[_currentKey.peerId] = textController.text;
    }
    _replyToMessage = null;
    _isReconnecting = false;
    _reconnectPeerId = '';
    chatSearchVisible = false;
    chatSearchText = '';
    _chatSearchMatchIndex = 0;
    _chatSearchMessageKeys.clear();
    chatSearchController.clear();
    updateConnIdOfKey(key);
    String? peerName;
    String? peerAvatar;
    if (key.connId == clientModeID) {
      // LUODA FIX: client-mode connections must never use the LOCAL profile
      // (pi) as the peer name. Resolve from the pairing store, then a live
      // client, then the existing message body before falling back to the id.
      final pairing = DirectPairingStore.findForConversation(key.peerId);
      peerName = pairing?.displayName.trim().isNotEmpty == true
          ? pairing!.displayName.trim()
          : '';
      if (peerName.isEmpty || _isSelfLikePeerName(peerName)) {
        final client = parent.target?.serverModel.clients
            .firstWhereOrNull((client) => client.peerId == key.peerId);
        peerName = (client?.name ?? '').trim();
        if (peerName.isEmpty || _isSelfLikePeerName(peerName)) {
          peerName = _messages[key]?.chatUser.firstName ?? '';
          if (peerName.isEmpty || _isSelfLikePeerName(peerName)) {
            peerName = '';
          }
        }
      }
      peerAvatar = pairing?.avatar.isNotEmpty == true
          ? pairing!.avatar
          : _messages[key]?.chatUser.profileImage;
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
    if (!_conversationRecords.containsKey(key.peerId)) {
      unawaited(_restoreConversation(key));
    }
  }

  /// 中继桥回调用：把经蓝牙网关转发来的信封作为普通消息接收。
  Future<void> receiveRelayedEnvelope(
    String envelopeLine, {
    String? conversationId,
  }) {
    return receive(
      clientModeID,
      envelopeLine,
      conversationId: conversationId,
      showChat: false,
    );
  }

  /// 中继桥回调用：网关用本机网络把原信封发给目标会话。
  /// 返回是否成功交给发送通道。
  Future<bool> sendWireRelayed(String peerId, String envelopeLine) async {
    final key = MessageKey(peerId, clientModeID);
    // 中继转发必须走本机「非蓝牙」通道，避免再次回到蓝牙中继形成环路。
    return _sendWireNonBluetooth(key, envelopeLine);
  }

  receive(int id, String rawText,
      {String? conversationId, bool showChat = true}) async {
    RuntimeLogger.instance.info(
        'CHAT-RX', 'enter id=$id len=${rawText.length} conv=$conversationId');
    final session = parent.target;
    if (session == null) {
      debugPrint("Failed to receive msg, session state is null");
      return;
    }
    if (rawText.isEmpty) return;
    // 网络通道收到的 relay 信封（外网设备 → 本网关 → 蓝牙端设备）先交给
    // 中继桥：目标若是本机蓝牙端设备则经 RFCOMM 转交，否则按本机消息处理。
    if (RelayBridge.isRelayLine(rawText)) {
      final consumed = await RelayBridge.instance.handleNetworkLine(rawText);
      if (consumed) return;
    }
    // Ignore messages from self to prevent echo loops and freezes.
    String? peerId;
    final client = id == clientModeID
        ? null
        : session.serverModel.clients
            .firstWhereOrNull((client) => client.id == id);
    if (id == clientModeID) {
      peerId = (conversationId != null && conversationId.isNotEmpty)
          ? conversationId
          : (_currentKey.peerId.isNotEmpty ? _currentKey.peerId : session.id);
    } else {
      peerId = client?.peerId;
    }
    // Decode the envelope before keying the conversation: an incoming direct
    // message carries the origin device id, which is the correct conversation
    // key on this side. Relying only on the transient session id or the
    // current chat made incoming messages land in the wrong conversation
    // (invisible until the user manually switched chats).
    String envelopeOriginId = '';
    final envelope = DirectChatEnvelope.decode(rawText);
    RuntimeLogger.instance
        .info('CHAT-RX', 'envelope type=${envelope?.type} peerId=$peerId');
    // A DotChat envelope that cannot be decoded must never be persisted as
    // raw text: it would create a garbage conversation whose preview shows
    // the base64 payload instead of the real message.
    if (rawText.startsWith(DirectChatEnvelope.prefix) && envelope == null) {
      RuntimeLogger.instance
          .info('CHAT-RX', 'drop undecodable dotchat envelope');
      return;
    }
    if (envelope != null && envelope.type == 'message') {
      // Envelope data is record.toJson() (snake_case keys, see
      // DirectChatEnvelope.message). Reading the camelCase key here made
      // origin always empty and incoming messages landed under an empty
      // conversation key, invisible until the user re-opened the chat.
      envelopeOriginId = (envelope.data['origin_device_id'] ??
              envelope.data['originDeviceId'] ??
              '')
          .toString()
          .trim();
      if (envelopeOriginId.isNotEmpty) {
        // LUODA: key the conversation by the SENDER's stable identity, not
        // by the sender's embedded conversation_id (that id is the key on the
        // SENDER's device and often equals the RECEIVER's own DotChat id,
        // e.g. "225960", which made incoming messages land in the wrong or a
        // self conversation). canonicalConversationId() then merges devices
        // of the same person into one account conversation.
        final senderDialId =
            (envelope.data['sender_dial_id'] ?? '').toString().trim();
        final fromClientPeer = (client?.peerId ?? '').trim();
        final senderIdentity = senderDialId.isNotEmpty && senderDialId != me.id
            ? senderDialId
            : (fromClientPeer.isNotEmpty && fromClientPeer != me.id
                ? fromClientPeer
                : '');
        if (senderIdentity.isNotEmpty) {
          peerId = senderIdentity;
        } else {
          // Legacy senders: keep the person-account conversation they
          // addressed when it is not our own id, otherwise reuse the key the
          // first pass assigned or the sender device id.
          final accountConversation =
              DirectPairingStore.stableAccountConversationId(
            (envelope.data['conversation_id'] ?? '').toString(),
          );
          final ownDialId = (session.id ?? '').trim();
          if (accountConversation.isNotEmpty &&
              accountConversation != me.id &&
              accountConversation != ownDialId) {
            peerId = accountConversation;
          } else if (peerId == null || peerId.isEmpty || peerId == me.id) {
            final stable = await _stablePeerIdForEnvelope(
              client: client,
              envelope: envelope,
            );
            peerId = stable.isNotEmpty ? stable : envelopeOriginId;
          }
        }
      }
    }
    if (peerId == null || peerId == me.id) {
      RuntimeLogger.instance
          .info('CHAT-RX', 'drop self/empty peerId=$peerId me=${me.id}');
      return; // self-message: already displayed by send()
    }

    final wasIpSource =
        DirectPairingStore.extractDirectEndpoint(peerId).isNotEmpty;
    // A Bluetooth wire message may be the first time this side learns the
    // sender's real identity (sender_dial_id). Capture the bt: conversation
    // before it is canonicalized away so the Bluetooth pairing can be linked
    // to the person account below (one contact row instead of two).
    final btConversation = (conversationId ?? '').trim().toLowerCase();
    final isBtMessage = envelope != null &&
        envelope.type == 'message' &&
        btConversation.startsWith('bt:');
    peerId = DirectPairingStore.canonicalConversationId(peerId);
    // Link the sender's device and live incoming clients to the person
    // account so replies can be routed back even before a full pairing
    // record (endpoint + fingerprint) exists for this phone.
    if (envelope != null && envelope.type == 'message') {
      final accountConversation =
          DirectPairingStore.stableAccountConversationId(peerId);
      if (accountConversation.isNotEmpty) {
        final envelopeDialId =
            (envelope.data['sender_dial_id'] ?? '').toString().trim();
        final livePeerId = envelopeDialId.isNotEmpty
            ? envelopeDialId
            : (client != null
                ? client.peerId
                : (id == clientModeID ? session.id : ''));
        await _rememberIncomingPersonDevice(
          accountConversation: accountConversation,
          originDeviceId: envelopeOriginId,
          livePeerId: livePeerId,
          senderName: (envelope.data['sender_name'] ?? '').toString(),
          srcPlatform: (envelope.data['src_platform'] ?? '').toString(),
        );
        if (isBtMessage) {
          // The Bluetooth peer revealed its person account: bind the bt:<mac>
          // pairing to it so the contact list merges the Bluetooth row with
          // the same device's network row (the "same customer twice" bug).
          unawaited(DirectPairingStore.linkBluetoothPeer(
            conversationId ?? '',
            accountConversation,
            displayName:
                (envelope.data['sender_name'] ?? '').toString().trim(),
          ));
        }
      }
    }

    final messagekey = MessageKey(peerId, id);
    if (envelope != null && envelope.type != 'message') {
      await _handleEnvelope(messagekey, envelope);
      return;
    }
    // A peer the user blocked ("no longer receive") must not land here:
    // drop its messages before they are persisted or trigger any UI.
    if (gFFI.chatSettingsModel.isBlocked(peerId)) {
      RuntimeLogger.instance
          .info('CHAT-RX', 'drop blocked message peerId=$peerId');
      return;
    }
    _touchChatActivity(peerId);

    late final ChatUser chatUser;
    if (id == clientModeID) {
      // LUODA FIX: never use the LOCAL profile (session.ffiModel.pi) as the
      // sender's name ? that renamed the conversation to the local username
      // ("LUODA") after receiving messages. Prefer the envelope's sender name,
      // then a live client matching the conversation, then the existing
      // message body, and only then fall back to the peer id.
      String? senderName;
      final envelopeSender =
          (envelope?.data['sender_name'] ?? '').toString().trim();
      if (envelopeSender.isNotEmpty &&
          !_isSelfLikePeerName(envelopeSender)) {
        senderName = envelopeSender;
      } else {
        final clientMatch = parent.target?.serverModel.clients
            .firstWhereOrNull((client) => client.peerId == peerId);
        final clientName = (clientMatch?.name ?? '').trim();
        if (clientName.isNotEmpty && !_isSelfLikePeerName(clientName)) {
          senderName = clientName;
        }
      }
      if (senderName == null || senderName.isEmpty) {
        final existing =
            _messages[MessageKey(peerId, id)]?.chatUser.firstName ?? '';
        if (existing.trim().isNotEmpty && !_isSelfLikePeerName(existing)) {
          senderName = existing.trim();
        }
      }
      final fallbackName =
          (senderName == null || senderName.isEmpty) ? peerId : senderName!;
      chatUser = ChatUser(
        firstName: fallbackName,
        profileImage:
            _messages[MessageKey(peerId, id)]?.chatUser.profileImage,
        id: peerId,
      );
    } else {
      if (client == null) {
        debugPrint("Failed to receive msg, client is null");
        return;
      }
      chatUser = ChatUser(
        id: peerId,
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
          RuntimeLogger.instance.info('CHAT-RX',
              'drop invalid record id=${incoming.id} origin=${incoming.originDeviceId} seq=${incoming.originSequence}');
          return;
        }
        record = incoming.copyWith(
          conversationId: peerId,
          senderName: normalizeDirectPeerName(
            incoming.senderName,
            fallback: chatUser.firstName ?? peerId,
          ),
          direction: DirectChatDirection.incoming,
          delivery: DirectChatDelivery.delivered,
          connMode: incoming.connMode.isNotEmpty
              ? incoming.connMode
              : DirectPairingStore.classifyConnMode(peerId),
          connPort: incoming.connPort > 0
              ? incoming.connPort
              : DirectPairingStore.connPortOf(peerId),
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
      } catch (error) {
        RuntimeLogger.instance.info('CHAT-RX', 'fromJson failed: $error');
        return;
      }
      final upserted = await DirectChatRepository.instance.upsert(record);
      RuntimeLogger.instance.info('CHAT-RX',
          'upserted=$upserted id=${record.id} conv=${record.conversationId}');
      // Merge a stale conversation keyed by the sender's device UUID (created
      // by older builds / the Android DirectChatService) into the DotChat-id
      // conversation so replies can dial the peer and one person never shows
      // as two conversations.
      final rxOrigin = (envelope.data['origin_device_id'] ??
              envelope.data['originDeviceId'] ??
              '')
          .toString()
          .trim();
      if (rxOrigin.isNotEmpty && rxOrigin != record.conversationId) {
        await DirectChatRepository.instance
            .remapConversation(rxOrigin, record.conversationId);
        // Drop the stale in-memory row so the recent list stops showing the
        // same person twice; its messages now live under the DotChat-id key.
        final staleKeys = _messages.keys
            .where((key) => key.peerId == rxOrigin)
            .toList(growable: false);
        for (final stale in staleKeys) {
          _messages.remove(stale);
        }
        if (_currentKey.peerId == rxOrigin) {
          _currentKey = MessageKey(record.conversationId, _currentKey.connId);
        }
        _scheduleRecentConversationRestore();
        notifyListeners();
      }
      // Same-person merge: a device that reinstalled the app gets a new id,
      // so this message may have landed in a conversation the user is not
      // looking at. Merge all same-person conversations into the primary one
      // and follow the remap in memory so the message is visible immediately.
      try {
        final personRemap =
            await DirectChatRepository.instance.mergeSamePersonConversations();
        if (personRemap.isNotEmpty) {
          for (final entry in personRemap.entries) {
            final oldBodyKeys = _messages.keys
                .where((key) => key.peerId == entry.key)
                .toList(growable: false);
            for (final oldKey in oldBodyKeys) {
              final oldBody = _messages.remove(oldKey);
              if (oldBody == null) continue;
              final newKey = MessageKey(entry.value, oldKey.connId);
              if (!_messages.containsKey(newKey)) {
                _messages[newKey] = MessageBody(oldBody.chatUser, []);
              }
              _messages[newKey]!.chatMessages.addAll(oldBody.chatMessages);
            }
          }
          if (personRemap.containsKey(_currentKey.peerId)) {
            _currentKey = MessageKey(
                personRemap[_currentKey.peerId]!, _currentKey.connId);
          }
          _scheduleRecentConversationRestore();
          notifyListeners();
        }
      } catch (_) {}
      _sendWire(messagekey, DirectChatEnvelope.receipt(record.id).encode());
      // Note: the same envelope is delivered twice (chat_server_mode with the
      // connection id, then chat_client_mode with clientModeID). The second
      // upsert returns false, but we must still populate the in-memory
      // conversation so the recent list updates without a manual refresh.
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
      insertMessage(messagekey,
          _taggedChatMessage(record, chatUser, wasIpSource: wasIpSource));
      notifyListeners();
      return;
    }
    // LUODA: incoming chat stays silent — do not pop up the CM window here.

    // show chat page (no floating overlay on mobile)
    if (showChat) await showChatPage(messagekey);
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
        if (!client.isChat) {
          windowOnTop(null);
          final tabs = session.serverModel.tabController.state.value.tabs;
          if (tabs.isNotEmpty) {
            // Mark unread without indexing an empty connection-manager tab list.
            final currentSelectedTab =
                session.serverModel.tabController.state.value.selectedTabInfo;
            if (currentSelectedTab.key != id.toString() && inputNode.hasFocus) {
              client.unreadChatMessageCount.value += 1;
            } else {
              parent.target?.serverModel.jumpTo(id);
            }
          }
        }
      } else {
        if (HomePage.homeKey.currentState?.isChatPageCurrentTab != true ||
            _currentKey != messagekey) {
          client.unreadChatMessageCount.value += 1;
          mobileUpdateUnreadSum();
        }
      }
    }
    insertMessage(messagekey,
        _taggedChatMessage(record, chatUser, wasIpSource: wasIpSource));
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
      // Strip trigger keywords so the image prompt is clean
      const imageTriggers = [
        '画',
        '图片',
        '图像',
        '生成图片',
        '绘',
        'draw',
        'image',
        'picture',
        'generate',
        'create',
        '生成'
      ];
      var cleanQuery = query;
      for (final kw in imageTriggers) {
        final asciiKeyword =
            RegExp(r'^[a-z]+$', caseSensitive: false).hasMatch(kw);
        final pattern = asciiKeyword
            ? r'\b' + RegExp.escape(kw) + r'\b'
            : RegExp.escape(kw);
        cleanQuery = cleanQuery.replaceAll(
          RegExp(pattern, caseSensitive: false),
          '',
        );
      }
      cleanQuery = cleanQuery.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleanQuery.isEmpty) cleanQuery = query; // fallback
      final localPath = await AiImageService.generate(cleanQuery);
      if (localPath == null || localPath.isEmpty) {
        throw Exception('No image returned');
      }

      // Remove progress message
      _messages[key]?.chatMessages.remove(step1);

      // Insert generated image as a file message
      final fileName = 'ai_${DateTime.now().millisecondsSinceEpoch}.png';
      final fileSize = File(localPath).lengthSync();
      final record = await DirectChatRepository.instance.createOutgoing(
        conversationId: key.peerId,
        connectionTarget: _messageSourceTarget(key),
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
      insertMessage(key, _taggedChatMessage(record, me));
      await _transmitRecord(key, record);
      notifyListeners();
    } catch (e) {
      debugPrint('Image generation failed: $e');
      _messages[key]?.chatMessages.remove(step1);
      final failMsg = ChatMessage(
        text: translate('Image generation failed'),
        user: me,
        createdAt: DateTime.now(),
        customProperties: {'ldesk_ai_reply': 'true', 'ldesk_ai_system': 'true'},
      );
      insertMessage(key, failMsg);
      notifyListeners();
    }
  }

  /// Handle "#" email export intent by opening a real email draft.
  Future<void> _handleEmailExport() async {
    final email = AiConfig.current.email;
    final key = _currentKey;

    final progress = ChatMessage(
      text: translate('Preparing email...'),
      user: me,
      createdAt: DateTime.now(),
      customProperties: {'ldesk_ai_reply': 'true', 'ldesk_ai_system': 'true'},
    );
    insertMessage(key, progress);
    notifyListeners();

    try {
      final messages = (_messages[key]?.chatMessages ?? const <ChatMessage>[])
          .where((message) => !identical(message, progress))
          .take(20)
          .toList(growable: false)
          .reversed
          .map(
            (message) => EmailDraftMessage(
              sender: message.user.firstName ?? message.user.id,
              sentAt: message.createdAt,
              text: message.text,
              fileName: (message.customProperties?['ldesk_file_name'] ?? '')
                  .toString(),
            ),
          )
          .toList(growable: false);
      final content = EmailDraftService.formatMessages(
        messages,
        fileLabel: translate('File'),
      );
      final opened = await EmailDraftService.openDraft(
        recipient: email,
        subject: translate('Chat messages'),
        body: content,
      );
      _messages[key]?.chatMessages.remove(progress);
      final result = ChatMessage(
        text: opened
            ? '${translate("Email draft opened")}: $email'
            : translate('Unable to open email client'),
        user: me,
        createdAt: DateTime.now(),
        customProperties: {'ldesk_ai_reply': 'true', 'ldesk_ai_system': 'true'},
      );
      insertMessage(key, result);
      notifyListeners();
    } catch (e) {
      debugPrint('Email export failed: $e');
      _messages[key]?.chatMessages.remove(progress);
      final failMsg = ChatMessage(
        text: translate('Export failed'),
        user: me,
        createdAt: DateTime.now(),
        customProperties: {'ldesk_ai_reply': 'true', 'ldesk_ai_system': 'true'},
      );
      insertMessage(key, failMsg);
      notifyListeners();
    }
  }

  Future<void> _sendMessage(ChatMessage message) async {
    final rawText = sanitizeInvalidUtf16(message.text).trim();
    if (rawText.isEmpty) {
      return;
    }
    // 文件助手：文字只保存本地，不走网络。
    if (_currentKey.peerId == kFileHelperId) {
      await _sendToFileHelper(DirectChatKind.text, text: rawText);
      return;
    }

    // # command: AI image, email export, or normal AI chat
    if (rawText.startsWith('#')) {
      final aiQuery = rawText.substring(1).trim();
      if (aiQuery.isNotEmpty) {
        // --- AI Image generation intent ---
        const imageKeywords = [
          '画',
          '图片',
          '图像',
          '生成图片',
          '绘',
          'draw',
          'image',
          'picture',
          'generate',
          'create'
        ];
        final isImageIntent =
            imageKeywords.any((kw) => aiQuery.toLowerCase().contains(kw));
        if (isImageIntent) {
          unawaited(_handleImageGeneration(aiQuery));
          inputNode.requestFocus();
          return;
        }

        // --- Email export intent detection ---
        final email = AiConfig.current.email;
        final hasValidEmail = email.isNotEmpty &&
            RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
        const exportKeywords = [
          '邮箱',
          '邮件',
          '导出',
          '保存',
          '发送到',
          'email',
          'mail',
          'export',
          'save'
        ];
        final isExportIntent = hasValidEmail &&
            exportKeywords.any((kw) => aiQuery.toLowerCase().contains(kw));
        if (isExportIntent) {
          unawaited(_handleEmailExport());
          inputNode.requestFocus();
          return;
        }
        // --- Normal AI chat ---
        if (AiConfig.current.enabled) {
          final key = _currentKey;
          // Show a local placeholder while AI is thinking
          final placeholder = ChatMessage(
            text: '${translate("AI thinking")}...',
            user: me,
            createdAt: DateTime.now(),
            customProperties: {
              'ldesk_ai_reply': 'true',
              'ldesk_ai_loading': 'true'
            },
          );
          insertMessage(key, placeholder);
          notifyListeners();

          final reply = await AiService.chat(aiQuery);
          if (reply != null && reply.isNotEmpty) {
            _messages[key]?.chatMessages.remove(placeholder);
            final record = await DirectChatRepository.instance.createOutgoing(
              conversationId: key.peerId,
              connectionTarget: _messageSourceTarget(key),
              kind: DirectChatKind.text,
              text: reply,
              senderId: me.id,
              senderName: me.firstName ?? '',
              senderAvatar: '',
            );
            // Create chat message with AI reply marker
            var aiMsg = _taggedChatMessage(record, me);
            aiMsg.customProperties ??= <String, dynamic>{};
            aiMsg.customProperties!['ldesk_ai_reply'] = 'true';
            insertMessage(key, aiMsg);
            await _transmitRecord(key, record);
            notifyListeners();
          } else {
            _messages[key]?.chatMessages.remove(placeholder);
            insertMessage(
              key,
              ChatMessage(
                text: translate('AI request failed'),
                user: me,
                createdAt: DateTime.now(),
                customProperties: const <String, dynamic>{
                  'ldesk_ai_reply': 'true',
                  'ldesk_ai_system': 'true',
                },
              ),
            );
            notifyListeners();
          }
          inputNode.requestFocus();
          return;
        }
        // If AI not configured and not export, fall through to send raw
      }
    }

    // Normal message send — both for non-# text AND #-prefixed
    // text that wasn't handled by the AI/image/export paths above.
    {
      final trimmedText = rawText;
      final key = _currentKey;
      if (key.peerId.isEmpty) return;
      _touchChatActivity(key.peerId);
      final replyId =
          (_replyToMessage?.customProperties?['ldesk_id'] ?? '').toString();
      final replySender = _replyToMessage == null
          ? ''
          : (_replyToMessage!.user.firstName ?? _replyToMessage!.user.id);
      final replyText = _replyToMessage?.text ?? '';
      DirectChatRecord? record;
      try {
        record = await DirectChatRepository.instance.createOutgoing(
          conversationId: key.peerId,
          connectionTarget: _messageSourceTarget(key),
          kind: DirectChatKind.text,
          text: trimmedText,
          senderId: me.id,
          senderName: me.firstName ?? '',
          senderAvatar: '',
          replyToId: replyId,
          replyToSender: replySender,
          replyToText: replyText.length > 80
              ? '${replyText.substring(0, 80)}...'
              : replyText,
        );
      } catch (e, st) {
        debugPrint('Failed to persist outgoing chat message: $e\n$st');
      }
      _replyToMessage = null;
      // Clear draft after send
      _drafts.remove(key.peerId);
      if (record != null) {
        insertMessage(key, _taggedChatMessage(record, me));
        _scheduleSelfDestruct(key, record, me);
        try {
          await _transmitRecord(key, record);
        } catch (e, st) {
          debugPrint('Failed to transmit outgoing chat message: $e\n$st');
        }
      } else {
        // Persistence failed — synthesize a transient queued record so the
        // message still shows up locally with a failed delivery state. The
        // user can then see they sent it and decide to retry.
        final tmp = DirectChatRecord(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          conversationId: key.peerId,
          originDeviceId: me.id,
          originSequence: 0,
          direction: DirectChatDirection.outgoing,
          kind: DirectChatKind.text,
          text: trimmedText,
          senderId: me.id,
          senderName: me.firstName ?? '',
          senderAvatar: '',
          sentAt: DateTime.now().toUtc(),
          delivery: DirectChatDelivery.failed,
          connMode: DirectPairingStore.classifyConnMode(
            _messageSourceTarget(key),
          ),
          connEndpoint: DirectPairingStore.connEndpointOf(
            _messageSourceTarget(key),
          ),
          connPort: DirectPairingStore.connPortOf(_messageSourceTarget(key)),
          srcPlatform: directChatPlatformLabel,
          replyToId: replyId,
          replyToText: replyText.length > 80
              ? '${replyText.substring(0, 80)}...'
              : replyText,
        );
        insertMessage(key, _taggedChatMessage(tmp, me));
      }

      // Always notify so the UI rebuilds and shows the bubble, even on
      // persistence / transmission failure.
      notifyListeners();
      inputNode.requestFocus();
    }
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

  Future<void> sendTextAndWait(String text) {
    return _sendMessage(
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
    insertMessage(key, _taggedChatMessage(updated, me));
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
    insertMessage(key, _taggedChatMessage(queued, me));
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
    insertMessage(key, _taggedChatMessage(updated, me));
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
          insertMessage(key, _taggedChatMessage(destroyed, user));
          await _transmitRecord(key, destroyed);
        } else {
          insertMessage(
            key,
            _taggedChatMessage(
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
    // 文件助手：复制到本地专用目录后只保存记录。
    if (key.peerId == kFileHelperId) {
      String inlineBytes = '';
      if (localPath.isNotEmpty && canInlineDirectChatFile(fileSize)) {
        try {
          final bytes = await File(localPath).readAsBytes();
          if (bytes.length <= kMaxInlineChatFileBytes) {
            inlineBytes = base64Encode(bytes);
          }
        } catch (_) {
          inlineBytes = '';
        }
      }
      var helperPath = localPath;
      if (helperPath.isNotEmpty) {
        final copied = await saveFileHelperFile(fileName, helperPath);
        if (copied != null) helperPath = copied;
      }
      await _sendToFileHelper(
        DirectChatKind.file,
        fileName: fileName,
        fileSize: fileSize,
        fileSha256: fileSha256,
        localPath: helperPath,
        inlineBytes: inlineBytes,
      );
      return;
    }
    _touchChatActivity(key.peerId);
    // LUODA FIX: inline small file/image bytes into the chat message so the
    // receiver can preview/open them without a separate file-transfer session.
    String inlineBytes = '';
    if (localPath.isNotEmpty && canInlineDirectChatFile(fileSize)) {
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
      connectionTarget: _messageSourceTarget(key),
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
    insertMessage(key, _taggedChatMessage(record, me));
    await _transmitRecord(key, record);
    notifyListeners();
  }

  Future<void> sendForwardBundle({
    required String title,
    required List<DirectChatForwardItem> items,
  }) async {
    final key = _currentKey;
    if (key.peerId.isEmpty || items.isEmpty) return;
    _touchChatActivity(key.peerId);
    final record = await DirectChatRepository.instance.createOutgoing(
      conversationId: key.peerId,
      connectionTarget: _messageSourceTarget(key),
      kind: DirectChatKind.forward,
      text: translate('Chat history'),
      senderId: me.id,
      senderName: me.firstName ?? '',
      senderAvatar: '',
      forwardTitle: title,
      forwardItems: items,
    );
    insertMessage(key, _taggedChatMessage(record, me));
    await _transmitRecord(key, record);
    notifyListeners();
  }

  Future<void> onDirectSessionReady({
    String? peerId,
    int? connId,
  }) async {
    final rawPeerId =
        peerId?.trim().isNotEmpty == true ? peerId!.trim() : _currentKey.peerId;
    final resolvedPeerId =
        DirectPairingStore.canonicalConversationId(rawPeerId);
    if (resolvedPeerId.isEmpty) return;
    _touchChatActivity(resolvedPeerId);
    await _refreshCmLiveChatConnId(resolvedPeerId);
    final key = MessageKey(
      resolvedPeerId,
      connId ?? _currentKey.connId,
    );
    changeCurrentKey(key);
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

  Future<void> refreshCurrentConversationFromStorage() async {
    if (_currentKey.peerId.isEmpty) return;
    await _restoreConversation(_currentKey);
  }

  /// Reload recent conversations from the persisted store and rebuild the
  /// UI. Called when the app returns to the foreground so messages persisted
  /// by the background service appear immediately (no 2-4s poll wait).
  Future<void> refreshRecentFromStorage() {
    _scheduleRecentConversationRestore();
    final peerId = _currentKey.peerId;
    if (peerId.isNotEmpty) {
      unawaited(_restoreConversation(_currentKey));
    }
    notifyListeners();
    return _recentRestoreTask ?? Future<void>.value();
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
      connectionTarget: _messageSourceTarget(key),
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
    insertMessage(key, _taggedChatMessage(record, me));
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
            insertMessage(key, _taggedChatMessage(record, me));
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
          _rememberCompanionDevice(key);
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
            'policies': DirectChatAccessController.instance.toSyncJson(),
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
          // LUODA: surface companion-synced records in memory right away so
          // the recent list / open chat refresh without waiting for the poll.
          final targetId = record.conversationId.trim().isNotEmpty
              ? record.conversationId
              : key.peerId;
          if (targetId.isNotEmpty) {
            final targetKey = targetId == kFileHelperId
                ? fileHelperKey
                : MessageKey(targetId, key.connId);
            final user = record.isOutgoing
                ? me
                : (_messages[targetKey]?.chatUser ??
                    ChatUser(id: targetId, firstName: record.senderName));
            insertMessage(targetKey, _taggedChatMessage(record, user));
            notifyListeners();
            if (!record.isOutgoing) {
              _maybeNotifyIncoming(record, targetId);
            }
          }
        } catch (_) {}
        return;
      case 'replica_contacts':
        final secret = (envelope.data['secret'] ?? '').toString();
        if (!DirectPairingStore.acceptsCompanionSecret(secret)) return;
        await DirectPairingStore.mergeContacts(
          envelope.data['contacts'] as List<dynamic>? ?? const [],
        );
        final policies = envelope.data['policies'];
        if (policies is Map) {
          await DirectChatAccessController.instance.mergeSyncData(
            Map<String, dynamic>.from(policies),
          );
        }
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
          id,
          emoji,
          deviceId,
        );
        if (reacted != null) {
          final user = _messages[key]?.chatUser;
          if (user != null) {
            insertMessage(key, _taggedChatMessage(reacted, user));
            notifyListeners();
          }
        }
        return;
      case 'edit':
        final editId = (envelope.data['id'] ?? '').toString();
        final newText = (envelope.data['text'] ?? '').toString();
        if (editId.isEmpty || newText.isEmpty) return;
        final edited = await DirectChatRepository.instance.editText(
          editId,
          newText,
        );
        if (edited != null) {
          final user = _messages[key]?.chatUser ?? me;
          insertMessage(key, _taggedChatMessage(edited, user));
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
    // LUODA: ensure a live chat session exists before marking the message as
    // sent. Opening a conversation from the recent list never established the
    // session, so messages were optimistically marked "sent" and silently
    // dropped (the "A rejects messages / never received" bug).
    final ensure = ensureChatConnection;
    await _refreshCmLiveChatConnId(key.peerId);
    if (ensure != null && !_hasLiveChatSession(key)) {
      await ensure(key.peerId, force: true);
      // LUODA: dialing may tear down the global session and leave the current
      // key empty; keep the sending conversation stable so the UI and any
      // follow-up writes stay on the conversation the user actually opened.
      await _refreshCmLiveChatConnId(key.peerId);
      if (_currentKey.peerId.isEmpty) {
        _currentKey = key;
      }
    }
    String senderDialId = '';
    try {
      senderDialId = (await bind.mainGetMyId()).trim();
    } catch (_) {}
    final sent = _sendWire(
      key,
      DirectChatEnvelope.message(record, senderDialId: senderDialId).encode(),
    );
    if (sent) {
      _touchChatActivity(key.peerId);
    } else {
      unawaited(ensureChatConnection?.call(key.peerId, force: true));
    }
    if (sent && record.delivery != DirectChatDelivery.delivered) {
      final updated = record.copyWith(delivery: DirectChatDelivery.sent);
      await DirectChatRepository.instance
          .markDelivery(record.id, updated.delivery);
      insertMessage(key, _taggedChatMessage(updated, me));
      notifyListeners();
      _scheduleDeliveryWatchdog(key, updated);
    }
  }

  /// 补发某会话中所有尚未送达（delivered）的待发消息。
  /// 在会话重建 / 保活重连成功后调用，避免“对端重启或掉线期间的消息滞留”。
  Future<void> flushPendingOutgoing(String peerId) async {
    if (peerId.isEmpty) return;
    if (!_flushingPeers.add(peerId)) return;
    try {
      final pending = await DirectChatRepository.instance.pendingFor(peerId);
      if (pending.isEmpty) return;
      final ffi = parent.target;
      if (ffi == null || ffi.closed) return;
      await _refreshCmLiveChatConnId(peerId);
      final incoming = ffi.serverModel.clients.firstWhereOrNull(
        (client) =>
            client.peerId.trim() == peerId &&
            client.authorized &&
            client.isChat &&
            !client.disconnected,
      );
      final cmConnId = _hasCmLiveChatClient(peerId) ? _cmLiveChatConnId : 0;
      final key = MessageKey(
        peerId,
        incoming != null
            ? incoming.id
            : (cmConnId > 0 ? cmConnId : ChatModel.clientModeID),
      );
      if ((incoming != null || cmConnId > 0) && currentKey != key) {
        changeCurrentKey(key);
      }
      for (final record in pending) {
        if (record.delivery == DirectChatDelivery.delivered) continue;
        await _transmitRecord(key, record);
      }
    } finally {
      _flushingPeers.remove(peerId);
    }
  }

  /// 发送后启动送达看门狗：若一段时间内未收到回执，说明直连已断，
  /// 强制重建会话并重发；重试多次仍无回执则标记为发送失败。
  void _scheduleDeliveryWatchdog(MessageKey key, DirectChatRecord record) {
    _deliveryWatchdogs[record.id]?.cancel();
    final timer = Timer(const Duration(seconds: 10), () async {
      _deliveryWatchdogs.remove(record.id);
      final current = await DirectChatRepository.instance.find(record.id);
      if (current == null ||
          !current.isOutgoing ||
          current.delivery == DirectChatDelivery.delivered) {
        _deliveryWatchdogRetries.remove(record.id);
        return;
      }
      final retries = (_deliveryWatchdogRetries[record.id] ?? 0) + 1;
      if (retries >= 36) {
        _deliveryWatchdogRetries.remove(record.id);
        await DirectChatRepository.instance
            .markDelivery(record.id, DirectChatDelivery.failed);
        final failed = current.copyWith(delivery: DirectChatDelivery.failed);
        insertMessage(key, _taggedChatMessage(failed, me));
        notifyListeners();
        return;
      }
      _deliveryWatchdogRetries[record.id] = retries;
      if (retries >= 2) {
        // The peer is not acknowledging even though the local session still
        // reports "live" (stale socket after the peer's connection manager
        // restarted or the network dropped). Tear the session down so the
        // next dial is a real re-dial instead of writing into a dead socket.
        // Otherwise messages stay stuck at "sent" until the app is restarted
        // (the "messages stop being delivered after a few" bug).
        try {
          final ffi = parent.target;
          if (ffi != null &&
              !ffi.closed &&
              ffi.connType == ConnType.chat &&
              ffi.chatModel.currentKey.peerId == key.peerId) {
            ffi.suppressConnectionDialogs = true;
            await ffi.close();
          } else {
            // Phone / main-window hosts the peer as an incoming chat client,
            // not as an FFI chat session. The stale client socket must be
            // closed too, otherwise every retry writes into the dead channel
            // and the message never gets re-delivered ("sent" forever).
            final staleClient = _liveChatClientForPeer(key.peerId);
            if (staleClient != null) {
              debugPrint('[SEND_WIRE] watchdog closing stale client connId=' +
                  staleClient.id.toString() +
                  ' peer=' +
                  key.peerId);
              // cmCloseConnection triggers the Rust on_client_remove event,
              // which removes the client from serverModel.clients.
              unawaited(bind.cmCloseConnection(connId: staleClient.id));
            }
          }
        } catch (error, stackTrace) {
          debugPrint(
              'Failed to tear down stale chat session: $error\n$stackTrace');
        }
      }
      final hasTarget =
          DirectPairingStore.resolveConnectionTarget(key.peerId) != null;
      if (hasTarget) {
        // Re-dial even when the FFI is currently closed: ensureChatConnection
        // restarts the session from scratch and the peer may only now be back
        // online (e.g. it rebooted and re-registered with the rendezvous).
        await ensureChatConnection?.call(key.peerId, force: true);
      }
      await _transmitRecord(key, current);
    });
    _deliveryWatchdogs[record.id] = timer;
  }

  Future<bool> hasPendingOutgoing(String peerId) async {
    final pending = await DirectChatRepository.instance.pendingFor(peerId);
    return pending.isNotEmpty;
  }

  Future<String?> firstPendingPeerId() async {
    final ids = await DirectChatRepository.instance.conversationIds();
    for (final id in ids) {
      final pending = await DirectChatRepository.instance.pendingFor(id);
      if (pending.isNotEmpty) return id;
    }
    return null;
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

  /// 本机（PC）被手机扫码绑定后，手机首次以伴生会话连入时记录绑定信息，
  /// 供“直连绑定手机”界面展示已绑定手机、并阻止重复绑定其它手机。
  void _rememberCompanionDevice(MessageKey key) {
    final serverModel = parent.target?.serverModel;
    if (serverModel == null) return;
    final client = serverModel.clients.firstWhereOrNull(
      (c) => c.peerId.trim() == key.peerId && c.authorized && c.isChat,
    );
    if (client == null) return;
    unawaited(DirectPairingStore.rememberBoundPhone(
      peerId: key.peerId,
      displayName: client.name,
    ));
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

  /// Resolves the stable conversation id for an incoming DotChat envelope.
  /// The live connection's [Client] knows the sender's DotChat id (the key
  /// every reply path compares against). When the connection is already gone
  /// (e.g. the duplicate client-mode delivery), reuse the conversation id
  /// that the first pass already assigned to this record so the two
  /// deliveries never split the conversation.
  Future<String> _stablePeerIdForEnvelope({
    required Client? client,
    required DirectChatEnvelope envelope,
  }) async {
    final fromClient = (client?.peerId ?? '').trim();
    if (fromClient.isNotEmpty) return fromClient;
    final recordId = (envelope.data['id'] ?? '').toString().trim();
    if (recordId.isNotEmpty) {
      try {
        final existing = await DirectChatRepository.instance.find(recordId);
        if (existing != null && existing.conversationId.isNotEmpty) {
          return existing.conversationId;
        }
      } catch (_) {}
    }
    return '';
  }

  /// Remembers that an incoming chat came from a device of the person
  /// [accountConversation]. Links both the sender's device UUID and the live
  /// incoming chat client's DotChat id, so `conversationPeerIds(account)`
  /// covers every identity the reply can be routed through.
  Future<void> _rememberIncomingPersonDevice({
    required String accountConversation,
    required String originDeviceId,
    String livePeerId = '',
    required String senderName,
    required String srcPlatform,
  }) async {
    if (originDeviceId.isNotEmpty && originDeviceId != accountConversation) {
      await DirectPairingStore.rememberPersonDevice(
        accountConversation,
        originDeviceId,
        displayName: senderName,
        platform: srcPlatform,
      );
    }
    // The live chat session peer id is the phone dialing id (e.g. 487878),
    // which is what the rendezvous server routes on. Record it so replies
    // to this person dial the phone even before a full pairing record
    // (endpoint + fingerprint) exists. Without it, offline replies stay
    // queued because only the device UUID was known.
    final peer = livePeerId.trim();
    if (peer.isNotEmpty &&
        peer != me.id &&
        peer != accountConversation &&
        DirectPairingStore.isDeviceId(peer)) {
      await DirectPairingStore.rememberPersonDevice(
        accountConversation,
        peer,
        displayName: senderName,
        platform: srcPlatform,
      );
    }
    final ffi = parent.target;
    if (ffi == null) return;
    for (final client in ffi.serverModel.clients) {
      final peer = client.peerId.trim();
      if (peer.isEmpty ||
          peer == me.id ||
          peer == accountConversation ||
          !DirectPairingStore.isDeviceId(peer)) {
        continue;
      }
      if (!client.authorized || !client.isChat || client.disconnected) {
        continue;
      }
      await DirectPairingStore.rememberPersonDevice(
        accountConversation,
        peer,
        displayName: client.name,
        platform: 'mobile',
      );
    }
  }

  /// Finds a live incoming chat client that belongs to the same person as
  /// [peerId]. The stored conversation may be keyed by the sender's device
  /// UUID or an IP endpoint while the incoming client is keyed by the
  /// DotChat id; conversationPeerIds resolves both sides to the same person.
  Client? _liveChatClientForPeer(String peerId) {
    final ffi = parent.target;
    if (ffi == null) return null;
    final ids = DirectPairingStore.conversationPeerIds(peerId);
    if (ids.isEmpty) return null;
    return ffi.serverModel.clients.firstWhereOrNull(
      (client) =>
          client.authorized &&
          client.isChat &&
          !client.disconnected &&
          ids.contains(client.peerId),
    );
  }

  /// True when there is a live chat session that can carry [key]'s messages.
  bool _hasLiveChatSession(MessageKey key) {
    final ffi = parent.target;
    if (ffi == null || ffi.closed) return false;
    // A live incoming chat connection hosted by the connection-manager
    // process counts as a live session too: replies to an incoming message
    // must not be dropped just because this window never saw the client.
    if (_hasCmLiveChatClient(key.peerId)) return true;
    if (key.connId <= clientModeID) {
      // Session-based chat: live once this FFI is an established chat session
      // to the same peer (the phone's global FFI or a desktop chat session).
      // A same-person incoming chat client also counts: the phone's global
      // FFI is the incoming chat session and replies must not be dropped
      // just because the stored conversation used the sender's device UUID.
      if (ffi.connType != ConnType.chat || !ffi.ffiModel.pi.isSet.isTrue) {
        return false;
      }
      if (ffi.chatModel.currentKey.peerId == key.peerId) return true;
      return _liveChatClientForPeer(key.peerId) != null;
    }
    return ffi.serverModel.clients.firstWhereOrNull(
          (client) =>
              client.id == key.connId &&
              client.authorized &&
              !client.disconnected,
        ) !=
        null;
  }

  /// Queries the connection-manager (Windows) for the live incoming chat
  /// client of [peerId] and caches its conn id. The desktop main window's
  /// client list can lag behind the CM process, so every send refreshes this
  /// before deciding how to route: if the CM hosts the peer's incoming chat
  /// connection, replies are sent back over it via `cmSendChat` instead of
  /// being dropped ("PC reply to an incoming phone message never arrives").
  Future<void> _refreshCmLiveChatConnId(String peerId) async {
    final ids = DirectPairingStore.conversationPeerIds(peerId);
    if (ids.isEmpty) {
      _cmLiveChatPeerId = '';
      _cmLiveChatConnId = 0;
      return;
    }
    try {
      final raw = await bind.cmGetClientsState();
      if (raw.isEmpty) {
        _cmLiveChatPeerId = '';
        _cmLiveChatConnId = 0;
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _cmLiveChatPeerId = '';
        _cmLiveChatConnId = 0;
        return;
      }
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final client = Client.fromJson(item);
        final clientPeer = client.peerId.trim();
        if (client.authorized &&
            client.isChat &&
            !client.disconnected &&
            clientPeer.isNotEmpty &&
            ids.contains(clientPeer)) {
          _cmLiveChatPeerId = peerId;
          _cmLiveChatConnId = client.id;
          return;
        }
      }
      _cmLiveChatPeerId = '';
      _cmLiveChatConnId = 0;
    } catch (error, stackTrace) {
      debugPrint('Failed to refresh CM chat client: $error\n$stackTrace');
      _cmLiveChatPeerId = '';
      _cmLiveChatConnId = 0;
    }
  }

  /// True when the cached CM chat client belongs to [peerId].
  bool _hasCmLiveChatClient(String peerId) =>
      _cmLiveChatConnId > 0 && _cmLiveChatPeerId == peerId;

  bool _sendWire(MessageKey key, String value) =>
      _sendWireImpl(key, value, allowBluetooth: true);

  /// 中继转发专用：只用本机网络通道（跳过蓝牙路由，避免环路）。
  bool _sendWireNonBluetooth(MessageKey key, String value) =>
      _sendWireImpl(key, value, allowBluetooth: false);

  /// 网络直发失败时的兜底：若本机有已连接的蓝牙网关设备，把消息封装成
  /// relay 信封经蓝牙发出，由网关用它的网络转发到目标（借流量上网）。
  /// 仅用于「无实时会话」这类可达性失败；显式拒绝（权限）不兜底。
  bool _relayViaBluetoothFallback(MessageKey key, String value) {
    if (btWireSink == null) return false;
    if (key.peerId.isEmpty || key.peerId == me.id) return false;
    final ffi = parent.target;
    if (ffi == null || ffi.closed) return false;
    final lastError = (ffi.ffiModel.lastConnectionError ?? '').trim();
    if (isDirectChatPermissionDenied(lastError)) return false;
    return RelayBridge.instance.sendViaBluetoothRelay(
      targetConversationId: key.peerId,
      envelopeLine: value,
    );
  }

  bool _sendWireImpl(MessageKey key, String value,
      {required bool allowBluetooth}) {
    final ffi = parent.target;
    if (ffi == null || ffi.closed) return false;
    debugPrint('[SEND_WIRE] send peer=' +
        key.peerId +
        ' connId=' +
        key.connId.toString() +
        ' me.id=' +
        me.id +
        ' closed=${ffi.closed}');
    // Never send messages to self — prevents deadlock and white-screen.
    if (key.peerId.isNotEmpty && key.peerId == me.id) {
      debugPrint('[SEND_WIRE] self-target blocked peer=' + key.peerId);
      return false;
    }
    // Bluetooth conversations are carried over the RFCOMM link.
    if (allowBluetooth &&
        btWireSink != null &&
        btWireSink!(key.peerId, value)) {
      return true;
    }
    try {
      if (key.connId <= clientModeID) {
        // clientModeID (-1) or uninitialized (-2): send via session.
        // Direct-chat sessions do not depend on remote-desktop state
        // (`pi.isSet`) and transient connection errors must not freeze the
        // input; only an explicit peer rejection blocks sending.
        final lastError = (ffi.ffiModel.lastConnectionError ?? '').trim();
        if (isDirectChatPermissionDenied(lastError)) {
          return false;
        }
        // A same-person incoming chat connection is a live channel too:
        // prefer it so replies to an incoming chat (e.g. the phone hosting
        // the session) are sent over the client channel instead of being
        // dropped by the session-based check below.
        final chatClient = _liveChatClientForPeer(key.peerId);
        if (chatClient != null) {
          debugPrint('[SEND_WIRE] chatClient cmSendChat connId=' +
              chatClient.id.toString() +
              ' peer=' +
              key.peerId);
          bind.cmSendChat(connId: chatClient.id, msg: value);
          return true;
        }
        // The live incoming chat connection may be hosted by the CM process
        // (Windows) and not yet visible in this window's client list. Route
        // the reply over it so incoming messages can always be answered.
        if (_hasCmLiveChatClient(key.peerId)) {
          debugPrint('[SEND_WIRE] cm fallback cmSendChat connId=' +
              _cmLiveChatConnId.toString() +
              ' peer=' +
              key.peerId);
          bind.cmSendChat(connId: _cmLiveChatConnId, msg: value);
          return true;
        }
        // Only report success over a live session; otherwise the delivery
        // watchdog reconnects and retries instead of silently dropping.
        if (!_hasLiveChatSession(key)) {
          debugPrint('[SEND_WIRE] no live session for peer=' +
              key.peerId +
              ' connId=' +
              key.connId.toString() +
              ' connType=' +
              (ffi.connType.toString()) +
              ' closed=' +
              ffi.closed.toString());
          // 无直达会话时尝试借蓝牙网关中继（仅当本机网络不可达）。
          if (_relayViaBluetoothFallback(key, value)) return true;
          return false;
        }
        debugPrint('[SEND_WIRE] sessionSendChat sessionId=' +
            sessionId.toString() +
            ' peer=' +
            key.peerId);
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
        debugPrint('[SEND_WIRE] no live client connId=' +
            key.connId.toString() +
            ' clients=' +
            ffi.serverModel.clients
                .map((c) => '${c.id}:${c.peerId}')
                .join(','));
        // The live incoming chat connection may be hosted by the CM process
        // (Windows) and not yet visible in this window's client list. Route
        // the reply over it so incoming messages can always be answered.
        if (_hasCmLiveChatClient(key.peerId)) {
          debugPrint('[SEND_WIRE] cm fallback cmSendChat connId=' +
              _cmLiveChatConnId.toString() +
              ' peer=' +
              key.peerId);
          bind.cmSendChat(connId: _cmLiveChatConnId, msg: value);
          return true;
        }
        // No live incoming client for this conversation: let the delivery
        // watchdog re-establish the connection and retry. 同时尝试借蓝牙
        // 网关中继（无实时客户端时可能本机无网、依赖网关出口）。
        if (_relayViaBluetoothFallback(key, value)) return true;
        return false;
      }
      debugPrint('[SEND_WIRE] cmSendChat connId=' +
          key.connId.toString() +
          ' peer=' +
          client.peerId);
      bind.cmSendChat(connId: key.connId, msg: value);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Failed to send direct chat message: $error\n$stackTrace');
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
          firstName: key.peerId == kFileHelperId
              ? translate('File Transfer Assistant')
              : normalizeDirectPeerName(
                  pairing?.displayName ?? '',
                  fallback: key.peerId,
                ),
          profileImage:
              pairing?.avatar.isNotEmpty == true ? pairing!.avatar : null,
        ),
        <ChatMessage>[],
      ),
    );
    // Cache full record list for "load older" pagination.
    _conversationRecords[key.peerId] = records;

    final incoming = records.firstWhereOrNull((record) => !record.isOutgoing);
    if (incoming != null && key.peerId != kFileHelperId) {
      body.chatUser.firstName = normalizeDirectPeerName(
        incoming.senderName,
        fallback: body.chatUser.firstName ?? key.peerId,
      );
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
        .map((record) => _taggedChatMessage(
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
    final newMessages = batch
        .map((record) => _taggedChatMessage(
              record,
              record.isOutgoing ? me : body.chatUser,
            ))
        .toList();
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
        : sanitizeInvalidUtf16(record.text);
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
        'ldesk_sender_id': record.senderId,
        'ldesk_conversation_id': record.conversationId,
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
        if (record.replyToSender.isNotEmpty)
          'ldesk_reply_to_sender': record.replyToSender,
        if (record.replyToText.isNotEmpty)
          'ldesk_reply_to_text': record.replyToText,
        if (record.reactions.isNotEmpty)
          'ldesk_reactions': Map<String, dynamic>.from(record.reactions),
        if (record.isEdited) 'ldesk_is_edited': true,
        if (record.editedAt != null)
          'ldesk_edited_at': record.editedAt!.toUtc().toIso8601String(),
        if (record.forwardTitle.isNotEmpty)
          'ldesk_forward_title': record.forwardTitle,
        if (record.srcPlatform.isNotEmpty)
          'ldesk_src_platform': record.srcPlatform,
        if (record.forwardItems.isNotEmpty)
          'ldesk_forward_items': record.forwardItems
              .map((item) => item.toJson())
              .toList(growable: false),
      },
    );
  }

  /// Same as _toChatMessage but tags the message with connection source info.
  /// 收到对方消息时触发手机端横幅通知（当前会话且窗口有焦点时不弹）。
  void _maybeNotifyIncoming(DirectChatRecord record, String targetId) {
    if (record.isOutgoing) return;
    // 用户正在看这个会话时，不再弹通知打扰。
    final isActiveConversation =
        _currentKey.peerId == targetId && isWindowFocus.value;
    if (isActiveConversation) return;
    final sender = record.senderName.trim().isNotEmpty
        ? record.senderName.trim()
        : targetId;
    final body = _notificationBody(record);
    if (body.isEmpty) return;
    unawaited(
      ChatNotifier.instance.showIncomingMessage(
        peerId: targetId,
        senderName: sender,
        body: body,
      ),
    );
  }

  String _notificationBody(DirectChatRecord record) {
    switch (record.kind) {
      case DirectChatKind.file:
        return '[${translate('File')}] ${record.fileName}';
      case DirectChatKind.voice:
        return '[${translate('Voice message')}]';
      case DirectChatKind.forward:
        return '[${translate('Chat history')}]';
      case DirectChatKind.text:
      default:
        final t = record.text.trim();
        if (t.isEmpty) return '';
        return t.length > 60 ? '${t.substring(0, 60)}…' : t;
    }
  }

  ChatMessage _taggedChatMessage(DirectChatRecord record, ChatUser user,
      {bool wasIpSource = false}) {
    final msg = _toChatMessage(record, user);
    msg.customProperties ??= <String, dynamic>{};
    if (record.connMode.isNotEmpty) {
      msg.customProperties!['ldesk_conn_mode'] = record.connMode;
      msg.customProperties!['ldesk_conn_endpoint'] = record.connEndpoint;
      msg.customProperties!['ldesk_conn_port'] = record.connPort;
    }
    if (wasIpSource) {
      msg.customProperties!['ldesk_conn_source'] = 'ip';
    }
    return msg;
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
      body.chatMessages.removeWhere(
          (m) => (m.customProperties?['ldesk_id'] ?? '').toString() == id);
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
    await DirectChatRepository.instance.deleteConversations([key.peerId]);
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
      id,
      emoji,
      deviceId,
    );
    if (updated == null) return;
    insertMessage(key, _taggedChatMessage(updated, me));
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
    insertMessage(key, _taggedChatMessage(updated, me));
    _sendWire(
        key, DirectChatEnvelope.edit(messageId: id, newText: trimmed).encode());
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
      body.chatMessages.removeWhere((m) => idsToDelete
          .contains((m.customProperties?['ldesk_id'] ?? '').toString()));
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
        unreadSet =
            (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toSet();
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
      final list =
          (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
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
  Future<void> setRawOption(
      {required String key, required String value}) async {
    try {
      await bind.mainSetLocalOption(key: key, value: value);
    } catch (_) {}
  }

  // ─── Multi-select ────────────────────────────────────────

  void enterMultiSelect(String firstMessageId) {
    _multiSelectMode = true;
    _selectedMessageIds.clear();
    _selectedMessageIds.add(firstMessageId);
    _anchorMessageId = firstMessageId;
    notifyListeners();
  }

  void toggleSelection(String messageId) {
    if (_selectedMessageIds.contains(messageId)) {
      _selectedMessageIds.remove(messageId);
      if (_selectedMessageIds.isEmpty) {
        _multiSelectMode = false;
        _anchorMessageId = null;
      }
    } else {
      _selectedMessageIds.add(messageId);
    }
    if (_multiSelectMode) _anchorMessageId = messageId;
    notifyListeners();
  }

  /// Ctrl+点击：切换单条消息选中状态，保持多选模式（即使清空也不退出）。
  void toggleSelectionKeepMode(String messageId) {
    if (_selectedMessageIds.contains(messageId)) {
      _selectedMessageIds.remove(messageId);
    } else {
      _selectedMessageIds.add(messageId);
    }
    _multiSelectMode = true;
    _anchorMessageId = messageId;
    notifyListeners();
  }

  /// Shift+点击：选中从锚点到 [targetMessageId] 之间的连续区间（含两端）。
  void selectRange(String targetMessageId) {
    final body = _messages[_currentKey];
    if (body == null) return;
    final ids = <String>[
      for (final msg in body.chatMessages)
        (msg.customProperties?['ldesk_id'] ?? '').toString(),
    ]..removeWhere((id) => id.isEmpty);
    final anchor = _anchorMessageId;
    if (anchor == null || !ids.contains(anchor)) {
      _selectedMessageIds.clear();
      _selectedMessageIds.add(targetMessageId);
    } else {
      _selectedMessageIds
        ..clear()
        ..addAll(computeRange(ids, anchor, targetMessageId));
    }
    _multiSelectMode = true;
    _anchorMessageId = targetMessageId;
    notifyListeners();
  }

  /// 计算 [anchor] 到 [target] 之间的连续消息 id 区间（含两端）。
  /// 锚点或目标不在列表时返回 [target]（退化单选）。纯函数便于测试。
  static List<String> computeRange(
    List<String> orderedIds,
    String anchor,
    String target,
  ) {
    final a = orderedIds.indexOf(anchor);
    final b = orderedIds.indexOf(target);
    if (a < 0 || b < 0) return <String>[target];
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    return orderedIds.sublist(lo, hi + 1);
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
    _anchorMessageId = null;
    notifyListeners();
  }

  close() {
    for (final timer in _selfDestructTimers.values) {
      timer.cancel();
    }
    _selfDestructTimers.clear();
    for (final timer in _deliveryWatchdogs.values) {
      timer.cancel();
    }
    _deliveryWatchdogs.clear();
    _deliveryWatchdogRetries.clear();
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

// ChatModel end

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
