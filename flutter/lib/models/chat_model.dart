import 'dart:async';
import 'dart:convert';
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

  Offset chatWindowPosition = Offset(20, 80);

  void setChatWindowPosition(Offset position) {
    chatWindowPosition = position;
    notifyListeners();
  }

  @override
  void dispose() {
    DirectChatRepository.instance.revision.removeListener(_onStoreRevision);
    for (final timer in _selfDestructTimers.values) {
      timer.cancel();
    }
    _selfDestructTimers.clear();
    textController.dispose();
    super.dispose();
  }

  late final ChatUser me;

  late final Map<MessageKey, MessageBody> _messages = {};
  final Map<int, String> _activeCompanionSecrets = <int, String>{};
  final Map<String, _IncomingVoiceTransfer> _incomingVoiceTransfers =
      <String, _IncomingVoiceTransfer>{};
  final Map<String, Timer> _selfDestructTimers = <String, Timer>{};
  bool _activeCompanionSyncInProgress = false;
  Future<void>? _recentRestoreTask;
  bool _recentRestoreQueued = false;

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
    if (identical(this, gFFI.chatModel)) {
      _scheduleRecentConversationRestore();
    } else if (_currentKey.peerId.isNotEmpty) {
      unawaited(_restoreConversation(_currentKey));
    }
  }

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
        if (!_isShowCMSidePage) {
          await toggleCMChatPage(key);
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
    if (peerId == null) {
      debugPrint("Failed to receive msg, peerId is null");
      return;
    }

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

    late final DirectChatRecord record;
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
    if (desktopType == DesktopType.cm) {
      await showCmWindow();
    }

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

  Future<void> _sendMessage(ChatMessage message) async {
    final trimmedText = message.text.trim();
    if (trimmedText.isEmpty) {
      return;
    }
    final key = _currentKey;
    if (key.peerId.isEmpty) return;
    final record = await DirectChatRepository.instance.createOutgoing(
      conversationId: key.peerId,
      kind: DirectChatKind.text,
      text: trimmedText,
      senderId: me.id,
      senderName: me.firstName ?? '',
      senderAvatar: '',
    );
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
  }) async {
    final key = _currentKey;
    if (key.peerId.isEmpty || fileName.isEmpty) return;
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
    try {
      if (key.connId == clientModeID) {
        if (ffi.ffiModel.pi.isSet.isTrue != true) return false;
        bind.sessionSendChat(sessionId: sessionId, text: value);
        return true;
      }
      final client = ffi.serverModel.clients.firstWhereOrNull(
        (client) =>
            client.id == key.connId &&
            client.authorized &&
            !client.disconnected,
      );
      if (client == null) return false;
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
      records = await DirectChatRepository.instance.forConversation(key.peerId);
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
    final incoming = records.firstWhereOrNull((record) => !record.isOutgoing);
    if (incoming != null) {
      if (incoming.senderName.isNotEmpty) {
        body.chatUser.firstName = incoming.senderName;
      }
      if (incoming.senderAvatar.isNotEmpty) {
        body.chatUser.profileImage = incoming.senderAvatar;
      }
    }
    body.chatMessages = records
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
        if (record.voiceDurationMs > 0)
          'ldesk_voice_duration_ms': record.voiceDurationMs,
        if (record.expiresAt != null)
          'ldesk_expires_at': record.expiresAt!.toUtc().toIso8601String(),
        'ldesk_disposition': record.disposition.name,
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
