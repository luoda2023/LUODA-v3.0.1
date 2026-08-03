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
  final nativeModelSource =
      File('lib/models/native_model.dart').readAsStringSync();
  final chatPageSource =
      File('lib/common/widgets/chat_page.dart').readAsStringSync();
  final peersViewSource =
      File('lib/common/widgets/peers_view.dart').readAsStringSync();
  final sharedStateSource =
      File('lib/common/shared_state.dart').readAsStringSync();
  final flutterFfiSource = File('../src/flutter_ffi.rs').readAsStringSync();
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
        contains('row as Peer,\n              directPairings,'));
    expect(contactItem, isNot(contains('DirectPairingStore.load()')));
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

  test('mobile peer tabs group recent favorites and contacts by trust', () {
    expect(peersViewSource, contains('groupByDirectChatPolicy'));
    expect(peersViewSource, contains('_mobileGroupedRows'));
    expect(peersViewSource, contains("_PeerGroupHeader('Friends'"));
    expect(peersViewSource, contains("_PeerGroupHeader('Strangers'"));
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

  test('conversation switching reuses loaded messages and stable identity', () {
    final chatModelSource =
        File('lib/models/chat_model.dart').readAsStringSync();
    final directChatSource =
        File('lib/common/direct_chat.dart').readAsStringSync();
    final changeKey = methodBody(
      chatModelSource,
      'changeCurrentKey(MessageKey key)',
      'receive(int id, String rawText)',
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
    expect(openContact, contains('_startDirectChat(requestedId)'));
    expect(
      startChat,
      contains('DirectPairingStore.findByEndpoint(requestedId)'),
    );
  });

  test('successful IP chat sessions rekey to the canonical device ID', () {
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
    expect(persistPairing, contains('DirectPairingStore.saveDiscovered('));
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
    expect(chatPageSource, contains('onSecondaryTap: (position) async'));
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
    expect(
      desktopHomeSource,
      contains(
        'if (peerId.isEmpty || peerId == gFFI.chatModel.me.id) return false;',
      ),
    );
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
    expect(handleMsgBox, contains('_lastConnectionError = text?.toString();'));
    expect(handleMsgBox, contains('notifyListeners();'));
  });

  test('android packaging refuses to omit the luoda native library', () {
    expect(androidBuildSource, contains('requiredLuodaAbis'));
    expect(androidBuildSource, contains('verifyLuodaNativeLibraries'));
    expect(androidBuildSource, contains('libluoda.so'));
    expect(
        androidBuildSource, contains('dependsOn(verifyLuodaNativeLibraries)'));
    expect(
        androidBuildSource, isNot(contains('abiFilters += requiredLuodaAbis')));
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
