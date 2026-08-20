part of 'desktop_setting_page.dart';

const int _kMaxRailBackgroundInputBytes = 12 * 1024 * 1024;
const int _kMaxRailBackgroundStoredBytes = 2 * 1024 * 1024;
const int _kRailBackgroundLongEdge = 1600;

Uint8List? _prepareDesktopRailBackground(Uint8List bytes) {
  final source = img.decodeImage(bytes);
  if (source == null) return null;

  var image = img.bakeOrientation(source);
  if (image.width > _kRailBackgroundLongEdge ||
      image.height > _kRailBackgroundLongEdge) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: _kRailBackgroundLongEdge,
            interpolation: img.Interpolation.cubic,
          )
        : img.copyResize(
            image,
            height: _kRailBackgroundLongEdge,
            interpolation: img.Interpolation.cubic,
          );
  }
  var encoded = img.encodeJpg(image, quality: 82);
  if (encoded.length > _kMaxRailBackgroundStoredBytes &&
      (image.width > 1200 || image.height > 1200)) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: 1200,
            interpolation: img.Interpolation.cubic,
          )
        : img.copyResize(
            image,
            height: 1200,
            interpolation: img.Interpolation.cubic,
          );
    encoded = img.encodeJpg(image, quality: 72);
  }
  if (encoded.length > _kMaxRailBackgroundStoredBytes &&
      (image.width > 900 || image.height > 900)) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: 900,
            interpolation: img.Interpolation.cubic,
          )
        : img.copyResize(
            image,
            height: 900,
            interpolation: img.Interpolation.cubic,
          );
    encoded = img.encodeJpg(image, quality: 64);
  }
  return encoded;
}

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

  /// 消息提示音音量（0-100）与震动时长档位（short/medium/long）。
  int _messageSoundVolume = 80;
  String _messageVibrationDuration = 'short';

  /// 语音朗读（sherpa-onnx 离线 TTS）：开关、声音、语速、模型状态。
  bool _ttsEnabled = false;
  bool _ttsContinuousRead = false;
  int _ttsVoiceId = 0;
  double _ttsSpeed = 1.0;
  bool _ttsModelReady = false;
  bool _ttsDownloading = false;
  double _ttsProgress = 0.0;
  int _ttsIdleTimeout = 5; // 默认 5 分钟
  VoidCallback? _ttsListener;

  @override
  void initState() {
    super.initState();
    _ttsEnabled = bind.mainGetOptionSync(key: TtsService.kEnabled) == 'Y';
    _ttsContinuousRead = bind.mainGetOptionSync(key: TtsService.kContinuousRead) == 'Y';
    _ttsIdleTimeout = TtsService.instance.idleTimeoutMinutes;
    _ttsVoiceId =
        int.tryParse(bind.mainGetOptionSync(key: TtsService.kVoiceId)) ?? 0;
    if (_ttsVoiceId < 0 || _ttsVoiceId >= TtsService.presetVoices.length) {
      _ttsVoiceId = 0;
    }
    final speedRaw = double.tryParse(
        bind.mainGetOptionSync(key: TtsService.kSpeed));
    _ttsSpeed = (speedRaw == null || speedRaw <= 0) ? 1.0 : speedRaw;
    _ttsListener = () {
      if (!mounted) return;
      setState(() {
        _ttsDownloading = TtsService.instance.isDownloading;
        _ttsProgress = TtsService.instance.downloadProgress;
      });
    };
    TtsService.instance.addListener(_ttsListener!);
    TtsService.instance.isModelDownloaded().then((ready) {
      if (mounted) setState(() => _ttsModelReady = ready);
    });
    _messageSoundVolume = int.tryParse(bind
            .mainGetOptionSync(key: kOptionMessageSoundVolume)
            .trim()) ??
        80;
    final dur = bind
        .mainGetOptionSync(key: kOptionMessageVibrationDuration)
        .trim();
    _messageVibrationDuration =
        (dur == 'medium' || dur == 'long') ? dur : 'short';
  }

  @override
  void dispose() {
    if (_ttsListener != null) {
      TtsService.instance.removeListener(_ttsListener!);
      _ttsListener = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        if (!isWeb) service(),
        theme(),
        language(),
        messageNotifications(),
        connectionInfo(),
        voiceReading(),
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
                              translate('Advanced settings'),
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
          railBackground(),
          if (!isWeb) audio(context),
          if (!isWeb) record(context),
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
      title: translate('Theme'),
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

  Widget railBackground() {
    final value = bind.mainGetLocalOption(key: kDesktopRailBackgroundOption);
    final backgroundBytes = decodeDesktopRailBackground(value);
    final hasBackground = backgroundBytes != null;
    final theme = Theme.of(context);

    Widget details() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              translate(
                hasBackground ? 'Custom background' : 'Default background',
              ),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              translate('Stored only on this device'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _chooseRailBackground,
                  icon: const Icon(Icons.image_outlined, size: 19),
                  label: Text(
                    translate(hasBackground ? 'Change' : 'Choose image'),
                  ),
                ),
                if (hasBackground)
                  TextButton.icon(
                    onPressed: _clearRailBackground,
                    icon: const Icon(Icons.restart_alt_rounded, size: 19),
                    label: Text(translate('Clear')),
                  ),
              ],
            ),
          ],
        );

    return _Card(
      title: translate('Sidebar background'),
      description: 'sidebar_background_tip',
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final preview = _railBackgroundPreview(backgroundBytes);
            if (constraints.maxWidth < 480) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  preview,
                  const SizedBox(height: 16),
                  details(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                preview,
                const SizedBox(width: 20),
                Expanded(child: details()),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _railBackgroundPreview(Uint8List? backgroundBytes) {
    final hasBackground = backgroundBytes != null;
    return Container(
      width: DesktopPrimaryRail.width,
      height: 156,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9E1),
        gradient: hasBackground
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xFFF0D1D2),
                  Color(0xFFE7E6EA),
                  Color(0xFFD9D9E1),
                ],
              ),
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: <Widget>[
          if (hasBackground)
            Positioned.fill(
              child: Image.memory(
                backgroundBytes!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (hasBackground)
            const Positioned.fill(
              child: ColoredBox(color: Color(0x80000000)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: <Widget>[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 34,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hasBackground
                        ? Colors.white.withOpacity(0.94)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.chat_bubble_rounded,
                    color: hasBackground
                        ? kDesktopRailSelectedForeground
                        : Theme.of(context).colorScheme.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(height: 3),
                Icon(
                  Icons.contacts_rounded,
                  color: hasBackground
                      ? Colors.white.withOpacity(0.88)
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.58),
                  size: 19,
                ),
                const Spacer(),
                Icon(
                  Icons.settings_rounded,
                  color: hasBackground
                      ? Colors.white.withOpacity(0.88)
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.58),
                  size: 19,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseRailBackground() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    Uint8List? bytes = file?.bytes;
    if (bytes == null && file?.path != null) {
      bytes = await File(file!.path!).readAsBytes();
    }
    if (bytes == null) return;
    if (bytes.length > _kMaxRailBackgroundInputBytes) {
      _showRailBackgroundMessage('background_image_too_large_tip');
      return;
    }

    Uint8List? prepared;
    try {
      prepared = await compute(_prepareDesktopRailBackground, bytes);
    } catch (error) {
      debugPrint('Failed to prepare rail background: $error');
    }
    if (!mounted) return;
    if (prepared == null) {
      _showRailBackgroundMessage('invalid_background_image_tip');
      return;
    }
    if (prepared.length > _kMaxRailBackgroundStoredBytes) {
      _showRailBackgroundMessage('background_image_too_large_tip');
      return;
    }

    await bind.mainSetLocalOption(
      key: kDesktopRailBackgroundOption,
      value: 'data:image/jpeg;base64,${base64Encode(prepared)}',
    );
    if (!mounted) return;
    desktopRailBackgroundRevision.value++;
    setState(() {});
  }

  Future<void> _clearRailBackground() async {
    await bind.mainSetLocalOption(
      key: kDesktopRailBackgroundOption,
      value: '',
    );
    if (!mounted) return;
    desktopRailBackgroundRevision.value++;
    setState(() {});
  }

  void _showRailBackgroundMessage(String key) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(translate(key))),
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
        title: translate('Service'),
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
    return _Card(title: translate('Other'), children: children);
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
      child: _Card(title: translate('Hardware Codec'), children: [
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
        title: translate('Audio Input Device'),
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
          title: translate('Recording'),
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
                                  String? selectedDirectory = await FilePicker
                                      .platform
                                      .getDirectoryPath(
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
        String currentKey = bind.mainGetLocalOption(key: kCommConfKeyLang);
        if (!keys.contains(currentKey)) {
          currentKey =
              localeName.toLowerCase().startsWith('zh') ? 'zh-cn' : 'en';
        }
        final isOptFixed = isOptionFixed(kCommConfKeyLang);
        return _Card(
          title: translate('Language'),
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
                  if (!isWeb) bind.mainChangeLanguage(lang: key);
                  if (isWeb) reloadCurrentWindow();
                  if (!isWeb) reloadAllWindows();
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

  /// 消息到达提醒：提示音开关 + 震动开关 + 自定义提示音。
  /// 与手机端共用同一组配置键（message-sound / message-vibration /
  /// message-sound-path），收到新消息时两端行为一致。
  Widget messageNotifications() {
    final soundPath =
        bind.mainGetOptionSync(key: kOptionMessageSoundPath).trim();
    final soundName = _toneDisplayName(soundPath);
    return _Card(
      title: translate('Message notifications'),
      description: 'Play a tone or vibrate when a new message arrives',
      children: [
        _OptionCheckBox(
          context,
          'Message sound',
          kOptionMessageSound,
          isServer: true,
        ),
        _OptionCheckBox(
          context,
          'Message vibration',
          kOptionMessageVibration,
          isServer: true,
        ),
        Padding(
          padding: const EdgeInsets.only(left: _kCheckBoxLeftMargin),
          child: Row(
            children: [
              const Icon(Icons.music_note_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  soundName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.25),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: translate('Notification sound'),
                onSelected: (value) async {
                  if (value == '__default__') {
                    await bind.mainSetOption(
                        key: kOptionMessageSoundPath, value: '');
                  } else if (value == '__file__') {
                    await _pickCustomSound();
                  } else {
                    await bind.mainSetOption(
                        key: kOptionMessageSoundPath,
                        value: '$kBuiltinTonePrefix$value');
                  }
                  if (mounted) setState(() {});
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: '__default__',
                    child: Text(translate('Default tone')),
                  ),
                  for (final tone in kBuiltinTones)
                    PopupMenuItem<String>(
                      value: tone['key']!,
                      child: Text(translate('Tone ${tone['label']}')),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: '__file__',
                    child: Text(translate('Choose audio file')),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        translate('Choose'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
              if (soundPath.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await bind.mainSetOption(
                        key: kOptionMessageSoundPath, value: '');
                    if (mounted) setState(() {});
                  },
                  child: Text(translate('Reset')),
                ),
            ],
          ),
        ),
        // 提示音音量滑块（与手机端共用 message-sound-volume 键）。
        Padding(
          padding: const EdgeInsets.only(left: _kCheckBoxLeftMargin),
          child: Row(
            children: [
              const Icon(Icons.volume_up_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                translate('Sound volume'),
                style: const TextStyle(height: 1.25),
              ),
              Expanded(
                child: Slider(
                  value: _messageSoundVolume.toDouble(),
                  min: 0,
                  max: 100,
                  activeColor: const Color(0xFF07C160),
                  onChanged: (v) => setState(() {
                    _messageSoundVolume = v.round();
                    bind.mainSetOption(
                      key: kOptionMessageSoundVolume,
                      value: v.round().toString(),
                    );
                  }),
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '$_messageSoundVolume%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A8D94),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 震动时长选择（与手机端共用 message-vibration-duration 键）。
        Padding(
          padding: const EdgeInsets.only(left: _kCheckBoxLeftMargin),
          child: Row(
            children: [
              const Icon(Icons.vibration_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  translate(
                    switch (_messageVibrationDuration) {
                      'medium' => 'Medium vibration',
                      'long' => 'Long vibration',
                      _ => 'Short vibration',
                    },
                  ),
                  style: const TextStyle(height: 1.25),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: translate('Vibration duration'),
                initialValue: _messageVibrationDuration,
                onSelected: (value) async {
                  await bind.mainSetOption(
                      key: kOptionMessageVibrationDuration, value: value);
                  if (mounted) setState(() {});
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'short',
                    child: Text(translate('Short vibration')),
                  ),
                  PopupMenuItem<String>(
                    value: 'medium',
                    child: Text(translate('Medium vibration')),
                  ),
                  PopupMenuItem<String>(
                    value: 'long',
                    child: Text(translate('Long vibration')),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        translate(
                          switch (_messageVibrationDuration) {
                            'medium' => 'Medium vibration',
                            'long' => 'Long vibration',
                            _ => 'Short vibration',
                          },
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 语音朗读（离线 TTS）：与手机端共用同一组配置键
  /// （tts-read-enabled-v1 / tts-voice-id-v1 / tts-speed-v1），
  /// 当前连接方式：直连优先，中继仅作最后手段（P2P 理念）。
  Widget connectionInfo() {
    final lanIp = bind.mainGetOptionSync(key: 'local-ip-addr');
    final publicIp = bind.mainGetOptionSync(key: 'public-ip');
    final port = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    final status =
        bind.mainGetOptionSync(key: 'direct-listener-status');
    final statusLabel = status == 'ready'
        ? translate('Ready')
        : (status.isEmpty ? translate('Listening') : status);
    return _Card(
      title: translate('Connection mode'),
      description: 'Direct P2P preferred; relay only as a last resort',
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.settings_ethernet_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${translate("Local Address")}: '
                  '$lanIp${port.isEmpty ? "" : ":$port"}'
                  '${publicIp.isEmpty ? "" : "\n${translate("Public IP")}: $publicIp"}',
                  style: const TextStyle(height: 1.4),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.cell_tower_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${translate("Listener status")}: $statusLabel',
                  style: const TextStyle(height: 1.25),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            translate('relay_last_resort_tip'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.color
                  ?.withOpacity(0.75),
            ),
          ),
        ),
      ],
    );
  }

  /// 收到新消息时按设置自动朗读。模型首次使用时下载，之后完全离线。
  Widget voiceReading() {
    final voiceName = _ttsModelReady
        ? (TtsService.presetVoices.length > _ttsVoiceId
            ? translate(TtsService.presetVoices[_ttsVoiceId])
            : translate(TtsService.presetVoices.first))
        : translate('Model not downloaded yet');
    return _Card(
      title: translate('Voice reading'),
      description: 'Offline voice reading via local model; no server involved',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(translate('Read new messages aloud')),
          subtitle: Text(
            translate('Auto-read incoming text messages when enabled'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          value: _ttsEnabled,
          onChanged: (value) async {
            await bind.mainSetLocalOption(
                key: TtsService.kEnabled, value: value ? 'Y' : '');
            if (mounted) setState(() => _ttsEnabled = value);
            // 关闭朗读开关时同步关闭连续朗读模式。
            if (!value && _ttsContinuousRead) {
              await TtsService.instance.setContinuousRead(false);
              if (mounted) setState(() => _ttsContinuousRead = false);
            }
            if (value && !_ttsModelReady) {
              await _ensureTtsModel();
            }
          },
        ),
        // 连续朗读模式：自动逐条朗读所有收到的文字消息。
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(translate('Continuous reading')),
          subtitle: Text(
            translate(
                'Automatically read all incoming messages one by one until turned off'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          value: _ttsContinuousRead,
          onChanged: (value) async {
            await TtsService.instance.setContinuousRead(value);
            if (mounted) setState(() => _ttsContinuousRead = value);
            if (value && !_ttsEnabled) {
              // 开启连续朗读时自动开启基础朗读开关。
              await bind.mainSetLocalOption(
                  key: TtsService.kEnabled, value: 'Y');
              if (mounted) setState(() => _ttsEnabled = true);
            }
            if (value && !_ttsModelReady) {
              await _ensureTtsModel();
            }
          },
        ),
        // 使用提示
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  translate(
                      'Right-click any text message in chat to read it aloud'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.65),
                  ),
                ),
              ),
            ],
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.graphic_eq_outlined, size: 20),
          title: Text(translate('Reading voice')),
          subtitle: Text(
            voiceName,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          enabled: _ttsModelReady,
          onTap: _ttsModelReady ? _showVoicePicker : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.speed_outlined, size: 20),
          title: Text(translate('Reading speed')),
          enabled: _ttsModelReady && _ttsEnabled,
          trailing: SizedBox(
            width: 200,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Expanded(
                  child: Slider(
                    value: _ttsSpeed,
                    min: 0.5,
                    max: 1.5,
                    divisions: 10,
                    activeColor: kWeChatPrimaryColor,
                    onChanged: (v) {
                      setState(() => _ttsSpeed = v);
                    },
                    onChangeEnd: (v) async {
                      await bind.mainSetLocalOption(
                        key: TtsService.kSpeed,
                        value: v.toStringAsFixed(1),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(_ttsSpeed * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A8D94),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.timer_outlined, size: 20),
          title: Text(translate('Engine idle timeout')),
          subtitle: Text(
            _ttsIdleTimeout == 0
                ? translate('Never auto-release')
                : '$_ttsIdleTimeout ${translate('minutes')}',
            style: const TextStyle(fontSize: 12),
          ),
          enabled: _ttsModelReady && _ttsEnabled,
          trailing: SizedBox(
            width: 200,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Expanded(
                  child: Slider(
                    value: _ttsIdleTimeout.toDouble(),
                    min: 0,
                    max: 15,
                    divisions: 16,
                    activeColor: kWeChatPrimaryColor,
                    onChanged: (v) {
                      setState(() => _ttsIdleTimeout = v.round());
                    },
                    onChangeEnd: (v) async {
                      await TtsService.instance
                          .setIdleTimeoutMinutes(v.round());
                    },
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    _ttsIdleTimeout == 0
                        ? translate('∞')
                        : '$_ttsIdleTimeout m',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A8D94),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_ttsModelReady)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline, size: 20),
            title: Text(translate('Delete voice model')),
            subtitle: Text(
              TtsService.instance.isModelBundled
                  ? translate('Bundled model (about 133 MB)')
                  : 'About 133 MB',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _confirmDeleteTtsModel,
          )
        else if (TtsService.instance.isModelBundled && _ttsDownloading)
          // 内置模型版本：正在从 assets 复制
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.content_copy_rounded, size: 20),
            title: Text(translate('Copying voice model…')),
            subtitle: Text(
              '${(_ttsProgress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 12,
                color: kWeChatPrimaryColor,
              ),
            ),
            enabled: false,
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _ttsDownloading
                  ? Icons.downloading_rounded
                  : Icons.download_outlined,
              size: 20,
            ),
            title: Text(_ttsDownloading
                ? translate('Downloading voice model…')
                : translate('Download voice model (about 133 MB)')),
            subtitle: Text(
              _ttsDownloading
                  ? '${(_ttsProgress * 100).toStringAsFixed(0)}%'
                  : translate('One-time download, then fully offline reading'),
              style: TextStyle(
                fontSize: 12,
                color: _ttsDownloading
                    ? kWeChatPrimaryColor
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            enabled: !_ttsDownloading,
            onTap: _startTtsDownload,
          ),
      ],
    );
  }

  Future<void> _ensureTtsModel() async {
    if (_ttsModelReady || _ttsDownloading) return;
    try {
      await TtsService.instance.downloadModel();
      if (mounted) setState(() => _ttsModelReady = true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(translate('Voice model ready'))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ttsDownloading = false;
          _ttsModelReady = false;
        });
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                translate('Voice model download failed, please retry')),
          ),
        );
      }
    }
  }

  void _startTtsDownload() {
    _ensureTtsModel();
  }

  Future<void> _showVoicePicker() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(translate('Reading voice')),
        children: <Widget>[
          for (var i = 0; i < TtsService.presetVoices.length; i++)
            ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: Text(translate(TtsService.presetVoices[i])),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline,
                        color: kWeChatPrimaryColor),
                    tooltip: translate('Preview'),
                    onPressed: () => TtsService.instance.preview(i),
                  ),
                  if (_ttsVoiceId == i)
                    const Icon(Icons.check, color: kWeChatPrimaryColor),
                ],
              ),
              onTap: () => Navigator.pop(ctx, i),
            ),
        ],
      ),
    );
    if (selected != null) {
      await bind.mainSetLocalOption(
          key: TtsService.kVoiceId, value: '$selected');
      if (mounted) setState(() => _ttsVoiceId = selected);
    }
  }

  Future<void> _confirmDeleteTtsModel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(translate('Delete voice model')),
        content: Text(translate(
            'This removes the offline voice model (about 133 MB). Reading aloud will stop until you download it again.')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(translate('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(translate('Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TtsService.instance.deleteModel();
    if (mounted) {
      setState(() {
        _ttsModelReady = false;
        _ttsDownloading = false;
      });
    }
  }

  /// 提示音显示名：内置音 → 中文名，空 → 默认音，其它 → 自定义文件名。
  String _toneDisplayName(String value) {
    final v = value.trim();
    if (v.isEmpty) return translate('Default tone');
    if (v.startsWith(kBuiltinTonePrefix)) {
      final name = v.substring(kBuiltinTonePrefix.length);
      final found = kBuiltinTones
          .where((t) => t['key'] == name)
          .toList();
      if (found.isNotEmpty) {
        return translate('Tone ${found.first['label']}');
      }
    }
    return v.split(Platform.pathSeparator).last;
  }

  Future<void> _pickCustomSound() async {
    try {
      final result =
          await FilePicker.platform.pickFiles(type: FileType.audio);
      final srcPath = result?.files.single.path;
      if (srcPath == null || srcPath.isEmpty) return;
      await bind.mainSetOption(key: kOptionMessageSoundPath, value: srcPath);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('pick custom sound failed: $e');
    }
  }
}
