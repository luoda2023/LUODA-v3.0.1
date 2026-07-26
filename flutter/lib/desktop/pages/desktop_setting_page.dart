import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/widgets/audio_input.dart';
import 'package:luoda_flutter/common/widgets/setting_widgets.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/desktop/pages/desktop_home_page.dart';
import 'package:luoda_flutter/desktop/pages/desktop_tab_page.dart';
import 'package:luoda_flutter/desktop/widgets/remote_toolbar.dart';
import 'package:luoda_flutter/desktop/widgets/desktop_primary_rail.dart';
import 'package:luoda_flutter/mobile/widgets/dialog.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:luoda_flutter/models/printer_model.dart';
import 'package:luoda_flutter/models/peer_model.dart';
import 'package:luoda_flutter/models/server_model.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:luoda_flutter/plugin/manager.dart';
import 'package:luoda_flutter/plugin/widgets/desktop_settings.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common/widgets/dialog.dart';
import '../../common/widgets/login.dart';

part 'desktop_setting_general.part.dart';
part 'desktop_setting_safety.part.dart';
part 'desktop_setting_network.part.dart';
part 'desktop_setting_display.part.dart';
part 'desktop_setting_account.part.dart';
part 'desktop_setting_checkbox.part.dart';
part 'desktop_setting_plugin.part.dart';
part 'desktop_setting_printer.part.dart';
part 'desktop_setting_about.part.dart';
part 'desktop_setting_helpers.part.dart';

const double _kTabHeight = 48;
const double _kCardFixedWidth = 960;
const double _kCardLeftMargin = 24;
const double _kContentHMargin = 18;
const double _kContentHSubMargin = _kContentHMargin + 33;
const double _kCheckBoxLeftMargin = 10;
const double _kRadioLeftMargin = 10;
const double _kListViewBottomMargin = 12;
const double _kTitleFontSize = 18;
const double _kContentFontSize = 14;
const Color _accentColor = MyTheme.accent;
const String _kSettingPageControllerTag = 'settingPageController';
const String _kSettingPageTabKeyTag = 'settingPageTabKey';

class _TabInfo {
  late final SettingsTabKey key;
  late final String label;
  late final IconData unselected;
  late final IconData selected;
  _TabInfo(this.key, this.label, this.unselected, this.selected);
}

enum SettingsTabKey {
  general,
  safety,
  network,
  display,
  plugin,
  account,
  printer,
  about,
}

class DesktopSettingPage extends StatefulWidget {
  final SettingsTabKey initialTabkey;

  static List<SettingsTabKey> get tabKeys {
    if (_tabKeys != null) return _tabKeys!;
    _tabKeys = _buildTabKeys();
    return _tabKeys!;
  }

  static List<SettingsTabKey>? _tabKeys;

  static List<SettingsTabKey> _buildTabKeys() {
    final keys = <SettingsTabKey>[SettingsTabKey.general];

    try {
      final jsonStr = bind.getSettingsTabConfig();
      final config = jsonDecode(jsonStr) as Map<String, dynamic>;

      final isOutgoingOnly = config['is_outgoing_only'] == true;
      final isIncomingOnly = config['is_incoming_only'] == true;
      final isDisableSettings = config['is_disable_settings'] == true;
      final isDisableAccount = config['is_disable_account'] == true;
      final hideSecuritySetting = config['hide_security_setting'] == true;
      final hideNetworkSetting = config['hide_network_setting'] == true;
      final hideRemotePrinterSetting =
          config['hide_remote_printer_setting'] == true;
      final pluginFeatureEnabled = config['plugin_feature_enabled'] == true;

      if (!isWeb &&
          !isOutgoingOnly &&
          !isDisableSettings &&
          !hideSecuritySetting) {
        keys.add(SettingsTabKey.safety);
      }

      if (!isDisableSettings && !hideNetworkSetting) {
        keys.add(SettingsTabKey.network);
      }

      if (!isIncomingOnly) {
        keys.add(SettingsTabKey.display);
      }

      if (!isWeb && !isIncomingOnly && pluginFeatureEnabled) {
        keys.add(SettingsTabKey.plugin);
      }

      if (!isDisableAccount) {
        keys.add(SettingsTabKey.account);
      }

      if (isWindows && !hideRemotePrinterSetting) {
        keys.add(SettingsTabKey.printer);
      }
    } catch (e) {
      debugPrint('Failed to init tab keys: $e');
    }

    keys.add(SettingsTabKey.about);
    return keys;
  }

