import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common/widgets/setting_widgets.dart';
import 'package:luoda_flutter/desktop/pages/desktop_setting_page.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common.dart';
import '../../common/direct_chat_policy.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/login.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import '../widgets/dialog.dart';
import 'home_page.dart';
import 'scan_page.dart';

class SettingsPage extends StatefulWidget implements PageShape {
  @override
  final title = translate("Me");

  @override
  final icon = const Icon(Icons.person_outline_rounded);

  @override
  final appBarActions = bind.isDisableSettings() ? [] : [ScanButton()];

  @override
  State<SettingsPage> createState() => _SettingsState();
}

const url = 'https://dicad.cn/';

enum KeepScreenOn {
  never,
  duringControlled,
  serviceOn,
}

String _keepScreenOnToOption(KeepScreenOn value) {
  switch (value) {
    case KeepScreenOn.never:
      return 'never';
    case KeepScreenOn.duringControlled:
      return 'during-controlled';
    case KeepScreenOn.serviceOn:
      return 'service-on';
  }
}

KeepScreenOn optionToKeepScreenOn(String value) {
  switch (value) {
    case 'never':
      return KeepScreenOn.never;
    case 'service-on':
      return KeepScreenOn.serviceOn;
    default:
      return KeepScreenOn.duringControlled;
  }
}

class _SettingsState extends State<SettingsPage> with WidgetsBindingObserver {
  final _hasIgnoreBattery =
      false; //androidVersion >= 26; // remove because not work on every device
  var _ignoreBatteryOpt = false;
  var _enableStartOnBoot = false;
  var _checkUpdateOnStartup = false;
  var _showTerminalExtraKeys = false;
  var _floatingWindowDisabled = false;
  var _keepScreenOn = KeepScreenOn.duringControlled; // relay on floating window
  var _enableAbr = false;
  var _denyLANDiscovery = false;
  var _onlyWhiteList = false;
  var _enableDirectIPAccess = false;
  var _enableRecordSession = false;
  var _enableHardwareCodec = false;
  var _allowWebSocket = false;
  var _autoRecordIncomingSession = false;
  var _autoRecordOutgoingSession = false;
  var _allowAutoDisconnect = false;
  var _localIP = "";
  var _directAccessPort = "";
  var _fingerprint = "";
  var _buildDate = "";
  var _autoDisconnectTimeout = "";
  var _hideServer = false;
  var _hideProxy = false;
  var _hideNetwork = false;
  var _hideWebSocket = false;
  var _enableTrustedDevices = false;
  var _enableUdpPunch = false;
  var _allowInsecureTlsFallback = false;
  var _disableUdp = false;
  var _enableIpv6Punch = false;
  var _isUsingPublicServer = false;
  var _allowAskForNoteAtEndOfConnection = false;
  var _preventSleepWhileConnected = true;
  var _directChatAlwaysOn = false;
  var _directChatTrustedOnly = true;
  var _directChatAutoReconnect = true;
  var _serverlessDirectOnly = false;
  var _showAdvancedSettings = false;

  _SettingsState() {
    _enableAbr = option2bool(
        kOptionEnableAbr, bind.mainGetOptionSync(key: kOptionEnableAbr));
    _denyLANDiscovery = !option2bool(kOptionEnableLanDiscovery,
        bind.mainGetOptionSync(key: kOptionEnableLanDiscovery));
    _onlyWhiteList = whitelistNotEmpty();
    _enableDirectIPAccess = option2bool(
        kOptionDirectServer, bind.mainGetOptionSync(key: kOptionDirectServer));
    _enableRecordSession = option2bool(kOptionEnableRecordSession,
        bind.mainGetOptionSync(key: kOptionEnableRecordSession));
    _enableHardwareCodec = option2bool(kOptionEnableHwcodec,
        bind.mainGetOptionSync(key: kOptionEnableHwcodec));
    _allowWebSocket = mainGetBoolOptionSync(kOptionAllowWebSocket);
    _allowInsecureTlsFallback =
        mainGetBoolOptionSync(kOptionAllowInsecureTLSFallback);
    _disableUdp = bind.mainGetOptionSync(key: kOptionDisableUdp) == 'Y';
    _autoRecordIncomingSession = option2bool(kOptionAllowAutoRecordIncoming,
        bind.mainGetOptionSync(key: kOptionAllowAutoRecordIncoming));
    _autoRecordOutgoingSession = option2bool(kOptionAllowAutoRecordOutgoing,
        bind.mainGetLocalOption(key: kOptionAllowAutoRecordOutgoing));
    _localIP = bind.mainGetOptionSync(key: 'local-ip-addr');
    _directAccessPort = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    _allowAutoDisconnect = option2bool(kOptionAllowAutoDisconnect,
        bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect));
    _autoDisconnectTimeout =
        bind.mainGetOptionSync(key: kOptionAutoDisconnectTimeout);
    _hideServer =
        bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
    _hideProxy = bind.mainGetBuildinOption(key: kOptionHideProxySetting) == 'Y';
    _hideNetwork =
        bind.mainGetBuildinOption(key: kOptionHideNetworkSetting) == 'Y';
    _hideWebSocket =
        bind.mainGetBuildinOption(key: kOptionHideWebSocketSetting) == 'Y' ||
            isWeb;
    _enableTrustedDevices = mainGetBoolOptionSync(kOptionEnableTrustedDevices);
    _enableUdpPunch = mainGetLocalBoolOptionSync(kOptionEnableUdpPunch);
    _enableIpv6Punch = mainGetLocalBoolOptionSync(kOptionEnableIpv6Punch);
    _allowAskForNoteAtEndOfConnection =
        mainGetLocalBoolOptionSync(kOptionAllowAskForNoteAtEndOfConnection);
    _preventSleepWhileConnected =
        mainGetLocalBoolOptionSync(kOptionKeepAwakeDuringOutgoingSessions);
    _showTerminalExtraKeys =
        mainGetLocalBoolOptionSync(kOptionEnableShowTerminalExtraKeys);
    final directChatAccess = DirectChatAccessController.instance..load();
    _directChatAlwaysOn = directChatAccess.alwaysOn;
    _directChatTrustedOnly =
        directChatAccess.audience == DirectChatAudience.friendsOnly;
    _directChatAutoReconnect = directChatAccess.autoReconnect;
    _serverlessDirectOnly =
        bind.mainGetOptionSync(key: kOptionServerlessDirectOnly) == 'Y';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var update = false;

