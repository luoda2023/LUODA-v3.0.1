import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String methodBody(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'missing $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('remote first-frame waiting state does not animate indefinitely', () {
    final source =
        File('lib/desktop/pages/remote_page.dart').readAsStringSync();
    final start = source.indexOf('class RemoteConnectionProgress');
    final end = source.indexOf('class _RemoteSessionStatusBar', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final progressSource = source.substring(start, end);
    expect(progressSource, contains('Icons.hourglass_top_rounded'));
    expect(progressSource, isNot(contains('CircularProgressIndicator')));
  });

  final serverModelSource =
      File('lib/models/server_model.dart').readAsStringSync();
  final desktopHomeSource =
      File('lib/desktop/pages/desktop_home_page.dart').readAsStringSync();
  final desktopTabSource =
      File('lib/desktop/pages/desktop_tab_page.dart').readAsStringSync();
  final win32WindowSource =
      File('windows/runner/win32_window.cpp').readAsStringSync();
  final mobileConnectionSource =
      File('lib/mobile/pages/connection_page.dart').readAsStringSync();
  final mobileHomeSource =
      File('lib/mobile/pages/home_page.dart').readAsStringSync();
  final scanSource = File('lib/mobile/pages/scan_page.dart').readAsStringSync();
  final modelSource = File('lib/models/model.dart').readAsStringSync();
  final chatModelSource = File('lib/models/chat_model.dart').readAsStringSync();
  final nativeModelSource =
      File('lib/models/native_model.dart').readAsStringSync();
  final chatPageSource =
      File('lib/common/widgets/chat_page.dart').readAsStringSync();
  final overlaySource =
      File('lib/common/widgets/overlay.dart').readAsStringSync();
  final peersViewSource =
      File('lib/common/widgets/peers_view.dart').readAsStringSync();
  final sharedStateSource =
      File('lib/common/shared_state.dart').readAsStringSync();
  final flutterFfiSource = File('../src/flutter_ffi.rs').readAsStringSync();
  final rustFlutterSource = File('../src/flutter.rs').readAsStringSync();
  final hbbCommonLibSource =
      File('../libs/hbb_common/src/lib.rs').readAsStringSync();
  final remotePageSource =
      File('lib/desktop/pages/remote_page.dart').readAsStringSync();
  final viewCameraPageSource =
      File('lib/desktop/pages/view_camera_page.dart').readAsStringSync();
  final multiWindowSource =
      File('lib/utils/multi_window_manager.dart').readAsStringSync();
  final androidBuildSource =
      File('android/app/build.gradle.kts').readAsStringSync();
  final androidBuildScriptSource = File('build_android.ps1').readAsStringSync();
  final rustBuildScriptSource = File('../build.rs').readAsStringSync();
  final androidAomPortSource =
      File('../res/vcpkg/aom/portfile.cmake').readAsStringSync();
  final androidFfmpegPortSource =
      File('../res/vcpkg/ffmpeg/portfile.cmake').readAsStringSync();
  final androidManifestSource =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final adaptiveIconSource = File(
    'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
  ).readAsStringSync();
  final androidIconScriptSource =
      File('../res/resize_for_apk.py').readAsStringSync();
  final pubspecSource = File('pubspec.yaml').readAsStringSync();

  test('server status polling clears stale remote-control blocking state', () {
    expect(serverModelSource,
        contains('videoConnCount is int ? videoConnCount : 0'));
    expect(serverModelSource, contains('stateGlobal.videoConnCount.value'));
  });

  test('periodic callbacks cannot overlap', () {
    final common = File('lib/common.dart').readAsStringSync();

    expect(common, contains('if (running) return;'));
    expect(common, contains('running = true;'));
    expect(common, contains('running = false;'));
  });

  test('draggable chat position is initialized before its first update', () {
    final constructor = methodBody(
      overlaySource,
      'DraggableKeyPosition(this.key)',
      '  get pos',
    );
    expect(constructor, contains('_debouncerStore = Debouncer<int>'));
    expect(overlaySource, isNot(contains('late Debouncer<int>')));
  });

  test('desktop resize edges use native Windows hit testing', () {
    expect(desktopTabSource, isNot(contains('DragToResizeArea(')));
    expect(win32WindowSource, contains('WM_NCHITTEST'));
    expect(win32WindowSource, contains('BorderlessResizeHitTest'));
  });

  test('desktop start service restores both installed and in-process hosts',
      () {
    final startService = methodBody(
      flutterFfiSource,
      'pub fn main_start_service()',
      'pub fn main_update_temporary_password()',
    );
    expect(
      startService,
      contains('Config::set_option("stop-service".into(), "".into())'),
    );
    expect(startService, contains('crate::platform::is_installed()'));
    expect(
      startService,
      contains('crate::ipc::set_option("stop-service", "")'),
    );
    expect(
      startService,
      contains('RendezvousMediator::restart()'),
    );
  });

  test('debug logging tolerates an already installed runtime logger', () {
    final initLog = methodBody(
      hbbCommonLibSource,
      'pub fn init_log(',
      '#[derive(Debug, Default, Deserialize, Serialize)]',
    );
    expect(initLog, contains('.try_init()'));
    expect(initLog, isNot(contains('init_from_env(')));
  });

  test('desktop startup survives package version metadata failures', () {
    final getVersion = methodBody(
      nativeModelSource,
      'static Future<String> getVersion() async',
      'bool registerEventHandler(',
    );
    expect(getVersion, contains('PackageInfo.fromPlatform()'));
    expect(getVersion, contains('catch (error, stackTrace)'));
    expect(getVersion, contains('instance._ffiBind.mainGetVersion()'));
  });

  test('desktop direct chat connects without a blocking dialog', () {
    final startChat = methodBody(
      desktopHomeSource,
      'Future<void> _startDirectChat(',
      'Peer? _findContact(',
    );
    expect(startChat, contains('suppressConnectionDialogs = true'));
    expect(startChat, isNot(contains('showLoading(')));
    expect(startChat, isNot(contains('suppressConnectionDialogs = false')));
    expect(
      startChat,
      contains('if (activate) {\n        _showConversationNotice('),
    );
  });

  test('desktop direct chat retries stale unconnected sessions', () {
    final startChat = methodBody(
      desktopHomeSource,
      'Future<void> _startDirectChat(',
      'Peer? _findContact(',
    );
    expect(startChat, contains('_directChatAttemptedAt'));
    expect(startChat, contains('ffiModel.pi.isSet.isTrue'));
    expect(startChat, contains('await existing.close()'));
    expect(startChat, contains('_removeDirectChatSession(existing)'));
  });

  test('desktop background chat retries are bounded and do not scan history',
      () {
    final refresh = methodBody(
      desktopHomeSource,
      'Future<void> _refreshDirectSessions()',
      'Future<bool> _canMaintainBackgroundChat(',
    );
    expect(refresh,
        contains('if (_refreshingDirectSessions || !mounted) return;'));
    expect(refresh, contains('_maintainTrustedChatSessions()'));
    expect(refresh, contains('_maintainPendingChatSessions()'));
    expect(refresh, isNot(contains('_maintainChatKeepAlive()')));
    expect(desktopHomeSource, contains('const Duration(seconds: 15)'));
    expect(desktopHomeSource, contains('_backgroundChatRetryDelays'));
    expect(desktopHomeSource, contains('latestPairingByConversation'));
  });

  test('desktop navigation and search update only the contact pane', () {
    final selectSection = methodBody(
      desktopHomeSource,
      'Future<void> _selectSection(',
      'Widget _buildContactsPane(',
    );
    expect(desktopHomeSource, contains('ValueNotifier<String> _selectedRail'));
    expect(desktopHomeSource, contains('ValueNotifier<String> _contactQuery'));
    expect(selectSection, isNot(contains('setState(')));
    expect(
      desktopHomeSource,
      contains('onChanged: (value) => _contactQuery.value = value'),
    );
  });

  test('desktop section switching does not reload fresh peer lists', () {
    final loadSection = methodBody(
      desktopHomeSource,
      'Future<void> _loadContactSection(',
      'Future<void> _startDirectChat(',
    );

    expect(desktopHomeSource, contains('_lastContactSectionLoad'));
    expect(desktopHomeSource, contains('_contactSectionRefreshInterval'));
    expect(loadSection, contains('now.difference(lastLoad) <'));
    expect(loadSection, contains('return;'));
  });

  test('desktop contact rows reuse one pairing snapshot per list build', () {
    final contactSection = methodBody(
      desktopHomeSource,
      'Widget _buildContactSection(BuildContext context)',
      'Widget _buildPeopleGroupHeader(',
    );
    final contactItem = methodBody(
      desktopHomeSource,
      'Widget _buildContactItem(',
      'Widget _buildDragFeedback(',
    );

    expect(contactSection, contains('final directPairings ='));
    expect(contactSection,
        contains('row as _DesktopPersonGroup,\n              directPairings,'));
    expect(contactItem, isNot(contains('DirectPairingStore.load()')));
  });

  test('desktop contacts contain friends only and omit trust group headers',
      () {
    final contactSection = methodBody(
      desktopHomeSource,
      'Widget _buildContactSection(BuildContext context)',
      'Widget _buildPeopleGroupHeader(',
    );

    expect(
      contactSection,
      contains("final friendsOnly = _selectedRailId == 'contacts';"),
    );
    expect(contactSection, contains('if (friendsOnly &&'));
    expect(contactSection, contains('if (friendsOnly) {'));
    expect(contactSection, contains('rows.addAll(personGroups)'));
  });

  test('peer tabs load once and filter synchronously', () {
    expect(peersViewSource, contains('void _loadInitialPeers()'));
    expect(peersViewSource, contains('_loadInitialPeers();'));
    expect(peersViewSource, isNot(contains('FutureBuilder<List<Peer>>')));
    expect(
      peersViewSource,
      isNot(contains('bind.mainLoadRecentPeers();\n    return widget;')),
    );
    expect(
      peersViewSource,
      isNot(contains('bind.mainLoadFavPeers();\n    return widget;')),
    );
  });

  test('peer tabs group recents and favorites but keep contacts friends-only',
      () {
    final recentView = methodBody(
      peersViewSource,
      'class RecentPeersView extends BasePeersView',
      'class FavoritePeersView extends BasePeersView',
    );
    final favoriteView = methodBody(
      peersViewSource,
      'class FavoritePeersView extends BasePeersView',
      'class DiscoveredPeersView extends BasePeersView',
    );
    final addressBookView = methodBody(
      peersViewSource,
      'class AddressBookPeersView extends BasePeersView',
      'class MyGroupPeerView extends BasePeersView',
    );

    expect(peersViewSource, contains('groupByDirectChatPolicy'));
    expect(peersViewSource, contains('final bool friendsOnly;'));
    expect(peersViewSource, contains('_buildWideGroupedPeers'));
    expect(peersViewSource, contains("_PeerGroup('Friends'"));
    expect(peersViewSource, contains("_PeerGroup('Strangers'"));
    expect(recentView, contains('groupByDirectChatPolicy: true'));
    expect(favoriteView, contains('groupByDirectChatPolicy: true'));
    expect(addressBookView, contains('friendsOnly: true'));
    expect(addressBookView, isNot(contains('groupByDirectChatPolicy: true')));
  });

  test('background chat reconnects only accepted friends on both clients', () {
    final desktopTrusted = methodBody(
      desktopHomeSource,
      'Future<void> _maintainTrustedChatSessions()',
      'Future<void> _maintainPendingChatSessions()',
    );
    final desktopPending = methodBody(
      desktopHomeSource,
      'Future<void> _maintainPendingChatSessions()',
      'Future<void> _refreshDirectSessions()',
    );
    final mobileKeepAlive = methodBody(
      mobileConnectionSource,
      'Future<void> _maintainChatKeepAlive()',
      'Widget _buildPairedContacts()',
    );
    for (final source in <String>[
      desktopTrusted,
      desktopPending,
      mobileKeepAlive,
    ]) {
      expect(source, contains('shouldAutoReconnect'));
    }
  });

  test('successful chat handshakes record prior acceptance', () {
    expect(
      modelSource,
      contains('DirectChatAccessController.instance.markAccepted'),
    );
    expect(
      serverModelSource,
      contains('DirectChatAccessController.instance.markAccepted'),
    );
  });

  test('chat workspace has no offline or reconnect status banners', () {
    expect(chatPageSource, isNot(contains('Widget reconnectBar')));
    expect(chatPageSource, isNot(contains('Widget offlineBar')));
    expect(chatPageSource, isNot(contains("translate('Reconnecting...')")));
    expect(
      chatPageSource,
      isNot(contains('Peer is offline — messages will be kept locally')),
    );
  });

  test('desktop chat suppresses automatic network status notices', () {
    final transitions = methodBody(
      desktopHomeSource,
      'void _checkConnectionTransitions()',
      '_updateWindowSize()',
    );

    expect(transitions, isNot(contains("translate('Network')")));
    expect(transitions, isNot(contains('_lastNetworkNoticeAt')));
    expect(transitions, isNot(contains('_WorkspaceNoticeTone.warning')));
    expect(transitions, isNot(contains('_WorkspaceNoticeTone.error')));
  });

  test('failed direct chat sessions stay offline and keep messages queued', () {
    final deliveryStatus = methodBody(
      desktopHomeSource,
      '(String, Color) _directDeliveryStatus(',
      'String _contactName(',
    );
    final sendWire = methodBody(
      chatModelSource,
      'bool _sendWire(',
      'Future<void> _restoreConversation(',
    );
    final deliveryWidget = methodBody(
      chatPageSource,
      'Widget deliveryWidget(',
      'return Row(',
    );

    expect(deliveryStatus, contains('if (error.trim().isNotEmpty)'));
    expect(deliveryStatus, contains("return ('Offline'"));
    // Direct-chat sending no longer depends on remote-desktop state; only an
    // explicit peer rejection (permission denied) blocks sending.
    expect(sendWire, contains('isDirectChatPermissionDenied'));
    expect(sendWire.indexOf('isDirectChatPermissionDenied'),
        lessThan(sendWire.indexOf('bind.sessionSendChat(')));
    expect(sendWire, isNot(contains('pi.isSet.isTrue')));
    expect(deliveryWidget, contains("label = translate('Waiting to send')"));
    expect(deliveryWidget, isNot(contains("label = translate('Sending...')")));
  });

  test('clicking a failed direct chat session starts a fresh connection', () {
    final openConversation = methodBody(
      desktopHomeSource,
      'void _openConversation(',
      'Widget _buildConversationList(',
    );
    final openContact = methodBody(
      desktopHomeSource,
      'void _openContactConversation(',
      '(String, Color) _contactDeliveryStatus(',
    );

    for (final source in <String>[openConversation, openContact]) {
      expect(source, contains('registered.ffiModel.lastConnectionError'));
      expect(source, contains('_startDirectChat('));
    }
  });

  test('conversation switching reuses loaded messages and stable identity', () {
    final chatModelSource =
        File('lib/models/chat_model.dart').readAsStringSync();
    final directChatSource =
        File('lib/common/direct_chat.dart').readAsStringSync();
    final changeKey = methodBody(
      chatModelSource,
      'changeCurrentKey(MessageKey key)',
      'receive(int id, String rawText,',
    );
    final updateIdentity = methodBody(
      chatModelSource,
      'void updatePeerIdentity(',
      'showChatIconOverlay(',
    );

    expect(changeKey, contains('_conversationRecords.containsKey(key.peerId)'));
    expect(updateIdentity, contains('if (changed) notifyListeners();'));
    expect(updateIdentity,
        isNot(contains('for (final entry in _messages.entries)')));
    expect(chatModelSource, contains('latestConversations()'));
    expect(directChatSource, contains('latestConversations()'));
  });

  test('conversation switching releases non-persistent direct sessions', () {
    final releaseIdle = methodBody(
      desktopHomeSource,
      'Future<void> _releaseInactiveDirectChatSessions(',
      'Future<void> _maintainTrustedChatSessions()',
    );

    expect(releaseIdle, contains('shouldAutoReconnect(canonicalPeerId)'));
    expect(releaseIdle, contains('_directChatSessions.remove(peerId)'));
    expect(releaseIdle, contains('await ffi.close()'));
    expect(
      desktopHomeSource,
      contains('unawaited(_releaseInactiveDirectChatSessions(peerId))'),
    );
  });

  test('mobile direct chat connects without a blocking dialog', () {
    final startChat = methodBody(
      mobileConnectionSource,
      'Future<void> _startDirectChat(',
      'Widget _buildPairedContacts()',
    );
    expect(startChat, contains('gFFI.suppressConnectionDialogs = true'));
    expect(startChat, isNot(contains('showLoading(')));
  });

  test('direct file transports connect in the background', () {
    final desktopFile = methodBody(
      desktopHomeSource,
      'Future<FFI?> _ensureDirectFileSession(',
      'Future<bool> _waitForFileDirectories(',
    );
    final mobileFile = methodBody(
      mobileHomeSource,
      'Future<FFI?> _ensureDirectFileSession(',
      'Future<bool> _waitForFileDirectories(',
    );
    for (final source in <String>[desktopFile, mobileFile]) {
      expect(source, contains('suppressConnectionDialogs = true'));
      expect(source, isNot(contains('showLoading(')));
    }
  });

  test('remote mouse window bounds use the actual window height', () {
    expect(
      modelSource,
      contains('final h = _windowRect!.height / devicePixelRatio;'),
    );
    expect(
      modelSource,
      isNot(contains('final h = _windowRect!.width / devicePixelRatio;')),
    );
  });

  test('mobile QR scanning always releases its in-flight guard', () {
    final scanHandler = methodBody(
      scanSource,
      'Future<void> _handleScannedValue(',
      'Future<void> _showServerSettingFromQr(',
    );
    expect(scanHandler, contains('try {'));
    expect(scanHandler, contains('finally'));
    expect(scanHandler, contains('_handlingScan = false;'));
  });

  test('remote page disposal cannot block the tab lifecycle', () {
    expect(remotePageSource, contains('void dispose()'));
    expect(
        remotePageSource, contains('unawaited(_finishDispose(closeSession))'));
    expect(remotePageSource, contains('.timeout(const Duration(seconds: 5))'));
    expect(remotePageSource, contains('removeSharedStates(widget.id)'));
  });

  test('desktop session manager rejects self targets before window creation',
      () {
    final newSession = methodBody(
      multiWindowSource,
      'Future<MultiWindowCallResult> newSession(',
      'Future<MultiWindowCallResult> newRemoteDesktop(',
    );
    final guard =
        newSession.indexOf('await DirectPairingStore.isSelfTarget(remoteId)');
    final probe = newSession.indexOf('for (final windowId');
    expect(guard, greaterThanOrEqualTo(0));
    expect(probe, greaterThan(guard));
    expect(
      newSession,
      contains(
          "'This is the current device. You cannot connect to or message yourself.'"),
    );
    expect(newSession, contains('return MultiWindowCallResult(-1, false);'));
  });

  test('chat message flex participates directly in the row layout', () {
    expect(chatPageSource, contains('final messageColumn = Flexible('));
    expect(chatPageSource, isNot(contains('child: Flexible(')));
  });

  test('IP contacts open the canonical paired conversation', () {
    final openContact = methodBody(
      desktopHomeSource,
      'void _openContactConversation(Peer peer)',
      '(String, Color) _contactDeliveryStatus(',
    );
    final startChat = methodBody(
      desktopHomeSource,
      'Future<void> _startDirectChat(',
      'Peer? _findContact(',
    );

    expect(openContact, contains('_conversationPeerId(requestedId)'));
    expect(openContact, contains('_selectedConversationPeerId = peerId'));
    expect(openContact, contains('MessageKey('));
    expect(openContact, contains('_startDirectChat(connectTarget)'));
    expect(
      startChat,
      contains('DirectPairingStore.findByEndpoint(requestedId)'),
    );
    expect(
      startChat,
      contains('DirectPairingStore.canonicalConversationId(requestedId)'),
    );
  });

  test('desktop mobile and incoming messages share the account conversation',
      () {
    expect(
      desktopHomeSource,
      contains('DirectPairingStore.canonicalConversationIdValue('),
    );
    expect(
      mobileConnectionSource,
      contains('DirectPairingStore.canonicalConversationId(id)'),
    );
    expect(
      chatModelSource,
      contains('DirectPairingStore.canonicalConversationId(key.peerId)'),
    );
    expect(
      chatModelSource,
      contains('DirectPairingStore.canonicalConversationId(peerId)'),
    );
  });

  test('successful IP chat sessions rekey to the canonical account ID', () {
    final canonicalize = methodBody(
      desktopHomeSource,
      'void _canonicalizeDirectChatSessions()',
      'FFI? _directChatSessionFor(',
    );
    final releaseIdle = methodBody(
      desktopHomeSource,
      'Future<void> _releaseInactiveDirectChatSessions(',
      'Future<void> _maintainTrustedChatSessions()',
    );

    expect(canonicalize, contains('ffi.chatModel.currentKey.peerId'));
    expect(canonicalize, contains('_directChatSessions[canonicalPeerId]'));
    expect(canonicalize, contains('_selectedConversationPeerId'));
    expect(releaseIdle, contains('ffi.chatModel.currentKey.peerId'));
  });

  test(
      'successful IP remote sessions persist ID fallback in either event order',
      () {
    final persistPairing = methodBody(
      modelSource,
      'Future<void> _persistDiscoveredDirectPairing(',
      'checkDesktopKeyboardMode() async',
    );
    final fingerprintEvent = modelSource
        .split("} else if (name == 'fingerprint') {")[1]
        .split("} else if (name == 'plugin_manager') {")[0];
    final peerInfoHandler = methodBody(
      modelSource,
      'handlePeerInfo(',
      'Future<void> _persistDiscoveredDirectPairing(',
    );

    expect(persistPairing, contains('sessionPeerId.trim()'));
    expect(persistPairing, contains('cachedPeerData.peerInfo'));
    expect(persistPairing, contains('FingerprintState.ensure'));
    expect(
      persistPairing,
      contains('DirectPairingStore.extractDirectEndpoint'),
    );
    expect(persistPairing, contains('DirectPairingStore.saveDiscovered('));
    expect(persistPairing, contains('accountId: conversationPeerId'));
    expect(persistPairing, contains('deviceName: _pi.hostname'));
    expect(persistPairing, contains('platform: _pi.platform'));
    expect(persistPairing, contains('secure: true'));
    expect(
      peerInfoHandler,
      contains('DirectPairingStore.canonicalConversationId(actualPeerId)'),
    );
    expect(fingerprintEvent,
        contains('await _persistDiscoveredDirectPairing(peerId)'));
    expect(peerInfoHandler,
        contains('await _persistDiscoveredDirectPairing(peerId)'));
  });

  test('remote session launch suppresses duplicate target requests', () {
    final connectDirect = methodBody(
      desktopHomeSource,
      'Future<void> _connectDirect(',
      'void _handleConversationAction(',
    );

    expect(connectDirect, contains('_openingDirectConnections.add'));
    expect(connectDirect, contains('_lastDirectConnectionAttempt'));
    expect(connectDirect, contains('finally'));
    expect(connectDirect, contains('_openingDirectConnections.remove'));
  });

  test('desktop message context menu remains reachable', () {
    final contextMenu = methodBody(
      chatPageSource,
      'Future<String?> _showWeChatContextMenu(',
      'Future<bool> _showWeChatConfirm(',
    );

    expect(contextMenu, isNot(contains('if (id.isEmpty) return null;')));
    expect(contextMenu, contains('RelativeRect.fromRect('));
    expect(contextMenu, isNot(contains('RelativeRect.fromLTRB(')));
    expect(chatPageSource, contains('MessageContextRegion('));
    // 桌面右键与手机长按共用消息操作菜单（_openMessageActions）。
    expect(chatPageSource, contains('onSecondaryTap: (position)'));
    expect(chatPageSource, contains('onLongPress: (position)'));
    expect(chatPageSource, contains('_openMessageActions('));
    expect(chatPageSource, contains('contextMenuBuilder: (_, __)'));
  });

  test('desktop composer supports scrolling and expansion', () {
    expect(chatPageSource, contains('_inputScrollController'));
    expect(chatPageSource, contains('thumbVisibility: true'));
    expect(chatPageSource, contains('trackVisibility: true'));
    expect(chatPageSource, contains('Icons.fullscreen_rounded'));
    expect(chatPageSource, contains('Icons.fullscreen_exit_rounded'));
    expect(chatPageSource, contains('_expandedHeight'));
  });

  test('desktop conversations exclude the local device identity', () {
    // 会话列表过滤掉本机身份与文件助手会话。
    final filter = desktopHomeSource.split('peerId == gFFI.chatModel.me.id')[0];
    expect(filter, contains('if (peerId.isEmpty ||'));
    expect(
      desktopHomeSource,
      contains('peerId == gFFI.chatModel.me.id'),
    );
    expect(desktopHomeSource, contains('peerId == kFileHelperId'));
    expect(desktopHomeSource, contains('return false;'));
  });

  test('desktop conversation preview localizes stored voice labels', () {
    final preview = methodBody(
      desktopHomeSource,
      'String _conversationPreview(',
      'IconData? _conversationFileIcon(',
    );
    expect(preview, contains("properties?['ldesk_kind'] == 'voice'"));
    expect(preview, contains("translate('Voice message')"));
  });

  test('remote shared state is reference counted per mounted session', () {
    expect(sharedStateSource, contains('_sharedStateReferenceCounts'));
    expect(sharedStateSource, contains('final count ='));
    expect(sharedStateSource, contains('if (count > 0)'));
    expect(sharedStateSource, contains('if (count > 1)'));

    final remoteInitState = methodBody(
      remotePageSource,
      'void initState()',
      'void _cancelPointerLockCenterDebounceTimer()',
    );
    expect(remoteInitState, contains('initSharedStates(widget.id);'));
    expect(remoteInitState, contains('_initStates(widget.id);'));

    final cameraInitState = methodBody(
      viewCameraPageSource,
      'void initState()',
      'void onWindowBlur()',
    );
    expect(cameraInitState, contains('initSharedStates(widget.id);'));
  });

  test('remote connection errors are retained for the inline error state', () {
    final handleMsgBox = methodBody(
      modelSource,
      'handleMsgBox(Map<String, dynamic> evt, SessionID sessionId, String peerId)',
      'bool shouldAutoReconnectDirectChat(',
    );
    expect(
      handleMsgBox,
      contains(
        'parent.target?.connType == ConnType.chat &&\n'
        "          _isEnvironmentError(text?.toString() ?? '')",
      ),
    );
    expect(handleMsgBox, contains('_lastConnectionError ='));
    expect(
      handleMsgBox,
      contains('directChatRejected ? directChatPermissionDeniedKey'),
    );
    expect(handleMsgBox, contains('notifyListeners();'));
  });

  test('android packaging refuses to omit the luoda native library', () {
    expect(androidBuildSource, contains('requiredLuodaAbis'));
    expect(androidBuildSource, contains('LUODA_ANDROID_ABIS'));
    expect(androidBuildSource, contains('verifyLuodaNativeLibraries'));
    expect(androidBuildSource, contains('libluoda.so'));
    expect(
        androidBuildSource, contains('dependsOn(verifyLuodaNativeLibraries)'));
    expect(
        androidBuildSource, isNot(contains('abiFilters += requiredLuodaAbis')));
    expect(
      androidBuildScriptSource,
      contains(r'$env:LUODA_ANDROID_ABIS = $Abi -join ","'),
    );
  });

  test('Flutter 3.24 Android assemble uses the AGP 8 copy fallback', () {
    expect(androidBuildSource, contains('needsFlutter324ApkCopyFallback'));
    expect(androidBuildSource, contains('gradle.projectsEvaluated'));
    expect(androidBuildSource, contains('assembleTask.actions.clear()'));
    expect(androidBuildSource, contains('outputs/apk/\$mode/app-\$mode.apk'));
    expect(androidBuildSource, contains('outputs/flutter-apk'));
  });

  test('Windows Android builds link the matching libsodium ABI', () {
    expect(
      androidBuildScriptSource,
      contains('function Resolve-AndroidSodiumLibDir'),
    );
    expect(androidBuildScriptSource, contains('"arm64-v8a" = "arm64-android"'));
    expect(
      androidBuildScriptSource,
      contains('"armeabi-v7a" = "arm-neon-android"'),
    );
    expect(
      androidBuildScriptSource,
      contains(r'$env:SODIUM_LIB_DIR = Resolve-AndroidSodiumLibDir'),
    );
    expect(androidBuildScriptSource, contains('"liblibsodium.a"'));
  });

  test('Windows Android toolchain candidates remain arrays', () {
    expect(
      RegExp(r'\$candidates = @\(\r?\n\s+@\(')
          .allMatches(androidBuildScriptSource)
          .length,
      3,
    );
    expect(
      androidBuildScriptSource,
      contains(r'.toolchains\android-sdk'),
    );
    expect(
      androidBuildScriptSource,
      contains(r'$env:CARGO_HOME = $workspaceCargoHome'),
    );
    expect(
      androidBuildScriptSource,
      contains(r'$env:RUSTUP_HOME = $workspaceRustupHome'),
    );
    expect(
      androidBuildScriptSource,
      contains(r'$env:ANDROID_HOME = $androidSdk'),
    );
  });

  test('Windows Android builds configure vcpkg and legacy bindgen', () {
    expect(androidBuildScriptSource, contains('function Resolve-VcpkgRoot'));
    expect(
      androidBuildScriptSource,
      contains(r'$env:VCPKG_ROOT = Resolve-VcpkgRoot'),
    );
    expect(
      androidBuildScriptSource,
      contains(r'$env:BINDGEN_EXTRA_CLANG_ARGS ='),
    );
    expect(androidBuildScriptSource, contains(r".Replace('\', '/')"));
    expect(androidBuildScriptSource, isNot(contains('"--bindgen"')));
    expect(androidBuildScriptSource, contains(r'include\stddef.h'));
    expect(androidBuildScriptSource, isNot(contains(r'[version]$_.Name')));
    expect(
      androidBuildScriptSource,
      contains(r'-resource-dir=$bindgenResourceDir'),
    );
    expect(
      androidBuildScriptSource,
      contains(r'--target=$($target.Bindgen)23'),
    );
    expect(androidBuildScriptSource, contains('-D__ANDROID_API__=23'));
    expect(
      androidBuildScriptSource,
      contains('Features = "flutter,use_dasp,mediacodec"'),
    );
    expect(
      androidBuildScriptSource,
      isNot(contains('Features = "flutter,hwcodec"')),
    );
    expect(
      androidBuildScriptSource,
      contains(r'$env:VCPKG_INSTALLED_ROOT ='),
    );
    expect(
      androidBuildScriptSource,
      contains('"build", "--lib", "--features", \$target.Features'),
    );
    expect(androidBuildScriptSource, contains('function Resolve-JavaHome'));
    expect(
      androidBuildScriptSource,
      contains(r'$env:JAVA_HOME = Resolve-JavaHome'),
    );
    expect(
      androidBuildScriptSource,
      contains(r'$env:APPDATA = $flutterAppData'),
    );
    expect(androidBuildScriptSource, contains(r'.runtime\flutter-appdata'));
    expect(
      androidBuildScriptSource,
      contains(r'$env:GRADLE_USER_HOME = $gradleUserHome'),
    );
    expect(androidBuildScriptSource, contains('"--no-pub"'));
  });

  test('Rust build script gates Windows native code by the target OS', () {
    expect(
      rustBuildScriptSource,
      contains('std::env::var("CARGO_CFG_TARGET_OS")'),
    );
    expect(rustBuildScriptSource, contains('if target_os == "windows"'));
    expect(
      rustBuildScriptSource,
      isNot(contains('#[cfg(windows)]\n    build_windows();')),
    );
  });

  test('mobile Flutter builds omit desktop-only debug chat recording', () {
    final newMessage = methodBody(
      rustFlutterSource,
      'fn new_message(&self, msg: String)',
      'fn switch_display(&self, display: &SwitchDisplay)',
    );
    expect(
      newMessage,
      contains(
        '#[cfg(not(any(target_os = "android", target_os = "ios")))]',
      ),
    );
    expect(newMessage, contains('crate::debug_api::record_chat_message'));
  });

  test('Windows Android AOM builds avoid unavailable GNU assembler', () {
    expect(
      androidAomPortSource,
      contains('VCPKG_TARGET_IS_ANDROID AND VCPKG_HOST_IS_WINDOWS'),
    );
    expect(androidAomPortSource, contains('-DAOM_TARGET_CPU=generic'));
  });

  test('Windows FFmpeg pkg-config option stays separate from target OS', () {
    expect(
      androidFfmpegPortSource,
      contains(r'pkgconf${VCPKG_HOST_EXECUTABLE_SUFFIX} ")'),
    );
    expect(androidFfmpegPortSource, contains('--target-os=android'));
  });

  test('launcher icons use the padded LUODA artwork on every platform', () {
    expect(pubspecSource, contains('image_path: "../res/icon_padded.png"'));
    expect(
      androidManifestSource,
      contains('android:roundIcon="@mipmap/ic_launcher_round"'),
    );
    expect(
      adaptiveIconSource,
      contains('@mipmap/ic_launcher_monochrome'),
    );
    expect(
      androidIconScriptSource,
      contains('os.path.join(repo_root, "res", "icon_padded.png")'),
    );
  });
}
