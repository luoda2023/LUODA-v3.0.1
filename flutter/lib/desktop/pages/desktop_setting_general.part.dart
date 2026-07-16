part of 'desktop_setting_page.dart';

class _General extends StatefulWidget {
  const _General({Key? key}) : super(key: key);

  @override
  State<_General> createState() => _GeneralState();
}
class _GeneralState extends State<_General> {
  final RxBool serviceStop = isWeb
      ? RxBool(false)
      : (Get.isRegistered<RxBool>(tag: 'stop-service')
          ? Get.find<RxBool>(tag: 'stop-service')
          : Get.put<RxBool>(false.obs, tag: 'stop-service'));
  RxBool serviceBtnEnabled = true.obs;
  bool _showOtherSettings = false;

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        if (!isWeb) service(),
        theme(),
        language(),
        if (!isWeb) audio(context),
        if (!isWeb) record(context),
        _otherSettings(),
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget _otherSettings() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(
              left: _kCardLeftMargin,
              right: _kCardLeftMargin,
              top: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kCardFixedWidth),
              child: SizedBox(
                width: double.infinity,
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        _showOtherSettings = !_showOtherSettings;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 18,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 21,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              translate('Other'),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            _showOtherSettings
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_showOtherSettings) ...[
          if (!isWeb) hwcodec(),
          if (!isWeb) const WaylandCard(),
          other(),
        ],
      ],
    );
  }

  Widget theme() {
    final current = MyTheme.getThemeModePreference().toShortString();
    onChanged(String value) async {
      await MyTheme.changeDarkMode(MyTheme.themeModeFromString(value));
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    Widget option(String value, String label, IconData icon) {
      final selected = current == value;
      final theme = Theme.of(context);
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isOptFixed ? null : () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primary.withOpacity(
                      theme.brightness == Brightness.dark ? 0.16 : 0.06,
                    )
                  : Colors.transparent,
              border: Border.all(
                color:
                    selected ? theme.colorScheme.primary : theme.dividerColor,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Radio<String>(
                  value: value,
                  groupValue: current,
                  onChanged: isOptFixed
                      ? null
                      : (next) {
                          if (next != null) onChanged(next);
                        },
                ),
                Icon(icon, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    translate(label),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _Card(
      title: 'Theme',
      description: 'theme_card_tip',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final options = [
              option('light', 'Light', Icons.light_mode_outlined),
              option('dark', 'Dark', Icons.dark_mode_outlined),
              option('system', 'Follow System', Icons.desktop_windows_outlined),
            ];
            if (constraints.maxWidth < 650) {
              return Column(
                children: options
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: item,
                      ),
                    )
                    .toList(),
              );
            }
            return Row(
              children: [
                for (var i = 0; i < options.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: options[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget service() {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    final hideStopService =
        bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y';

    return Obx(() {
      if (hideStopService && !serviceStop.value) {
        return const Offstage();
      }

      return _Card(
        title: 'Service',
        description: 'service_card_tip',
        title_suffix: [
          ElevatedButton.icon(
            onPressed: serviceBtnEnabled.value
                ? () {
                    () async {
                      serviceBtnEnabled.value = false;
                      await start_service(serviceStop.value);
                      Future.delayed(const Duration(seconds: 1), () {
                        serviceBtnEnabled.value = true;
                      });
                    }();
                  }
                : null,
            icon: Icon(
              serviceStop.value
                  ? Icons.play_circle_outline_rounded
                  : Icons.stop_circle_outlined,
              size: 19,
            ),
            label: Text(translate(serviceStop.value ? 'Start' : 'Stop')),
          ),
        ],
        children: const [],
      );
    });
  }

  Widget other() {
    final showAutoUpdate = isWindows && bind.mainIsInstalled();
    final children = <Widget>[
      if (!isWeb && !bind.isIncomingOnly())
        _OptionCheckBox(context, 'Confirm before closing multiple tabs',
            kOptionEnableConfirmClosingTabs,
            isServer: false),
      _OptionCheckBox(context, 'Adaptive bitrate', kOptionEnableAbr),
      if (!isWeb) wallpaper(),
      if (!isWeb && !bind.isIncomingOnly()) ...[
        _OptionCheckBox(
          context,
          'Open connection in new tab',
          kOptionOpenNewConnInTabs,
          isServer: false,
        ),
        // though this is related to GUI, but opengl problem affects all users, so put in config rather than local
        if (isLinux)
          Tooltip(
            message: translate('software_render_tip'),
            child: _OptionCheckBox(
              context,
              "Always use software rendering",
              kOptionAllowAlwaysSoftwareRender,
            ),
          ),
        if (!isWeb)
          Tooltip(
            message: translate('texture_render_tip'),
            child: _OptionCheckBox(
              context,
              "Use texture rendering",
              kOptionTextureRender,
              optGetter: bind.mainGetUseTextureRender,
              optSetter: (k, v) async =>
                  await bind.mainSetLocalOption(key: k, value: v ? 'Y' : 'N'),
            ),
          ),
        if (isWindows)
          Tooltip(
            message: translate('d3d_render_tip'),
            child: _OptionCheckBox(
              context,
              "Use D3D rendering",
              kOptionD3DRender,
              isServer: false,
            ),
          ),
        if (!isWeb && !bind.isCustomClient())
          _OptionCheckBox(
            context,
            'Check for software update on startup',
            kOptionEnableCheckUpdate,
            isServer: false,
            enabled: false, // Disabled by LUODA
          ),
        if (showAutoUpdate)
          _OptionCheckBox(
            context,
            'Auto update',
            kOptionAllowAutoUpdate,
            isServer: true,
            enabled: false, // Disabled by LUODA
          ),
        if (isWindows && !bind.isOutgoingOnly())
          _OptionCheckBox(
            context,
            'Capture screen using DirectX',
            kOptionDirectxCapture,
          ),
        if (!bind.isIncomingOnly()) ...[
          _OptionCheckBox(
            context,
            'Enable UDP hole punching',
            kOptionEnableUdpPunch,
            isServer: false,
          ),
          _OptionCheckBox(
            context,
            'Enable IPv6 P2P connection',
            kOptionEnableIpv6Punch,
            isServer: false,
          ),
        ],
      ],
    ];

    // Add client-side wakelock option for desktop platforms
    if (!bind.isIncomingOnly()) {
      children.add(_OptionCheckBox(
        context,
        'keep-awake-during-outgoing-sessions-label',
        kOptionKeepAwakeDuringOutgoingSessions,
        isServer: false,
      ));
    }

    if (!isWeb && bind.mainShowOption(key: kOptionAllowLinuxHeadless)) {
      children.add(_OptionCheckBox(
          context, 'Allow linux headless', kOptionAllowLinuxHeadless));
    }
    if (!bind.isDisableAccount()) {
      children.add(_OptionCheckBox(
        context,
        'note-at-conn-end-tip',
        kOptionAllowAskForNoteAtEndOfConnection,
        isServer: false,
        optSetter: (key, value) async {
          if (value && !gFFI.userModel.isLogin) {
            final res = await loginDialog();
            if (res != true) return;
          }
          await mainSetLocalBoolOption(key, value);
        },
      ));
    }
    return _Card(title: 'Other', children: children);
  }

  Widget wallpaper() {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    return futureBuilder(future: () async {
      final support = await bind.mainSupportRemoveWallpaper();
      return support;
    }(), hasData: (data) {
      if (data is bool && data == true) {
        bool value = mainGetBoolOptionSync(kOptionAllowRemoveWallpaper);
        return Row(
          children: [
            Flexible(
              child: _OptionCheckBox(
                context,
                'Remove wallpaper during incoming sessions',
                kOptionAllowRemoveWallpaper,
                update: (bool v) {
                  setState(() {});
                },
              ),
            ),
            if (value)
              _CountDownButton(
                text: 'Test',
                second: 5,
                onPressed: () {
                  bind.mainTestWallpaper(second: 5);
                },
              )
          ],
        );
      }

      return Offstage();
    });
  }

  Widget hwcodec() {
    final hwcodec = bind.mainHasHwcodec();
    final vram = bind.mainHasVram();
    return Offstage(
      offstage: !(hwcodec || vram),
      child: _Card(title: 'Hardware Codec', children: [
        _OptionCheckBox(
          context,
          'Enable hardware codec',
          kOptionEnableHwcodec,
          update: (bool v) {
            if (v) {
              bind.mainCheckHwcodec();
            }
          },
        )
      ]),
    );
  }

  Widget audio(BuildContext context) {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    builder(devices, currentDevice, setDevice) {
      final child = SizedBox(
        width: 300,
        child: ComboBox(
          keys: devices,
          values: devices,
          initialKey: currentDevice,
          onChanged: (key) async {
            setDevice(key);
            setState(() {});
          },
        ),
      );
      return _Card(
        title: 'Audio Input Device',
        title_suffix: [child],
        children: const [],
      );
    }

    return AudioInput(builder: builder, isCm: false, isVoiceCall: false);
  }

  Widget record(BuildContext context) {
    final showRootDir = isWindows && bind.mainIsInstalled();
    return futureBuilder(future: () async {
      String user_dir = bind.mainVideoSaveDirectory(root: false);
      String root_dir =
          showRootDir ? bind.mainVideoSaveDirectory(root: true) : '';
      bool user_dir_exists = await Directory(user_dir).exists();
      bool root_dir_exists =
          showRootDir ? await Directory(root_dir).exists() : false;
      return {
        'user_dir': user_dir,
        'root_dir': root_dir,
        'user_dir_exists': user_dir_exists,
        'root_dir_exists': root_dir_exists,
      };
    }(), hasData: (data) {
      Map<String, dynamic> map = data as Map<String, dynamic>;
      String user_dir = map['user_dir']!;
      String root_dir = map['root_dir']!;
      bool root_dir_exists = map['root_dir_exists']!;
      bool user_dir_exists = map['user_dir_exists']!;
      return _Card(
        title: 'Recording',
        description: 'recording_card_tip',
        children: [
        if (!bind.isOutgoingOnly())
          _OptionCheckBox(context, 'Automatically record incoming sessions',
              kOptionAllowAutoRecordIncoming),
        if (!bind.isIncomingOnly())
          _OptionCheckBox(context, 'Automatically record outgoing sessions',
              kOptionAllowAutoRecordOutgoing,
              isServer: false),
        if (showRootDir && !bind.isOutgoingOnly())
          Row(
            children: [
              Text(
                  '${translate(bind.isIncomingOnly() ? "Directory" : "Incoming")}:'),
              Expanded(
                child: GestureDetector(
                    onTap: root_dir_exists
                        ? () => launchUrl(Uri.file(root_dir))
                        : null,
                    child: Text(
                      root_dir,
                      softWrap: true,
                      style: root_dir_exists
                          ? const TextStyle(
                              decoration: TextDecoration.underline)
                          : null,
                    )).marginOnly(left: 10),
              ),
            ],
          ).marginOnly(left: _kContentHMargin),
        if (!(showRootDir && bind.isIncomingOnly()))
          Row(
            children: [
              Text(
                  '${translate((showRootDir && !bind.isOutgoingOnly()) ? "Outgoing" : "Directory")}:'),
              Expanded(
                child: GestureDetector(
                    onTap: user_dir_exists
                        ? () => launchUrl(Uri.file(user_dir))
                        : null,
                    child: Text(
                      user_dir,
                      softWrap: true,
                      style: user_dir_exists
                          ? const TextStyle(
                              decoration: TextDecoration.underline)
                          : null,
                    )).marginOnly(left: 10),
              ),
              ElevatedButton(
                      onPressed: isOptionFixed(kOptionVideoSaveDirectory)
                          ? null
                          : () async {
                              String? initialDirectory;
                              if (await Directory.fromUri(
                                      Uri.directory(user_dir))
                                  .exists()) {
                                initialDirectory = user_dir;
                              }
                              String? selectedDirectory =
                                  await FilePicker.platform.getDirectoryPath(
                                      initialDirectory: initialDirectory);
                              if (selectedDirectory != null) {
                                await bind.mainSetLocalOption(
                                    key: kOptionVideoSaveDirectory,
                                    value: selectedDirectory);
                                setState(() {});
                              }
                            },
                      child: Text(translate('Change')))
                  .marginOnly(left: 5),
            ],
          ).marginOnly(left: _kContentHMargin),
      ]);
    });
  }

  Widget language() {
    return futureBuilder(
      future: () async {
        String langs = await bind.mainGetLangs();
        return {'langs': langs};
      }(),
      hasData: (res) {
        Map<String, String> data = res as Map<String, String>;
        List<dynamic> langsList = jsonDecode(data['langs']!);
        Map<String, String> langsMap = {for (var v in langsList) v[0]: v[1]};
        List<String> keys = langsMap.keys.toList();
        List<String> values = langsMap.values.toList();
        keys.insert(0, defaultOptionLang);
        values.insert(0, translate('Default'));
        String currentKey = bind.mainGetLocalOption(key: kCommConfKeyLang);
        if (!keys.contains(currentKey)) {
          currentKey = defaultOptionLang;
        }
        final isOptFixed = isOptionFixed(kCommConfKeyLang);
        return _Card(
          title: 'Language',
          description: 'language_card_tip',
          title_suffix: [
            SizedBox(
              width: 300,
              child: ComboBox(
                keys: keys,
                values: values,
                initialKey: currentKey,
                onChanged: (key) async {
                  await bind.mainSetLocalOption(
                    key: kCommConfKeyLang,
                    value: key,
                  );
                  if (isWeb) reloadCurrentWindow();
                  if (!isWeb) reloadAllWindows();
                  if (!isWeb) bind.mainChangeLanguage(lang: key);
                },
                enabled: !isOptFixed,
              ),
            ),
          ],
          children: const [],
        );
      },
    );
  }
}