      if (_hasIgnoreBattery) {
        if (await checkAndUpdateIgnoreBatteryStatus()) {
          update = true;
        }
      }

      if (await checkAndUpdateStartOnBoot()) {
        update = true;
      }

      // start on boot depends on ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS and SYSTEM_ALERT_WINDOW
      var enableStartOnBoot =
          await gFFI.invokeMethod(AndroidChannel.kGetStartOnBootOpt);
      if (enableStartOnBoot) {
        if (!await canStartOnBoot()) {
          enableStartOnBoot = false;
          gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
        }
      }

      if (enableStartOnBoot != _enableStartOnBoot) {
        update = true;
        _enableStartOnBoot = enableStartOnBoot;
      }

      var checkUpdateOnStartup =
          mainGetLocalBoolOptionSync(kOptionEnableCheckUpdate);
      if (checkUpdateOnStartup != _checkUpdateOnStartup) {
        update = true;
        _checkUpdateOnStartup = checkUpdateOnStartup;
      }

      var floatingWindowDisabled =
          bind.mainGetLocalOption(key: kOptionDisableFloatingWindow) == "Y" ||
              !await AndroidPermissionManager.check(kSystemAlertWindow);
      if (floatingWindowDisabled != _floatingWindowDisabled) {
        update = true;
        _floatingWindowDisabled = floatingWindowDisabled;
      }

      final keepScreenOn = _floatingWindowDisabled
          ? KeepScreenOn.never
          : optionToKeepScreenOn(
              bind.mainGetLocalOption(key: kOptionKeepScreenOn));
      if (keepScreenOn != _keepScreenOn) {
        update = true;
        _keepScreenOn = keepScreenOn;
      }

      final fingerprint = await bind.mainGetFingerprint();
      if (_fingerprint != fingerprint) {
        update = true;
        _fingerprint = fingerprint;
      }

      final buildDate = await bind.mainGetBuildDate();
      if (_buildDate != buildDate) {
        update = true;
        _buildDate = buildDate;
      }

      final isUsingPublicServer = await bind.mainIsUsingPublicServer();
      if (_isUsingPublicServer != isUsingPublicServer) {
        update = true;
        _isUsingPublicServer = isUsingPublicServer;
      }

