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
  final addressBookSource = File(
    'lib/common/widgets/address_book.dart',
  ).readAsStringSync();
  final settingsSource = File(
    'lib/desktop/pages/desktop_setting_page.dart',
  ).readAsStringSync();
  final settingsGeneralSource = File(
    'lib/desktop/pages/desktop_setting_general.part.dart',
  ).readAsStringSync();
  final remoteToolbarSource = File(
    'lib/desktop/widgets/remote_toolbar.dart',
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
  final cargoSource = File('../Cargo.toml').readAsStringSync();
  final peerModelSource = File(
    'lib/models/peer_model.dart',
  ).readAsStringSync();
  final protocolSource = File(
    '../libs/hbb_common/protos/message.proto',
  ).readAsStringSync();
  final clientSource = File('../src/client.rs').readAsStringSync();
  final serverConnectionSource = File(
    '../src/server/connection.rs',
  ).readAsStringSync();
  final directListenerSource = File(
    '../src/rendezvous_mediator.rs',
  ).readAsStringSync();
  final serverSource = File('../src/server.rs').readAsStringSync();
  final flutterBridgeSource = File('../src/flutter.rs').readAsStringSync();

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
    expect(mobileConnectionSource, contains('bool _chatMode = true'));
    expect(mobileConnectionSource, contains('isChat: true'));
    expect(mobileConnectionSource, contains('SegmentedButton<bool>'));
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
