import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final peerCardSource = File(
    'lib/common/widgets/peer_card.dart',
  ).readAsStringSync();
  final homePageSource = File(
    'lib/desktop/pages/desktop_home_page.dart',
  ).readAsStringSync();
  final desktopTabSource = File(
    'lib/desktop/pages/desktop_tab_page.dart',
  ).readAsStringSync();
  final desktopMainTitleBarSource = File(
    'lib/desktop/widgets/desktop_main_title_bar.dart',
  ).readAsStringSync();
  final multiWindowManagerSource = File(
    'lib/utils/multi_window_manager.dart',
  ).readAsStringSync();
  final addressBookSource = File(
    'lib/common/widgets/address_book.dart',
  ).readAsStringSync();
  final settingsSource = File(
    'lib/desktop/pages/desktop_setting_page.dart',
  ).readAsStringSync();
  final settingsGeneralSource = File(
    'lib/desktop/pages/desktop_setting_general.part.dart',
  ).readAsStringSync();
  final settingsHelpersSource = File(
    'lib/desktop/pages/desktop_setting_helpers.part.dart',
  ).readAsStringSync();
  final remoteToolbarSource = File(
    'lib/desktop/widgets/remote_toolbar.dart',
  ).readAsStringSync();
  final viewerCollaborationSource = File(
    'lib/desktop/widgets/viewer_collaboration_panel.dart',
  ).readAsStringSync();
  final viewerListSource = File(
    'lib/common/widgets/viewer_list_panel.dart',
  ).readAsStringSync();
  final sharedChatSource = File(
    'lib/common/widgets/shared_chat_panel.dart',
  ).readAsStringSync();
  final inviteViewerSource = File(
    'lib/desktop/widgets/invite_viewer_dialog.dart',
  ).readAsStringSync();
  final joinViewerSource = File(
    'lib/common/widgets/join_viewer_page.dart',
  ).readAsStringSync();
  final desktopRailSource = File(
    'lib/desktop/widgets/desktop_primary_rail.dart',
  ).readAsStringSync();
  final modelSource = File(
    'lib/models/model.dart',
  ).readAsStringSync();
  final serverModelSource = File(
    'lib/models/server_model.dart',
  ).readAsStringSync();
  final mobileHomeSource = File(
    'lib/mobile/pages/home_page.dart',
  ).readAsStringSync();
  final mobileConnectionSource = File(
    'lib/mobile/pages/connection_page.dart',
  ).readAsStringSync();
  final mobileSettingsSource = File(
    'lib/mobile/pages/settings_page.dart',
  ).readAsStringSync();
  final mobileServerSource = File(
    'lib/mobile/pages/server_page.dart',
  ).readAsStringSync();
  final chatPageSource = File(
    'lib/common/widgets/chat_page.dart',
  ).readAsStringSync();
  final directChatSource = File(
    'lib/common/direct_chat.dart',
  ).readAsStringSync();
  final chatModelSource = File(
    'lib/models/chat_model.dart',
  ).readAsStringSync();
  final directPairingSource = File(
    'lib/common/direct_pairing.dart',
  ).readAsStringSync();
  final androidPermissionSource = File(
    'android/app/src/main/kotlin/com/luoda/remote/common.kt',
  ).readAsStringSync();
  final androidStringsSource = File(
    'android/app/src/main/res/values/strings.xml',
  ).readAsStringSync();
  final androidDirectChatServiceSource = File(
    'android/app/src/main/kotlin/com/luoda/remote/DirectChatService.kt',
  ).readAsStringSync();
  final androidMainServiceSource = File(
    'android/app/src/main/kotlin/com/luoda/remote/MainService.kt',
  ).readAsStringSync();
  final commonRustSource = File('../src/common.rs').readAsStringSync();
  final displayServiceSource = File(
    '../src/server/display_service.rs',
  ).readAsStringSync();
  final portableServiceSource = File(
    '../src/server/portable_service.rs',
  ).readAsStringSync();
  final flutterCommonSource = File(
    'lib/common.dart',
  ).readAsStringSync();
  final webBridgeSource = File(
    'lib/web/bridge.dart',
  ).readAsStringSync();
  final clientWorkflowSource = File(
    '../.github/workflows/build-client-exe.yml',
  ).readAsStringSync();
  final windowsWorkflowSource = File(
    '../.github/workflows/build-exe.yml',
  ).readAsStringSync();
  final iosWorkflowSource = File(
    '../.github/workflows/build-ios.yml',
  ).readAsStringSync();
  final msiWorkflowSource = File(
    '../.github/workflows/build-msi.yml',
  ).readAsStringSync();
  final msiProjectSource = File(
    '../res/msi/Package/Package.wixproj',
  ).readAsStringSync();
  final cargoSource = File('../Cargo.toml').readAsStringSync();
  final peerModelSource = File(
    'lib/models/peer_model.dart',
  ).readAsStringSync();
  final protocolSource = File(
    '../libs/hbb_common/protos/message.proto',
  ).readAsStringSync();
  final clientSource = File('../src/client.rs').readAsStringSync();
  final chineseLangSource = File('../src/lang/cn.rs').readAsStringSync();
  final clientIoLoopSource = File(
    '../src/client/io_loop.rs',
  ).readAsStringSync();
  final serverConnectionSource = File(
    '../src/server/connection.rs',
  ).readAsStringSync();
  final directListenerSource = File(
    '../src/rendezvous_mediator.rs',
  ).readAsStringSync();
  final serverSource = File('../src/server.rs').readAsStringSync();
  final flutterBridgeSource = File('../src/flutter.rs').readAsStringSync();
  final serverConnectionViewerSource = File(
    '../src/server/connection.rs',
  ).readAsStringSync();
  final uiSessionSource = File(
    '../src/ui_session_interface.rs',
  ).readAsStringSync();

  test('viewer control events are intercepted before ordinary chat', () {
    final guards = RegExp(
      r'if \(parent\.target\?\.viewerSessionModel\.handleWireMessage\(value\) !=\s*true\)',
    ).allMatches(modelSource);
    final clientControl = modelSource.indexOf(
      'viewerSessionModel.handleWireMessage(value)',
    );
    final clientChat = modelSource.indexOf(
      'chatModel.receive(ChatModel.clientModeID, value)',
    );
    expect(guards.length, 2);
    expect(clientControl, greaterThanOrEqualTo(0));
    expect(clientChat, greaterThan(clientControl));
  });

  test('remote collaboration panel replaces contract stubs', () {
    for (final source in <String>[
      viewerListSource,
      sharedChatSource,
      inviteViewerSource,
    ]) {
      expect(source, isNot(contains('contract stub')));
      expect(source, isNot(contains('Intentionally a no-op stub')));
    }
    expect(
      remoteToolbarSource,
      contains('ViewerCollaborationPanel.show('),
    );
    expect(viewerCollaborationSource, contains('InviteViewerDialog.show('));
    expect(viewerCollaborationSource, contains('ViewerListPanel('));
    expect(viewerCollaborationSource, contains('SharedChatPanel('));
  });

  test('viewer join is a reachable direct session on desktop and mobile', () {
    expect(joinViewerSource, isNot(contains('contract stub')));
    expect(joinViewerSource, contains('Direct endpoint'));
    expect(joinViewerSource, contains('onJoinRequested'));
    expect(homePageSource, contains('JoinViewerPage('));
    expect(mobileConnectionSource, contains('_ConnectionMode.viewer'));
    expect(mobileConnectionSource, contains('JoinViewerPage('));
    expect(inviteViewerSource, contains('ViewerInviteLink('));
  });

  test('viewer wire mode is configured before the session starts', () {
    final configure = modelSource.indexOf('sessionPrepareViewer(');
    final start = modelSource.indexOf('sessionStart(sessionId:');
    expect(configure, greaterThanOrEqualTo(0));
    expect(start, greaterThan(configure));
    expect(uiSessionSource, contains('fn viewer_join_request(&self)'));
    expect(clientIoLoopSource, contains('viewer_join_request()'));
    expect(clientIoLoopSource, contains('peer.send(&viewer_join)'));
  });

  test('server routes Flutter misc viewer controls and starts video', () {
    expect(
      serverConnectionViewerSource,
      contains('Some(misc::Union::JoinAsViewer(jv))'),
    );
    expect(
      serverConnectionViewerSource,
      contains('Some(misc::Union::ChatBroadcast(cb))'),
    );
    expect(
      serverConnectionViewerSource,
      contains('viewer_fanout::register_host('),
    );
    expect(
      serverConnectionViewerSource,
      contains('send_logon_response_and_keep_alive().await'),
    );
  });

  test('peer card more action has a real keyboard activation callback', () {
    expect(peerCardSource, isNot(contains('onTap: () {}')));
    expect(peerCardSource, contains('onTap: () => _showPeerMenu(peer.id)'));
    expect(peerCardSource, contains('onTap: onTap'));
    expect(addressBookSource, contains('onTap: () => _showMenu(menuPos)'));
  });

  test(
    'unknown platform card fallback keeps dark text at WCAG AA contrast',
    () {
      const foreground = Color(0xFF17233A);
      const fallbackStartLightness = 0.70;

      expect(peerCardSource, contains('withLightness(.70)'));
      expect(peerCardSource, contains('withLightness(.80)'));

      for (var hue = 0; hue < 360; hue++) {
        final background = HSLColor.fromAHSL(
          1,
          hue.toDouble(),
          0.62,
          fallbackStartLightness,
        ).toColor();
        expect(
          _contrastRatio(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: 'Fallback hue $hue must remain readable',
        );
      }
    },
  );

  test('UPnP unsupported status uses the existing explicit translation', () {
    expect(
      homePageSource,
      contains(
        "if (status == 'unsupported') return 'upnp_mapping_unsupported_tip';",
      ),
    );
  });

  test('desktop home keeps the chat-first three-pane shell contract', () {
    expect(homePageSource, contains('_buildPrimaryRail'));
    expect(homePageSource, contains('_buildContactsPane'));
    expect(homePageSource, contains('_buildConversationWorkspace'));
    expect(homePageSource, contains("'Paired ID / IP:port'"));
    expect(homePageSource, contains('ChatPage('));
    expect(homePageSource, contains('_sendFilesFromConversation'));
    expect(homePageSource, contains('_buildActiveTransferStrip'));
    expect(homePageSource, contains('_directChatSessionFor'));
    expect(homePageSource, contains('_maintainTrustedChatSessions'));
    expect(modelSource, contains('suppressConnectionDialogs'));
    expect(homePageSource, contains('ffi.ffiModel.direct != true'));
    expect(homePageSource, contains('chatFfi.ffiModel.direct == true'));
    expect(homePageSource, contains('localController.sendFiles'));
  });

  test('desktop contacts reuse an authorized inbound chat session', () {
    expect(homePageSource, contains('_incomingDirectChatClientFor'));
    expect(homePageSource, contains('client.authorized &&'));
    expect(homePageSource, contains('client.isChat &&'));
    expect(homePageSource, contains('!client.disconnected'));
    expect(homePageSource, contains('incoming?.id ?? ChatModel.clientModeID'));
    expect(homePageSource, contains('active == null && incoming == null'));
  });

  test('desktop contact list includes every paired direct contact', () {
    expect(homePageSource, contains('_buildPairedContactItem'));
    expect(
      homePageSource,
      contains('standalonePairings.length + peers.length'),
    );
    expect(homePageSource, isNot(contains('pairings.take(3)')));
  });

  test('desktop bottom rail opens the phone pairing QR code', () {
    expect(desktopRailSource, contains('onPairPhone'));
    expect(desktopRailSource, contains('Icons.phone_android_rounded'));
    expect(
      homePageSource,
      contains('onPairPhone: () => _showPairingQrDialog(context)'),
    );
  });

  test('desktop settings entry exists only in the bottom primary rail', () {
    expect(homePageSource, contains('onSettings: DesktopTabPage.onAddSetting'));
    expect(desktopTabSource, isNot(contains("message: 'Settings'")));
    expect(desktopTabSource, isNot(contains('tail: Offstage(')));
  });

  test('desktop main window uses a dedicated LDesk title bar', () {
    expect(desktopTabSource, contains('topBar: Obx('));
    expect(desktopTabSource, contains('return LDeskMainTitleBar('));
    expect(desktopMainTitleBarSource, contains('class LDeskMainTitleBar'));
    expect(desktopMainTitleBarSource, contains("'LDesk'"));
    expect(
      desktopMainTitleBarSource,
      contains('windowManager.startDragging()'),
    );
    expect(desktopMainTitleBarSource, contains('windowManager.maximize()'));
    expect(desktopMainTitleBarSource, contains('windowManager.unmaximize()'));
    expect(desktopMainTitleBarSource, contains('windowManager.minimize()'));
    expect(desktopMainTitleBarSource, contains('windowManager.close()'));
    expect(
      desktopTabSource,
      contains('tabController.jumpToByKey(kTabLabelHomePage)'),
    );
  });

  test('selected and recent contacts can start remote desktop directly', () {
    expect(homePageSource, contains('final canStartDirectSession ='));
    expect(
      homePageSource,
      contains('canStartDirectSession: canStartDirectSession'),
    );
    expect(
      homePageSource,
      contains(
        'onDoubleTap: () => _connectDirect(context, pairing.peerId)',
      ),
    );
    expect(
      homePageSource,
      contains('onDoubleTap: () => _connectDirect(context, peer.id)'),
    );
  });

  test('contact pane uses restrained dividers below the search controls', () {
    expect(homePageSource, contains('Color(0xFFE5E5E7)'));
    expect(homePageSource, contains('Color(0xFF3A3D43)'));
    expect(
      homePageSource,
      isNot(contains('theme.dividerColor.withOpacity(0.65)')),
    );
  });

  test('desktop session window calls cannot wait forever', () {
    expect(multiWindowManagerSource, contains('_sessionProbeTimeout'));
    expect(multiWindowManagerSource, contains('_sessionLaunchTimeout'));
    expect(multiWindowManagerSource, contains('.timeout('));
    expect(multiWindowManagerSource, contains('_discardUnresponsiveWindow'));
  });

  test('desktop rail background is local, configurable, and readable', () {
    expect(
      desktopRailSource,
      contains("'desktop-rail-background-image-v1'"),
    );
    expect(desktopRailSource, contains('desktopRailBackgroundRevision'));
    expect(desktopRailSource, contains('MemoryImage('));
    expect(desktopRailSource, contains('Color(0x80000000)'));
    expect(settingsGeneralSource, contains('FileType.image'));
    expect(settingsGeneralSource, contains('img.bakeOrientation'));
    expect(settingsGeneralSource, contains('img.copyResize'));
    expect(settingsGeneralSource, contains('img.encodeJpg'));
    expect(settingsGeneralSource, contains('bind.mainSetLocalOption('));
    expect(
      settingsGeneralSource,
      contains('desktopRailBackgroundRevision.value++'),
    );
  });

  test('settings keep every category while allowing advanced grouping', () {
    for (final category in <String>[
      'general',
      'safety',
      'network',
      'display',
      'plugin',
      'account',
      'printer',
      'about',
    ]) {
      expect(settingsSource, contains('SettingsTabKey.$category'));
    }
    expect(settingsSource, contains('_advancedSettingsExpanded'));
  });

  test('desktop settings use a compact human-scale type and spacing system',
      () {
    expect(settingsSource, contains('const double _kTabHeight = 48'));
    expect(settingsSource, contains('const double _kTitleFontSize = 18'));
    expect(settingsSource, contains('const double _kContentFontSize = 14'));
    expect(settingsSource, contains('fontSize: 18'));
    expect(settingsHelpersSource, contains('top: 16'));
    expect(settingsHelpersSource, contains('EdgeInsets.all(18)'));
    expect(settingsHelpersSource, isNot(contains('EdgeInsets.all(24)')));
  });

  test('remote assistance keeps chat and all existing session tools', () {
    expect(remoteToolbarSource, contains("translate('Text chat')"));
    expect(remoteToolbarSource, contains('_FileTransferMenu'));
    expect(remoteToolbarSource, contains('isFileTransfer: true'));
    expect(remoteToolbarSource, contains('_DisplayMenu'));
    expect(
      remoteToolbarSource.indexOf('toolbarItems.add(_ChatMenu'),
      lessThan(
        remoteToolbarSource.indexOf('toolbarItems.add(_FileTransferMenu'),
      ),
    );
    expect(
      remoteToolbarSource.indexOf('toolbarItems.add(_FileTransferMenu'),
      lessThan(remoteToolbarSource.indexOf('_ControlMenu(')),
    );
  });

  test('direct chat reconnects without exposing relay fallback', () {
    expect(modelSource, contains("'direct-chat-auto-reconnect'"));
    expect(
      modelSource,
      contains("text != 'Direct messages rejected by this contact'"),
    );
    expect(
      modelSource,
      contains('parent.target?.connType != ConnType.chat'),
    );
    expect(modelSource, contains('void markConnectionClosed()'));
    expect(modelSource, contains('ffiModel.markConnectionClosed()'));
  });

  test('mobile connection defaults to direct chat and keeps remote assist', () {
    expect(
      mobileConnectionSource,
      contains(
        '_ConnectionMode _connectionMode = _ConnectionMode.chat',
      ),
    );
    expect(mobileConnectionSource, contains('isChat: true'));
    expect(
      mobileConnectionSource,
      contains('SegmentedButton<_ConnectionMode>'),
    );
    expect(mobileHomeSource, contains('void selectChatPage()'));
    expect(chatPageSource, contains('currentKey.peerId.isEmpty'));
    expect(chatPageSource, contains('onAttachFile'));
    expect(chatPageSource, contains('onRemoteAssist'));
  });

  test('mobile messages open from a WeChat-style conversation list', () {
    expect(mobileHomeSource, contains('class _MobileMessagesPage'));
    expect(mobileHomeSource, contains('_pages.add(_MobileMessagesPage('));
    expect(mobileHomeSource, contains('ListView.separated('));
    expect(mobileHomeSource, contains('_latestMessageTime'));
    expect(mobileHomeSource, contains('_openCurrentConversation'));
    expect(mobileHomeSource, contains('isMobile && _chatDetailOpen'));
    expect(mobileHomeSource, contains('Navigator.of(context).push'));
  });

  test('mobile contacts reuse an authorized inbound chat session', () {
    expect(mobileConnectionSource, contains('lastIndexWhere((client) =>'));
    expect(
      mobileConnectionSource,
      contains('client.peerId.trim() == peerId'),
    );
    expect(
      mobileConnectionSource,
      contains('MessageKey(peerId, incoming.id)'),
    );
  });

  test('mobile shell keeps a readable chat-first WeChat-style hierarchy', () {
    expect(
      mobileHomeSource.indexOf('_pages.add(_MobileMessagesPage('),
      lessThan(mobileHomeSource.indexOf('_pages.add(ConnectionPage(')),
    );
    expect(chatPageSource, contains('translate("Messages")'));
    expect(mobileConnectionSource, contains('translate("Contacts")'));
    expect(mobileServerSource, contains('translate("Remote assistance")'));
    expect(mobileSettingsSource, contains('translate("Me")'));
    expect(mobileHomeSource, contains('selectedFontSize: 12'));
    expect(mobileHomeSource, contains('unselectedFontSize: 12'));
    expect(mobileHomeSource, contains('fontSize: 17'));
    expect(chatPageSource, contains('width: isDesktopHome ? 36 : 48'));
    expect(chatPageSource, contains('fontSize: isDesktopHome ? 14 : 15'));
    expect(chatPageSource, contains('fontSize: 11'));
    expect(chatPageSource, contains('const Color(0xFF95EC69)'));
  });

  test('mobile permission center only requests missing permissions', () {
    expect(mobileServerSource, contains('translate("Permission center")'));
    expect(mobileServerSource, contains('_completePermissions'));
    expect(mobileServerSource, contains('if (!serverModel.fileOk)'));
    expect(mobileServerSource, contains('if (!serverModel.audioOk)'));
    expect(mobileServerSource, contains('if (!_notificationOk)'));
    expect(mobileServerSource, contains('if (!serverModel.inputOk)'));
    expect(
      mobileServerSource,
      contains('didChangeAppLifecycleState(AppLifecycleState state)'),
    );
    expect(
      androidPermissionSource,
      contains('mapOf("type" to type, "result" to all)'),
    );
    expect(androidPermissionSource, isNot(contains('if (all)')));
  });

  test('always-on direct messages asks for notification permission once', () {
    expect(
      mobileSettingsSource,
      contains('Future<void> _requestDirectChatNotificationPermissionOnce()'),
    );
    expect(mobileSettingsSource, contains('androidVersion < 33'));
    expect(
      mobileSettingsSource,
      contains('AndroidPermissionManager.check(kAndroid13Notification)'),
    );
    expect(
      mobileSettingsSource,
      contains("'direct-chat-notification-permission-prompted-v1'"),
    );
    expect(
      mobileSettingsSource,
      contains('AndroidPermissionManager.request(kAndroid13Notification)'),
    );
    final alwaysOnToggle = mobileSettingsSource
        .split("title: Text(translate('Allow always-on direct messages'))")[1]
        .split(
            "title: Text(translate('Only trusted contacts can message me'))")[0];
    expect(
      alwaysOnToggle,
      contains('await _requestDirectChatNotificationPermissionOnce()'),
    );
  });

  test('LDesk branding preserves existing identity and URI compatibility', () {
    expect(
      commonRustSource,
      contains('DEFAULT_PRODUCT_DISPLAY_NAME: &str = "LDesk"'),
    );
    expect(commonRustSource, contains('if configured == "LUODA"'));
    expect(commonRustSource, contains('"luoda://".to_owned()'));
    expect(androidStringsSource,
        contains('<string name="app_name">LDesk</string>'));
    expect(cargoSource, contains('ProductName = "LDesk"'));
  });

  test('mobile conversation file transfer refuses relay sessions', () {
    expect(
      mobileHomeSource,
      contains(
        'DirectPairingStore.resolveConnectionTarget(peerId)',
      ),
    );
    expect(mobileHomeSource, contains('existing.ffiModel.direct == true'));
    expect(mobileHomeSource, contains('if (ffi.ffiModel.direct != true)'));
    expect(mobileHomeSource, contains('localController.sendFiles'));
    expect(
      mobileHomeSource,
      contains('Direct connection failed. File relay is disabled.'),
    );
  });

  test('direct chat persists, acknowledges and incrementally synchronizes', () {
    expect(directChatSource, contains('DirectChatDelivery.queued'));
    expect(directChatSource, contains('DirectChatDelivery.sent'));
    expect(directChatSource, contains('DirectChatDelivery.delivered'));
    expect(directChatSource, contains('DirectChatDelivery.failed'));
    expect(directChatSource, contains("DirectChatEnvelope('sync_request'"));
    expect(directChatSource, contains("DirectChatEnvelope('receipt'"));
    expect(directChatSource, contains('originSequence'));
    expect(directChatSource, contains('record.originSequence >'));
    expect(chatPageSource, contains("translate('Waiting to send')"));
    expect(chatPageSource, contains("translate('Delivered')"));
  });

  test('restored inbound chat sessions request missed messages', () {
    final restorePath = serverModelSource
        .split('updateClientState([String? json]) async')[1]
        .split('void addConnection')[0];
    expect(
      restorePath,
      contains('chatModel.onDirectSessionReady('),
    );
    expect(
      mobileHomeSource,
      contains('await gFFI.serverModel.updateClientState()'),
    );
  });

  test('active companion sessions refresh incremental sync every 30 minutes',
      () {
    expect(mobileHomeSource, contains('const Duration(minutes: 30)'));
    final activeSessionPath = mobileHomeSource
        .split('if (existing != null &&')[1]
        .split('if (existing != null)')[0];
    expect(
      activeSessionPath,
      contains('await existing.chatModel.requestCompanionSync('),
    );
    expect(
      chatModelSource,
      contains('Future<void> requestCompanionSync('),
    );
    expect(
      chatModelSource,
      contains('DirectChatEnvelope.replicaRequest('),
    );
  });

  test('paired direct sessions are encrypted and identity pinned', () {
    expect(protocolSource, contains('bytes public_key = 2;'));
    expect(protocolSource, contains('bytes signed_id = 3;'));
    expect(protocolSource, contains('bytes identity_public_key = 4;'));
    expect(protocolSource, contains('string pairing_secret = 3;'));
    expect(directPairingSource, contains('String get connectionTarget'));
    expect(directPairingSource, contains("'&sync="));
    expect(clientSource, contains('secure_direct_connection'));
    expect(clientSource, contains('Direct peer fingerprint mismatch'));
    expect(clientSource, contains('identity_public_key'));
    expect(clientSource, contains('direct_fallback_endpoint'));
    expect(serverSource, contains('public_key: pk.into()'));
    expect(
      directListenerSource,
      contains('hbb_common::Stream::from(tcp_stream, local_addr)'),
    );
    expect(
      directListenerSource,
      contains('let start_lan_listening = false;'),
    );
    expect(
      serverConnectionSource,
      contains('chat_companion_verified'),
    );
    expect(
      serverConnectionSource,
      contains('authenticated_peer_id'),
    );
    expect(
      serverConnectionSource,
      contains('direct-chat-peer-keys-v1'),
    );
  });

  test('direct IP probing authenticates the requested port and neighbors', () {
    expect(
        clientSource, contains('direct_probe_addresses(ip, preferred_port)'));
    expect(
      clientSource,
      contains('connect_direct_candidates(endpoint.ip(), endpoint.port())'),
    );
    expect(
      clientSource,
      contains('connect_direct_candidates(ip, DEFAULT_DIRECT_PORT as u16)'),
    );
    expect(clientSource, contains('Client::secure_direct_connection('));
  });

  test('headless Windows capture waits for the virtual display to enumerate',
      () {
    expect(
      displayServiceSource,
      allOf(
        contains('HEADLESS_DISPLAY_WAIT_TIMEOUT'),
        contains('Duration::from_secs(8)'),
      ),
    );
    expect(
      displayServiceSource,
      allOf(
        contains('HEADLESS_DISPLAY_POLL_INTERVAL'),
        contains('Duration::from_millis(200)'),
      ),
    );
    expect(displayServiceSource, contains('wait_for_headless_display()'));
    expect(
      portableServiceSource,
      contains('display_service::plug_in_headless_and_wait()'),
    );
    expect(
      portableServiceSource,
      contains('display_service::no_displays(&displays)'),
    );
  });

  test('custom desktop client consistently uses a 380 by 500 window', () {
    expect(
      flutterCommonSource,
      contains('const kCustomClientWindowSize = Size(380, 500)'),
    );
    expect(
      flutterCommonSource,
      contains('restoreWidth = kCustomClientWindowSize.width'),
    );
    expect(
      flutterCommonSource,
      contains('restoreHeight = kCustomClientWindowSize.height'),
    );
    expect(
      homePageSource,
      contains('width: kCustomClientWindowSize.width'),
    );
    expect(
      desktopTabSource,
      contains('windowManager.setSize(kCustomClientWindowSize)'),
    );
  });

  test('custom client EXE is a dedicated LDesk identity panel', () {
    final clientPanel = homePageSource
        .split('Widget buildLeftPane(BuildContext context) {')[1]
        .split('final isIncomingOnly =')[0];
    expect(clientPanel, contains('buildIDBoard(context)'));
    expect(clientPanel, contains('buildPasswordBoard(context)'));
    expect(clientPanel, contains('buildDirectAccessBoard(context)'));
    expect(
      clientPanel,
      contains('"LDesk \${translate(\'Remote assistance\')}"'),
    );
    expect(clientPanel, isNot(contains('_buildRemoteCenter')));
    expect(clientPanel, isNot(contains('DesktopSettingPage')));
    expect(desktopTabSource, contains('final title = compactClient'));
    expect(desktopTabSource, contains("translate('Remote assistance')"));
    expect(clientWorkflowSource, contains('name: Build LDesk Client EXE'));
    expect(clientWorkflowSource, contains('SignOutput/LDesk-Client-x64.exe'));
    expect(clientWorkflowSource, contains('LDesk-3.1.1-Client-x64.exe'));
    expect(clientWorkflowSource, contains('Images\\icon.ico'));
    expect(
      clientWorkflowSource,
      contains('Smoke test LDesk client identity panel'),
    );
    expect(
      clientWorkflowSource,
      contains('Normalize Windows resource encoding'),
    );
  });

  test('web session bridge accepts direct chat sessions', () {
    final sessionAdd = webBridgeSource
        .split('String sessionAddSync(')[1]
        .split('Stream<EventToUI> sessionStart')[0];
    expect(sessionAdd, contains('required bool isChat'));
    expect(sessionAdd, contains("'isChat': isChat"));
  });

  test('MSI normalizes Windows resources before Flutter build', () {
    final normalization =
        msiWorkflowSource.indexOf('Normalize Windows resource encoding');
    final flutterBuild = msiWorkflowSource.indexOf('Build Flutter Windows');
    expect(normalization, greaterThan(0));
    expect(flutterBuild, greaterThan(normalization));
  });

  test('MSI package and release asset use LDesk branding', () {
    expect(msiWorkflowSource, contains('--app-name LDesk'));
    expect(msiWorkflowSource, contains('LDesk-3.1.1-MSI'));
    expect(msiWorkflowSource, contains('LDesk-3.1.1-Setup-\$culture.msi'));
    expect(msiWorkflowSource, contains('LDesk-3.1.1-Setup-*.msi'));
    expect(msiProjectSource, contains('<OutputName>LDesk-Setup</OutputName>'));
  });

  test('desktop chat rail uses persistent conversations instead of contacts',
      () {
    expect(
      homePageSource,
      contains("if (_selectedRailId == 'chat')"),
    );
    expect(homePageSource, contains('_buildConversationList(context)'));
    expect(homePageSource, contains('gFFI.chatModel.messages.entries'));
    expect(homePageSource, contains('_conversationPreview(entry)'));
    expect(
      homePageSource,
      contains('onDoubleTap: () => _connectDirect(context, peerId)'),
    );
    expect(
      chatModelSource,
      contains('_scheduleRecentConversationRestore()'),
    );
    expect(chatModelSource, contains('identical(this, gFFI.chatModel)'));
  });

  test('Windows smoke test uploads a nonblank main-window screenshot', () {
    expect(windowsWorkflowSource, contains('LDesk-main-window.png'));
    expect(windowsWorkflowSource, contains('CopyFromScreen'));
    expect(windowsWorkflowSource, contains('Screenshot appears blank'));
  });

  test('mobile contacts show identity and direct-message policy status', () {
    expect(mobileConnectionSource, contains('_pairedContactAvatar(pairing)'));
    expect(mobileConnectionSource, contains('_pairedMessageStatus(pairing)'));
    expect(mobileConnectionSource, contains("'Messages allowed'"));
    expect(mobileConnectionSource, contains("'Messages rejected'"));
    expect(mobileConnectionSource, contains('avatar: pairing.avatar'));
    expect(chineseLangSource, contains('"Search conversations"'));
    expect(chineseLangSource, contains('"Not connected"'));
  });

  test('iOS release keeps the unsigned IPA when signing is unavailable', () {
    expect(iosWorkflowSource, contains('Upload IPA to draft release'));
    expect(iosWorkflowSource, contains('LDesk-3.1.1-unsigned.ipa'));
    expect(iosWorkflowSource, contains('files: flutter/build/ios/ipa/*.ipa'));
  });

  test('Android always-on chat uses a dedicated messaging service', () {
    expect(
      androidDirectChatServiceSource,
      contains('class DirectChatService : Service()'),
    );
    expect(androidDirectChatServiceSource, contains('START_STICKY'));
    expect(androidDirectChatServiceSource, contains('FFI.startServer'));
    expect(
      androidDirectChatServiceSource,
      contains('FFI.initDirectChatService(this)'),
    );
    expect(
      androidDirectChatServiceSource,
      contains('"direct_chat_message"'),
    );
    expect(
      flutterBridgeSource,
      contains('call_direct_chat_service_set_by_name'),
    );
    expect(
      mobileSettingsSource,
      contains("invokeMethod('set_direct_chat_service', value)"),
    );
    expect(androidMainServiceSource, contains('val isChat ='));
    expect(
      androidMainServiceSource,
      contains('!isFileTransfer && !isChat && !isStart'),
    );
  });

  test('local identity and always-on messaging settings remain available', () {
    expect(mobileSettingsSource, contains("key: 'user_info'"));
    expect(
      mobileSettingsSource,
      contains('gFFI.chatModel.refreshLocalIdentity(notify: true)'),
    );
    expect(
      settingsSource,
      contains('gFFI.chatModel.refreshLocalIdentity(notify: true)'),
    );
    expect(
      mobileSettingsSource,
      contains("key: 'direct-chat-always-on'"),
    );
    expect(
      mobileSettingsSource,
      contains("key: 'direct-chat-trusted-only'"),
    );
    expect(
      mobileSettingsSource,
      contains("key: 'direct-chat-auto-reconnect'"),
    );
    expect(
      mobileSettingsSource,
      contains("key: 'direct-chat-contact-policies'"),
    );
  });

  test('peer display name and avatar cross the direct protocol both ways', () {
    expect(protocolSource, contains('string display_name = 14;'));
    expect(protocolSource, contains('string avatar = 15;'));
    expect(protocolSource, contains('string peer_id = 16;'));
    expect(clientSource, contains('display_name: pi.display_name.clone()'));
    expect(clientSource, contains('avatar: pi.avatar.clone()'));
    expect(serverConnectionSource, contains('local_profile_identity'));
    expect(serverConnectionSource, contains('peer.store(&peer_id)'));
    expect(flutterBridgeSource, contains('("display_name", &pi.display_name)'));
    expect(flutterBridgeSource, contains('("avatar", &pi.avatar)'));
    expect(modelSource, contains("_pi.displayName = evt['display_name']"));
    expect(modelSource, contains("_pi.avatar = evt['avatar']"));
  });

  test('peer profile fields stay out of address-book upload payloads', () {
    final customJsonBody = peerModelSource
        .split('toCustomJson({required bool includingHash})')[1]
        .split('toGroupCacheJson()')[0];
    expect(customJsonBody, isNot(contains('display_name')));
    expect(customJsonBody, isNot(contains('avatar')));
  });

  test('local profile takes precedence over account profile on direct links',
      () {
    final clientIdentity = clientSource
        .split('fn create_login_msg(')[1]
        .split('let mut lr = LoginRequest')[0];
    expect(
      clientIdentity.indexOf('LocalConfig::get_option("user_info")'),
      lessThan(
        clientIdentity.indexOf('get_builtin_option(keys::OPTION_AVATAR)'),
      ),
    );
    final serverIdentity = serverConnectionSource
        .split('fn local_profile_identity(')[1]
        .split('#[cfg(any(target_os')[0];
    expect(
      serverIdentity.indexOf('read_user_info("display_name")'),
      lessThan(
        serverIdentity.indexOf(
          'get_builtin_option(keys::OPTION_DISPLAY_NAME)',
        ),
      ),
    );
    expect(
      serverIdentity.indexOf('read_user_info("avatar")'),
      lessThan(
        serverIdentity.indexOf('get_builtin_option(keys::OPTION_AVATAR)'),
      ),
    );
  });
}