      if (update) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      () async {
        final ibs = await checkAndUpdateIgnoreBatteryStatus();
        final sob = await checkAndUpdateStartOnBoot();
        if (ibs || sob) {
          setState(() {});
        }
      }();
    }
  }

  Future<bool> checkAndUpdateIgnoreBatteryStatus() async {
    final res = await AndroidPermissionManager.check(
        kRequestIgnoreBatteryOptimizations);
    if (_ignoreBatteryOpt != res) {
      _ignoreBatteryOpt = res;
      return true;
    } else {
      return false;
    }
  }

  Future<bool> checkAndUpdateStartOnBoot() async {
    if (!await canStartOnBoot() && _enableStartOnBoot) {
      _enableStartOnBoot = false;
      debugPrint(
          "checkAndUpdateStartOnBoot and set _enableStartOnBoot -> false");
      gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
      return true;
    } else {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    final outgoingOnly = bind.isOutgoingOnly();
    final incomingOnly = bind.isIncomingOnly();
    final customClientSection = CustomSettingsSection(
        child: Column(
      children: [
        if (bind.isCustomClient())
          Align(
            alignment: Alignment.center,
            child: loadPowered(context),
          ),
        Align(
          alignment: Alignment.center,
          child: loadLogo(),
        )
      ],
    ));
    final List<AbstractSettingsTile> enhancementsTiles = [];
    final enable2fa = bind.mainHasValid2FaSync();
    final List<AbstractSettingsTile> tfaTiles = [
      SettingsTile.switchTile(
        title: Text(translate('enable-2fa-title')),
        initialValue: enable2fa,
        onToggle: (v) async {
          update() async {
            setState(() {});
          }

          if (v == false) {
            CommonConfirmDialog(
                gFFI.dialogManager, translate('cancel-2fa-confirm-tip'), () {
              change2fa(callback: update);
            });
          } else {
            change2fa(callback: update);
          }
        },
      ),
      if (enable2fa)
        SettingsTile.switchTile(
          title: Text(translate('Telegram bot')),
          initialValue: bind.mainHasValidBotSync(),
          onToggle: (v) async {
            update() async {
              setState(() {});
            }

            if (v == false) {
              CommonConfirmDialog(
                  gFFI.dialogManager, translate('cancel-bot-confirm-tip'), () {
                changeBot(callback: update);
              });
            } else {
              changeBot(callback: update);
            }
          },
        ),
      if (enable2fa)
        SettingsTile.switchTile(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('Enable trusted devices')),
              Text('* ${translate('enable-trusted-devices-tip')}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          initialValue: _enableTrustedDevices,
          onToggle: isOptionFixed(kOptionEnableTrustedDevices)
              ? null
              : (v) async {
                  mainSetBoolOption(kOptionEnableTrustedDevices, v);
                  setState(() {
                    _enableTrustedDevices = v;
                  });
                },
        ),
      if (enable2fa && _enableTrustedDevices)
        SettingsTile(
            title: Text(translate('Manage trusted devices')),
            trailing: Icon(Icons.arrow_forward_ios),
            onPressed: (context) {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return _ManageTrustedDevices();
              }));
            })
    ];
    final List<AbstractSettingsTile> shareScreenTiles = [
      SettingsTile.switchTile(
        title: Text(translate('Deny LAN discovery')),
        initialValue: _denyLANDiscovery,
        onToggle: isOptionFixed(kOptionEnableLanDiscovery)
            ? null
            : (v) async {
                await bind.mainSetOption(
                    key: kOptionEnableLanDiscovery,
                    value: bool2option(kOptionEnableLanDiscovery, !v));
                final newValue = !option2bool(kOptionEnableLanDiscovery,
                    await bind.mainGetOption(key: kOptionEnableLanDiscovery));
                setState(() {
                  _denyLANDiscovery = newValue;
                });
              },
      ),
      SettingsTile.switchTile(
        title: Row(children: [
          Expanded(child: Text(translate('Use IP Whitelisting'))),
          Offstage(
                  offstage: !_onlyWhiteList,
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Color.fromARGB(255, 255, 204, 0)))
              .marginOnly(left: 5)
        ]),
        initialValue: _onlyWhiteList,
        onToggle: (_) async {
          update() async {
            final onlyWhiteList = whitelistNotEmpty();
            if (onlyWhiteList != _onlyWhiteList) {
              setState(() {
                _onlyWhiteList = onlyWhiteList;
              });
            }
          }

          changeWhiteList(callback: update);
        },
      ),
      SettingsTile.switchTile(
        title: Text(translate('Adaptive bitrate')),
        initialValue: _enableAbr,
        onToggle: isOptionFixed(kOptionEnableAbr)
            ? null
            : (v) async {
                await mainSetBoolOption(kOptionEnableAbr, v);
                final newValue = await mainGetBoolOption(kOptionEnableAbr);
                setState(() {
                  _enableAbr = newValue;
                });
              },
      ),
      SettingsTile.switchTile(
        title: Text(translate('Enable recording session')),
        initialValue: _enableRecordSession,
        onToggle: isOptionFixed(kOptionEnableRecordSession)
            ? null
            : (v) async {
                await mainSetBoolOption(kOptionEnableRecordSession, v);
                final newValue =
                    await mainGetBoolOption(kOptionEnableRecordSession);
                setState(() {
                  _enableRecordSession = newValue;
                });
              },
      ),
      SettingsTile.switchTile(
        title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(translate("Direct IP Access")),
                    Offstage(
                        offstage: !_enableDirectIPAccess,
                        child: Text(
                          '${translate("Local Address")}: $_localIP${_directAccessPort.isEmpty ? "" : ":$_directAccessPort"}',
                          style: Theme.of(context).textTheme.bodySmall,
                        )),
                  ])),
              Offstage(
                  offstage: !_enableDirectIPAccess,
                  child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.edit,
                        size: 20,
                      ),
                      onPressed: isOptionFixed(kOptionDirectAccessPort)
                          ? null
                          : () async {
                              final port = await changeDirectAccessPort(
                                  _localIP, _directAccessPort);
                              setState(() {
                                _directAccessPort = port;
                              });
                            }))
            ]),
        initialValue: _enableDirectIPAccess,
        onToggle: isOptionFixed(kOptionDirectServer)
            ? null
            : (_) async {
                _enableDirectIPAccess = !_enableDirectIPAccess;
                String value =
                    bool2option(kOptionDirectServer, _enableDirectIPAccess);
                await bind.mainSetOption(
                    key: kOptionDirectServer, value: value);
                setState(() {});
              },
      ),
      SettingsTile.switchTile(
        title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(translate("auto_disconnect_option_tip")),
                    Offstage(
                        offstage: !_allowAutoDisconnect,
                        child: Text(
                          '${_autoDisconnectTimeout.isEmpty ? '10' : _autoDisconnectTimeout} min',
                          style: Theme.of(context).textTheme.bodySmall,
                        )),
                  ])),
              Offstage(
                  offstage: !_allowAutoDisconnect,
                  child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.edit,
                        size: 20,
                      ),
                      onPressed: isOptionFixed(kOptionAutoDisconnectTimeout)
                          ? null
                          : () async {
                              final timeout = await changeAutoDisconnectTimeout(
                                  _autoDisconnectTimeout);
                              setState(() {
                                _autoDisconnectTimeout = timeout;
                              });
                            }))
            ]),
        initialValue: _allowAutoDisconnect,
        onToggle: isOptionFixed(kOptionAllowAutoDisconnect)
            ? null
            : (_) async {
                _allowAutoDisconnect = !_allowAutoDisconnect;
                String value = bool2option(
                    kOptionAllowAutoDisconnect, _allowAutoDisconnect);
                await bind.mainSetOption(
                    key: kOptionAllowAutoDisconnect, value: value);
                setState(() {});
              },
      )
    ];
    if (_hasIgnoreBattery) {
      enhancementsTiles.insert(
          0,
          SettingsTile.switchTile(
              initialValue: _ignoreBatteryOpt,
              title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(translate('Keep LUODA background service')),
                    Text('* ${translate('Ignore Battery Optimizations')}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
              onToggle: (v) async {
                if (v) {
                  await AndroidPermissionManager.request(
                      kRequestIgnoreBatteryOptimizations);
                } else {
                  final res = await gFFI.dialogManager.show<bool>(
                      (setState, close, context) => CustomAlertDialog(
                            title: Text(translate("Open System Setting")),
                            content: Text(translate(
                                "android_open_battery_optimizations_tip")),
                            actions: [
                              dialogButton("Cancel",
                                  onPressed: () => close(), isOutline: true),
                              dialogButton(
                                "Open System Setting",
                                onPressed: () => close(true),
                              ),
                            ],
                          ));
                  if (res == true) {
                    AndroidPermissionManager.startAction(
                        kActionApplicationDetailsSettings);
                  }
                }
              }));
    }
    enhancementsTiles.add(SettingsTile.switchTile(
        initialValue: _enableStartOnBoot,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(translate('Start on boot')),
          Text(
              '* ${translate('Start the screen sharing service on boot, requires special permissions')}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        onToggle: (toValue) async {
          if (toValue) {
            // 1. request kIgnoreBatteryOptimizations
            if (!await AndroidPermissionManager.check(
                kRequestIgnoreBatteryOptimizations)) {
              if (!await AndroidPermissionManager.request(
                  kRequestIgnoreBatteryOptimizations)) {
                return;
              }
            }

            // 2. request kSystemAlertWindow
            if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
              if (!await AndroidPermissionManager.request(kSystemAlertWindow)) {
                return;
              }
            }

            // (Optional) 3. request input permission
          }
          setState(() => _enableStartOnBoot = toValue);

          gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, toValue);
        }));

    if (!bind.isCustomClient()) {
      enhancementsTiles.add(
        SettingsTile.switchTile(
          initialValue: _checkUpdateOnStartup,
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(translate('Check for software update on startup')),
          ]),
          onToggle: (bool toValue) async {
            await mainSetLocalBoolOption(kOptionEnableCheckUpdate, toValue);
            setState(() => _checkUpdateOnStartup = toValue);
          },
        ),
      );
    }

    enhancementsTiles.add(
      SettingsTile.switchTile(
        initialValue: _showTerminalExtraKeys,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(translate('Show terminal extra keys')),
        ]),
        onToggle: (bool v) async {
          await mainSetLocalBoolOption(kOptionEnableShowTerminalExtraKeys, v);
          final newValue =
              mainGetLocalBoolOptionSync(kOptionEnableShowTerminalExtraKeys);
          setState(() {
            _showTerminalExtraKeys = newValue;
          });
        },
      ),
    );

    onFloatingWindowChanged(bool toValue) async {
      if (toValue) {
        if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
          if (!await AndroidPermissionManager.request(kSystemAlertWindow)) {
            return;
          }
        }
      }
      final disable = !toValue;
      bind.mainSetLocalOption(
          key: kOptionDisableFloatingWindow,
          value: disable ? 'Y' : defaultOptionNo);
      setState(() => _floatingWindowDisabled = disable);
      gFFI.serverModel.androidUpdatekeepScreenOn();
    }

    enhancementsTiles.add(SettingsTile.switchTile(
        initialValue: !_floatingWindowDisabled,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(translate('Floating window')),
          Text('* ${translate('floating_window_tip')}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        onToggle: bind.mainIsOptionFixed(key: kOptionDisableFloatingWindow)
            ? null
            : onFloatingWindowChanged));

    enhancementsTiles.add(_getPopupDialogRadioEntry(
      title: 'Keep screen on',
      list: [
        _RadioEntry('Never', _keepScreenOnToOption(KeepScreenOn.never)),
        _RadioEntry('During controlled',
            _keepScreenOnToOption(KeepScreenOn.duringControlled)),
        _RadioEntry('During service is on',
            _keepScreenOnToOption(KeepScreenOn.serviceOn)),
      ],
      getter: () => _keepScreenOnToOption(_floatingWindowDisabled
          ? KeepScreenOn.never
          : optionToKeepScreenOn(
              bind.mainGetLocalOption(key: kOptionKeepScreenOn))),
      asyncSetter: isOptionFixed(kOptionKeepScreenOn) || _floatingWindowDisabled
          ? null
          : (value) async {
              await bind.mainSetLocalOption(
                  key: kOptionKeepScreenOn, value: value);
              setState(() => _keepScreenOn = optionToKeepScreenOn(value));
              gFFI.serverModel.androidUpdatekeepScreenOn();
            },
    ));

    final disabledSettings = bind.isDisableSettings();
    final hideSecuritySettings =
        bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) == 'Y';
    final localProfile = _localProfile();
    final localDisplayName =
        (localProfile['display_name'] ?? localProfile['name'] ?? '')
            .toString()
            .trim();
    final settings = SettingsList(
      sections: [
        customClientSection,
        SettingsSection(
          title: Text(translate('Profile and direct messages')),
          tiles: [
            SettingsTile.navigation(
              leading: _localProfileAvatar(38),
              title: Text(
                localDisplayName.isEmpty
                    ? translate('Local profile')
                    : localDisplayName,
              ),
              description: Text(translate('Avatar and display name')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onPressed: (_) => _editLocalProfile(),
            ),
            SettingsTile.switchTile(
              leading: const Icon(Icons.mark_chat_unread_outlined),
              title: Text(translate('Allow always-on direct messages')),
              description: Text(translate('Available when LDesk is running')),
              initialValue: _directChatAlwaysOn,
              onToggle: (value) async {
                await DirectChatAccessController.instance.setAlwaysOn(value);
                if (isAndroid) {
                  if (value) {
                    await _requestDirectChatNotificationPermissionOnce();
                  }
                  await gFFI.invokeMethod('set_direct_chat_service', value);
                }
                if (mounted) {
                  setState(() => _directChatAlwaysOn = value);
                }
              },
            ),
            SettingsTile.switchTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(translate('Only trusted contacts can message me')),
              initialValue: _directChatTrustedOnly,
              enabled: _directChatAlwaysOn,
              onToggle: _directChatAlwaysOn
                  ? (value) async {
                      await DirectChatAccessController.instance.setAudience(
                        value
                            ? DirectChatAudience.friendsOnly
                            : DirectChatAudience.everyone,
                      );
                      setState(() => _directChatTrustedOnly = value);
                    }
                  : null,
            ),
            if (_showAdvancedSettings)
              SettingsTile.switchTile(
                leading: const Icon(Icons.sync_rounded),
                title: Text(
                  translate('Reconnect trusted contacts automatically'),
                ),
                initialValue: _directChatAutoReconnect,
                enabled: _directChatAlwaysOn,
                onToggle: _directChatAlwaysOn
                    ? (value) async {
                        await DirectChatAccessController.instance
                            .setAutoReconnect(value);
                        setState(() => _directChatAutoReconnect = value);
                      }
                    : null,
              ),
            if (_showAdvancedSettings)
              SettingsTile.navigation(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: Text(translate('Contact message permissions')),
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: _directChatAlwaysOn,
                onPressed: _directChatAlwaysOn
                    ? (_) => _showContactMessagePermissions()
                    : null,
              ),
          ],
        ),
        if (!kLocalProfileOnly && !bind.isDisableAccount())
          SettingsSection(
            title: Text(translate('Account')),
            tiles: [
              SettingsTile(
                title: Obx(() => Text(gFFI.userModel.userName.value.isEmpty
                    ? translate('Login')
                    : '${translate('Logout')} (${gFFI.userModel.accountLabelWithHandle})')),
                leading: Obx(() {
                  final avatar = bind.mainResolveAvatarUrl(
                      avatar: gFFI.userModel.avatar.value);
                  return buildAvatarWidget(
                        avatar: avatar,
                        size: 28,
                        borderRadius: null,
                        fallback: Icon(Icons.person),
                      ) ??
                      Icon(Icons.person);
                }),
                onPressed: (context) {
                  if (gFFI.userModel.userName.value.isEmpty) {
                    loginDialog();
                  } else {
                    logOutConfirmDialog();
                  }
                },
              ),
            ],
          ),
        SettingsSection(title: Text(translate("Settings")), tiles: [
          if (_showAdvancedSettings)
            SettingsTile.switchTile(
              title: Text(translate('Serverless direct mode')),
              description: Text(translate(
                'When enabled, device ID connections are disabled; IP, QR, and LAN connections stay direct. When disabled, device IDs try direct first and use encrypted TCP relay only if needed.',
              )),
              leading: const Icon(Icons.shield_outlined),
              initialValue: _serverlessDirectOnly,
              onToggle:
                  disabledSettings || isOptionFixed(kOptionServerlessDirectOnly)
                      ? null
                      : (value) async {
                          await bind.mainSetOption(
                            key: kOptionServerlessDirectOnly,
                            value: value ? 'Y' : 'N',
                          );
                          if (mounted) {
                            setState(() => _serverlessDirectOnly = value);
                          }
                        },
            ),
          if (_showAdvancedSettings &&
              !_serverlessDirectOnly &&
              !disabledSettings &&
              !_hideNetwork &&
              !_hideServer)
            SettingsTile(
                title: Text(translate('ID/Relay Server')),
                leading: Icon(Icons.cloud),
                onPressed: (context) {
                  showServerSettings(gFFI.dialogManager, (callback) async {
                    _isUsingPublicServer = await bind.mainIsUsingPublicServer();
                    setState(callback);
                  });
                }),
          if (_showAdvancedSettings &&
              !_serverlessDirectOnly &&
              !_hideNetwork &&
              !_hideProxy)
            SettingsTile(
                title: Text(translate('Socks5/Http(s) Proxy')),
                leading: Icon(Icons.network_ping),
                onPressed: (context) {
                  changeSocks5Proxy();
                }),
          if (_showAdvancedSettings &&
              !_serverlessDirectOnly &&
              !disabledSettings &&
              !_hideNetwork &&
              !_hideWebSocket)
            SettingsTile.switchTile(
              title: Text(translate('Use WebSocket')),
              initialValue: _allowWebSocket,
              onToggle: isOptionFixed(kOptionAllowWebSocket)
                  ? null
                  : (v) async {
                      await mainSetBoolOption(kOptionAllowWebSocket, v);
                      final newValue =
                          await mainGetBoolOption(kOptionAllowWebSocket);
                      setState(() {
                        _allowWebSocket = newValue;
                      });
                    },
            ),
          if (_showAdvancedSettings &&
              !_serverlessDirectOnly &&
              !_isUsingPublicServer)
            SettingsTile.switchTile(
              title: Text(translate('Allow insecure TLS fallback')),
              initialValue: _allowInsecureTlsFallback,
              onToggle: isOptionFixed(kOptionAllowInsecureTLSFallback)
                  ? null
                  : (v) async {
                      await mainSetBoolOption(
                          kOptionAllowInsecureTLSFallback, v);
                      final newValue = mainGetBoolOptionSync(
                          kOptionAllowInsecureTLSFallback);
                      setState(() {
                        _allowInsecureTlsFallback = newValue;
                      });
                    },
            ),
          if (_showAdvancedSettings &&
              !_serverlessDirectOnly &&
              isAndroid &&
              !outgoingOnly &&
              !_isUsingPublicServer)
            SettingsTile.switchTile(
              title: Text(translate('Disable UDP')),
              initialValue: _disableUdp,
              onToggle: isOptionFixed(kOptionDisableUdp)
                  ? null
                  : (v) async {
                      await bind.mainSetOption(
                          key: kOptionDisableUdp, value: v ? 'Y' : 'N');
                      final newValue =
                          bind.mainGetOptionSync(key: kOptionDisableUdp) == 'Y';
                      setState(() {
                        _disableUdp = newValue;
                      });
                    },
            ),
          if (_showAdvancedSettings && !_serverlessDirectOnly && !incomingOnly)
            SettingsTile.switchTile(
              title: Text(translate('Enable UDP hole punching')),
              initialValue: _enableUdpPunch,
              onToggle: (v) async {
                await mainSetLocalBoolOption(kOptionEnableUdpPunch, v);
                final newValue =
                    mainGetLocalBoolOptionSync(kOptionEnableUdpPunch);
                setState(() {
                  _enableUdpPunch = newValue;
                });
              },
            ),
          if (_showAdvancedSettings && !_serverlessDirectOnly && !incomingOnly)
            SettingsTile.switchTile(
              title: Text(translate('Enable IPv6 P2P connection')),
              initialValue: _enableIpv6Punch,
              onToggle: (v) async {
                await mainSetLocalBoolOption(kOptionEnableIpv6Punch, v);
                final newValue =
                    mainGetLocalBoolOptionSync(kOptionEnableIpv6Punch);
                setState(() {
                  _enableIpv6Punch = newValue;
                });
              },
            ),
          SettingsTile(
              title: Text(translate('Language')),
              leading: Icon(Icons.translate),
              onPressed: (context) {
                showLanguageSettings(gFFI.dialogManager);
              }),
          SettingsTile(
            title: Text(translate(
                Theme.of(context).brightness == Brightness.light
                    ? 'Light Theme'
                    : 'Dark Theme')),
            leading: Icon(Theme.of(context).brightness == Brightness.light
                ? Icons.dark_mode
                : Icons.light_mode),
            onPressed: (context) {
              showThemeSettings(gFFI.dialogManager);
            },
          ),
          if (_showAdvancedSettings && !bind.isDisableAccount())
            SettingsTile.switchTile(
              title: Text(translate('note-at-conn-end-tip')),
              initialValue: _allowAskForNoteAtEndOfConnection,
              onToggle: (v) async {
                if (v && !gFFI.userModel.isLogin) {
                  final res = await loginDialog();
                  if (res != true) return;
                }
                await mainSetLocalBoolOption(
                    kOptionAllowAskForNoteAtEndOfConnection, v);
                final newValue = mainGetLocalBoolOptionSync(
                    kOptionAllowAskForNoteAtEndOfConnection);
                setState(() {
                  _allowAskForNoteAtEndOfConnection = newValue;
                });
              },
            ),
          if (_showAdvancedSettings && !incomingOnly)
            SettingsTile.switchTile(
              title:
                  Text(translate('keep-awake-during-outgoing-sessions-label')),
              initialValue: _preventSleepWhileConnected,
              onToggle: (v) async {
                await mainSetLocalBoolOption(
                    kOptionKeepAwakeDuringOutgoingSessions, v);
                setState(() {
                  _preventSleepWhileConnected = v;
                });
              },
            ),
        ]),
        SettingsSection(
          title: Text(translate('More')),
          tiles: [
            SettingsTile.navigation(
              leading: const Icon(Icons.tune_rounded),
              title: Text(translate('Advanced settings')),
              trailing: Icon(
                _showAdvancedSettings
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              onPressed: (_) => setState(
                () => _showAdvancedSettings = !_showAdvancedSettings,
              ),
            ),
          ],
        ),
        if (_showAdvancedSettings && isAndroid)
          SettingsSection(title: Text(translate('Hardware Codec')), tiles: [
            SettingsTile.switchTile(
              title: Text(translate('Enable hardware codec')),
              initialValue: _enableHardwareCodec,
              onToggle: isOptionFixed(kOptionEnableHwcodec)
                  ? null
                  : (v) async {
                      await mainSetBoolOption(kOptionEnableHwcodec, v);
                      final newValue =
                          await mainGetBoolOption(kOptionEnableHwcodec);
                      setState(() {
                        _enableHardwareCodec = newValue;
                      });
                    },
            ),
          ]),
        if (_showAdvancedSettings && isAndroid)
          SettingsSection(
            title: Text(translate("Recording")),
            tiles: [
              if (!outgoingOnly)
                SettingsTile.switchTile(
                  title:
                      Text(translate('Automatically record incoming sessions')),
                  initialValue: _autoRecordIncomingSession,
                  onToggle: isOptionFixed(kOptionAllowAutoRecordIncoming)
                      ? null
                      : (v) async {
                          await bind.mainSetOption(
                              key: kOptionAllowAutoRecordIncoming,
                              value: bool2option(
                                  kOptionAllowAutoRecordIncoming, v));
                          final newValue = option2bool(
                              kOptionAllowAutoRecordIncoming,
                              await bind.mainGetOption(
                                  key: kOptionAllowAutoRecordIncoming));
                          setState(() {
                            _autoRecordIncomingSession = newValue;
                          });
                        },
                ),
              if (!incomingOnly)
                SettingsTile.switchTile(
                  title:
                      Text(translate('Automatically record outgoing sessions')),
                  initialValue: _autoRecordOutgoingSession,
                  onToggle: isOptionFixed(kOptionAllowAutoRecordOutgoing)
                      ? null
                      : (v) async {
                          await bind.mainSetLocalOption(
                              key: kOptionAllowAutoRecordOutgoing,
                              value: bool2option(
                                  kOptionAllowAutoRecordOutgoing, v));
                          final newValue = option2bool(
                              kOptionAllowAutoRecordOutgoing,
                              bind.mainGetLocalOption(
                                  key: kOptionAllowAutoRecordOutgoing));
                          setState(() {
                            _autoRecordOutgoingSession = newValue;
                          });
                        },
                ),
              SettingsTile(
                title: Text(translate("Directory")),
                description: Text(bind.mainVideoSaveDirectory(root: false)),
              ),
            ],
          ),
        if (_showAdvancedSettings &&
            isAndroid &&
            !disabledSettings &&
            !outgoingOnly &&
            !hideSecuritySettings)
          SettingsSection(title: Text('2FA'), tiles: tfaTiles),
        if (_showAdvancedSettings &&
            isAndroid &&
            !disabledSettings &&
            !outgoingOnly &&
            !hideSecuritySettings)
          SettingsSection(
            title: Text(translate("Share screen")),
            tiles: shareScreenTiles,
          ),
        if (_showAdvancedSettings && !bind.isIncomingOnly())
          defaultDisplaySection(),
        if (_showAdvancedSettings &&
            isAndroid &&
            !disabledSettings &&
            !outgoingOnly &&
            !hideSecuritySettings)
          SettingsSection(
            title: Text(translate("Enhancements")),
            tiles: enhancementsTiles,
          ),
        SettingsSection(
          title: Text(translate("About")),
          tiles: [
            SettingsTile(
                onPressed: (context) async {
                  await launchUrl(Uri.parse(url));
                },
                title: Text(translate("Version: ") + version),
                value: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('dicad.cn',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                      )),
                ),
                leading: Icon(Icons.info)),
            SettingsTile(
                title: Text(translate("Build Date")),
                value: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(_buildDate),
                ),
                leading: Icon(Icons.query_builder)),
            if (isAndroid)
              SettingsTile(
                  onPressed: (context) => onCopyFingerprint(_fingerprint),
                  title: Text(translate("Fingerprint")),
                  value: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(_fingerprint),
                  ),
                  leading: Icon(Icons.fingerprint)),
            SettingsTile(
              title: Text(translate("Privacy Statement")),
              onPressed: (context) =>
                  launchUrlString('https://dicad.cn/privacy.html'),
              leading: Icon(Icons.privacy_tip),
            )
          ],
        ),
      ],
    );
    return settings;
  }

  Map<String, dynamic> _localProfile() {
    try {
      final raw = bind.mainGetLocalOption(key: 'user_info');
      if (raw.isNotEmpty) {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Widget _localProfileAvatar(double size, {String? avatar}) {
    final value = avatar ?? (_localProfile()['avatar'] ?? '').toString();
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.58,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: buildAvatarWidget(
              avatar: value,
              size: size,
              borderRadius: 8,
              fallback: fallback,
            ) ??
            fallback,
      ),
    );
  }

  Future<void> _editLocalProfile() async {
    final profile = _localProfile();
    final nameController = TextEditingController(
      text: (profile['display_name'] ?? profile['name'] ?? '').toString(),
    );
    var avatar = (profile['avatar'] ?? '').toString();
    String avatarMime = 'image/png';
    Uint8List? selectedBytes;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(translate('Local profile')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 76,
                height: 76,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: selectedBytes == null
                      ? _localProfileAvatar(76, avatar: avatar)
                      : Image.memory(selectedBytes!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                    withData: true,
                  );
                  final file = result?.files.single;
                  final bytes = file?.bytes;
                  if (bytes == null) return;
                  if (bytes.length > 512 * 1024) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text(
                            translate(
                              'Avatar image must be smaller than 512 KB',
                            ),
                          ),
                        ),
                      );
                    }
                    return;
                  }
                  final extension = file?.extension?.toLowerCase();
                  avatarMime = extension == 'jpg' || extension == 'jpeg'
                      ? 'image/jpeg'
                      : extension == 'webp'
                          ? 'image/webp'
                          : 'image/png';
                  setDialogState(() => selectedBytes = bytes);
                },
                icon: const Icon(Icons.photo_outlined),
                label: Text(translate('Choose image')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                maxLength: 32,
                decoration: InputDecoration(
                  labelText: translate('Display name'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(translate('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(translate('Save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true) {
      nameController.dispose();
      return;
    }
    if (selectedBytes != null) {
      avatar = 'data:$avatarMime;base64,${base64Encode(selectedBytes!)}';
    }
    profile['display_name'] = nameController.text.trim();
    profile['avatar'] = avatar;
    await bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(profile));
    gFFI.chatModel.refreshLocalIdentity(notify: true);
    nameController.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _requestDirectChatNotificationPermissionOnce() async {
    if (!isAndroid || androidVersion < 33) return;
    if (await AndroidPermissionManager.check(kAndroid13Notification)) return;
    const promptedKey = 'direct-chat-notification-permission-prompted-v1';
    if (bind.mainGetLocalOption(key: promptedKey) == 'Y') return;
    await bind.mainSetLocalOption(key: promptedKey, value: 'Y');
    await AndroidPermissionManager.request(kAndroid13Notification);
  }

  Future<void> _showContactMessagePermissions() async {
    final access = DirectChatAccessController.instance..load();
    final policies = <String, String>{...access.peerPolicies};

    final peersById = <String, Peer>{};
    for (final peer in <Peer>[
      ...gFFI.recentPeersModel.peers,
      ...gFFI.favoritePeersModel.peers,
      ...gFFI.abModel.peersModel.peers,
      ...gFFI.groupModel.peersModel.peers,
    ]) {
      peersById[peer.id] = peer;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          translate('Contact message permissions'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: translate('Close'),
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: peersById.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              translate(
                                'A contact will appear here after the first direct connection.',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: peersById.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 72,
                          ),
                          itemBuilder: (context, index) {
                            final peer = peersById.values.elementAt(index);
                            final name = peer.alias.trim().isNotEmpty
                                ? peer.alias.trim()
                                : peer.displayName.trim().isNotEmpty
                                    ? peer.displayName.trim()
                                    : peer.hostname.trim().isNotEmpty
                                        ? peer.hostname.trim()
                                        : peer.username.trim().isNotEmpty
                                            ? peer.username.trim()
                                            : peer.id;
                            final policy = policies[peer.id] ?? 'ask';
                            final policyLabel = policy == 'allow'
                                ? 'Allow'
                                : policy == 'deny'
                                    ? 'Reject'
                                    : 'Ask every time';
                            final avatarFallback = Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: str2color(name),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                name.characters.first,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                            return ListTile(
                              leading: buildAvatarWidget(
                                    avatar: peer.avatar,
                                    size: 40,
                                    borderRadius: 8,
                                    fallback: avatarFallback,
                                  ) ??
                                  avatarFallback,
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${peer.id}  ·  ${translate(policyLabel)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: translate('Message permission'),
                                initialValue: policy,
                                onSelected: (value) async {
                                  setSheetState(
                                    () => policies[peer.id] = value,
                                  );
                                  await access.setPeerPolicy(peer.id, value);
                                },
                                itemBuilder: (_) => <PopupMenuEntry<String>>[
                                  PopupMenuItem(
                                    value: 'allow',
                                    child: Text(translate('Allow')),
                                  ),
                                  PopupMenuItem(
                                    value: 'ask',
                                    child: Text(translate('Ask every time')),
                                  ),
                                  PopupMenuItem(
                                    value: 'deny',
                                    child: Text(translate('Reject')),
                                  ),
                                ],
                                icon: const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> canStartOnBoot() async {
    // start on boot depends on ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS and SYSTEM_ALERT_WINDOW
    if (_hasIgnoreBattery && !_ignoreBatteryOpt) {
      return false;
    }
    if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
      return false;
    }
    return true;
  }

  defaultDisplaySection() {
    return SettingsSection(
      title: Text(translate("Display Settings")),
      tiles: [
        SettingsTile(
            title: Text(translate('Display Settings')),
            leading: Icon(Icons.desktop_windows_outlined),
            trailing: Icon(Icons.arrow_forward_ios),
            onPressed: (context) {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return _DisplayPage();
              }));
            })
      ],
    );
  }
}

void showLanguageSettings(OverlayDialogManager dialogManager) async {
  try {
    final langs = (json.decode(await bind.mainGetLangs()) as List<dynamic>)
        .where((entry) => entry[0] == 'en' || entry[0] == 'zh-cn')
        .toList();
    var lang = bind.mainGetLocalOption(key: kCommConfKeyLang);
    if (!langs.any((entry) => entry[0] == lang)) {
      lang = localeName.toLowerCase().startsWith('zh') ? 'zh-cn' : 'en';
    }
    dialogManager.show((setState, close, context) {
      setLang(v) async {
        if (lang != v) {
          setState(() {
            lang = v;
          });
          await bind.mainSetLocalOption(key: kCommConfKeyLang, value: v);
          bind.mainChangeLanguage(lang: v);
          HomePage.homeKey.currentState?.refreshPages();
          Future.delayed(Duration(milliseconds: 200), close);
        }
      }

      final isOptFixed = isOptionFixed(kCommConfKeyLang);
      return CustomAlertDialog(
        content: Column(
          children: langs.map((e) {
            final key = e[0] as String;
            final name = e[1] as String;
            return getRadio(
              Text(name),
              key,
              lang,
              isOptFixed ? null : setLang,
            );
          }).toList(),
        ),
      );
    }, backDismiss: true, clickMaskDismiss: true);
  } catch (e) {
    //
  }
}

void showThemeSettings(OverlayDialogManager dialogManager) async {
  var themeMode = MyTheme.getThemeModePreference();

  dialogManager.show((setState, close, context) {
    setTheme(v) {
      if (themeMode != v) {
        setState(() {
          themeMode = v;
        });
        MyTheme.changeDarkMode(themeMode);
        Future.delayed(Duration(milliseconds: 200), close);
      }
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    return CustomAlertDialog(
      content: Column(children: [
        getRadio(Text(translate('Light')), ThemeMode.light, themeMode,
            isOptFixed ? null : setTheme),
        getRadio(Text(translate('Dark')), ThemeMode.dark, themeMode,
            isOptFixed ? null : setTheme),
        getRadio(Text(translate('Follow System')), ThemeMode.system, themeMode,
            isOptFixed ? null : setTheme)
      ]),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}

void showAbout(OverlayDialogManager dialogManager) {
  dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('About LUODA')),
      content: Wrap(direction: Axis.vertical, spacing: 12, children: [
        Text('${translate('Version')}: $version'),
        InkWell(
            onTap: () async {
              const url = 'https://dicad.cn/';
              await launchUrl(Uri.parse(url));
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('dicad.cn',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  )),
            )),
      ]),
      actions: [],
    );
  }, clickMaskDismiss: true, backDismiss: true);
}

class ScanButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.qr_code_scanner),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (BuildContext context) => ScanPage(),
          ),
        );
      },
    );
  }
}

