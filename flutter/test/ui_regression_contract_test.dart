import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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
  final mainSource = File(
    'lib/main.dart',
  ).readAsStringSync();
  final peerCardSource = File(
    'lib/common/widgets/peer_card.dart',
  ).readAsStringSync();
  final homePageSource = File(
    'lib/desktop/pages/desktop_home_page.dart',
  ).readAsStringSync();
  final commonSource = File(
    'lib/common.dart',
  ).readAsStringSync();
  final emailDraftSource = File(
    'lib/common/email_draft_service.dart',
  ).readAsStringSync();
  final desktopConnectionSource = File(
    'lib/desktop/pages/connection_page.dart',
  ).readAsStringSync();
  final clipboardImageProbeSource = File(
    'lib/desktop/clipboard_image_probe.dart',
  ).readAsStringSync();
  final clipboardImageProbeNativeSource = File(
    'lib/desktop/clipboard_image_probe_native.dart',
  ).readAsStringSync();
  final remotePageSource = File(
    'lib/desktop/pages/remote_page.dart',
  ).readAsStringSync();
  final remoteTabSource = File(
    'lib/desktop/pages/remote_tab_page.dart',
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
  final settingsAboutSource = File(
    'lib/desktop/pages/desktop_setting_about.part.dart',
  ).readAsStringSync();
  final desktopNetworkSettingsSource = File(
    'lib/desktop/pages/desktop_setting_network.part.dart',
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
  final localContactsSource = File(
    'lib/common/widgets/local_contacts_view.dart',
  ).readAsStringSync();
  final peerTabStripSource = File(
    'lib/common/widgets/peer_tab_strip.dart',
  ).readAsStringSync();
  final desktopServerSource = File(
    'lib/desktop/pages/server_page.dart',
  ).readAsStringSync();
  final mobileSettingsSource = File(
    'lib/mobile/pages/settings_page.dart',
  ).readAsStringSync();
  final mobileServerSource = File(
    'lib/mobile/pages/server_page.dart',
  ).readAsStringSync();
  final mobileRemoteSource = File(
    'lib/mobile/pages/remote_page.dart',
  ).readAsStringSync();
  final mobileScanSource = File(
    'lib/mobile/pages/scan_page.dart',
  ).readAsStringSync();
  final bluetoothChatSource = File(
    'lib/mobile/pages/bt_chat_page.dart',
  ).readAsStringSync();
  final androidManifestSource = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final chatPageSource = File(
    'lib/common/widgets/chat_page.dart',
  ).readAsStringSync();
  final richTextEmojiSource = File(
    'lib/common/widgets/rich_text_builder.dart',
  ).readAsStringSync();
  final meetingGroupPanelSource = File(
    'lib/common/widgets/meeting_group_panel.dart',
  ).readAsStringSync();
  final pluginSettingsSource = File(
    'lib/plugin/widgets/desktop_settings.dart',
  ).readAsStringSync();
  final fileViewerSource = File(
    'lib/common/widgets/file_viewer.dart',
  ).readAsStringSync();
  final filePreviewPageSource = File(
    'lib/desktop/pages/file_preview_page.dart',
  ).readAsStringSync();
  final weChatTokensSource = File(
    'lib/common/wechat_ui_tokens.dart',
  ).readAsStringSync();
  final voiceMessageControlsSource = File(
    'lib/common/widgets/voice_message_controls.dart',
  ).readAsStringSync();
  final directVoiceStorageSource = File(
    'lib/common/direct_voice_storage_io.dart',
  ).readAsStringSync();
  final directChatSource = File(
    'lib/common/direct_chat.dart',
  ).readAsStringSync();
  final directChatPolicySource = File(
    'lib/common/direct_chat_policy.dart',
  ).readAsStringSync();
  final directChatStorageSource = File(
    'lib/common/direct_chat_storage_io.dart',
  ).readAsStringSync();
  final chatModelSource = File(
    'lib/models/chat_model.dart',
  ).readAsStringSync();
  final chatSettingsModelSource = File(
    'lib/models/chat_settings_model.dart',
  ).readAsStringSync();
  final directPairingSource = File(
    'lib/common/direct_pairing.dart',
  ).readAsStringSync();
  final directConnectionDetailsSource = File(
    'lib/common/widgets/direct_connection_details.dart',
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
  final androidAppGradleSource = File(
    'android/app/build.gradle.kts',
  ).readAsStringSync();
  final commonRustSource = File('../src/common.rs').readAsStringSync();
  final configRustSource = File(
    '../libs/hbb_common/src/config.rs',
  ).readAsStringSync();
  final clientRustSource = File('../src/client.rs').readAsStringSync();
  final rendezvousRustSource =
      File('../src/rendezvous_mediator.rs').readAsStringSync();
  final coreMainSource = File('../src/core_main.rs').readAsStringSync();
  final platformWindowsSource = File(
    '../src/platform/windows.rs',
  ).readAsStringSync();
  final flutterFfiSource = File('../src/flutter_ffi.rs').readAsStringSync();
  final portablePackerSource = File(
    '../libs/portable/src/main.rs',
  ).readAsStringSync();
  final portablePackerUiSource = File(
    '../libs/portable/src/ui.rs',
  ).readAsStringSync();
  final portablePackerCargoSource = File(
    '../libs/portable/Cargo.toml',
  ).readAsStringSync();
  final displayServiceSource = File(
    '../src/server/display_service.rs',
  ).readAsStringSync();
  final videoServiceSource = File(
    '../src/server/video_service.rs',
  ).readAsStringSync();
  final virtualDisplaySource = File(
    '../src/virtual_display_manager.rs',
  ).readAsStringSync();
  final portableServiceSource = File(
    '../src/server/portable_service.rs',
  ).readAsStringSync();
  final remotePrinterSource = File(
    '../libs/remote_printer/src/lib.rs',
  ).readAsStringSync();
  final flutterCommonSource = File(
    'lib/common.dart',
  ).readAsStringSync();
  final flutterMainSource = File(
    'lib/main.dart',
  ).readAsStringSync();
  final windowsRunnerMainSource = File(
    'windows/runner/main.cpp',
  ).readAsStringSync();
  final runtimeLoggerSource = File(
    'lib/runtime_logger.dart',
  ).readAsStringSync();
  final rustLanguageSource = File(
    '../src/lang.rs',
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
  final macosWorkflowSource = File(
    '../.github/workflows/build-dmg.yml',
  ).readAsStringSync();
  final macosPodfileSource = File(
    'macos/Podfile',
  ).readAsStringSync();
  final macosProjectSource = File(
    'macos/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();
  final msiWorkflowSource = File(
    '../.github/workflows/build-msi.yml',
  ).readAsStringSync();
  final msiProjectSource = File(
    '../res/msi/Package/Package.wixproj',
  ).readAsStringSync();
  final msiPackageSource = File(
    '../res/msi/Package/Components/LUODA.wxs',
  ).readAsStringSync();
  final cargoSource = File('../Cargo.toml').readAsStringSync();
  final pubspecSource = File('pubspec.yaml').readAsStringSync();
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
  final traySource = File('../src/tray.rs').readAsStringSync();
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
  final ipcSource = File('../src/ipc.rs').readAsStringSync();
  final uiCmSource = File(
    '../src/ui_cm_interface.rs',
  ).readAsStringSync();

  final uiSessionSource = File(
    '../src/ui_session_interface.rs',
  ).readAsStringSync();

  test('viewer control events are intercepted before ordinary chat', () {
    final guards = RegExp(
      r'viewerSessionModel\.handleWireMessage\(value\)',
    ).allMatches(modelSource);
    final consumedGuards = RegExp(
      r'if \(consumed != true\)',
    ).allMatches(modelSource);
    final clientControl = modelSource.indexOf(
      'viewerSessionModel.handleWireMessage(value)',
    );
    final clientChat = modelSource.indexOf(
      'chatModel.receive(ChatModel.clientModeID, value)',
    );
    expect(guards.length, 2);
    expect(consumedGuards.length, 2);
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
    expect(
      remoteToolbarSource,
      contains('ViewerCollaborationPanel.showInvite('),
    );
    expect(viewerCollaborationSource, contains('InviteViewerDialog.show('));
    expect(viewerCollaborationSource, contains("translate('Invite Viewer')"));
    expect(
      viewerCollaborationSource,
      contains("translate('Viewer permission required')"),
    );
    expect(viewerCollaborationSource, contains('ViewerListPanel('));
    expect(viewerCollaborationSource, contains('SharedChatPanel('));
  });

  test('viewer join is reachable by device ID or direct endpoint', () {
    expect(joinViewerSource, isNot(contains('contract stub')));
    expect(joinViewerSource, contains("translate('ID or IP:port')"));
    expect(joinViewerSource, contains('isViewerConnectionTarget(endpoint)'));
    expect(joinViewerSource, contains('onJoinRequested'));
    expect(homePageSource, contains('JoinViewerPage('));
    expect(mobileConnectionSource, contains('_ConnectionMode.viewer'));
    expect(mobileConnectionSource, contains('JoinViewerPage('));
    expect(inviteViewerSource, contains('ViewerInviteLink('));
  });

  test('viewer invites require explicit permission from the controlled side',
      () {
    expect(protocolSource, contains('Viewer = 9;'));
    expect(clientIoLoopSource, contains('Ok(Permission::Viewer)'));
    expect(modelSource, contains("_permissions['viewer'] == true"));
    expect(serverModelSource, contains('bool viewer = false'));
    expect(desktopServerSource, contains('Icons.group_add_outlined'));
    expect(desktopServerSource, contains('name: "viewer"'));
    expect(viewerCollaborationSource, contains('ffi.ffiModel.viewer'));
    expect(serverConnectionSource,
        contains('viewer invite request rejected: permission disabled'));
    expect(ipcSource, contains('viewer: bool'));
    expect(uiCmSource, contains('pub viewer: bool'));
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
    expect(homePageSource, contains("translate('Connect by ID / IP')"));
    expect(homePageSource, contains('ChatPage('));
    expect(homePageSource, contains('_sendFilesFromConversation'));
    expect(homePageSource, contains('_buildActiveTransferStrip'));
    expect(homePageSource, contains('_directChatSessionFor'));
    expect(homePageSource, contains('_maintainTrustedChatSessions'));
    expect(modelSource, contains('suppressConnectionDialogs'));
    expect(homePageSource, contains('ffi.ffiModel.direct != true'));
    expect(homePageSource, contains('isDirectChatSessionReady('));
    expect(homePageSource, contains('localController.sendFiles'));
  });

  test('desktop primary rail does not duplicate recent access history', () {
    final railFlow = homePageSource
        .split('Widget _buildPrimaryRail')[1]
        .split('Future<void> _selectSection')[0];
    expect(railFlow, contains("id: 'recent'"));
    expect(railFlow, isNot(contains("id: 'history'")));
    final sectionFlow = homePageSource
        .split('Future<void> _selectSection')[1]
        .split('Widget _buildContactsPane')[0];
    expect(sectionFlow, isNot(contains("'history'")));
    final settingsRailFlow = settingsSource
        .split('Widget _buildPrimaryRail')[1]
        .split('return DesktopPrimaryRail')[0];
    expect(settingsRailFlow, isNot(contains("id: 'history'")));
  });

  test('desktop shell localizes visible copy and exposes network state', () {
    for (final key in <String>[
      'Messages',
      'Recent sessions',
      'Favorites',
      'Contacts',
      'Search conversations',
      'Connect by ID / IP',
      'Remote assistance',
      'Join as Viewer',
      'Pair phone',
      'My Identity',
    ]) {
      expect(homePageSource, contains("translate('$key')"));
    }
    expect(homePageSource, contains('_buildWorkspaceNotice(context)'));
    expect(
        homePageSource, isNot(contains('_buildNetworkStatusBadge(context)')));
    expect(homePageSource, contains('serverModel.connectStatus'));
    expect(homePageSource, isNot(contains("label: '消息'")));
    expect(homePageSource, isNot(contains("Text('连接对方')")));
    expect(desktopRailSource, isNot(contains("label: '设置'")));
  });

  test('new desktop shell exposes message audience beside local status', () {
    expect(homePageSource, contains('onSelected: _selectSection'));
    expect(homePageSource, contains('_buildPresenceStatusStrip(context)'));
    expect(homePageSource, contains("translate('My status')"));
    expect(homePageSource, contains("translate('Message permissions')"));
    expect(homePageSource, contains('DirectChatAudience.friendsOnly'));
    expect(homePageSource, contains('DirectChatAudience.everyone'));
    expect(homePageSource, contains('position: PopupMenuPosition.under'));
    expect(homePageSource, contains('offset: const Offset(0, 8)'));
    expect(
      homePageSource,
      contains('BoxConstraints.tightFor(width: 288)'),
    );
    expect(homePageSource, contains("addGroup('Friends', true)"));
    expect(homePageSource, contains("addGroup('Strangers', false)"));
    expect(
      desktopTabSource,
      contains('DesktopHomePage.selectSection'),
    );
    expect(desktopTabSource, isNot(contains('PeerTabPage.selectDesktopTab')));
  });

  test('message permission menu uses the standard compact desktop row height',
      () {
    final audienceMenu = homePageSource
        .split('Widget _messageAudienceCell(BuildContext context)')[1]
        .split('void _showDirectConnectDialog(BuildContext context)')[0];

    expect('height: 36'.allMatches(audienceMenu).length, 2);
    expect(audienceMenu, contains('fontSize: 13'));
    expect(audienceMenu, contains('height: 1'));
  });

  test('managed entry context menu uses one compact text and row height', () {
    final managedEntryMenu = homePageSource
        .split('Future<void> _showManagedEntryMenu(')[1]
        .split('@override\n  Widget build(BuildContext context)')[0];

    // 9 项：选择/收藏/好友或陌生/标签/移动/静音/关闭震动/拉黑/删除。
    expect('height: 36'.allMatches(managedEntryMenu).length, 9);
    expect(managedEntryMenu, contains('fontSize: 13'));
    expect(managedEntryMenu, contains('height: 1'));
    expect(managedEntryMenu, contains('letterSpacing: 0'));
    expect(
      managedEntryMenu,
      contains('constraints: const BoxConstraints.tightFor(width: 176)'),
    );
  });

  test('conversation header replaces file transfer with active chat search',
      () {
    final header = homePageSource
        .split('Widget _buildConversationHeader(')[1]
        .split('Widget _conversationActionButton(')[0];

    expect(header, contains('required ChatModel chatModel'));
    expect(header, contains("tooltip: translate('Search Messages')"));
    expect(header, contains('chatModel.openChatSearch'));
    expect(header, isNot(contains("tooltip: translate('File Transfer')")));
    expect(header, isNot(contains('_sendFilesFromConversation(peerId)')));
    expect(chatPageSource, contains('chatSearchMatches'));
    expect(chatPageSource, contains('selectPreviousChatSearchResult'));
    expect(chatPageSource, contains('selectNextChatSearchResult'));
    expect(chatPageSource, contains("translate('No results')"));
    expect(chatModelSource, contains('final FocusNode chatSearchFocusNode'));
    expect(chatModelSource, contains('void openChatSearch()'));
    expect(chatModelSource, contains('void closeChatSearch()'));
    expect(
        chatPageSource, contains('focusNode: chatModel.chatSearchFocusNode'));
    expect(chatPageSource, contains('autofocus: false'));
    expect(chatPageSource, contains('chatModel.closeChatSearch'));
  });

  test('switch-side requests require an explicit local confirmation', () {
    final switchBackFlow = modelSource
        .split("} else if (name == 'switch_back')")[1]
        .split("} else if (name == 'portable_service_running')")[0];
    expect(switchBackFlow, contains('showConfirmSwitchSidesDialog('));
    expect(switchBackFlow, isNot(contains('await bind.sessionSwitchSides(')));
  });

  test('desktop and mobile avatars expose persistent mute and block badges',
      () {
    final desktopAvatar = homePageSource
        .split('Widget _buildConversationAvatar({')[1]
        .split('Peers _contactModelFor(String section)')[0];
    final mobileAvatar = mobileHomeSource
        .split('Widget _avatar(MapEntry<MessageKey, MessageBody> entry)')[1]
        .split('Widget _buildAudienceSelector(')[0];

    for (final avatar in <String>[desktopAvatar, mobileAvatar]) {
      expect(avatar, contains('chatSettingsModel.isMuted'));
      expect(avatar, contains('chatSettingsModel.isBlocked'));
      expect(avatar, contains('Icons.volume_off_rounded'));
      expect(avatar, contains('Icons.block_rounded'));
    }
    expect(
      homePageSource,
      contains('gFFI.chatSettingsModel,\n        _directChatAccess,'),
    );
    expect(chatSettingsModelSource, contains('void _ensureLoaded()'));
    expect(
      chatSettingsModelSource,
      contains('DirectPairingStore.canonicalConversationId'),
    );
  });

  test('connection failures stay actionable and settings navigation stays live',
      () {
    expect(remotePageSource, contains('_buildConnectionFailure'));
    expect(remotePageSource, contains('clearConnectionError'));
    expect(remotePageSource, contains("translate('Retry')"));
    expect(
      uiSessionSource,
      contains('self.lc.write().unwrap().force_relay = force_relay;'),
    );
    final settingsLayout = settingsSource
        .split('final iconOnly = tabWidth == 64;')[1]
        .split('Widget _header(')[0];
    expect(settingsLayout, contains('return Row('));
    expect(
      settingsLayout.indexOf('_buildPrimaryRail(context)'),
      lessThan(settingsLayout.indexOf('child: _buildBlock')),
    );
  });

  test('remote window exposes the active direct or relay route without hover',
      () {
    expect(
      remoteTabSource,
      contains("translate(direct ? 'Direct' : 'Relay')"),
    );
    expect(remoteTabSource, contains("streamType == 'Relay'"));
    expect(remoteTabSource, contains(r"'$route / $streamType'"));
    expect(remoteTabSource, contains('getConnectionText('));
  });

  test('language changes notify other windows before rebuilding the shell', () {
    final changeIndex = settingsGeneralSource.indexOf(
      'bind.mainChangeLanguage(lang: key)',
    );
    final reloadIndex = settingsGeneralSource.indexOf('reloadAllWindows()');
    expect(changeIndex, greaterThanOrEqualTo(0));
    expect(reloadIndex, greaterThan(changeIndex));
  });

  test('desktop chat matches the latest WeChat density and bubble language',
      () {
    for (final color in <String>[
      '0xFFE3E8E5',
      '0xFFF0F1F2',
      '0xFFF7F7F7',
      '0xFF95EC69',
      '0xFF07C160',
      '0xFFE5E5E5',
      '0xFFFFFFFF',
    ]) {
      expect(weChatTokensSource, contains(color));
    }
    expect(
        desktopMainTitleBarSource, contains('static const double height = 32'));
    expect(desktopMainTitleBarSource, contains('windowManager.setAlwaysOnTop'));
    expect(desktopMainTitleBarSource, contains('workspaceChrome'));
    expect(desktopMainTitleBarSource, contains('weChatConversationListWidth'));
    expect(desktopRailSource, contains('kWeChatChromeColor'));
    expect(desktopRailSource, contains('kWeChatDesktopRailWidth'));
    expect(desktopRailSource, isNot(contains('LinearGradient(')));
    expect(homePageSource, contains('weChatConversationListWidth'));
    expect(homePageSource, contains('height: 68'));
    expect(homePageSource, contains('kWeChatSelectedConversationColor'));
    expect(chatPageSource, contains('class _DesktopChatComposer'));
    expect(chatPageSource, contains('_collapsedHeight = 132'));
    expect(chatPageSource, contains('_expandedHeight = 260'));
    expect(chatPageSource, contains('class _ChatBubbleTailPainter'));
    expect(chatPageSource, contains('BorderRadius.circular(5)'));
    expect(chatPageSource, contains('scaledBubbleWidth'));
    expect(chatPageSource, contains('bubbleWidthCap'));
    expect(chatPageSource, contains('responsiveBubbleWidth'));
    expect(chatPageSource,
        contains('separatorFrequency: SeparatorFrequency.hours'));
    expect(sharedChatSource, contains('class _SharedChatBubbleTailPainter'));
    expect(
      _contrastRatio(
        const Color(0xFF181818),
        const Color(0xFF9DF29F),
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('desktop contacts reuse an authorized inbound chat session', () {
    expect(homePageSource, contains('_incomingDirectChatClientFor'));
    expect(
      homePageSource,
      contains('DirectPairingStore.conversationPeerIds(peerId)'),
    );
    expect(
      homePageSource,
      contains('DirectPairingStore.conversationPeerIds(client.peerId)'),
    );
    expect(homePageSource, contains('client.authorized &&'));
    expect(homePageSource, contains('client.isChat &&'));
    expect(homePageSource, contains('!client.disconnected'));
    expect(homePageSource, contains('incoming?.id ?? ChatModel.clientModeID'));
    expect(homePageSource, contains('active == null && incoming == null'));
    final workspaceRoute = homePageSource
        .split('Widget _buildConversationWorkspace(BuildContext context) {')[1]
        .split('Future<void> _setConversationAlias')[0];
    expect(
      workspaceRoute,
      contains('final incoming = _incomingDirectChatClientFor(peerId);'),
    );
    expect(
      workspaceRoute,
      contains('incoming == null ? configuredFfi : null'),
    );
  });

  test('message conversations swipe right between friend and stranger groups',
      () {
    final conversationList = homePageSource
        .split('Widget _buildConversationList(BuildContext context)')[1]
        .split('Widget _buildContactItem(')[0];

    expect(conversationList, contains('Dismissible('));
    expect(
      conversationList,
      contains('direction: DismissDirection.startToEnd'),
    );
    expect(conversationList, contains('confirmDismiss: (_) async'));
    expect(conversationList, contains("isFriend ? 'ask' : 'allow'"));
    expect(conversationList, contains('_directChatAccess.setPeerPolicy('));
    expect(conversationList, isNot(contains('LongPressDraggable<String>')));
  });

  test('stale outbound chat sessions are shown offline and reconnected', () {
    final deliveryStatus = homePageSource
        .split('(String, Color) _directDeliveryStatus(')[1]
        .split('Future<void> _loadContactSection')[0];
    final startDirectChat = homePageSource
        .split('Future<void> _startDirectChat(')[1]
        .split('Future<void> _persistDirectChatSession')[0];

    expect(deliveryStatus, contains('isDirectChatSessionReady('));
    expect(
        startDirectChat, contains('final ready = isDirectChatSessionReady('));
    expect(startDirectChat, contains('if (ready || connecting)'));
  });

  test('chat-only connection manager starts hidden without a waiting window',
      () {
    final runConnectionManager = mainSource
        .split('void runConnectionManagerScreen() async {')[1]
        .split('bool _isCmReadyToShow = false;')[0];
    expect(
      runConnectionManager,
      contains('await hideCmWindow(isStartup: true);'),
    );
    expect(
      runConnectionManager,
      isNot(contains('await showCmWindow(isStartup: true);')),
    );
    expect(runConnectionManager, contains('updateClientState()'));
  });

  test('main window bridges hidden connection-manager chat sessions', () {
    expect(ipcSource, contains('CmQueryClients'));
    expect(ipcSource, contains('CmClientsState(String)'));
    expect(ipcSource, contains('CmSendChat'));
    expect(uiCmSource, contains('chat_message_revision'));
    expect(uiCmSource, contains('Data::CmQueryClients'));
    expect(uiCmSource, contains('Data::CmSendChat'));
    expect(flutterFfiSource, contains('cm_clients_state_from_ipc'));
    expect(flutterFfiSource, contains('Data::CmSendChat'));
    expect(
      serverModelSource,
      contains('desktopType == DesktopType.main'),
    );
    expect(serverModelSource, contains('chatOnly: true'));
    expect(serverModelSource, contains('chatMessageRevision'));
  });

  test('desktop contact list includes every paired direct contact', () {
    expect(homePageSource, contains('_buildPairedContactItem'));
    expect(homePageSource, contains('rows.addAll(grouped)'));
    expect(homePageSource, contains('rows.addAll(personGroups)'));
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

  test('desktop rail omits the redundant bottom more button', () {
    expect(homePageSource, isNot(contains('onMore:')));
    expect(
      desktopRailSource,
      contains('if (onMore != null)'),
    );
  });

  test('conversation hover and selection keep readable foregrounds', () {
    expect(
      weChatTokensSource,
      contains('kWeChatConversationHoverColor'),
    );
    expect(homePageSource, contains('hoverColor: conversationHoverColor'));
    expect(
      RegExp(
        r'color:\s*selected\s*\?\s*Colors\.white\s*:\s*theme\.colorScheme\.onSurface',
      ).hasMatch(homePageSource),
      isTrue,
    );
    expect(
      _contrastRatio(
        Colors.white,
        const Color(0xFF057A3A),
      ),
      greaterThanOrEqualTo(4.5),
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
    expect(desktopMainTitleBarSource, contains("brandName = '点聊'"));
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
      contains('controller.jumpToByKey(kTabLabelHomePage)'),
    );
  });

  test('conversation rows do not start remote desktop on double click', () {
    expect(homePageSource, contains('final canStartDirectSession ='));
    expect(
      homePageSource,
      contains('canStartDirectSession: canStartDirectSession'),
    );
    expect(
      homePageSource,
      isNot(contains(
        'onDoubleTap: () => _connectDirect(context, pairing.peerId)',
      )),
    );
    expect(
      homePageSource,
      isNot(contains('onDoubleTap: () => _connectDirect(context, peer.id)')),
    );
  });

  test('desktop and mobile expose verified P2P device and IP details', () {
    expect(
      directConnectionDetailsSource,
      contains('DirectPairingStore.boundDevices'),
    );
    expect(directConnectionDetailsSource, contains('endpointHistory'));
    expect(
      directConnectionDetailsSource,
      contains('DirectPairingStore.bindDevice'),
    );
    expect(
      directConnectionDetailsSource,
      contains('DirectPairingStore.unbindDevice'),
    );
    expect(homePageSource, contains('showDirectConnectionDetails('));
    expect(mobileHomeSource, contains('showDirectConnectionDetails('));
    expect(
      directChatPolicySource,
      contains('DirectPairingStore.canonicalConversationId(peerId)'),
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

  test('desktop network keeps protocol switches behind advanced settings', () {
    expect(
      desktopNetworkSettingsSource,
      contains('bool _showAdvancedNetworkSettings = false;'),
    );
    expect(
      desktopNetworkSettingsSource,
      contains('if (_showAdvancedNetworkSettings) network(context)'),
    );
    expect(
      RegExp(r'if \(_showAdvancedNetworkSettings\)')
          .allMatches(desktopNetworkSettingsSource)
          .length,
      greaterThanOrEqualTo(5),
    );
  });

  test('desktop general settings show only common choices by default', () {
    final primaryFlow = settingsGeneralSource
        .split('Widget build(BuildContext context)')[1]
        .split('Widget _otherSettings()')[0];
    expect(primaryFlow, contains('service()'));
    expect(primaryFlow, contains('theme()'));
    expect(primaryFlow, contains('language()'));
    expect(primaryFlow, isNot(contains('railBackground()')));
    expect(primaryFlow, isNot(contains('audio(context)')));
    expect(primaryFlow, isNot(contains('record(context)')));

    final advancedFlow = settingsGeneralSource
        .split('Widget _otherSettings()')[1]
        .split('Widget theme()')[0];
    expect(advancedFlow, contains("translate('Advanced settings')"));
    expect(advancedFlow, contains('railBackground()'));
    expect(advancedFlow, contains('audio(context)'));
    expect(advancedFlow, contains('record(context)'));
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
    expect(
      modelSource,
      contains('DirectChatAccessController.instance.shouldAutoReconnect'),
    );
    expect(
      directChatPolicySource,
      contains("autoReconnectKey = 'direct-chat-auto-reconnect'"),
    );
    expect(
      modelSource,
      contains("text == 'Direct messages rejected by this contact'"),
    );
    expect(
      modelSource,
      contains('parent.target?.connType != ConnType.chat'),
    );
    expect(modelSource, contains('void markConnectionClosed()'));
    expect(modelSource, contains('ffiModel.markConnectionClosed()'));
  });

  test('direct chat never opens remote authentication dialogs', () {
    final msgBoxPrelude = modelSource
        .split('handleMsgBox(Map<String, dynamic> evt')[1]
        .split("if (type == 're-input-password')")[0];

    expect(msgBoxPrelude, contains('connType == ConnType.chat'));
    for (final type in <String>[
      'input-password',
      're-input-password',
      'input-2fa',
      'session-login',
      'session-re-login',
      'session-login-password',
      'session-login-re-password',
    ]) {
      expect(msgBoxPrelude, contains("'$type'"));
    }
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
      contains('_buildConnectionModeSwitch'),
    );
    expect(mobileHomeSource, contains('void selectChatPage()'));
    expect(chatPageSource, contains('currentKey.peerId.isEmpty'));
    expect(chatPageSource, contains('onAttachFile'));
    expect(chatPageSource, contains('onRemoteAssist'));
  });

  test('mobile messages open from a WeChat-style conversation list', () {
    expect(mobileHomeSource, contains('class _MobileMessagesPage'));
    expect(mobileHomeSource, contains('_pages.add(_MobileMessagesPage('));
    expect(mobileHomeSource, contains('ListView.builder('));
    expect(mobileHomeSource, contains('_latestMessageTime'));
    expect(mobileHomeSource, contains('_openCurrentConversation'));
    expect(mobileHomeSource, contains('isMobile && _chatDetailOpen'));
    expect(mobileHomeSource, contains('Navigator.of(context).push'));
  });

  test('mobile contacts reuse an authorized inbound chat session', () {
    expect(
      mobileConnectionSource,
      contains('lastIndexWhere((client) {'),
    );
    expect(
      mobileConnectionSource,
      contains('DirectPairingStore.conversationPeerIds(client.peerId)'),
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
    expect(mobileHomeSource, contains('MobileText.title'));
    expect(chatPageSource, contains('width: isDesktopHome ? 36 : 48'));
    expect(chatPageSource, contains('fontSize: isDesktopHome ? 14 : 15'));
    expect(chatPageSource, contains('fontSize: 11'));
    expect(chatPageSource, contains('const Color(0xFF95EC69)'));
  });

  test('message source labels survive live receive restore and pagination', () {
    final restoreConversation = chatModelSource
        .split('Future<void> _restoreConversation(MessageKey key) async {')[1]
        .split('bool hasOlderMessages(MessageKey key)')[0];
    final loadOlder = chatModelSource
        .split('Future<int> loadOlderMessages(MessageKey key) async {')[1]
        .split('ChatMessage _toChatMessage(')[0];
    final replicaReceive = chatModelSource
        .split("case 'replica_message':")[1]
        .split("case 'replica_contacts':")[0];

    expect(restoreConversation, contains('_taggedChatMessage('));
    expect(loadOlder, contains('_taggedChatMessage('));
    expect(replicaReceive, contains('_taggedChatMessage('));
    expect(chatModelSource, contains("'ldesk_conn_endpoint'"));
    // 每条消息前置灰色小字（connSourceLabelOf），标明设备 + 连接方式 + 端口。
    expect(chatPageSource, contains('connSourceLabelOf(message)'));
    expect(chatPageSource, contains('connSourceEndpointOf(ChatMessage message)'));
    expect(
      chatPageSource,
      contains('DirectPairingStore.connEndpointOf(raw)'),
    );
    expect(
      chatModelSource,
      contains("msg.customProperties!['ldesk_conn_mode'] = record.connMode;"),
    );
    // 提示文字与时间统一字号，统一中性灰 + 50% 透明度（_chatMetaGrey），
    // 浅深色主题各一种颜色，透明度一致避免深浅不一。
    final sourceRender = chatPageSource.split('if (showMessageSource)')[1];
    expect(sourceRender, contains('fontSize: 10'));
    expect(sourceRender, contains('_chatMetaGrey(dark)'));
    // 统一灰色定义：同一种灰色 + 50% 透明度。
    expect(chatPageSource, contains('_chatMetaGrey(bool dark)'));
    expect(chatPageSource, contains('.withOpacity(0.5)'));
    expect(chatPageSource, contains('const Color(0xFF9AA0A8)'));
    expect(chatPageSource, contains('const Color(0xFF8A8F98)'));
  });

  test('mobile QR scanner exposes camera and gallery controls', () {
    expect(mobileConnectionSource, contains('builder: (_) => ScanPage()'));
    expect(mobileSettingsSource, contains('=> ScanPage()'));
    expect(mobileScanSource, contains('class ScanPage'));
    expect(mobileScanSource, contains('QRView('));
    expect(mobileScanSource, contains('onQRViewCreated: _onQRViewCreated'));
    expect(mobileScanSource, contains('_buildImagePickerButton()'));
    expect(mobileScanSource, contains('toggleFlash()'));
    expect(mobileScanSource, contains('flipCamera()'));
    expect(
      mobileScanSource,
      contains('Camera permission is required to scan pairing QR codes.'),
    );
    expect(androidManifestSource, contains('android.permission.CAMERA'));
  });

  test('mobile QR scanner routes pairing, app links and invalid payloads', () {
    expect(mobileScanSource, contains('DirectPairingStore.parsePayload(data)'));
    expect(
        mobileScanSource, contains('await DirectPairingStore.save(pairing)'));
    expect(mobileScanSource, contains("key: 'direct-chat-always-on'"));
    expect(mobileScanSource, contains("set_direct_chat_service"));
    expect(mobileScanSource, contains('Navigator.pop(context, pairing)'));
    expect(mobileScanSource,
        contains('data.startsWith(bind.mainUriPrefixSync())'));
    expect(mobileScanSource, contains('_showServerSettingFromQr(data)'));
    expect(
        mobileScanSource, contains('ServerConfig.decode(data.substring(7))'));
    expect(mobileScanSource, contains("translate('Invalid QR code')"));
  });

  test('mobile remote canvas keeps the actual connection route visible', () {
    expect(mobileRemoteSource, contains('_MobileConnectionRouteBadge'));
    expect(
      mobileRemoteSource,
      contains('ConnectionTypeState.find(id)'),
    );
    expect(mobileRemoteSource, contains('getConnectionText('));
    expect(mobileRemoteSource, contains("translate('Connecting...')"));
    expect(mobileRemoteSource, contains('connection.stream_type.value'));
  });

  test(
      'serverless direct-only mode is runtime selectable on desktop and mobile',
      () {
    for (final source in [
      desktopNetworkSettingsSource,
      mobileSettingsSource,
    ]) {
      expect(source, contains('kOptionServerlessDirectOnly'));
      expect(source, contains("value ? 'Y' : 'N'"));
      expect(source, contains('ID/Relay Server'));
      expect(source, contains('encrypted TCP relay'));
    }
    expect(clientRustSource, contains('ConnectionRoute::Rendezvous'));
    expect(
      clientRustSource,
      contains('enforce_rendezvous_policy(crate::is_serverless_direct_only())'),
    );
    expect(
      rendezvousRustSource,
      contains('while crate::is_serverless_direct_only()'),
    );
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
      contains('mapOf("type" to type, "result" to result)'),
    );
    expect(androidPermissionSource, isNot(contains('if (all)')));
  });

  test('mobile remote surfaces are compact, bounded and touch accessible', () {
    final permissionRow = mobileServerSource
        .split('class PermissionRow extends StatelessWidget')[1]
        .split('class ConnectionManager extends StatelessWidget')[0];
    final mobileToolbar = mobileRemoteSource
        .split('Widget getBottomAppBar()')[1]
        .split('bool get showCursorPaint')[0];

    expect(
      mobileServerSource,
      contains('constraints: const BoxConstraints(maxWidth: 720)'),
    );
    expect(mobileServerSource, isNot(contains('child: Card(')));
    expect(permissionRow, contains('SwitchListTile('));
    expect(permissionRow, isNot(contains('border: Border.all(')));
    expect(permissionRow, contains('height: 0.5'));
    expect(permissionRow, contains('margin: const EdgeInsets.only(left: 48)'));
    expect(permissionRow, contains('const Color(0x80E5E5E5)'));
    // 分隔线统一为点聊列表标准色：浅色 0x80E5E5E5 / 深色 0xFF3A3D43。
    expect(permissionRow, contains('const Color(0xFF3A3D43)'));
    expect(permissionRow, isNot(contains('dividerColor.withOpacity(0.3)')));
    expect(permissionRow, isNot(contains('Divider(')));
    expect(mobileToolbar, contains('const Color(0xFF20252E)'));
    expect(mobileToolbar, contains('SingleChildScrollView('));
    expect(mobileToolbar, contains("tooltip: translate('Close')"));
    expect(mobileToolbar, contains("tooltip: translate('Display')"));
    expect(mobileToolbar, contains("tooltip: translate('Text chat')"));
    expect(mobileToolbar, contains('width: 48'));
    expect(remoteToolbarSource, contains('SingleChildScrollView('));
    expect(remoteToolbarSource, contains('_MobileActionMenu'));
    expect(remoteToolbarSource, contains('_CloseMenu'));
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
        .split("leading: const Icon(Icons.verified_user_outlined),")[0];
    expect(
      alwaysOnToggle,
      contains('await _requestDirectChatNotificationPermissionOnce()'),
    );
  });

  test('LDesk branding preserves existing identity and URI compatibility', () {
    expect(
      commonRustSource,
      contains('DEFAULT_PRODUCT_DISPLAY_NAME: &str = "点聊"'),
    );
    expect(commonRustSource, contains('if configured == "LUODA"'));
    expect(commonRustSource, contains('"luoda://".to_owned()'));
    expect(
        androidStringsSource, contains('<string name="app_name">点聊</string>'));
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

  test('desktop ID and IP entry delegates unpaired IDs to the core', () {
    expect(directPairingSource, contains('isDeviceId(input)'));
    expect(
      directPairingSource,
      contains('if (isDeviceId(input)) return input;'),
    );
    expect(
      homePageSource,
      contains('DirectPairingStore.isSelfTarget(peerIdOrEndpoint)'),
    );
    expect(
      directPairingSource,
      contains("normalizedHost.startsWith('127.')"),
    );
  });

  test('desktop chat exposes text voice file and remote assistance workflows',
      () {
    expect(chatPageSource, contains('readOnly: isDesktopHome ||'));
    expect(
      chatPageSource,
      isNot(contains('readOnly: isDesktopHome ? true : readOnly')),
    );
    expect(chatModelSource, contains('void sendText(String text)'));
    expect(chatModelSource, contains('Future<void> sendVoiceClip('));
    expect(chatPageSource, contains('VoiceMessageRecorderButton('));
    final fileFlow = homePageSource
        .split('Future<void> _sendFilesFromConversation')[1]
        .split('Future<FFI?> _ensureDirectFileSession')[0];
    expect(fileFlow, contains('FilePicker.platform.pickFiles'));
    expect(fileFlow, contains('await _ensureDirectFileSession(peerId)'));
    expect(fileFlow, contains('localController.sendFiles'));
    expect(
      fileFlow.indexOf('FilePicker.platform.pickFiles'),
      lessThan(fileFlow.indexOf('_ensureDirectFileSession(peerId)')),
    );
    final remoteFlow = homePageSource
        .split('Future<void> _connectDirect')[1]
        .split('Future<bool> _isSelfTarget')[0];
    expect(remoteFlow, contains('DirectPairingStore.resolveConnectionTarget'));
    expect(remoteFlow, contains('await connect('));
  });

  test('image selection, clipboard paste and preview are distinct workflows',
      () {
    expect(chatPageSource, contains('onSendImage'));
    expect(chatPageSource, contains('Icons.image_outlined'));
    expect(chatPageSource, isNot(contains('Icons.content_paste_go_outlined')));
    expect(chatPageSource, contains('LogicalKeyboardKey.keyV'));
    expect(chatPageSource, contains('_pasteClipboardText'));
    expect(
      chatPageSource,
      contains('SliverGridDelegateWithMaxCrossAxisExtent'),
    );

    final imagePickerFlow = homePageSource
        .split('Future<void> _pickImagesForConversation')[1]
        .split('Future<Map<String, dynamic>?> _readClipboardImage')[0];
    expect(imagePickerFlow, contains('FileType.image'));
    expect(imagePickerFlow, contains('allowMultiple: true'));

    final clipboardFlow = homePageSource
        .split('Future<bool> _pasteImageToConversation')[1]
        .split('Future<void> _sendImageFile')[0];
    expect(clipboardFlow, isNot(contains('FilePicker.platform.pickFiles')));
    expect(clipboardFlow, contains("translate('Clipboard has no image')"));
    expect(homePageSource, contains('getApplicationSupportDirectory'));
    expect(homePageSource, contains('isWindowsClipboardImageAvailable()'));
    expect(
      homePageSource,
      isNot(contains("package:win32/win32.dart")),
    );
    expect(
      clipboardImageProbeSource,
      contains("if (dart.library.html) 'clipboard_image_probe_web.dart'"),
    );
    expect(
      clipboardImageProbeNativeSource,
      contains('IsClipboardFormatAvailable'),
    );

    expect(fileViewerSource, isNot(contains('setFullscreen(true)')));
    // LUODA FIX (2026-08-22): the desktop preview is a REAL independent OS
    // window again. The 2026-08-15 blank-child-window issue is root-caused
    // and fixed in three parts this must keep asserting:
    //   1. main.dart must SKIP initEnv for file-preview child windows (the
    //      old hang came from the Rust backend blocking on an unknown app
    //      type before the child engine could attach);
    //   2. the child window must NOT be parent-shown() — exactly like the
    //      session windows, the child shows itself after its first frame
    //      (runMultiWindow ends with WindowController.show()). Parent-side
    //      show() exposed a not-yet-rendered window and intermittently left
    //      it stuck on the raw background (the all-black/all-white bug);
    //   3. the init background must be white, never black.
    expect(fileViewerSource, contains('DesktopMultiWindow.createWindow'));
    expect(fileViewerSource, contains('WindowType.FilePreview.index'));
    expect(fileViewerSource, isNot(contains('..show()')));
    expect(fileViewerSource, contains('setInitBackgroundColor(Colors.white)'));
    expect(fileViewerSource, contains('MaterialPageRoute<void>'));
    expect(fileViewerSource, contains('_FileViewerPage('));
    expect(fileViewerSource, contains('siblingPaths: siblingPaths'));
    expect(fileViewerSource, contains('FilePreviewKind.image'));
    expect(fileViewerSource, contains('OpenFilex.open'));
    expect(mainSource, contains('case WindowType.FilePreview:'));
    expect(
      mainSource,
      contains('if (appType != kAppTypeDesktopFilePreview)'),
    );
    expect(filePreviewPageSource, contains('filePreviewIcon(fileName)'));
    expect(filePreviewPageSource, contains('_ensureFirstPaint'));
    expect(chatPageSource, contains('Future<void> _openMessageFilePreview('));
    expect(chatPageSource, contains('siblingPaths: siblingPaths'));
    expect(filePreviewPageSource, contains('TransformationController'));
    expect(filePreviewPageSource, contains('void _zoomImage(double factor)'));
    expect(filePreviewPageSource, contains('Icons.add_circle_outline'));
    expect(filePreviewPageSource, contains('Icons.remove_circle_outline'));
    expect(filePreviewPageSource, contains('Icons.rotate_right_rounded'));
    expect(filePreviewPageSource, contains('Icons.remove_rounded'));
    expect(filePreviewPageSource, contains('Icons.crop_square_rounded'));
    expect(filePreviewPageSource, contains('Icons.close_rounded'));
    expect(filePreviewPageSource, contains('final isImage = filePreviewKindForName(fileName)'));
    expect(
      filePreviewPageSource,
      contains('WindowController.fromWindowId(widget.windowId)'),
    );
    expect(
        filePreviewPageSource, contains('_windowController.startDragging()'));
    expect(filePreviewPageSource, contains('onPointerDown: _beginWindowDrag'));
    expect(
      filePreviewPageSource,
      contains('onPointerUp: (_) => _endWindowDrag()'),
    );
    expect(
      filePreviewPageSource,
      contains('onPointerCancel: (_) => _endWindowDrag()'),
    );
    expect(filePreviewPageSource, isNot(contains('onPanDown:')));
    expect(filePreviewPageSource, isNot(contains('onPanStart:')));
    expect(filePreviewPageSource, contains('Timer.periodic('));
    expect(filePreviewPageSource, contains('GetCursorPos(cursorPoint)'));
    expect(filePreviewPageSource, contains('_windowController.getFrame()'));
    expect(filePreviewPageSource, contains('_windowController.setFrame('));
    expect(filePreviewPageSource, contains('_windowFrame = frame'));
    expect(filePreviewPageSource, contains('void _goPrevious()'));
    expect(filePreviewPageSource, contains('void _goNext()'));
    expect(filePreviewPageSource, contains('width: 36,'));
    expect(filePreviewPageSource, contains('height: 36,'));
    expect(filePreviewPageSource, contains('this.iconSize = 20'));
    expect(
      filePreviewPageSource,
      isNot(contains('leadingWidth: hasMultiple ? 164 : null')),
    );
    expect(chineseLangSource, contains('"Paste Image"'));
    expect(chineseLangSource, contains('"Clipboard has no image"'));
  });

  test('chat attachments use image thumbnails and compact document cards', () {
    expect(chatPageSource, contains('final isImageAttachment ='));
    expect(chatPageSource, contains('FilterQuality.high'));
    expect(chatPageSource, contains('Icons.insert_drive_file_rounded'));
    expect(chatPageSource, contains('attachmentBubbleColor'));
  });

  test('chat identity opens device details and supports a local alias', () {
    expect(homePageSource, contains('_setConversationAlias('));
    expect(homePageSource, contains('bind.mainSetPeerAlias('));
    expect(homePageSource, contains('initialAlias:'));
    expect(directConnectionDetailsSource, contains('onRename'));
    expect(directConnectionDetailsSource, contains("translate('Alias')"));
  });

  test('emoji picker, composer and message text prefer crisp system emoji', () {
    expect(chatPageSource, contains('kChatEmojiFontFallback'));
    expect(richTextEmojiSource, contains('kChatEmojiFontFallback'));
    expect(richTextEmojiSource, contains("'Segoe UI Emoji'"));
  });

  test('desktop composer uses a quarter-width outline and outline-only hover',
      () {
    final composerSource = chatPageSource
        .split('class _DesktopChatComposerState')[1]
        .split('class _ComposerToolButton')[0];

    expect(composerSource, contains('width: 0.25'));
    expect(
      composerSource,
      contains(
        'overlayColor: const WidgetStatePropertyAll(Colors.transparent)',
      ),
    );
    expect(composerSource, contains('states.contains(WidgetState.hovered)'));
    expect(composerSource, contains('BorderSide(color: kWeChatPrimaryColor'));
    expect(composerSource, contains('hoverColor: Colors.transparent'));
    expect(composerSource, isNot(contains('boxShadow: _inputFocused')));
  });

  test('desktop emoji picker stays open for repeated selections', () {
    final insertEmojiSource = chatPageSource
        .split('void _insertEmoji(String emoji)')[1]
        .split('@override')[0];

    expect(insertEmojiSource, contains('text.replaceRange(start, end, emoji)'));
    expect(
      insertEmojiSource,
      isNot(contains('_showEmojiPicker = false')),
    );
  });

  test('message translation is rendered inline below the original text', () {
    final translateFlow = chatPageSource
        .split("if (action == 'translate')")[1]
        .split("if (action == 'send-email')")[0];
    expect(translateFlow, contains('beginMessageTranslation'));
    expect(translateFlow, contains('completeMessageTranslation'));
    expect(translateFlow, isNot(contains('showDialog')));
    expect(chatPageSource, contains('messageTranslation(messageId)'));
    expect(chatPageSource, contains('isMessageTranslationPending(messageId)'));
  });

  test('recall stays in the context menu without a red bubble-side shortcut',
      () {
    expect(chatPageSource, contains("_ChatMenuAction("));
    expect(chatPageSource, contains("'recall'"));
    expect(chatPageSource, contains("'destroy'"));
    expect(chatPageSource, isNot(contains('Color(0x33FF6B6B)')));
    expect(chatPageSource, isNot(contains('Color(0x1AE5484D)')));
  });

  test('single and multi-message forwarding use the target peer session', () {
    expect(chatModelSource, contains('Future<void> sendForwardBundle('));
    expect(chatPageSource, contains('ForwardMessagesCallback'));
    expect(chatPageSource, contains("translate('Forward individually')"));
    expect(chatPageSource, contains("translate('Merge and forward')"));
    expect(chatPageSource, contains('_selectedMessagesForForward()'));
    expect(
        homePageSource, contains('Future<bool> _forwardConversationMessages('));
    expect(homePageSource, contains('targetModel.sendForwardBundle('));
    expect(homePageSource,
        contains('fileSession.fileModel.localController.sendFiles('));
    expect(mobileHomeSource,
        contains('onForwardMessages: _forwardConversationMessages'));
    expect(mobileHomeSource, contains('gFFI.chatModel.sendForwardBundle('));
    expect(chatPageSource, contains("properties?['ldesk_kind'] == 'forward'"));
    expect(chatPageSource, contains('_buildForwardBundle('));
    expect(chatPageSource, contains('_showForwardBundleDetails('));
  });

  test('chat typography has multilingual symbol and emoji fallbacks', () {
    final pubspecSource = File('pubspec.yaml').readAsStringSync();
    expect(pubspecSource, contains('family: LDeskNotoSansCJKSC'));
    expect(pubspecSource, contains('assets/NotoSansCJKsc-Regular.otf'));
    expect(pubspecSource, contains('family: LDeskNotoSansSymbols2'));
    expect(pubspecSource, contains('assets/NotoSansSymbols2-Regular.ttf'));
    expect(pubspecSource, contains('family: LDeskNotoColorEmoji'));
    expect(pubspecSource, contains('assets/NotoColorEmoji.ttf'));
    final bundledCjkFont = File('assets/NotoSansCJKsc-Regular.otf');
    final bundledSymbolsFont = File('assets/NotoSansSymbols2-Regular.ttf');
    final bundledEmojiFont = File('assets/NotoColorEmoji.ttf');
    expect(bundledCjkFont.existsSync(), isTrue);
    expect(bundledCjkFont.lengthSync(), greaterThan(16000000));
    expect(bundledSymbolsFont.existsSync(), isTrue);
    expect(bundledSymbolsFont.lengthSync(), greaterThan(500000));
    expect(bundledEmojiFont.existsSync(), isTrue);
    expect(bundledEmojiFont.lengthSync(), greaterThan(5000000));
    expect(File('assets/NotoSansCJK-OFL.txt').existsSync(), isTrue);
    expect(File('assets/NotoSansSymbols2-OFL.txt').existsSync(), isTrue);
    expect(File('assets/NotoColorEmoji-OFL.txt').existsSync(), isTrue);
    for (final workflow in <String>[
      windowsWorkflowSource,
      clientWorkflowSource,
      msiWorkflowSource,
    ]) {
      expect(workflow, contains('assets\\NotoSansCJKsc-Regular.otf'));
      expect(workflow, contains('assets\\NotoSansSymbols2-Regular.ttf'));
      expect(workflow, contains('assets\\NotoColorEmoji.ttf'));
    }
    expect(commonSource, contains('fontFamilyFallback: fontFamilyFallback'));
    for (final family in <String>[
      'LDeskNotoSansCJKSC',
      'LDeskNotoSansSymbols2',
      'LDeskNotoColorEmoji',
      'Microsoft YaHei UI',
      'PingFang SC',
      'Noto Sans CJK SC',
      'SimSun-ExtB',
      'SimSun-ExtG',
      'Segoe UI Symbol',
      'Segoe UI Emoji',
      'Noto Color Emoji',
    ]) {
      expect(commonSource, contains("'$family'"));
    }
  });

  test('email actions open a populated draft instead of reporting fake send',
      () {
    expect(chatPageSource, contains('EmailDraftService.openDraft('));
    expect(chatModelSource, contains('EmailDraftService.formatMessages('));
    expect(emailDraftSource, contains("scheme: 'mailto'"));
    expect(chatModelSource, isNot(contains('dir.delete(recursive: true)')));
    expect(chatModelSource,
        isNot(contains("translate(\"Sent successfully to\")")));
    expect(chatPageSource, contains("'Send 20 recent to email'"));
    expect(chatPageSource, isNot(contains('Export 20 recent (ZIP)')));
  });

  test('desktop composer transient controls are mutually exclusive', () {
    expect(chatPageSource, contains('void _closeTransientPanels()'));
    expect(
        chatPageSource, contains('void _runToolAction(VoidCallback action)'));
    expect(
        chatPageSource, contains('onInteractionStart: _closeTransientPanels'));
    expect(chatPageSource, contains('onOpen: _closeTransientPanels'));
  });

  test('settings title bar omits the redundant back button', () {
    expect(
      desktopTabSource,
      isNot(contains('onBack: key == kTabLabelSettingPage')),
    );
  });

  test('remembered passwords persist for direct endpoints and peer IDs', () {
    expect(clientSource, contains('config_id: String'));
    expect(
        clientSource, contains('PeerConfig::load(&self.config_id).password'));
    expect(clientSource, contains('config.store(&self.config_id)'));
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

  test('offline direct chat retries storage locks and resumes queued messages',
      () {
    expect(directChatStorageSource,
        contains('static const _maxLockAttempts = 12;'));
    expect(
        directChatStorageSource,
        contains(
            'for (var attempt = 0; attempt < _maxLockAttempts; attempt++)'));
    expect(directChatStorageSource, contains('FileLock.exclusive'));
    expect(directChatStorageSource, contains('FileLock.shared'));
    expect(directChatSource, contains('Failed to refresh direct chat history'));
    expect(chatModelSource,
        contains('Failed to restore direct chat conversation'));
    expect(homePageSource, contains('_maintainPendingChatSessions'));
    expect(homePageSource, contains('Duration(seconds: 5)'));
    expect(homePageSource, contains('_checkConnectionTransitions'));
    expect(homePageSource, isNot(contains('_lastNetworkStatus')));
    expect(homePageSource, isNot(contains("translate('Network')")));
    expect(homePageSource, contains('_notifiedChatConnections.add'));
    expect(chatPageSource, contains("translate('Waiting to send')"));
    expect(chatModelSource, contains('DirectChatDelivery.delivered'));
    expect(directChatSource, contains('markUndeliveredQueued'));
    expect(chatModelSource, contains('markCurrentUndeliveredQueued'));
    expect(modelSource, contains('markCurrentUndeliveredQueued'));
  });

  test('sent direct messages support recall and permanent destruction', () {
    expect(directChatSource, contains('DirectChatDisposition.recalled'));
    expect(directChatSource, contains('DirectChatDisposition.destroyed'));
    expect(directChatSource, contains('mutateOutgoing'));
    expect(chatModelSource, contains('recallMessage('));
    expect(chatModelSource, contains('destroyMessage('));
    expect(chatPageSource, contains('onLongPressMessage:'));
    expect(chatPageSource, contains("_ChatMenuAction("));
    expect(chatPageSource, contains("'recall'"));
    expect(chatPageSource, contains("'destroy'"));
  });

  test('voice messages record, validate, transfer and play over direct chat',
      () {
    expect(pubspecSource, contains('record: 5.2.1'));
    expect(pubspecSource, contains('audioplayers: 6.1.0'));
    expect(directChatSource,
        contains('enum DirectChatKind { text, file, voice, forward }'));
    expect(directChatSource, contains("DirectChatEnvelope('voice_chunk'"));
    expect(directChatSource, contains("DirectChatEnvelope('voice_request'"));
    expect(
        directVoiceStorageSource, contains('maxClipBytes = 8 * 1024 * 1024'));
    expect(voiceMessageControlsSource, contains('AudioEncoder.wav'));
    expect(voiceMessageControlsSource, contains('Duration(minutes: 3)'));
    expect(voiceMessageControlsSource, contains('class VoiceMessageBubble'));
    expect(voiceMessageControlsSource, contains('BytesSource('));
    expect(chatModelSource, contains('const chunkSize = 24 * 1024'));
    expect(chatModelSource, contains('sha256.convert(clip)'));
    expect(chatModelSource, contains('total > 342'));
    expect(chatModelSource, contains('_incomingVoiceTransfers.length >= 8'));
    expect(chatModelSource, contains('_isCompanionSession(key)'));
    expect(chatPageSource, contains('VoiceMessageRecorderButton('));
    expect(chatPageSource, contains('VoiceMessageBubble('));
  });

  test('restored inbound chat sessions request missed messages', () {
    final restorePath = serverModelSource
        .split(
            'updateClientState({String? json, bool chatOnly = false}) async')[1]
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

  test(
      'active companion sessions refresh incremental sync on platform intervals',
      () {
    expect(mobileHomeSource, contains('const Duration(minutes: 30)'));
    expect(homePageSource, contains('const Duration(seconds: 5)'));
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
      homePageSource,
      contains('gFFI.chatModel.syncActiveCompanionSessions()'),
    );
    expect(
      chatModelSource,
      contains('Future<void> syncActiveCompanionSessions()'),
    );
    expect(
      chatModelSource,
      contains('_activeCompanionSecrets[key.connId] = secret'),
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

  test('paired chat falls back from stale endpoints to ID rendezvous', () {
    expect(
      clientSource,
      contains('Direct endpoints failed; falling back to device ID'),
    );
    expect(clientSource, contains('other_server = None;'));
    expect(
      clientSource,
      isNot(contains(
        'Direct chat requires a reachable peer address; relay fallback is disabled',
      )),
    );
  });

  test('direct listener reports its real startup state to every desktop shell',
      () {
    expect(directListenerSource, contains('direct-listener-status'));
    expect(directListenerSource, contains('"connecting"'));
    expect(directListenerSource, contains('"ready"'));
    expect(directListenerSource, contains('"not-ready"'));
    expect(
      desktopConnectionSource,
      contains("key: kOptionDirectListenerStatus"),
    );
    expect(
      desktopConnectionSource,
      isNot(contains('directPort.isNotEmpty\n        ? SvcStatus.ready')),
    );
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
      contains('display_service::try_get_displays_add_amyuni_headless()'),
    );
    expect(
      portableServiceSource,
      contains('virtual_display_manager::virtual_display_resolution()'),
    );
    expect(videoServiceSource, contains('FIRST_FRAME_CAPTURE_TIMEOUT'));
    expect(videoServiceSource, contains('Duration::from_secs(8)'));
    expect(videoServiceSource, contains('first frame capture timed out'));
  });

  test('headless peers still publish their authenticated identity', () {
    final noDisplays = uiSessionSource
        .split('if pi.displays.is_empty() {')[1]
        .split('return;')[0];
    expect(uiSessionSource, contains('canonical_direct_peer_id('));
    expect(noDisplays, contains('self.set_peer_info(&pi)'));
    expect(noDisplays.indexOf('self.set_peer_info(&pi)'),
        lessThan(noDisplays.indexOf('self.msgbox(')));
  });

  test('Windows Server registration uses the fixed TCP rendezvous endpoint',
      () {
    expect(configRustSource, contains('dotchat.dicad.cn:23116'));
    expect(rendezvousRustSource, contains('normalize_transport_options'));
    expect(rendezvousRustSource, contains('OPTION_ALLOW_WEBSOCKET'));
    expect(flutterFfiSource, contains('OPTION_DISABLE_UDP'));
    expect(flutterFfiSource, contains('OPTION_ALLOW_WEBSOCKET'));
  });

  test('portable Windows Server prepares and prefers a virtual display', () {
    expect(
      rendezvousRustSource,
      contains('PORTABLE_APPNAME_RUNTIME_ENV_KEY'),
    );
    expect(virtualDisplaySource, contains('has_headless_display'));
    expect(displayServiceSource, contains('display.is_online()'));
    expect(displayServiceSource, contains('prefer_virtual_display'));
    expect(
      videoServiceSource,
      contains('Failed to copy screen to Windows buffer'),
    );
    expect(videoServiceSource, contains('prefer_virtual_display()'));
    expect(videoServiceSource, contains('bail!("SWITCH")'));
  });

  test('Windows packages contain the signed headless display driver', () {
    const driverUrl =
        'https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip';
    const driverSha =
        '629B51E9944762BAE73948171C65D09A79595CF4C771A82EBC003FBBA5B24F51';
    for (final source in <String>[windowsWorkflowSource, msiWorkflowSource]) {
      expect(source, contains(driverUrl));
      expect(source, contains(driverSha));
      expect(source, contains('usbmmidd_v2\\usbmmIdd.inf'));
      expect(source, contains('usbmmidd_v2\\usbmmidd.cat'));
      expect(source, contains('usbmmidd_v2\\x64\\usbmmIdd.dll'));
      expect(source, contains('usbmmidd_v2\\deviceinstaller64.exe'));
    }
  });

  test('headless Windows hosts install and activate the bundled driver', () {
    final prepareHeadless = displayServiceSource
        .split('prepare_windows_server_headless_display() -> ResultType<()>')[1]
        .split('pub fn try_get_displays_')[0];
    final portableStartup = portableServiceSource
        .split('pub(crate) fn start_portable_service(para: StartPara)')[1]
        .split('pub extern "C" fn drop_portable_service_shared_memory')[0];
    final systemCapture = portableServiceSource
        .split('fn run_capture(shmem: Arc<SharedMemory>)')[1]
        .split('fn run_ipc_client()')[0];
    final amyuniDriver = virtualDisplaySource.split('pub mod amyuni_idd {')[1];

    expect(
      prepareHeadless,
      contains('plug_in_headless_and_wait().map(|_| ())'),
    );
    expect(
      prepareHeadless,
      isNot(contains('is_win_server() || is_portable')),
    );
    expect(portableStartup, contains('display_service::try_get_displays()'));
    expect(
      portableStartup,
      contains('virtual_display_manager::virtual_display_resolution()'),
    );
    expect(portableStartup, isNot(contains('bail!("no display available!")')));
    expect(
      systemCapture,
      contains('display_service::try_get_displays_add_amyuni_headless()'),
    );
    expect(
      coreMainSource,
      contains('virtual_display_manager::install_update_driver()'),
    );
    final installIddCommand = coreMainSource
        .split('args[0] == "--install-idd"')[1]
        .split('return None;')[0];
    expect(installIddCommand, contains('std::process::exit(1)'));
    expect(
      amyuniDriver,
      contains('pub fn install_update_driver() -> ResultType<()>'),
    );
    expect(platformWindowsSource, contains('--install-idd'));
    expect(
      platformWindowsSource,
      contains('if errorlevel 1 exit /b %errorlevel%'),
    );
    expect(msiPackageSource, contains('Id="InstallAmyuniIdd"'));
    expect(msiPackageSource, contains('ExeCommand="--install-idd"'));
  });

  test('custom desktop client consistently uses a 470 by 500 window', () {
    expect(
      flutterCommonSource,
      contains('const kCustomClientWindowSize = Size(470, 500)'),
    );
    expect(
      flutterCommonSource,
      contains('restoreWidth = kCustomClientWindowSize.width'),
    );
    expect(
      flutterCommonSource,
      contains('restoreHeight = kCustomClientWindowSize.height'),
    );
    expect(homePageSource, contains('child: SizedBox.expand('));
    expect(
      desktopTabSource,
      contains('windowManager.setSize(kCustomClientWindowSize)'),
    );
    expect(
      flutterMainSource,
      contains('windowManager.setMinimumSize(kCustomClientWindowSize)'),
    );
    expect(
      flutterMainSource,
      contains('windowManager.setMaximumSize(kCustomClientWindowSize)'),
    );
    final clientHeader = homePageSource
        .split('Widget _buildClientHeader(BuildContext context)')[1]
        .split('Widget _buildClientIdentityCard(')[0];
    expect(clientHeader, contains('width: double.infinity'));
    expect(
      clientHeader,
      contains('crossAxisAlignment: CrossAxisAlignment.center'),
    );
    expect(clientHeader, contains('OnlineStatusWidget(compact: true)'));
    expect(
      homePageSource,
      contains('_buildIdentityCard(context, model, compact: true)'),
    );
    expect(desktopConnectionSource, contains('this.compact = false'));
    expect(desktopConnectionSource, contains('if (widget.compact)'));
  });

  test('desktop defaults to Chinese without overriding a user choice', () {
    expect(
      coreMainSource,
      contains('LocalConfig::get_option(keys::OPTION_LANGUAGE).is_empty()'),
    );
    expect(
      coreMainSource,
      contains('config::LocalConfig::set_option('),
    );
    expect(coreMainSource, contains('keys::OPTION_LANGUAGE.to_string()'));
    expect(coreMainSource, contains('"zh-cn".to_string()'));
  });

  test('ordinary desktop exposes identity and both first-contact actions', () {
    final emptyConversation = homePageSource
        .split(
            'Widget _buildEmptyConversation(BuildContext context, {Peer? contact})')[1]
        .split('Widget _buildContactSection(BuildContext context)')[0];
    expect(emptyConversation, contains("translate('My Identity')"));
    expect(
      emptyConversation,
      contains("'Tell the other device your ID or IP to connect.'"),
    );
    expect(
      emptyConversation,
      contains('translate('),
    );
    expect(emptyConversation, contains('_buildIdentityCard('));
    expect(emptyConversation, contains("translate('Connect by ID / IP')"));
    expect(emptyConversation, contains("translate('Copy device ID')"));

    final directDialog = homePageSource
        .split('void _showDirectConnectDialog(BuildContext context)')[1]
        .split('Widget _buildConversationWorkspace(BuildContext context)')[0];
    expect(directDialog, contains("translate('Start a direct conversation')"));
    expect(directDialog, contains("translate('Remote assistance')"));
    expect(directDialog, contains('_startDirectChat(target)'));
    expect(directDialog, contains('_connectDirect(context, target)'));
  });

  test('direct endpoint chat keeps its editor after peer identity remapping',
      () {
    final workspace = homePageSource
        .split('Widget _buildConversationWorkspace(BuildContext context)')[1]
        .split('Widget _buildConversationHeader(')[0];
    expect(workspace, contains('DirectPairingStore.findForConversation'));
    expect(workspace, contains('selectedPairing?.conversationId'));
  });

  test('every successful direct session is saved for later ID connections', () {
    final peerInfoHandler = modelSource
        .split(
            'handlePeerInfo(Map<String, dynamic> evt, String peerId, bool isCache) async')[1]
        .split('_pi.sasEnabled =')[0];
    final saveIndex = peerInfoHandler
        .indexOf('await _persistDiscoveredDirectPairing(peerId)');
    final chatOnlyIndex = peerInfoHandler.indexOf(
      'ffi.connType == ConnType.chat',
    );
    expect(saveIndex, greaterThanOrEqualTo(0));
    expect(chatOnlyIndex, greaterThan(saveIndex));
    expect(modelSource, contains('DirectPairingStore.saveDiscovered('));
  });

  test('desktop shell uses a restrained WeChat typography scale', () {
    expect(weChatTokensSource, contains('kWeChatHeadingFontSize = 16'));
    expect(weChatTokensSource, contains('kWeChatBodyFontSize = 14'));
    expect(weChatTokensSource, contains('kWeChatMetaFontSize = 12'));
    expect(weChatTokensSource, contains('kWeChatTextHeight = 1.3'));
  });

  test('about page contains readable Chinese branding copy', () {
    expect(
        settingsAboutSource, contains("translate('LUODA Remote Assistance')"));
    expect(settingsAboutSource, isNot(contains('Color(0xFF2A84BA)')));
    expect(settingsAboutSource, isNot(contains('AI赋能工程设计')));
  });

  test('title bar and primary rail share the configured background', () {
    expect(
      desktopMainTitleBarSource,
      contains('desktopRailBackgroundRevision'),
    );
    expect(
      desktopMainTitleBarSource,
      contains('desktopRailBackgroundDecoration(context)'),
    );
    expect(
      desktopRailSource,
      contains('BoxDecoration desktopRailBackgroundDecoration('),
    );
  });

  test('portable launcher never overwrites a running LDesk instance', () {
    expect(portablePackerSource, contains('activate_existing_instance'));
    expect(portablePackerSource, contains('FindWindowW'));
    expect(portablePackerSource, contains('ShowWindow'));
    expect(portablePackerSource, contains('SetForegroundWindow'));
    expect(portablePackerSource, isNot(contains('remove_dir_all')));
  });

  test('portable launcher uses a green progress bar instead of the legacy GIF',
      () {
    expect(portablePackerCargoSource, contains('"progress-bar"'));
    expect(portablePackerUiSource, contains('nwg::ProgressBar'));
    expect(portablePackerUiSource, contains('ProgressBarState::Normal'));
    expect(portablePackerUiSource, contains('PORTABLE_PROGRESS'));
    expect(portablePackerUiSource, isNot(contains('spin.gif')));
  });

  test(
      'custom client identity and connection state follow the selected language',
      () {
    expect(homePageSource, contains("translate('Remote assistance')"));
    expect(homePageSource, isNot(contains('chinese: true')));
    expect(homePageSource, isNot(contains('forceChinese: true')));
    expect(desktopConnectionSource, contains("translate('Direct listening')"));
    expect(desktopConnectionSource, isNot(contains('forceChinese ?')));
    expect(
      desktopTabSource,
      contains("translate('LUODA Remote Assistance')"),
    );
  });

  test('Windows tray embeds the latest compact LDesk icon', () {
    expect(traySource, contains('include_bytes!("../res/tray-icon.png")'));
    expect(
      File('../res/tray-icon.png').readAsBytesSync(),
      orderedEquals(File('../Images/icon-32.png').readAsBytesSync()),
    );
    const trayMapping =
        "@{ Source = 'Images\\icon-32.png'; Target = 'res\\tray-icon.png' }";
    expect(windowsWorkflowSource, contains(trayMapping));
    expect(clientWorkflowSource, contains(trayMapping));
  });

  test('mobile launcher icons keep the complete LDesk mark in a safe zone', () {
    final iosSource = img.decodePng(
      File('../res/icon_ios.png').readAsBytesSync(),
    );
    final iosIcon = img.decodePng(
      File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
        'Icon-App-1024x1024@1x.png',
      ).readAsBytesSync(),
    );
    final androidIcon = img.decodePng(
      File(
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      ).readAsBytesSync(),
    );

    expect(iosSource, isNotNull);
    expect(iosIcon, isNotNull);
    expect(androidIcon, isNotNull);
    expect(iosIcon!.width, 1024);
    expect(iosIcon.height, 1024);

    final iosCorner = iosIcon.getPixel(0, 0);
    expect(iosCorner.a, 255);
    expect(iosCorner.g, greaterThan(iosCorner.r));
    expect(iosCorner.g, greaterThan(iosCorner.b));

    final androidCorner = androidIcon!.getPixel(0, 0);
    expect(androidCorner.a, 0);
    final androidCenter = androidIcon.getPixel(
      androidIcon.width ~/ 2,
      androidIcon.height ~/ 2,
    );
    expect(androidCenter.a, 255);
    expect(androidCenter.g, greaterThan(androidCenter.r));
    expect(androidCenter.g, greaterThan(androidCenter.b));
    expect(
      iosWorkflowSource,
      contains('source = Image.open(root / "res/icon_ios.png")'),
    );
    expect(
      macosWorkflowSource,
      contains('SOURCE="\$GITHUB_WORKSPACE/res/icon_padded.png"'),
    );
    expect(
      File('windows/runner/resources/app_icon.ico').readAsBytesSync(),
      orderedEquals(File('../Images/icon.ico').readAsBytesSync()),
    );
  });

  test('custom client EXE is a dedicated LDesk identity panel', () {
    final clientPanel = homePageSource
        .split('Widget buildLeftPane(BuildContext context) {')[1]
        .split('final isIncomingOnly =')[0];
    expect(clientPanel, contains('_buildClientHeader(context)'));
    expect(clientPanel, contains('_buildClientIdentityCard(context)'));
    expect(clientPanel, isNot(contains('buildIDBoard(context)')));
    expect(clientPanel, isNot(contains('buildPasswordBoard(context)')));
    expect(clientPanel, isNot(contains('buildDirectAccessBoard(context)')));
    expect(clientPanel, isNot(contains('_buildRemoteCenter')));
    expect(clientPanel, isNot(contains('DesktopSettingPage')));
    expect(desktopTabSource, contains('final title = compactClient'));
    expect(
      desktopTabSource,
      contains("translate('LUODA Remote Assistance')"),
    );
    expect(clientWorkflowSource, contains('name: Build LDesk Client EXE'));
    expect(clientWorkflowSource, contains('SignOutput/LDesk-Client-x64.exe'));
    expect(clientWorkflowSource, contains('LDesk-3.1.1-Client-x64.exe'));
    expect(clientWorkflowSource, contains('Images\\icon.ico'));
    expect(
      clientWorkflowSource,
      contains('Smoke test LDesk client identity panel'),
    );
    expect(clientWorkflowSource, contains('LDesk-client-window.png'));
    expect(clientWorkflowSource, contains('CopyFromScreen'));
    expect(
      clientWorkflowSource,
      contains('Normalize Windows resource encoding'),
    );
  });

  test('shared identity card copies ID password and direct IP values', () {
    expect(homePageSource,
        contains('onTap: () => _copyValue(model.serverId.text)'));
    expect(homePageSource,
        contains('onCopy: () => _copyValue(model.serverPasswd.text)'));
    expect(
      homePageSource,
      matches(
        RegExp(
          r'onPressed:\s*available\s*\? \(\) => _copyValue\(value\)\s*: null',
        ),
      ),
    );
    expect(
      homePageSource,
      contains('final copyAction = onCopy ?? (prominent ? onTap : null)'),
    );
    expect(
        homePageSource, contains('onDoubleTap: available ? copyAction : null'));
    expect(
      homePageSource,
      matches(
        RegExp(
          r'onDoubleTap:\s*available\s*\? \(\) => _copyValue\(value\)\s*: null',
        ),
      ),
    );
    expect(homePageSource, contains('Icons.copy_rounded'));
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

  test('MSI package and release asset use 点聊 branding', () {
    expect(msiWorkflowSource, contains('--app-name 点聊'));
    expect(msiWorkflowSource, contains('LDesk-3.1.1-MSI'));
    expect(msiWorkflowSource, contains('LDesk-3.1.1-Setup-\$culture.msi'));
    expect(msiWorkflowSource, contains('LDesk-3.1.1-Setup-*.msi'));
    expect(msiProjectSource, contains('<OutputName>LDesk-Setup</OutputName>'));
  });

  test('Windows packages retain the remote printer adapter', () {
    for (final source in <String>[windowsWorkflowSource, msiWorkflowSource]) {
      expect(source, contains('printer_driver_adapter.zip'));
      expect(source, contains('printer_driver_adapter.dll'));
      expect(source, contains('luoda_printer_driver_v4-1.4.zip'));
      expect(source, contains('RustDeskPrinterDriver.inf'));
      expect(source, contains('Expand-Archive'));
    }
    expect(
      remotePrinterSource,
      contains(
        'drivers/rustdesk_printer_driver_v4-1.4/RustDeskPrinterDriver.inf',
      ),
    );
    expect(remotePrinterSource, contains('RustDesk v4 Printer Driver'));
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
      isNot(contains('onDoubleTap: () => _connectDirect(context, peerId)')),
    );
    expect(
      chatModelSource,
      contains('_scheduleRecentConversationRestore()'),
    );
    expect(chatModelSource, contains('gFFI.chatModel'));
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

  test('contact navigation is labeled and groups one person across devices',
      () {
    expect(
      mobileConnectionSource,
      contains('PeerTabIndex.ab.index'),
    );
    expect(mobileConnectionSource, contains("translate('My Identity')"));
    expect(peerTabStripSource, contains('this.showLabels = false'));
    expect(peerTabStripSource, contains('height: showLabels ? 48 : 40'));
    expect(peerTabStripSource, contains('Semantics('));
    expect(localContactsSource, contains('pairing.conversationId'));
    expect(localContactsSource, contains('final List<DirectPairing> devices'));
    expect(localContactsSource, contains('showDirectConnectionDetails('));
    expect(mobileConnectionSource, contains("return parts.join(' · ');"));
    expect(homePageSource, contains("return parts.join(' · ');"));
    expect(homePageSource, contains('final subtitle = deviceSummary;'));
  });

  test('mobile contacts use a focused first screen and preserve every tool',
      () {
    // 首屏：不再有折叠面板 / 身份卡片 / 大号 hero 卡片，工具卡片直接排布。
    final primaryScreen = mobileConnectionSource
        .split('Widget build(BuildContext context)')[1]
        .split('Widget _buildConnectionToolsPanel()')[0];
    final contactsPanel = mobileConnectionSource
        .split('Widget _buildConnectionToolsPanel()')[1]
        .split('Widget _buildQuickActions()')[0];
    final quickActions = mobileConnectionSource
        .split('Widget _buildQuickActions()')[1]
        .split('Widget _buildQuickAction(')[0];
    final quickAction = mobileConnectionSource
        .split('Widget _buildQuickAction(')[1]
        .split('Future<void> _openContactSearch()')[0];
    final deviceHistory = mobileConnectionSource
        .split('void _openDeviceHistory()')[1]
        .split('Widget _buildStatusCard()')[0];
    final mobileInitPages = mobileHomeSource
        .split('void initPages()')[1]
        .split('void _startRemoteFromChat()')[0];

    expect(primaryScreen, contains('AlwaysScrollableScrollPhysics'));
    expect(primaryScreen, isNot(contains('_connectionToolsExpanded')));
    expect(primaryScreen, isNot(contains('_buildIdentitySummary()')));
    expect(primaryScreen, isNot(contains('PeerTabPage()')));
    // 顶部改为极简样式：在线状态与搜索图标都上移到 AppBar（与点聊页一致），
    // 页面内不再有顶栏行 / 大号 hero / 设备 ID chip。
    expect(mobileConnectionSource, isNot(contains('Widget _buildContactsHero')));
    expect(contactsPanel, isNot(contains('OnlineStatusText')));
    expect(contactsPanel, isNot(contains('openContactSearch')));
    expect(mobileHomeSource, contains('openContactSearch'));
    expect(mobileHomeSource, contains('OnlineStatusText'));
    expect(contactsPanel, isNot(contains("translate('Device ID')")));
    expect(contactsPanel, isNot(contains('LinearGradient(')));
    // 工具面板：顶部行 → 4 个功能卡片；联系人列表已拆出为全宽独立区块。
    // AppBar 已居中显示"联系人"标题，正文不再重复标题。
    expect(contactsPanel, contains('_buildQuickActions()'));
    expect(contactsPanel, isNot(contains('_buildPairedContacts()')));
    // 全宽列表：build 方法里顶部行/卡片与列表分属两个 Sliver。
    expect(
      primaryScreen,
      contains('SliverToBoxAdapter(child: _buildPairedContacts())'),
    );
    expect(contactsPanel, isNot(contains('_buildContactsHeader()')));
    expect(contactsPanel, isNot(contains('_buildExpandedConnectionTools()')));
    expect(contactsPanel, isNot(contains('AnimatedSize(')));

    for (final label in <String>[
      'Pair phone',
      'Bluetooth scan',
      'Connection',
      'Access history',
    ]) {
      expect(quickActions, contains("'$label'"));
    }
    // 会议页同款：同一行排布、圆角 14 卡片、图标块 + 标题 + 副标题，
    // 超窄屏/大字体时退回 2 列网格。
    expect(quickActions, contains('constraints.maxWidth >= 300'));
    expect(quickActions, contains('textScale <= 1.6'));
    expect(quickActions, contains('Expanded('));
    expect(quickAction, contains('child: Material('));
    expect(quickAction, contains('Semantics('));
    expect(quickAction, contains('BorderRadius.circular(14)'));
    expect(quickAction, contains('BorderRadius.circular(10)'));
    // 访问历史设备页面隐藏“收藏” tab（收藏已独立为 PC 导航大项 /
    // 手机右上角“+”菜单入口）。
    expect(deviceHistory, contains('const DeviceHistoryPage(),'));
    expect(mobileConnectionSource, contains('_matchesContactQuery('));
    expect(mobileConnectionSource, contains('Semantics('));

    expect(
      mobileInitPages,
      contains('_pages.add(ConnectionPage('),
    );
    expect(mobileInitPages, contains('openContactSearch'));
    expect(mobileInitPages, isNot(contains('Icons.qr_code_scanner_rounded')));
    expect(
      mobileInitPages,
      isNot(contains('Icons.bluetooth_searching_rounded')),
    );
    expect(
      chineseLangSource,
      contains('(\"Connection & identity\", \"连接与身份\")'),
    );
  });

  test('mobile settings root keeps a visible back button and scan action', () {
    // 设置入口从右上角“+”微信风格菜单进入；验证菜单项与设置页结构。
    final moreMenu = mobileHomeSource
        .split('icon: const Icon(Icons.add_circle_outline_rounded),')[1]
        .split('bottomNavigationBar: _buildBottomNav(context)')[0];
    final settingsRoot = mobileSettingsSource
        .split('final settings = SettingsList(')[1]
        .split('Map<String, dynamic> _localProfile()')[0];

    expect(moreMenu, contains("value: 'settings'"));
    expect(moreMenu, contains("translate('My settings')"));
    for (final entry in <String>[
      "translate('Scan & bind')",
      "translate('Add friend')",
      "translate('Bluetooth scan')",
      "translate('Remote connection')",
      "translate('Access history')",
    ]) {
      expect(mobileHomeSource, contains(entry));
    }
    expect(settingsRoot, contains('return Scaffold('));
    expect(settingsRoot, contains('leading: IconButton('));
    expect(settingsRoot, contains('Icons.arrow_back_rounded'));
    expect(settingsRoot, contains('Navigator.of(context).pop()'));
    expect(settingsRoot, contains("title: Text(translate('Me'))"));
    expect(settingsRoot, contains('actions: widget.appBarActions'));
  });

  test('Bluetooth scan stays visible and preserves the full chat workflow', () {
    final contactsHeader = homePageSource
        .split('Widget _buildContactsPane(BuildContext context)')[1]
        .split('SizedBox(\n            height: 48,')[0];
    expect(contactsHeader, contains("tooltip: translate('Bluetooth scan')"));
    expect(contactsHeader, contains('Icons.bluetooth_searching_rounded'));
    expect(
      contactsHeader,
      contains('onPressed: () => _openBluetoothScan(context)'),
    );

    for (final preservedAction in <String>[
      '_toggleScan',
      '_connectDevice',
      '_disconnect',
      '_toggleBlock',
      '_attachFile',
      'ChatPage(',
    ]) {
      expect(bluetoothChatSource, contains(preservedAction));
    }
    expect(bluetoothChatSource, contains('LayoutBuilder('));
    expect(bluetoothChatSource, contains('constraints.maxWidth >= 860'));
    expect(bluetoothChatSource, contains('_buildDesktopWorkspace'));
    expect(bluetoothChatSource, contains('_buildDeviceExplorer'));
    expect(bluetoothChatSource, contains('_buildConversationEmptyState'));
    expect(bluetoothChatSource, contains('? () => _openConversation(device)'));
    expect(
      bluetoothChatSource,
      contains('constraints: const BoxConstraints(minHeight: 48)'),
    );
    expect(
      bluetoothChatSource,
      contains("translate('Bluetooth scan permission required')"),
    );
  });

  test('mobile remote service keeps the scam warning safety flow', () {
    expect(mobileServerSource, contains('class ScamWarningDialog'));
    expect(
      mobileServerSource,
      contains('int _countdown = bind.isCustomClient() ? 0 : 12;'),
    );
    expect(mobileServerSource, contains("key: 'show-scam-warning'"));
    expect(mobileServerSource, contains("translate(\"Don't show again\")"));
    expect(mobileServerSource, contains("translate('Decline')"));
    expect(mobileServerSource, contains("translate('I Agree')"));
    expect(
      RegExp(r'showScamWarning\(context, serverModel\)')
          .allMatches(mobileServerSource)
          .length,
      greaterThanOrEqualTo(3),
    );
  });

  test('desktop contacts open offline conversations and keep remote shortcut',
      () {
    final personContactFlow = homePageSource
        .split('Widget _buildPersonContactItem(')[1]
        .split('Widget _buildMergedChatRow(')[0];
    expect(personContactFlow,
        contains('final conversationContact = contact ?? peer;'));
    expect(
      personContactFlow.indexOf('if (conversationContact != null) {'),
      lessThan(personContactFlow.indexOf('else if (pairing != null) {')),
    );
    expect(
      RegExp(r'onDoubleTap: _contactSelectionMode')
          .allMatches(homePageSource)
          .length,
      greaterThanOrEqualTo(4),
    );
    expect(
      personContactFlow,
      contains('() => _connectDirect(context, primaryPeerId)'),
    );
  });

  test('iOS release keeps the unsigned IPA when signing is unavailable', () {
    expect(iosWorkflowSource, contains('Upload IPA to draft release'));
    expect(iosWorkflowSource, contains('LDesk-3.1.1-unsigned.ipa'));
    expect(iosWorkflowSource, contains('files: flutter/build/ios/ipa/*.ipa'));
  });

  test('runtime diagnostics capture startup, crashes and CI smoke output', () {
    expect(flutterMainSource, contains('RuntimeLogger.instance.init()'));
    expect(flutterMainSource, contains('installErrorHooks()'));
    expect(runtimeLoggerSource, contains('FlutterError.onError'));
    expect(
        runtimeLoggerSource, contains('PlatformDispatcher.instance.onError'));
    expect(runtimeLoggerSource, contains('ldesk-flutter-'));
    expect(runtimeLoggerSource, contains('Future<void> _pendingWrite'));
    expect(runtimeLoggerSource, contains('_maxEntriesPerWindow'));
    expect(runtimeLoggerSource, contains('Timer(_flushInterval'));
    expect(runtimeLoggerSource, contains('_scheduleFlush()'));
    final writeFlow = runtimeLoggerSource
        .split('void _write(')[1]
        .split('void _enqueueLine(')[0];
    expect(writeFlow, isNot(contains('sink.flush()')));
    expect(
      runtimeLoggerSource,
      isNot(contains('unawaited(_sink!.flush()')),
    );
    expect(windowsWorkflowSource, contains('-RedirectStandardOutput'));
    expect(windowsWorkflowSource, contains('-RedirectStandardError'));
    expect(windowsWorkflowSource, contains(r'Join-Path $env:ProgramData'));
    expect(windowsWorkflowSource, contains(r'Join-Path $env:APPDATA'));
  });

  test('desktop startup does not wait for connection status refresh', () {
    final runMainAppStart = flutterMainSource.indexOf(
      'void runMainApp(bool startService) async',
    );
    final runMobileAppStart = flutterMainSource.indexOf(
      'void runMobileApp() async',
      runMainAppStart,
    );
    final runMainAppSource = flutterMainSource.substring(
      runMainAppStart,
      runMobileAppStart,
    );

    expect(
      runMainAppSource,
      contains('unawaited(bind.mainCheckConnectStatus());'),
    );
    expect(
      runMainAppSource,
      isNot(contains('await bind.mainCheckConnectStatus();')),
    );
    expect(windowsRunnerMainSource, contains('SET_FOREGROUND_WINDOW'));
    expect(windowsRunnerMainSource, contains('ShowWindow(startup_window'));
    expect(windowsRunnerMainSource, contains('LUODA_APPNAME'));
    expect(windowsRunnerMainSource, contains('380u, 500u'));
    expect(windowsRunnerMainSource, contains('std::this_thread::sleep_for'));
  });

  test('macOS deployment target supports the direct voice recorder', () {
    expect(macosPodfileSource, contains("platform :osx, '10.15'"));
    expect(macosProjectSource, contains('MACOSX_DEPLOYMENT_TARGET = 10.15;'));
    expect(
      macosProjectSource,
      isNot(contains('MACOSX_DEPLOYMENT_TARGET = 10.14;')),
    );
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

  test('Android SDK levels support the direct voice recorder', () {
    expect(androidAppGradleSource, contains('compileSdkVersion(35)'));
    expect(androidAppGradleSource, contains('minSdkVersion(23)'));
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
    expect(mobileSettingsSource,
        contains('DirectChatAccessController.instance.setAlwaysOn'));
    expect(mobileSettingsSource,
        contains('DirectChatAccessController.instance.setAudience'));
    expect(mobileSettingsSource, contains('.setAutoReconnect(value)'));
    expect(directChatPolicySource,
        contains("peerPoliciesKey = 'direct-chat-contact-policies'"));
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

  test('incoming chat bubbles align with avatars without repeated names', () {
    final messageRowSource = chatPageSource
        .split('Widget weChatMessageRow(')[1]
        .split('if (!chatModel.chatSearchVisible')[0];
    expect(messageRowSource, isNot(contains('message.user.firstName')));
    expect(messageRowSource, isNot(contains('name.isNotEmpty')));
    expect(
      messageRowSource,
      contains('crossAxisAlignment: CrossAxisAlignment.start'),
    );
  });

  test('desktop incoming messages never open the obsolete chat overlay', () {
    final showChatPageSource = chatModelSource
        .split('showChatPage(MessageKey key) async {')[1]
        .split('toggleCMChatPage(MessageKey key) async {')[0];
    expect(
      showChatPageSource,
      contains('Never pop up the floating chat'),
    );
    expect(showChatPageSource, contains('changeCurrentKey(key)'));
  });

  test('chat-only receives never index the empty connection-manager tabs', () {
    final receiveSource = chatModelSource
        .split('receive(int id, String rawText,')[1]
        .split('void send(ChatMessage message)')[0];
    final desktopServerPath = receiveSource
        .split('if (client == null) return;')[1]
        .split('} else {')[0];
    expect(desktopServerPath, contains('if (!client.isChat) {'));
    expect(desktopServerPath, contains('windowOnTop(null)'));
    expect(desktopServerPath, contains('tabs.isNotEmpty'));
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

  test('remote connection startup stays non-blocking until the first frame',
      () {
    final waitingSource = modelSource
        .split('void showConnectedWaitingForImage')[1]
        .split('void showPrivacyFailedDialog')[0];
    expect(remotePageSource, contains('firstFrameTimedOut'));
    expect(remotePageSource, contains('RemoteConnectionProgress'));
    expect(remotePageSource,
        isNot(contains("showLoading(translate('Connecting...')")));
    expect(remotePageSource, isNot(contains('? emptyOverlay()')));
    expect(modelSource, contains('firstFrameTimeoutTimer'));
    expect(remotePageSource, contains('Remote frame timeout'));
    expect(waitingSource, isNot(contains('dialogManager.show(')));
  });

  test('remote frames resync geometry when the peer resolution changes', () {
    expect(flutterBridgeSource, contains('push_frame_size_event'));
    expect(flutterBridgeSource, contains('"name": "frame_size"'));
    final textureRenderSource = flutterBridgeSource
        .split('fn on_rgba_flutter_texture_render')[1]
        .split('// This function is only used')[0];
    expect(
      textureRenderSource.indexOf('self.push_frame_size_event'),
      lessThan(textureRenderSource.indexOf('for (_, session)')),
    );
    expect(flutterBridgeSource, contains('info.size = (rgba.w, rgba.h)'));
    expect(modelSource, contains("name == 'frame_size'"));
    expect(modelSource, contains('handleFrameSize(evt, sessionId)'));
    expect(modelSource, contains('hoty = hotyOrigin * scale'));
    expect(modelSource, contains('final tgtHeight = (height * scale).toInt()'));
  });

  test('desktop chat renders one editor and exposes message controls', () {
    expect(chatPageSource, contains('readOnly: isDesktopHome ||'));
    expect(chatPageSource, contains('_DesktopChatComposer'));
    expect(chatPageSource, contains('retryMessage('));
    expect(chatPageSource, contains('setSelfDestructMessage('));
    expect(chatPageSource, contains('_showWeChatContextMenu'));
    expect(chatModelSource, contains('Future<bool> retryMessage('));
    expect(chatModelSource, contains('Future<bool> setSelfDestructMessage('));
    expect(directChatSource, contains("'expires_at'"));
    expect(directChatSource, contains('setSelfDestruct('));
  });

  test('legacy messages keep basic desktop context menu actions', () {
    final actionsSource = chatPageSource
        .split('List<_ChatMenuAction> actions')[
            chatPageSource.split('List<_ChatMenuAction> actions').length - 1]
        .split('return (')[0];
    expect(actionsSource, contains("'copy'"));
    expect(actionsSource, contains("'reply'"));
    expect(actionsSource, contains("'recall'"));
    expect(actionsSource, contains("'delete'"));
  });

  test('direct pairing only advertises a ready listener in a compact dialog',
      () {
    expect(homePageSource, contains("kOptionDirectListenerStatus"));
    expect(homePageSource, contains("listenerStatus != 'ready'"));
    expect(homePageSource, contains('ConstrainedBox('));
    expect(homePageSource, contains('size: 184'));
    expect(homePageSource, contains('barrierDismissible: true'));
  });

  test('desktop rail routes the VIP entry to the VIP features page', () {
    expect(homePageSource, contains("id: 'vip'"));
    expect(homePageSource, contains("if (section == 'vip')"));
    expect(homePageSource, contains('return const VipFeaturesPage()'));
    expect(homePageSource,
        isNot(contains("return const PeerTabPage(showTabStrip: false);")));
  });

  test('desktop managed-entry menu stays anchored to the clicked item', () {
    expect(homePageSource, contains('overlayBox.globalToLocal(position)'));
    expect(homePageSource, contains('RelativeRect.fromRect('));
    expect(
      homePageSource,
      isNot(contains('RelativeRect.fromLTRB(position.dx, position.dy, 0, 0)')),
    );
  });

  test('desktop connection notices use a compact workspace overlay', () {
    expect(homePageSource, contains('_buildWorkspaceNotice'));
    expect(homePageSource, contains('AnimatedSwitcher('));
    expect(homePageSource, contains('_WorkspaceNoticeTone'));
    expect(
      homePageSource,
      isNot(contains('SnackBar(content: Text(message)')),
    );
  });

  test('desktop identity connection action opens the active ID or IP dialog',
      () {
    expect(
      homePageSource,
      isNot(contains('onPressed: ConnectionPage.focusRemoteId')),
    );
    expect(homePageSource, contains('_showDirectConnectDialog(context)'));
  });

  test('desktop conversation header omits the duplicate online badge', () {
    expect(homePageSource, isNot(contains('_buildNetworkStatusBadge')));
  });

  test('all static Flutter labels have simplified Chinese translations', () {
    final translatePattern = RegExp(
      r'''translate\(\s*(['"])((?:\\.|(?!\1).)*)\1\s*\)''',
    );
    final tuplePattern = RegExp(
      r'''\("((?:\\.|[^"])*)",\s*"((?:\\.|[^"])*)"\)''',
    );
    final usedKeys = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in translatePattern.allMatches(source)) {
        final key =
            match.group(2)!.replaceAll(r"\'", "'").replaceAll(r'\"', '"');
        if (!key.contains(r'$')) usedKeys.add(key);
      }
    }
    usedKeys.addAll(<String>{
      'Record voice message',
      'Stop and send voice message',
      'Pin',
      'Unpin',
      'Pin Toolbar',
      'Unpin Toolbar',
    });
    // Symbols that are identical in all languages must not be flagged.
    usedKeys.removeWhere((key) => key.length <= 2 && RegExp(r'^[^a-zA-Z]+$').hasMatch(key));
    final cnSource = File('../src/lang/cn.rs').readAsStringSync();
    final translations = <String, String>{
      for (final match in tuplePattern.allMatches(cnSource))
        match.group(1)!: match.group(2)!,
    };
    final missing = usedKeys.where((key) {
      final value = translations[key];
      return value == null || value.trim().isEmpty || value == key;
    }).toList()
      ..sort();
    expect(missing, isEmpty, reason: 'Missing Chinese translations: $missing');
  });

  test('language settings expose only English and simplified Chinese', () {
    final localeBlock = flutterCommonSource
        .split('List<Locale> supportedLocales')[1]
        .split('];')[0];
    expect(RegExp(r'Locale\(').allMatches(localeBlock).length, 2);
    expect(localeBlock, contains("Locale('en', 'US')"));
    expect(localeBlock, contains("Locale('zh', 'CN')"));

    final languagesBlock =
        rustLanguageSource.split('pub const LANGS')[1].split('];')[0];
    expect(RegExp(r'\("').allMatches(languagesBlock).length, 2);
    expect(languagesBlock, contains(r'("en", "English")'));
    expect(languagesBlock, contains(r'("zh-cn", "\u{7b80}'));
    final desktopLanguageFlow = settingsGeneralSource
        .split('Widget language()')[1]
        .split('\n  }\n}')[0];
    expect(desktopLanguageFlow, isNot(contains('keys.insert')));
    final mobileLanguageFlow = mobileSettingsSource
        .split('void showLanguageSettings')[1]
        .split('void showThemeSettings')[0];
    expect(
      mobileLanguageFlow,
      isNot(contains("getRadio(Text(translate('Default'))")),
    );
  });

  test('English UI does not fall back to Chinese static labels', () {
    final translatePattern = RegExp(
      r'''translate\(\s*(['"])((?:\\.|(?!\1).)*)\1\s*\)''',
    );
    final tuplePattern = RegExp(
      r'''\("((?:\\.|[^"])*)",\s*"((?:\\.|[^"])*)"\)''',
    );
    final usedKeys = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final match
          in translatePattern.allMatches(entity.readAsStringSync())) {
        final key = match.group(2)!;
        if (!key.contains(r'$')) usedKeys.add(key);
      }
    }
    final enSource = File('../src/lang/en.rs').readAsStringSync();
    final translations = <String, String>{
      for (final match in tuplePattern.allMatches(enSource))
        match.group(1)!: match.group(2)!,
    };
    final cjk = RegExp(r'[\u3400-\u9fff]');
    final mixed = usedKeys.where((key) {
      final value = translations[key] ?? key;
      return cjk.hasMatch(value);
    }).toList()
      ..sort();
    expect(mixed, isEmpty,
        reason: 'Chinese labels leaked into English: $mixed');
  });

  test('group and plugin settings do not bypass localization', () {
    expect(
      meetingGroupPanelSource,
      contains("hintText: translate('Group name')"),
    );
    expect(pluginSettingsSource, contains("Text(translate('Options'))"));
  });

  test('mobile settings and invite controls avoid hardcoded English labels',
      () {
    expect(mobileSettingsSource, isNot(contains("Text('Version: ")));
    expect(mobileSettingsSource, isNot(contains("Text('Error: ")));
    expect(inviteViewerSource, isNot(contains("Text('\$m min')")));
  });

  test('mobile settings keep technical connection switches advanced-only', () {
    final primarySettingsFlow = mobileSettingsSource
        .split('SettingsSection(title: Text(translate("Settings"))')[1]
        .split("title: Text(translate('More'))")[0];
    expect(
      RegExp(r'if \(_showAdvancedSettings')
          .allMatches(primarySettingsFlow)
          .length,
      greaterThanOrEqualTo(8),
    );
    expect(
      primarySettingsFlow,
      contains('if (_showAdvancedSettings && !incomingOnly)'),
    );
  });

  test('new history lists hide loopback duplicates and collapse device aliases',
      () {
    expect(homePageSource, contains('_isLoopbackPeer(peer)'));
    expect(homePageSource, contains('_historyIdentity(peer)'));
    expect(homePageSource, contains('seenPeerKeys.add(identity)'));
  });

  test('desktop shows file helper only after phone pairing and closes QR dialog',
      () {
    // 绑定手机后：文件传输助手置顶出现（微信风格）。
    expect(homePageSource, contains('boundToPhone ='));
    expect(homePageSource, contains('ensureFileHelperEntry()'));
    expect(homePageSource, contains('gFFI.chatModel.fileHelperKey'));
    expect(homePageSource, contains('MapEntry<MessageKey, MessageBody>('));
    expect(homePageSource, contains('if (fileHelperRow != null)'));
    // 二维码弹窗：绑定成功后自动关闭（监听 DirectPairingStore.revision）。
    final qrFlow = homePageSource
        .split('Future<void> _showPairingQrDialog(')[1]
        .split('Future<void> _showBoundPhoneDialog(')[0];
    expect(qrFlow, contains('DirectPairingStore.revision.addListener'));
    expect(qrFlow, contains('Navigator.of(ctx).pop()'));
    expect(qrFlow, contains('removeListener(bindingListener)'));
  });
}
