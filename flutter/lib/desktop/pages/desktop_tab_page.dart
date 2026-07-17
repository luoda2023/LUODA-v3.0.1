import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/desktop/pages/desktop_home_page.dart';
import 'package:luoda_flutter/desktop/pages/desktop_setting_page.dart';
import 'package:luoda_flutter/common/widgets/peer_tab_page.dart';
import 'package:luoda_flutter/desktop/widgets/desktop_main_title_bar.dart';
import 'package:luoda_flutter/desktop/widgets/tabbar_widget.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
// import 'package:flutter/services.dart';

import '../../common/shared_state.dart';

class DesktopTabPage extends StatefulWidget {
  const DesktopTabPage({Key? key}) : super(key: key);

  @override
  State<DesktopTabPage> createState() => _DesktopTabPageState();

  static void onAddSetting(
      {SettingsTabKey initialPage = SettingsTabKey.general}) {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelSettingPage,
          label: kTabLabelSettingPage,
          selectedIcon: Icons.build_sharp,
          unselectedIcon: Icons.build_outlined,
          page: DesktopSettingPage(
            key: const ValueKey(kTabLabelSettingPage),
            initialTabkey: initialPage,
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }

  static Future<void> showHome({int peerTabIndex = 0}) async {
    try {
      final controller = Get.find<DesktopTabController>();
      final index = controller.state.value.tabs
          .indexWhere((tab) => tab.key == kTabLabelHomePage);
      if (index >= 0) {
        controller.jumpTo(index);
      }
      await PeerTabPage.selectDesktopTab(peerTabIndex);
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopTabPageState extends State<DesktopTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _DesktopTabPageState() {
    RemoteCountState.init();
    Get.put<DesktopTabController>(tabController);
    tabController.add(TabInfo(
        key: kTabLabelHomePage,
        label: kTabLabelHomePage,
        selectedIcon: Icons.home_sharp,
        unselectedIcon: Icons.home_outlined,
        closable: false,
        page: DesktopHomePage(
          key: const ValueKey(kTabLabelHomePage),
          isClientOnly: isCustomClient,
        )));
    if (bind.isIncomingOnly() || isCustomClient) {
      tabController.onSelected = (key) {
        if (isCustomClient) {
          windowManager.setSize(kCustomClientWindowSize);
          setResizable(false);
          return;
        }
        if (key == kTabLabelHomePage) {
          windowManager.setSize(getIncomingOnlyHomeSize());
          setResizable(false);
        } else {
          windowManager.setSize(getIncomingOnlySettingsSize());
          setResizable(true);
        }
      };
    }
  }

  @override
  void initState() {
    super.initState();
    // HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /*
  bool _handleKeyEvent(KeyEvent event) {
    if (!mouseIn && event is KeyDownEvent) {
      print('key down: ${event.logicalKey}');
      shouldBeBlocked(_block, canBeBlocked);
    }
    return false; // allow it to propagate
  }
  */

  @override
  void dispose() {
    // HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    Get.delete<DesktopTabController>();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 客户端定制版只保留关闭按钮，不显示最小化和最大化。
    final bool compactClient = isCustomClient;
    final tabWidget = Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: DesktopTab(
              controller: tabController,
              topBarHeight: LDeskMainTitleBar.height,
              topBar: Obx(() {
                final state = tabController.state.value;
                final selected =
                    state.selected >= 0 && state.selected < state.tabs.length
                        ? state.selected
                        : 0;
                final key = state.tabs.isEmpty
                    ? kTabLabelHomePage
                    : state.tabs[selected].key;
                final title = key == kTabLabelSettingPage
                    ? translate('Settings')
                    : translate('Messages');
                return LDeskMainTitleBar(
                  title: title,
                  showThemeToggle: !compactClient,
                  showMinimize: !compactClient,
                  showMaximize: !compactClient,
                  showClose: true,
                  canMaximize:
                      !(bind.isIncomingOnly() && key == kTabLabelHomePage),
                  onBack: key == kTabLabelSettingPage
                      ? () => tabController.jumpToByKey(kTabLabelHomePage)
                      : null,
                );
              }),
              showMinimize: !compactClient,
              showMaximize: !compactClient,
              showClose: true,
            )));
    return isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => DragToResizeArea(
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: windowManagerEnableResizeEdges,
              child: tabWidget,
            ),
          );
  }
}