class _DisplayPage extends StatefulWidget {
  const _DisplayPage();

  @override
  State<_DisplayPage> createState() => __DisplayPageState();
}

class __DisplayPageState extends State<_DisplayPage> {
  @override
  Widget build(BuildContext context) {
    final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
    final h264 = codecsJson['h264'] ?? false;
    final h265 = codecsJson['h265'] ?? false;
    var codecList = [
      _RadioEntry('Auto', 'auto'),
      _RadioEntry('VP8', 'vp8'),
      _RadioEntry('VP9', 'vp9'),
      _RadioEntry('AV1', 'av1'),
      if (h264) _RadioEntry('H264', 'h264'),
      if (h265) _RadioEntry('H265', 'h265')
    ];
    RxBool showCustomImageQuality = false.obs;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios)),
        title: Text(translate('Display Settings')),
        centerTitle: true,
      ),
      body: SettingsList(sections: [
        SettingsSection(
          tiles: [
            _getPopupDialogRadioEntry(
              title: 'Default View Style',
              list: [
                _RadioEntry('Scale original', kRemoteViewStyleOriginal),
                _RadioEntry('Scale adaptive', kRemoteViewStyleAdaptive)
              ],
              getter: () =>
                  bind.mainGetUserDefaultOption(key: kOptionViewStyle),
              asyncSetter: isOptionFixed(kOptionViewStyle)
                  ? null
                  : (value) async {
                      await bind.mainSetUserDefaultOption(
                          key: kOptionViewStyle, value: value);
                    },
            ),
            _getPopupDialogRadioEntry(
              title: 'Default Image Quality',
              list: [
                _RadioEntry('Good image quality', kRemoteImageQualityBest),
                _RadioEntry('Balanced', kRemoteImageQualityBalanced),
                _RadioEntry('Optimize reaction time', kRemoteImageQualityLow),
                _RadioEntry('Custom', kRemoteImageQualityCustom),
              ],
              getter: () {
                final v =
                    bind.mainGetUserDefaultOption(key: kOptionImageQuality);
                showCustomImageQuality.value = v == kRemoteImageQualityCustom;
                return v;
              },
              asyncSetter: isOptionFixed(kOptionImageQuality)
                  ? null
                  : (value) async {
                      await bind.mainSetUserDefaultOption(
                          key: kOptionImageQuality, value: value);
                      showCustomImageQuality.value =
                          value == kRemoteImageQualityCustom;
                    },
              tail: customImageQualitySetting(),
              showTail: showCustomImageQuality,
              notCloseValue: kRemoteImageQualityCustom,
            ),
            _getPopupDialogRadioEntry(
              title: 'Default Codec',
              list: codecList,
              getter: () =>
                  bind.mainGetUserDefaultOption(key: kOptionCodecPreference),
              asyncSetter: isOptionFixed(kOptionCodecPreference)
                  ? null
                  : (value) async {
                      await bind.mainSetUserDefaultOption(
                          key: kOptionCodecPreference, value: value);
                    },
            ),
          ],
        ),
        SettingsSection(
          title: Text(translate('Other Default Options')),
          tiles:
              otherDefaultSettings().map((e) => otherRow(e.$1, e.$2)).toList(),
        ),
      ]),
    );
  }

  SettingsTile otherRow(String label, String key) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    final isOptFixed = isOptionFixed(key);
    return SettingsTile.switchTile(
      initialValue: value,
      title: Text(translate(label)),
      onToggle: isOptFixed
          ? null
          : (b) async {
              await bind.mainSetUserDefaultOption(
                  key: key, value: b ? 'Y' : defaultOptionNo);
              setState(() {});
            },
    );
  }
}