  DesktopSettingPage({Key? key, required this.initialTabkey}) : super(key: key);

  @override
  State<DesktopSettingPage> createState() =>
      _DesktopSettingPageState(initialTabkey);

  static void switch2page(SettingsTabKey page) {
    try {
      int index = tabKeys.indexOf(page);
      if (index == -1) {
        return;
      }
      if (Get.isRegistered<PageController>(tag: _kSettingPageControllerTag)) {
        DesktopTabPage.onAddSetting(initialPage: page);
        PageController controller =
            Get.find<PageController>(tag: _kSettingPageControllerTag);
        Rx<SettingsTabKey> selected =
            Get.find<Rx<SettingsTabKey>>(tag: _kSettingPageTabKeyTag);
        selected.value = page;
        controller.jumpToPage(index);
      } else {
        DesktopTabPage.onAddSetting(initialPage: page);
      }
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopSettingPageState extends State<DesktopSettingPage>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver {
  late PageController controller;
  late Rx<SettingsTabKey> selectedTab;

  @override
  bool get wantKeepAlive => true;

  final RxBool _block = false.obs;
  final RxBool _canBeBlocked = false.obs;
  Timer? _videoConnTimer;
  late bool _advancedSettingsExpanded;

  _DesktopSettingPageState(SettingsTabKey initialTabkey) {
    var initialIndex = DesktopSettingPage.tabKeys.indexOf(initialTabkey);
    if (initialIndex == -1) {
      initialIndex = 0;
    }
    selectedTab = DesktopSettingPage.tabKeys[initialIndex].obs;
    _advancedSettingsExpanded = const <SettingsTabKey>{
      SettingsTabKey.display,
      SettingsTabKey.plugin,
      SettingsTabKey.printer,
    }.contains(selectedTab.value);
    Get.put<Rx<SettingsTabKey>>(selectedTab, tag: _kSettingPageTabKeyTag);
    controller = PageController(initialPage: initialIndex);
    Get.put<PageController>(controller, tag: _kSettingPageControllerTag);
    controller.addListener(() {
      if (controller.page != null) {
        int page = controller.page!.toInt();
        if (page < DesktopSettingPage.tabKeys.length) {
          selectedTab.value = DesktopSettingPage.tabKeys[page];
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _videoConnTimer =
        periodic_immediate(Duration(milliseconds: 1000), () async {
      if (!mounted) {
        return;
      }
      _canBeBlocked.value = await canBeBlocked();
    });
  }

  @override
  void dispose() {
    _videoConnTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    Get.delete<PageController>(tag: _kSettingPageControllerTag);
    Get.delete<Rx<SettingsTabKey>>(tag: _kSettingPageTabKeyTag);
    controller.dispose();
    super.dispose();
  }

  List<_TabInfo> _settingTabs() {
    final List<_TabInfo> settingTabs = <_TabInfo>[];
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          settingTabs
              .add(_TabInfo(tab, 'General', Icons.tune_rounded, Icons.tune));
          break;
        case SettingsTabKey.safety:
          settingTabs.add(
              _TabInfo(tab, 'Security', Icons.shield_rounded, Icons.shield));
          break;
        case SettingsTabKey.network:
          settingTabs.add(
              _TabInfo(tab, 'Network', Icons.language_rounded, Icons.language));
          break;
        case SettingsTabKey.display:
          settingTabs.add(
              _TabInfo(tab, 'Display', Icons.monitor_rounded, Icons.monitor));
          break;
        case SettingsTabKey.plugin:
          settingTabs.add(_TabInfo(
              tab, 'Plugin', Icons.extension_rounded, Icons.extension));
          break;
        case SettingsTabKey.account:
          settingTabs.add(_TabInfo(tab, 'Account', Icons.account_circle_rounded,
              Icons.account_circle));
          break;
        case SettingsTabKey.printer:
          settingTabs
              .add(_TabInfo(tab, 'Printer', Icons.print_rounded, Icons.print));
          break;
        case SettingsTabKey.about:
          settingTabs
              .add(_TabInfo(tab, 'About', Icons.info_rounded, Icons.info));
          break;
      }
    }
    return settingTabs;
  }

  List<Widget> _children() {
    final children = List<Widget>.empty(growable: true);
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          children.add(const _General());
          break;
        case SettingsTabKey.safety:
          children.add(const _Safety());
          break;
        case SettingsTabKey.network:
          children.add(const _Network());
          break;
        case SettingsTabKey.display:
          children.add(const _Display());
          break;
        case SettingsTabKey.plugin:
          children.add(const _Plugin());
          break;
        case SettingsTabKey.account:
          children.add(const _Account());
          break;
        case SettingsTabKey.printer:
          children.add(const _Printer());
          break;
        case SettingsTabKey.about:
          children.add(const _About());
          break;
      }
    }
    return children;
  }

  Widget _buildBlock({required List<Widget> children}) {
    // check both mouseMoveTime and videoConnCount
    return Obx(() {
      final videoConnBlock =
          _canBeBlocked.value && stateGlobal.videoConnCount > 0;
      return Stack(children: [
        buildRemoteBlock(
          block: _block,
          mask: false,
          use: canBeBlocked,
          child: preventMouseKeyBuilder(
            child: Row(children: children),
            block: videoConnBlock,
          ),
        ),
        if (videoConnBlock)
          Container(
            color: Colors.black.withOpacity(0.5),
          )
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth >= 1080
              ? 268.0
              : constraints.maxWidth >= 820
                  ? 232.0
                  : 64.0;
          final iconOnly = tabWidth == 64;
          return Row(
            children: <Widget>[
              _buildPrimaryRail(context),
              Expanded(
                child: _buildBlock(
                  children: <Widget>[
                    Container(
                      width: tabWidth,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border(
                            right: BorderSide(color: theme.dividerColor)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(context, iconOnly: iconOnly),
                          Flexible(
                            child: _listView(
                              tabs: _settingTabs(),
                              iconOnly: iconOnly,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ColoredBox(
                        color: theme.scaffoldBackgroundColor,
                        child: PageView(
                          controller: controller,
                          physics: const NeverScrollableScrollPhysics(),
                          children: _children(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, {required bool iconOnly}) {
    final theme = Theme.of(context);
    final settingsText = Text(
      translate('Settings'),
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
    return Column(
      children: <Widget>[
        SizedBox(
          height: 60,
          child: Row(
            children: [
              if (isWeb)
                IconButton(
                  tooltip: translate('Back'),
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              Expanded(
                child: iconOnly
                    ? const Center(
                        child: Icon(Icons.settings_outlined, size: 22),
                      )
                    : settingsText,
              ),
            ],
          ).paddingSymmetric(horizontal: iconOnly ? 8 : 22),
        ),
        if (!iconOnly) _profileHeader(context),
      ],
    );
  }

  Widget _listView({
    required List<_TabInfo> tabs,
    required bool iconOnly,
  }) {
    final scrollController = ScrollController();
    if (iconOnly) {
      return ListView(
        controller: scrollController,
        children:
            tabs.map((tab) => _listItem(tab: tab, iconOnly: true)).toList(),
      );
    }
    final primary = tabs
        .where((tab) => const <SettingsTabKey>{
              SettingsTabKey.general,
              SettingsTabKey.safety,
              SettingsTabKey.network,
              SettingsTabKey.account,
            }.contains(tab.key))
        .toList();
    final advanced = tabs
        .where((tab) => const <SettingsTabKey>{
              SettingsTabKey.display,
              SettingsTabKey.plugin,
              SettingsTabKey.printer,
            }.contains(tab.key))
        .toList();
    final about = tabs.where((tab) => tab.key == SettingsTabKey.about).toList();
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 12),
      children: <Widget>[
        ...primary.map((tab) => _listItem(tab: tab, iconOnly: false)),
        if (advanced.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(
              () => _advancedSettingsExpanded = !_advancedSettingsExpanded,
            ),
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.tune_rounded, size: 19),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        translate('Advanced settings'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                    Icon(
                      _advancedSettingsExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_advancedSettingsExpanded)
            ...advanced.map(
              (tab) => _listItem(tab: tab, iconOnly: false),
            ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Divider(height: 1, color: Theme.of(context).dividerColor),
        ),
        ...about.map((tab) => _listItem(tab: tab, iconOnly: false)),
      ],
    );
  }

  Widget _listItem({required _TabInfo tab, required bool iconOnly}) {
    return Obx(() {
      final theme = Theme.of(context);
      final selected = tab.key == selectedTab.value;
      final foreground = selected
          ? theme.colorScheme.primary
          : theme.textTheme.bodyMedium?.color;
      return SizedBox(
        height: _kTabHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 10 : 12,
            vertical: 2,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              hoverColor: theme.hoverColor,
              onTap: () {
                if (selectedTab.value != tab.key) {
                  final index = DesktopSettingPage.tabKeys.indexOf(tab.key);
                  if (index == -1) {
                    return;
                  }
                  controller.jumpToPage(index);
                }
                selectedTab.value = tab.key;
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 14),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.onSurface.withOpacity(
                          theme.brightness == Brightness.dark ? 0.14 : 0.08,
                        )
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: iconOnly
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: iconOnly ? translate(tab.label) : '',
                      child: Icon(
                        selected ? tab.selected : tab.unselected,
                        color: foreground,
                        size: 20,
                      ),
                    ),
                    if (!iconOnly) const SizedBox(width: 13),
                    if (!iconOnly)
                      Expanded(
                        child: Text(
                          translate(tab.label),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: foreground,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildPrimaryRail(BuildContext context) {
    const destinations = <DesktopRailDestination>[
      DesktopRailDestination(
        id: 'chat',
        label: 'Chat',
        icon: Icons.chat_bubble_outline_rounded,
      ),
      DesktopRailDestination(
        id: 'recent',
        label: 'Recent sessions',
        icon: Icons.history_rounded,
      ),
      DesktopRailDestination(
        id: 'favorites',
        label: 'Favorites',
        icon: Icons.star_outline_rounded,
      ),
      DesktopRailDestination(
        id: 'discovered',
        label: 'Discovered',
        icon: Icons.radar_rounded,
      ),
      DesktopRailDestination(
        id: 'contacts',
        label: 'Address book',
        icon: Icons.contacts_outlined,
      ),
      DesktopRailDestination(
        id: 'history',
        label: 'Access history devices',
        icon: Icons.devices_outlined,
      ),
      DesktopRailDestination(
        id: 'vip',
        label: 'VIP features',
        icon: Icons.workspace_premium_outlined,
      ),
    ];
    const indexes = <String, int>{
      'chat': 0,
      'recent': 0,
      'favorites': 1,
      'discovered': 2,
      'contacts': 3,
      'history': 4,
      'vip': 5,
    };
    return DesktopPrimaryRail(
      destinations: destinations,
      selectedId: '',
      settingsSelected: true,
      avatar: _localProfileAvatar(44),
      onAvatarPressed: _editLocalProfile,
      onSelected: (id) =>
          DesktopTabPage.showHome(peerTabIndex: indexes[id] ?? 0),
      onSettings: () {},
    );
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

  Widget _profileHeader(BuildContext context) {
    final profile = _localProfile();
    final name =
        (profile['display_name'] ?? profile['name'] ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Material(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.045),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _editLocalProfile,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                SizedBox(width: 42, height: 42, child: _localProfileAvatar(42)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name.isEmpty ? translate('Local profile') : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        translate('Edit avatar and display name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _localProfileAvatar(double size, {String? avatar}) {
    final value = avatar ?? (_localProfile()['avatar'] ?? '').toString();
    return buildAvatarWidget(
          avatar: value,
          size: size,
          borderRadius: 8,
          fallback: Image.asset('assets/avatar.png', fit: BoxFit.cover),
        ) ??
        Image.asset('assets/avatar.png', fit: BoxFit.cover);
  }

  Future<void> _editLocalProfile() async {
    final profile = _localProfile();
    final nameController = TextEditingController(
      text: (profile['display_name'] ?? profile['name'] ?? '').toString(),
    );
    var avatar = (profile['avatar'] ?? '').toString();
    Uint8List? selectedBytes;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(translate('Local profile')),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 76,
                  height: 76,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: selectedBytes != null
                        ? Image.memory(selectedBytes!, fit: BoxFit.cover)
                        : _localProfileAvatar(76, avatar: avatar),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () async {
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
                    if (bytes.length > 512 * 1024) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              translate(
                                  'Avatar image must be smaller than 512 KB'),
                            ),
                          ),
                        );
                      }
                      return;
                    }
                    setDialogState(() => selectedBytes = bytes);
                  },
                  icon: const Icon(Icons.photo_outlined, size: 19),
                  label: Text(translate('Choose image')),
                ),
                const SizedBox(height: 12),
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
      avatar = 'data:image/png;base64,${base64Encode(selectedBytes!)}';
    }
    profile['display_name'] = nameController.text.trim();
    profile['avatar'] = avatar;
    await bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(profile));
    gFFI.chatModel.refreshLocalIdentity(notify: true);
    nameController.dispose();
    if (mounted) setState(() {});
  }
}

//#region pages
