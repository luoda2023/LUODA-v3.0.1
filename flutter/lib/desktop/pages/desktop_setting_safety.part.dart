part of 'desktop_setting_page.dart';

enum _AccessMode {
  custom,
  full,
  view,
}
class _Safety extends StatefulWidget {
  const _Safety({Key? key}) : super(key: key);

  @override
  State<_Safety> createState() => _SafetyState();
}
class _SafetyState extends State<_Safety> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool locked = bind.mainIsInstalled();
  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
        controller: scrollController,
        child: Column(
          children: [
            _lock(locked, 'Unlock Security Settings', () {
              locked = false;
              setState(() => {});
            }),
            preventMouseKeyBuilder(
              block: locked,
              child: Column(children: [
                permissions(context),
                password(context),
                _Card(
                  title: '2FA',
                  description: 'two_factor_card_tip',
                  showIcon: true,
                  children: [tfa()],
                ),
                if (!isChangeIdDisabled())
                  _Card(
                    title: translate('ID'),
                    description: 'device_id_card_tip',
                    showIcon: true,
                    children: [changeId()],
                  ),
                more(context),
              ]),
            ),
          ],
        )).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget tfa() {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      RxBool has2fa = bind.mainHasValid2FaSync().obs;
      RxBool hasBot = bind.mainHasValidBotSync().obs;
      update() async {
        has2fa.value = bind.mainHasValid2FaSync();
        setState(() {});
      }

      onChanged(bool? checked) async {
        if (checked == false) {
          CommonConfirmDialog(
              gFFI.dialogManager, translate('cancel-2fa-confirm-tip'), () {
            change2fa(callback: update);
          });
        } else {
          change2fa(callback: update);
        }
      }

      final tfa = GestureDetector(
        child: InkWell(
          child: Obx(() => Row(
                children: [
                  Expanded(
                      child: Text(
                    translate('enable-2fa-title'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled)),
                  )),
                  Switch(
                    value: has2fa.value,
                    onChanged: enabled ? (value) => onChanged(value) : null,
                  ),
                ],
              )),
        ),
        onTap: enabled ? () => onChanged(!has2fa.value) : null,
      ).marginOnly(left: _kCheckBoxLeftMargin);
      if (!has2fa.value) {
        return tfa;
      }
      updateBot() async {
        hasBot.value = bind.mainHasValidBotSync();
        setState(() {});
      }

      onChangedBot(bool? checked) async {
        if (checked == false) {
          CommonConfirmDialog(
              gFFI.dialogManager, translate('cancel-bot-confirm-tip'), () {
            changeBot(callback: updateBot);
          });
        } else {
          changeBot(callback: updateBot);
        }
      }

      final bot = GestureDetector(
        child: Tooltip(
          waitDuration: Duration(milliseconds: 300),
          message: translate("enable-bot-tip"),
          child: InkWell(
              child: Obx(() => Row(
                    children: [
                      Checkbox(
                              value: hasBot.value,
                              onChanged: enabled ? onChangedBot : null)
                          .marginOnly(right: 5),
                      Expanded(
                          child: Text(
                        translate('Telegram bot'),
                        style: TextStyle(
                            color: disabledTextColor(context, enabled)),
                      ))
                    ],
                  ))),
        ),
        onTap: () {
          onChangedBot(!hasBot.value);
        },
      ).marginOnly(left: _kCheckBoxLeftMargin + 30);

      final trust = Row(
        children: [
          Flexible(
            child: Tooltip(
              waitDuration: Duration(milliseconds: 300),
              message: translate("enable-trusted-devices-tip"),
              child: _OptionCheckBox(context, "Enable trusted devices",
                  kOptionEnableTrustedDevices,
                  enabled: !locked, update: (v) {
                setState(() {});
              }),
            ),
          ),
          if (mainGetBoolOptionSync(kOptionEnableTrustedDevices))
            ElevatedButton(
                onPressed: locked
                    ? null
                    : () {
                        manageTrustedDeviceDialog();
                      },
                child: Text(translate('Manage trusted devices')))
        ],
      ).marginOnly(left: 30);

      return Column(
        children: [tfa, bot, trust],
      );
    }

    return tmpWrapper();
  }

  Widget changeId() {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: ((context, model, child) {
          return _Button('Change ID', changeIdDialog,
              enabled: !locked && model.connectStatus > 0);
        })));
  }

  Widget permissions(context) {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      String accessMode = bind.mainGetOptionSync(key: kOptionAccessMode);
      _AccessMode mode;
      if (accessMode == 'full') {
        mode = _AccessMode.full;
      } else if (accessMode == 'view') {
        mode = _AccessMode.view;
      } else {
        mode = _AccessMode.custom;
      }
      String initialKey;
      bool? fakeValue;
      switch (mode) {
        case _AccessMode.custom:
          initialKey = '';
          fakeValue = null;
          break;
        case _AccessMode.full:
          initialKey = 'full';
          fakeValue = true;
          break;
        case _AccessMode.view:
          initialKey = 'view';
          fakeValue = false;
          break;
      }

      return _Card(
        title: translate('Permissions'),
        description: 'permissions_card_tip',
        showIcon: true,
        title_suffix: [
          SizedBox(
            width: 220,
            child: ComboBox(
              keys: [defaultOptionAccessMode, 'full', 'view'],
              values: [
                translate('Custom'),
                translate('Full Access'),
                translate('Screen Share'),
              ],
              enabled: enabled && !isOptionFixed(kOptionAccessMode),
              initialKey: initialKey,
              onChanged: (mode) async {
                await bind.mainSetOption(key: kOptionAccessMode, value: mode);
                setState(() {});
              },
            ),
          ),
        ],
        children: [
          _ResponsiveSettingGrid(
            children: [
              _OptionCheckBox(
                context,
                'Enable keyboard/mouse',
                kOptionEnableKeyboard,
                enabled: enabled,
                fakeValue: fakeValue,
              ),
              if (isWindows)
                _OptionCheckBox(
                  context,
                  'Enable remote printer',
                  kOptionEnableRemotePrinter,
                  enabled: enabled,
                  fakeValue: fakeValue,
                ),
              _OptionCheckBox(
                context,
                'Enable clipboard',
                kOptionEnableClipboard,
                enabled: enabled,
                fakeValue: fakeValue,
              ),
              _OptionCheckBox(
                context,
                'Enable file transfer',
                kOptionEnableFileTransfer,
                enabled: enabled,
                fakeValue: fakeValue,
              ),
              _OptionCheckBox(
                context,
                'Enable audio',
                kOptionEnableAudio,
                enabled: enabled,
                fakeValue: fakeValue,
              ),
              _OptionCheckBox(
                context,
                'Enable camera',
                kOptionEnableCamera,
                enabled: enabled,
                fakeValue: fakeValue,
              ),
              _OptionCheckBox(
                context,
                'Enable terminal',
                kOptionEnableTerminal,
                enabled: enabled,
                fakeValue: fakeValue,
              ),
              _OptionCheckBox(
                context,
                'Enable TCP tunneling',
                kOptionEnableTunnel,
                enabled: enabled,
                fakeValue: fakeValue,
              ),
              _OptionCheckBox(
                context,
                'Enable remote restart',
                kOptionEnableRemoteRestart,
                enabled: enabled,
                fakeValue: fakeValue,
              ),
              _OptionCheckBox(
                context,
                'Enable recording session',
                kOptionEnableRecordSession,
                enabled: enabled,
                fakeValue: fakeValue,
              ),
              if (isWindows)
                _OptionCheckBox(
                  context,
                  'Enable blocking user input',
                  kOptionEnableBlockInput,
                  enabled: enabled,
                  fakeValue: fakeValue,
                ),
              _OptionCheckBox(
                context,
                'Enable remote configuration modification',
                kOptionAllowRemoteConfigModification,
                enabled: enabled,
                fakeValue: fakeValue,
              ),
            ],
          ),
        ],
      );
    }

    return tmpWrapper();
  }

  Widget password(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: ((context, model, child) {
          List<String> passwordKeys = [
            kUseTemporaryPassword,
            kUsePermanentPassword,
            kUseBothPasswords,
          ];
          List<String> passwordValues = [
            translate('Use one-time password'),
            translate('Use permanent password'),
            translate('Use both passwords'),
          ];
          bool tmpEnabled = model.verificationMethod != kUsePermanentPassword;
          bool permEnabled = model.verificationMethod != kUseTemporaryPassword;
          String currentValue =
              passwordValues[passwordKeys.indexOf(model.verificationMethod)];
          List<Widget> radios = passwordValues
              .map(
                (value) => _Radio<String>(
                  context,
                  value: value,
                  groupValue: currentValue,
                  label: value,
                  onChanged: locked
                      ? null
                      : ((value) async {
                          callback() async {
                            await model.setVerificationMethod(
                              passwordKeys[passwordValues.indexOf(value)],
                            );
                            await model.updatePasswordModel();
                          }

                          if (value ==
                                  passwordValues[passwordKeys.indexOf(
                                    kUsePermanentPassword,
                                  )] &&
                              (await bind.mainGetCommon(
                                    key: "permanent-password-set",
                                  )) !=
                                  "true") {
                            if (isChangePermanentPasswordDisabled()) {
                              await callback();
                              return;
                            }
                            setPasswordDialog(notEmptyCallback: callback);
                          } else {
                            await callback();
                          }
                        }),
                ),
              )
              .toList();

          var onChanged = tmpEnabled && !locked
              ? (value) {
                  if (value != null) {
                    () async {
                      await model.setTemporaryPasswordLength(value.toString());
                      await model.updatePasswordModel();
                    }();
                  }
                }
              : null;
          List<Widget> lengthRadios = ['4', '6', '8', '10']
              .map(
                (value) => GestureDetector(
                  child: Row(
                    children: [
                      Radio(
                        value: value,
                        groupValue: model.temporaryPasswordLength,
                        onChanged: onChanged,
                      ),
                      Text(
                        value,
                        style: TextStyle(
                          color: disabledTextColor(context, onChanged != null),
                        ),
                      ),
                    ],
                  ).paddingOnly(right: 10),
                  onTap: () => onChanged?.call(value),
                ),
              )
              .toList();

          final isOptFixedNumOTP = isOptionFixed(
            kOptionAllowNumericOneTimePassword,
          );
          final isNumOPTChangable = !isOptFixedNumOTP && tmpEnabled && !locked;
          final numericOneTimePassword = GestureDetector(
            child: InkWell(
              child: Row(
                children: [
                  Checkbox(
                    value: model.allowNumericOneTimePassword,
                    onChanged: isNumOPTChangable
                        ? (bool? v) {
                            model.switchAllowNumericOneTimePassword();
                          }
                        : null,
                  ).marginOnly(right: 5),
                  Expanded(
                    child: Text(
                      translate('Numeric one-time password'),
                      style: TextStyle(
                        color: disabledTextColor(context, isNumOPTChangable),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            onTap: isNumOPTChangable
                ? () => model.switchAllowNumericOneTimePassword()
                : null,
          ).marginOnly(left: _kContentHSubMargin - 5);

          final modeKeys = <String>[
            'password',
            'click',
            defaultOptionApproveMode,
          ];
          final modeValues = [
            translate('Accept sessions via password'),
            translate('Accept sessions via click'),
            translate('Accept sessions via both'),
          ];
          var modeInitialKey = model.approveMode;
          if (!modeKeys.contains(modeInitialKey)) {
            modeInitialKey = defaultOptionApproveMode;
          }
          final usePassword = model.approveMode != 'click';

          final isApproveModeFixed = isOptionFixed(kOptionApproveMode);
          return _Card(
            title: translate('Password'),
            description: 'password_card_tip',
            showIcon: true,
            title_suffix: [
              SizedBox(
                width: 260,
                child: ComboBox(
                  enabled: !locked && !isApproveModeFixed,
                  keys: modeKeys,
                  values: modeValues,
                  initialKey: modeInitialKey,
                  onChanged: (key) => model.setApproveMode(key),
                ),
              ),
            ],
            children: [
              if (usePassword) radios[0],
              if (usePassword)
                _SubLabeledWidget(
                  context,
                  'One-time password length',
                  Row(children: [...lengthRadios]),
                  enabled: tmpEnabled && !locked,
                ),
              if (usePassword) numericOneTimePassword,
              if (usePassword) radios[1],
              if (usePassword && !isChangePermanentPasswordDisabled())
                _SubButton(
                  'Set permanent password',
                  setPasswordDialog,
                  permEnabled && !locked,
                ),
              // if (usePassword)
              //   hide_cm(!locked).marginOnly(left: _kContentHSubMargin - 6),
              if (usePassword) radios[2],
            ],
          );
        }),
      ),
    );
  }

  Widget more(BuildContext context) {
    bool enabled = !locked;
    return _Card(title: translate('Security'), children: [
      shareRdp(context, enabled),
      _OptionCheckBox(context, 'Deny LAN discovery', 'enable-lan-discovery',
          reverse: true, enabled: enabled),
      ...directIp(context),
      whitelist(),
      ...autoDisconnect(context),
      _OptionCheckBox(context, 'keep-awake-during-incoming-sessions-label',
          kOptionKeepAwakeDuringIncomingSessions,
          reverse: false, enabled: enabled),
      if (bind.mainIsInstalled())
        _OptionCheckBox(context, 'allow-only-conn-window-open-tip',
            'allow-only-conn-window-open',
            reverse: false, enabled: enabled),
      if (bind.mainIsInstalled() && !isUnlockPinDisabled()) unlockPin()
    ]);
  }

  shareRdp(BuildContext context, bool enabled) {
    onChanged(bool b) async {
      await bind.mainSetShareRdp(enable: b);
      setState(() {});
    }

    bool value = bind.mainIsShareRdp();
    return Offstage(
      offstage: !(isWindows && bind.mainIsInstalled()),
      child: GestureDetector(
          child: Row(
            children: [
              Checkbox(
                      value: value,
                      onChanged: enabled ? (_) => onChanged(!value) : null)
                  .marginOnly(right: 5),
              Expanded(
                child: Text(translate('Enable RDP session sharing'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled))),
              )
            ],
          ).marginOnly(left: _kCheckBoxLeftMargin),
          onTap: enabled ? () => onChanged(!value) : null),
    );
  }

  List<Widget> directIp(BuildContext context) {
    TextEditingController controller = TextEditingController();
    update(bool v) => setState(() {});
    RxBool applyEnabled = false.obs;
    return [
      _OptionCheckBox(context, 'Enable direct IP access', kOptionDirectServer,
          update: update, enabled: !locked),
      () {
        // Simple temp wrapper for PR check
        tmpWrapper() {
          bool enabled = option2bool(kOptionDirectServer,
              bind.mainGetOptionSync(key: kOptionDirectServer));
          if (!enabled) applyEnabled.value = false;
          controller.text =
              bind.mainGetOptionSync(key: kOptionDirectAccessPort);
          final isOptFixed = isOptionFixed(kOptionDirectAccessPort);
          return Offstage(
            offstage: !enabled,
            child: _SubLabeledWidget(
              context,
              'Port',
              Row(children: [
                SizedBox(
                  width: 95,
                  child: TextField(
                    controller: controller,
                    enabled: enabled && !locked && !isOptFixed,
                    onChanged: (_) => applyEnabled.value = true,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(
                          r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$')),
                    ],
                    decoration: const InputDecoration(
                      hintText: '21118',
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    ),
                  ).workaroundFreezeLinuxMint().marginOnly(right: 15),
                ),
                Obx(() => ElevatedButton(
                      onPressed: applyEnabled.value &&
                              enabled &&
                              !locked &&
                              !isOptFixed
                          ? () async {
                              applyEnabled.value = false;
                              await bind.mainSetOption(
                                  key: kOptionDirectAccessPort,
                                  value: controller.text);
                            }
                          : null,
                      child: Text(
                        translate('Apply'),
                      ),
                    ))
              ]),
              enabled: enabled && !locked && !isOptFixed,
            ),
          );
        }

        return tmpWrapper();
      }(),
    ];
  }

  Widget whitelist() {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      RxBool hasWhitelist = whitelistNotEmpty().obs;
      update() async {
        hasWhitelist.value = whitelistNotEmpty();
      }

      onChanged(bool? checked) async {
        changeWhiteList(callback: update);
      }

      final isOptFixed = isOptionFixed(kOptionWhitelist);
      return GestureDetector(
        child: Tooltip(
          message: translate('whitelist_tip'),
          child: Obx(() => Row(
                children: [
                  Checkbox(
                          value: hasWhitelist.value,
                          onChanged: enabled && !isOptFixed ? onChanged : null)
                      .marginOnly(right: 5),
                  Offstage(
                    offstage: !hasWhitelist.value,
                    child: MouseRegion(
                      child: const Icon(Icons.warning_amber_rounded,
                              color: Color.fromARGB(255, 255, 204, 0))
                          .marginOnly(right: 5),
                      cursor: SystemMouseCursors.click,
                    ),
                  ),
                  Expanded(
                      child: Text(
                    translate('Use IP Whitelisting'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled)),
                  ))
                ],
              )),
        ),
        onTap: enabled
            ? () {
                onChanged(!hasWhitelist.value);
              }
            : null,
      ).marginOnly(left: _kCheckBoxLeftMargin);
    }

    return tmpWrapper();
  }

  Widget hide_cm(bool enabled) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: (context, model, child) {
          final enableHideCm = model.approveMode == 'password' &&
              model.verificationMethod == kUsePermanentPassword;
          onHideCmChanged(bool? b) {
            if (b != null) {
              bind.mainSetOption(
                  key: 'allow-hide-cm', value: bool2option('allow-hide-cm', b));
            }
          }

          return Tooltip(
              message: enableHideCm ? "" : translate('hide_cm_tip'),
              child: GestureDetector(
                onTap:
                    enableHideCm ? () => onHideCmChanged(!model.hideCm) : null,
                child: Row(
                  children: [
                    Checkbox(
                            value: model.hideCm,
                            onChanged: enabled && enableHideCm
                                ? onHideCmChanged
                                : null)
                        .marginOnly(right: 5),
                    Expanded(
                      child: Text(
                        translate('Hide connection management window'),
                        style: TextStyle(
                            color: disabledTextColor(
                                context, enabled && enableHideCm)),
                      ),
                    ),
                  ],
                ),
              ));
        }));
  }

  List<Widget> autoDisconnect(BuildContext context) {
    TextEditingController controller = TextEditingController();
    update(bool v) => setState(() {});
    RxBool applyEnabled = false.obs;
    return [
      _OptionCheckBox(
          context, 'auto_disconnect_option_tip', kOptionAllowAutoDisconnect,
          update: update, enabled: !locked),
      () {
        bool enabled = option2bool(kOptionAllowAutoDisconnect,
            bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect));
        if (!enabled) applyEnabled.value = false;
        controller.text =
            bind.mainGetOptionSync(key: kOptionAutoDisconnectTimeout);
        final isOptFixed = isOptionFixed(kOptionAutoDisconnectTimeout);
        return Offstage(
          offstage: !enabled,
          child: _SubLabeledWidget(
            context,
            'Timeout in minutes',
            Row(children: [
              SizedBox(
                width: 95,
                child: TextField(
                  controller: controller,
                  enabled: enabled && !locked && !isOptFixed,
                  onChanged: (_) => applyEnabled.value = true,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(
                        r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$')),
                  ],
                  decoration: const InputDecoration(
                    hintText: '10',
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ).workaroundFreezeLinuxMint().marginOnly(right: 15),
              ),
              Obx(() => ElevatedButton(
                    onPressed:
                        applyEnabled.value && enabled && !locked && !isOptFixed
                            ? () async {
                                applyEnabled.value = false;
                                await bind.mainSetOption(
                                    key: kOptionAutoDisconnectTimeout,
                                    value: controller.text);
                              }
                            : null,
                    child: Text(
                      translate('Apply'),
                    ),
                  ))
            ]),
            enabled: enabled && !locked && !isOptFixed,
          ),
        );
      }(),
    ];
  }

  Widget unlockPin() {
    bool enabled = !locked;
    RxString unlockPin = bind.mainGetUnlockPin().obs;
    update() async {
      unlockPin.value = bind.mainGetUnlockPin();
    }

    onChanged(bool? checked) async {
      changeUnlockPinDialog(unlockPin.value, update);
    }

    final isOptFixed = isOptionFixed(kOptionWhitelist);
    return GestureDetector(
      child: Obx(() => Row(
            children: [
              Checkbox(
                      value: unlockPin.isNotEmpty,
                      onChanged: enabled && !isOptFixed ? onChanged : null)
                  .marginOnly(right: 5),
              Expanded(
                  child: Text(
                translate('Unlock with PIN'),
                style: TextStyle(color: disabledTextColor(context, enabled)),
              ))
            ],
          )),
      onTap: enabled
          ? () {
              onChanged(!unlockPin.isNotEmpty);
            }
          : null,
    ).marginOnly(left: _kCheckBoxLeftMargin);
  }
}