class _ManageTrustedDevices extends StatefulWidget {
  const _ManageTrustedDevices();

  @override
  State<_ManageTrustedDevices> createState() => __ManageTrustedDevicesState();
}

class __ManageTrustedDevicesState extends State<_ManageTrustedDevices> {
  RxList<TrustedDevice> trustedDevices = RxList.empty(growable: true);
  RxList<Uint8List> selectedDevices = RxList.empty();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('Manage trusted devices')),
        centerTitle: true,
        actions: [
          Obx(() => IconButton(
              icon: Icon(Icons.delete, color: Colors.white),
              onPressed: selectedDevices.isEmpty
                  ? null
                  : () {
                      confrimDeleteTrustedDevicesDialog(
                          trustedDevices, selectedDevices);
                    }))
        ],
      ),
      body: FutureBuilder(
          future: TrustedDevice.get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('${translate('Error')}: ${snapshot.error}'),
              );
            }
            final devices = snapshot.data as List<TrustedDevice>;
            trustedDevices = devices.obs;
            return trustedDevicesTable(trustedDevices, selectedDevices);
          }),
    );
  }
}

class _RadioEntry {
  final String label;
  final String value;
  _RadioEntry(this.label, this.value);
}

typedef _RadioEntryGetter = String Function();
typedef _RadioEntrySetter = Future<void> Function(String);

