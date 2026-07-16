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
  final remoteToolbarSource = File(
    'lib/desktop/widgets/remote_toolbar.dart',
  ).readAsStringSync();
  final modelSource = File(
    'lib/models/model.dart',
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
  final chatPageSource = File(
    'lib/common/widgets/chat_page.dart',
  ).readAsStringSync();
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
    expect(homePageSource, contains("'ID / IP:port'"));
    expect(homePageSource, contains('ChatPage('));
    expect(homePageSource, contains('_sendFilesFromConversation'));
    expect(homePageSource, contains('_buildActiveTransferStrip'));
    expect(homePageSource, contains('ffi.ffiModel.direct != true'));
    expect(homePageSource, contains('chatFfi.ffiModel.direct != true'));
    expect(homePageSource, contains('localController.sendFiles'));
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
    expect(remoteToolbarSource, contains('buildFileTransfer'));
    expect(remoteToolbarSource, contains('buildDisplay'));
    expect(
      remoteToolbarSource.indexOf('toolbarItems.add(_ChatMenu'),
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
    expect(chatPageSource, contains('isDirectOutgoingChat'));
    expect(
      chatPageSource,
      contains('chatModel.parent.target?.ffiModel.direct == true'),
    );
  });

  test('mobile conversation file transfer refuses relay sessions', () {
    expect(
      mobileHomeSource,
      contains(
        'ffi.start(peerId, isFileTransfer: true, forceRelay: false)',
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

  test('local profile takes precedence over account profile on direct links', () {
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