SettingsTile _getPopupDialogRadioEntry({
  required String title,
  required List<_RadioEntry> list,
  required _RadioEntryGetter getter,
  required _RadioEntrySetter? asyncSetter,
  Widget? tail,
  RxBool? showTail,
  String? notCloseValue,
}) {
  RxString groupValue = ''.obs;
  RxString valueText = ''.obs;

  init() {
    groupValue.value = getter();
    final e = list.firstWhereOrNull((e) => e.value == groupValue.value);
    if (e != null) {
      valueText.value = e.label;
    }
  }

  init();

  void showDialog() async {
    gFFI.dialogManager.show((setState, close, context) {
      final onChanged = asyncSetter == null
          ? null
          : (String? value) async {
              if (value == null) return;
              await asyncSetter(value);
              init();
              if (value != notCloseValue) {
                close();
              }
            };

      return CustomAlertDialog(
          content: Obx(
        () => Column(children: [
          ...list
              .map((e) => getRadio(Text(translate(e.label)), e.value,
                  groupValue.value, onChanged))
              .toList(),
          Offstage(
            offstage:
                !(tail != null && showTail != null && showTail.value == true),
            child: tail,
          ),
        ]),
      ));
    }, backDismiss: true, clickMaskDismiss: true);
  }

  return SettingsTile(
    title: Text(translate(title)),
    onPressed: asyncSetter == null ? null : (context) => showDialog(),
    value: Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Obx(() => Text(translate(valueText.value))),
    ),
  );
}
