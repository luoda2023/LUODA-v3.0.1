import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/shared_state.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/models/input_model.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:luoda_flutter/desktop/pages/remote_page.dart';
import 'package:luoda_flutter/desktop/widgets/remote_toolbar.dart';
import 'package:luoda_flutter/desktop/widgets/tabbar_widget.dart';
import 'package:luoda_flutter/desktop/widgets/material_mod_popup_menu.dart'
    as mod_menu;
import 'package:luoda_flutter/desktop/widgets/popup_menu.dart';
import 'package:luoda_flutter/utils/multi_window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:bot_toast/bot_toast.dart';

import '../../common/widgets/dialog.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';

class _MenuTheme {
  // kMinInteractiveDimension
  static const double height = 40.0;
  static const double dividerHeight = 12.0;
}

class ConnectionTabPage extends StatefulWidget {
  final Map<String, dynamic> params;

  const ConnectionTabPage({Key? key, required this.params}) : super(key: key);

  @override
  State<ConnectionTabPage> createState() => _ConnectionTabPageState(params);
}

class _ConnectionTabPageState extends State<ConnectionTabPage> {
  final tabController =
      Get.put(DesktopTabController(tabType: DesktopTabType.remoteScreen));
  final contentKey = UniqueKey();
  static const IconData selectedIcon = Icons.desktop_windows_sharp;
  static const IconData unselectedIcon = Icons.desktop_windows_outlined;

  String? peerId;
  bool _isScreenRectSet = false;
  int? _display;

  var connectionMap = RxList<Widget>.empty(growable: true);

  _ConnectionTabPageState(Map<String, dynamic> params) {
    RemoteCountState.init();
    peerId = params['id'];
    final sessionId = params['session_id'];
    final tabWindowId = params['tab_window_id'];
    final display = params['display'];
    final displays = params['displays'];
    final screenRect = parseParamScreenRect(params);
    _isScreenRectSet = screenRect != null;
    _display = display as int?;
    tryMoveToScreenAndSetFullscreen(screenRect);
    if (peerId != null) {
      ConnectionTypeState.init(peerId!);
      tabController.onSelected = (id) {
        final remotePage = tabController.widget(id);
        if (remotePage is RemotePage) {
          final ffi = remotePage.ffi;
          bind.setCurSessionId(sessionId: ffi.sessionId);
        }
        WindowController.fromWindowId(params['windowId'])
            .setTitle(getWindowNameWithId(id));
        UnreadChatCountState.find(id).value = 0;
      };
      tabController.add(TabInfo(
        key: peerId!,
        label: peerId!,
        selectedIcon: selectedIcon,
        unselectedIcon: unselectedIcon,
        onTabCloseButton: () async {
          if (await desktopTryShowTabAuditDialogCloseCancelled(
            id: peerId!,
            tabController: tabController,
          )) {
            return;
          }
          tabController.closeBy(peerId!);
        },
        page: RemotePage(
          key: ValueKey(peerId),
          id: peerId!,
          sessionId: sessionId == null ? null : SessionID(sessionId),
          tabWindowId: tabWindowId,
          display: display,
          displays: displays?.cast<int>(),
          password: params['password'],
          toolbarState: ToolbarState(),
          tabController: tabController,
          switchUuid: params['switch_uuid'],
          forceRelay: params['forceRelay'],
          isSharedPassword: params['isSharedPassword'],
          viewerToken: params['viewerToken'],
          viewerId: params['viewerId'],
          viewerDisplayName: params['viewerDisplayName'],
        ),
      ));
      _update_remote_count();
    }
    tabController.onRemoved = (_, id) => onRemoveId(id);
    luodaWinManager.setMethodHandler(_remoteMethodHandler);
  }

  @override
  void initState() {
    super.initState();

    if (!_isScreenRectSet) {
      Future.delayed(Duration.zero, () {
        restoreWindowPosition(
          WindowType.RemoteDesktop,
          windowId: windowId(),
          peerId: tabController.state.value.tabs.isEmpty
              ? null
              : tabController.state.value.tabs[0].key,
          display: _display,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const chrome = Color(0xFF20232A);
    const chromeRaised = Color(0xFF282C34);
    final remoteTheme = theme.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF11151C),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF07C160),
        surface: chromeRaised,
        background: Color(0xFF11151C),
        onSurface: Color(0xFFF2F3F5),
      ),
      dividerColor: const Color(0xFF383D47),
    );
    final child = Theme(
      data: remoteTheme,
      child: Scaffold(
        backgroundColor: remoteTheme.colorScheme.background,
        body: DesktopTab(
          controller: tabController,
          onWindowCloseButton: handleWindowCloseButton,
          topBarHeight: 42,
          topBar: _RemoteWindowTitleBar(
            controller: tabController,
            windowId: windowId(),
            onCloseWindow: _closeRemoteWindow,
            menuBuilder: _tabMenuBuilder,
          ),
          selectedBorderColor: remoteTheme.colorScheme.primary,
          selectedTabBackgroundColor: chromeRaised,
          unSelectedTabBackgroundColor: chrome,
          pageViewBuilder: (pageView) => pageView,
          labelGetter: DesktopTab.tablabelGetter,
          tabBuilder: (key, icon, label, themeConf) => Obx(() {
            final connectionType = ConnectionTypeState.find(key);
            if (!connectionType.isValid()) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  label,
                ],
              );
            } else {
              bool secure =
                  connectionType.secure.value == ConnectionType.strSecure;
              bool direct =
                  connectionType.direct.value == ConnectionType.strDirect;
              String msgConn = getConnectionText(
                  secure, direct, connectionType.stream_type.value);
              var msgFingerprint = '${translate('Fingerprint')}:\n';
              var fingerprint = FingerprintState.find(key).value;
              if (fingerprint.isEmpty) {
                fingerprint = 'N/A';
              }
              if (fingerprint.length > 5 * 8) {
                var first = fingerprint.substring(0, 39);
                var second = fingerprint.substring(40);
                msgFingerprint += '$first\n$second';
              } else {
                msgFingerprint += fingerprint;
              }

              final tab = Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  Tooltip(
                    message: '$msgConn\n$msgFingerprint',
                    child: SvgPicture.asset(
                      'assets/${connectionType.secure.value}${connectionType.direct.value}.svg',
                      width: themeConf.iconSize,
                      height: themeConf.iconSize,
                    ).paddingOnly(right: 5),
                  ),
                  label,
                  unreadMessageCountBuilder(UnreadChatCountState.find(key))
                      .marginOnly(left: 4),
                ],
              );

              return Listener(
                onPointerDown: (e) {
                  if (e.kind != ui.PointerDeviceKind.mouse) {
                    return;
                  }
                  final remotePage = tabController.state.value.tabs
                      .firstWhere((tab) => tab.key == key)
                      .page as RemotePage;
                  if (remotePage.ffi.ffiModel.pi.isSet.isTrue &&
                      e.buttons == 2) {
                    showRightMenu(
                      (CancelFunc cancelFunc) {
                        return _tabMenuBuilder(key, cancelFunc);
                      },
                      target: e.position,
                    );
                  }
                },
                child: tab,
              );
            }
          }),
        ),
      ),
    );
    final tabWidget = isLinux
        ? buildVirtualWindowFrame(context, child)
        : workaroundWindowBorder(
            context,
            Obx(() => Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: MyTheme.color(context).border!,
                        width: stateGlobal.windowBorderWidth.value),
                  ),
                  child: child,
                )));
    return isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(() => SubWindowDragToResizeArea(
              key: contentKey,
              child: tabWidget,
              // Specially configured for a better resize area and remote control.
              childPadding: kDragToResizeAreaPadding,
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: subWindowManagerEnableResizeEdges,
              windowId: stateGlobal.windowId,
            ));
  }

  Future<void> _closeRemoteWindow() async {
    if (!await handleWindowCloseButton()) return;
    await WindowController.fromWindowId(windowId()).close();
  }

  // Note: Some dup code to ../widgets/remote_toolbar
  Widget _tabMenuBuilder(String key, CancelFunc cancelFunc) {
    final List<MenuEntryBase<String>> menu = [];
    const EdgeInsets padding = EdgeInsets.only(left: 8.0, right: 5.0);
    final remotePage = tabController.state.value.tabs
        .firstWhere((tab) => tab.key == key)
        .page as RemotePage;
    final ffi = remotePage.ffi;
    final pi = ffi.ffiModel.pi;
    final perms = ffi.ffiModel.permissions;
    final sessionId = ffi.sessionId;
    final toolbarState = remotePage.toolbarState;
    menu.addAll([
      MenuEntryButton<String>(
        childBuilder: (TextStyle? style) => Obx(() => Text(
              translate(
                  toolbarState.hide.isTrue ? 'Show Toolbar' : 'Hide Toolbar'),
              style: style,
            )),
        proc: () {
          toolbarState.switchHide(sessionId);
          cancelFunc();
        },
        padding: padding,
      ),
    ]);

    if (tabController.state.value.tabs.length > 1) {
      final splitAction = MenuEntryButton<String>(
        childBuilder: (TextStyle? style) => Text(
          translate('Move tab to new window'),
          style: style,
        ),
        proc: () async {
          await DesktopMultiWindow.invokeMethod(
              kMainWindowId,
              kWindowEventMoveTabToNewWindow,
              '${windowId()},$key,$sessionId,RemoteDesktop');
          cancelFunc();
        },
        padding: padding,
      );
      menu.insert(1, splitAction);
    }

    if (perms['restart'] != false &&
        (pi.platform == kPeerPlatformLinux ||
            pi.platform == kPeerPlatformWindows ||
            pi.platform == kPeerPlatformMacOS)) {
      menu.add(MenuEntryButton<String>(
        childBuilder: (TextStyle? style) => Text(
          translate('Restart remote device'),
          style: style,
        ),
        proc: () => showRestartRemoteDevice(
            pi, peerId ?? '', sessionId, ffi.dialogManager),
        padding: padding,
        dismissOnClicked: true,
        dismissCallback: cancelFunc,
      ));
    }

    if (perms['keyboard'] != false && !ffi.ffiModel.viewOnly) {
      menu.add(RemoteMenuEntry.insertLock(sessionId, padding,
          dismissFunc: cancelFunc));

      if (pi.platform == kPeerPlatformLinux || pi.sasEnabled) {
        menu.add(RemoteMenuEntry.insertCtrlAltDel(sessionId, padding,
            dismissFunc: cancelFunc));
      }
    }

    menu.addAll([
      MenuEntryDivider<String>(),
      MenuEntryButton<String>(
        childBuilder: (TextStyle? style) => Text(
          translate('Copy Fingerprint'),
          style: style,
        ),
        proc: () => onCopyFingerprint(FingerprintState.find(key).value),
        padding: padding,
        dismissOnClicked: true,
        dismissCallback: cancelFunc,
      ),
      MenuEntryButton<String>(
        childBuilder: (TextStyle? style) => Text(
          translate('Close'),
          style: style,
        ),
        proc: () async {
          if (await desktopTryShowTabAuditDialogCloseCancelled(
            id: key,
            tabController: tabController,
          )) {
            return;
          }
          tabController.closeBy(key);
          cancelFunc();
        },
        padding: padding,
      )
    ]);

    return mod_menu.PopupMenu<String>(
      items: menu
          .map((entry) => entry.build(
              context,
              MenuConfig(
                commonColor: Theme.of(context).colorScheme.primary,
                height: _MenuTheme.height,
                dividerHeight: _MenuTheme.dividerHeight,
              )))
          .expand((i) => i)
          .toList(),
    );
  }

  void onRemoveId(String id) async {
    if (tabController.state.value.tabs.isEmpty) {
      // Keep calling until the window status is hidden.
      //
      // Workaround for Windows:
      // If you click other buttons and close in msgbox within a very short period of time, the close may fail.
      // `await WindowController.fromWindowId(windowId()).close();`.
      Future<void> loopCloseWindow() async {
        int c = 0;
        final windowController = WindowController.fromWindowId(windowId());
        while (c < 20 &&
            tabController.state.value.tabs.isEmpty &&
            (!await windowController.isHidden())) {
          await windowController.close();
          await Future.delayed(Duration(milliseconds: 100));
          c++;
        }
      }

      loopCloseWindow();
    }
    ConnectionTypeState.delete(id);
    // Clean up relative mouse mode state for this peer.
    stateGlobal.relativeMouseModeState.remove(id);
    _update_remote_count();
  }

  int windowId() {
    return widget.params["windowId"];
  }

  Future<bool> handleWindowCloseButton() async {
    final connLength = tabController.length;
    if (connLength == 1) {
      if (await desktopTryShowTabAuditDialogCloseCancelled(
        id: tabController.state.value.tabs[0].key,
        tabController: tabController,
      )) {
        return false;
      }
    }
    if (connLength <= 1) {
      tabController.clear();
      return true;
    } else {
      final bool res;
      if (!option2bool(kOptionEnableConfirmClosingTabs,
          bind.mainGetLocalOption(key: kOptionEnableConfirmClosingTabs))) {
        res = true;
      } else {
        res = await closeConfirmDialog();
      }
      if (res) {
        tabController.clear();
      }
      return res;
    }
  }

  _update_remote_count() =>
      RemoteCountState.find().value = tabController.length;

  Future<dynamic> _remoteMethodHandler(call, fromWindowId) async {
    debugPrint(
        "[Remote Page] call ${call.method} with args ${call.arguments} from window $fromWindowId");

    dynamic returnValue;
    // for simplify, just replace connectionId
    if (call.method == kWindowEventNewRemoteDesktop) {
      final args = jsonDecode(call.arguments);
      final id = args['id'];
      final switchUuid = args['switch_uuid'];
      final sessionId = args['session_id'];
      final tabWindowId = args['tab_window_id'];
      final display = args['display'];
      final displays = args['displays'];
      final screenRect = parseParamScreenRect(args);
      final prePeerCount = tabController.length;
      Future.delayed(Duration.zero, () async {
        if (stateGlobal.fullscreen.isTrue) {
          await WindowController.fromWindowId(windowId()).setFullscreen(false);
          stateGlobal.setFullscreen(false, procWnd: false);
        }
        await setNewConnectWindowFrame(windowId(), id!, prePeerCount,
            WindowType.RemoteDesktop, display, screenRect);
        Future.delayed(Duration(milliseconds: isWindows ? 100 : 0), () async {
          await windowOnTop(windowId());
        });
      });
      ConnectionTypeState.init(id);
      tabController.add(TabInfo(
        key: id,
        label: id,
        selectedIcon: selectedIcon,
        unselectedIcon: unselectedIcon,
        onTabCloseButton: () async {
          if (await desktopTryShowTabAuditDialogCloseCancelled(
            id: id,
            tabController: tabController,
          )) {
            return;
          }
          tabController.closeBy(id);
        },
        page: RemotePage(
          key: ValueKey(id),
          id: id,
          sessionId: sessionId == null ? null : SessionID(sessionId),
          tabWindowId: tabWindowId,
          display: display,
          displays: displays?.cast<int>(),
          password: args['password'],
          toolbarState: ToolbarState(),
          tabController: tabController,
          switchUuid: switchUuid,
          forceRelay: args['forceRelay'],
          isSharedPassword: args['isSharedPassword'],
          viewerToken: args['viewerToken'],
          viewerId: args['viewerId'],
          viewerDisplayName: args['viewerDisplayName'],
        ),
      ));
    } else if (call.method == kWindowDisableGrabKeyboard) {
      // ???
    } else if (call.method == "onDestroy") {
      tabController.clear();
    } else if (call.method == kWindowActionRebuild) {
      reloadCurrentWindow();
    } else if (call.method == kWindowEventActiveSession) {
      final jumpOk = tabController.jumpToByKey(call.arguments);
      if (jumpOk) {
        windowOnTop(windowId());
      }
      return jumpOk;
    } else if (call.method == kWindowEventActiveDisplaySession) {
      final args = jsonDecode(call.arguments);
      final id = args['id'];
      final display = args['display'];
      final jumpOk = tabController.jumpToByKeyAndDisplay(id, display);
      if (jumpOk) {
        windowOnTop(windowId());
      }
      return jumpOk;
    } else if (call.method == kWindowEventGetRemoteList) {
      return tabController.state.value.tabs
          .map((e) => e.key)
          .toList()
          .join(',');
    } else if (call.method == kWindowEventGetSessionIdList) {
      return tabController.state.value.tabs
          .map((e) => '${e.key},${(e.page as RemotePage).ffi.sessionId}')
          .toList()
          .join(';');
    } else if (call.method == kWindowEventGetCachedSessionData) {
      // Ready to show new window and close old tab.
      final args = jsonDecode(call.arguments);
      final id = args['id'];
      final close = args['close'];
      try {
        final remotePage = tabController.state.value.tabs
            .firstWhere((tab) => tab.key == id)
            .page as RemotePage;
        returnValue = remotePage.ffi.ffiModel.cachedPeerData.toString();
      } catch (e) {
        debugPrint('Failed to get cached session data: $e');
      }
      if (close && returnValue != null) {
        closeSessionOnDispose[id] = false;
        tabController.closeBy(id);
      }
    } else if (call.method == kWindowEventRemoteWindowCoords) {
      final remotePage =
          tabController.state.value.selectedTabInfo.page as RemotePage;
      final ffi = remotePage.ffi;
      final displayRect = ffi.ffiModel.displaysRect();
      if (displayRect != null) {
        final wc = WindowController.fromWindowId(windowId());
        Rect? frame;
        try {
          frame = await wc.getFrame();
        } catch (e) {
          debugPrint(
              "Failed to get frame of window $windowId, it may be hidden");
        }
        if (frame != null) {
          ffi.cursorModel.moveLocal(0, 0);
          final coords = RemoteWindowCoords(
              frame,
              CanvasCoords.fromCanvasModel(ffi.canvasModel),
              CursorCoords.fromCursorModel(ffi.cursorModel),
              displayRect);
          returnValue = jsonEncode(coords.toJson());
        }
      }
    } else if (call.method == kWindowEventSetFullscreen) {
      stateGlobal.setFullscreen(call.arguments == 'true');
    }
    _update_remote_count();
    return returnValue;
  }
}

class _RemoteWindowTitleBar extends StatefulWidget {
  final DesktopTabController controller;
  final int windowId;
  final Future<void> Function() onCloseWindow;
  final Widget Function(String, CancelFunc) menuBuilder;

  const _RemoteWindowTitleBar({
    required this.controller,
    required this.windowId,
    required this.onCloseWindow,
    required this.menuBuilder,
  });

  @override
  State<_RemoteWindowTitleBar> createState() => _RemoteWindowTitleBarState();
}

class _RemoteWindowTitleBarState extends State<_RemoteWindowTitleBar> {
  bool _retryScheduled = false;

  void _retryAfterRemotePageMounts() {
    if (_retryScheduled) return;
    _retryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryScheduled = false;
      if (mounted) setState(() {});
    });
  }

  FFI? _selectedFfi(RemotePage page) {
    try {
      return page.ffi;
    } catch (_) {
      _retryAfterRemotePageMounts();
      return null;
    }
  }

  String _resolution(FFI ffi) {
    final pi = ffi.ffiModel.pi;
    final display = pi.currentDisplay;
    if (display == kAllDisplayValue) return translate('Select Monitor');
    if (display < 0 || display >= pi.displays.length) return '-';
    final current = pi.displays[display];
    return '${current.width}x${current.height}';
  }

  Future<void> _returnToConversation(String peerId) async {
    await luodaWinManager.call(
      WindowType.Main,
      kWindowEventOpenDirectChat,
      {'id': peerId},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF20232A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF343944), width: 1),
        ),
      ),
      child: Obx(() {
        final state = widget.controller.state.value;
        if (state.tabs.isEmpty || state.selected >= state.tabs.length) {
          return const SizedBox.shrink();
        }
        final tab = state.selectedTabInfo;
        final peerId = tab.key;
        final remotePage = tab.page as RemotePage;
        final ffi = _selectedFfi(remotePage);
        final title = DesktopTab.tablabelGetter(peerId).value;

        return Row(
          children: [
            if (isMacOS && !kUseCompatibleUiMode) const SizedBox(width: 78),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) =>
                    WindowController.fromWindowId(widget.windowId)
                        .startDragging(),
                onDoubleTap: () => toggleMaximize(false),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: ffi?.ffiModel.pi.isSet.isTrue == true
                            ? const Color(0xFF07C160)
                            : const Color(0xFFF0A020),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        '${translate('Remote Desktop')} - $title',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF2F3F5),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Obx(() {
                      final connectionType = ConnectionTypeState.find(peerId);
                      if (!connectionType.isValid()) {
                        return const SizedBox.shrink();
                      }
                      final secure = connectionType.secure.value ==
                          ConnectionType.strSecure;
                      final direct = connectionType.direct.value ==
                          ConnectionType.strDirect;
                      var streamType = connectionType.stream_type.value;
                      if (streamType == 'Relay') streamType = 'TCP';
                      final route = translate(direct ? 'Direct' : 'Relay');
                      final label =
                          streamType.isEmpty ? route : '$route / $streamType';
                      final color = direct
                          ? const Color(0xFF39D477)
                          : const Color(0xFFF0A020);
                      return Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Tooltip(
                          message: getConnectionText(
                            secure,
                            direct,
                            streamType,
                          ),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 132),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: color.withOpacity(0.48),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.link_rounded,
                                    size: 13, color: color),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    if (ffi != null && MediaQuery.sizeOf(context).width >= 900)
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          ffi.ffiModel,
                          ffi.qualityMonitorModel,
                        ]),
                        builder: (context, _) {
                          final data = ffi.qualityMonitorModel.data;
                          final delay =
                              data.delay == null ? '-' : '${data.delay}ms';
                          return Row(
                            children: [
                              const SizedBox(width: 22),
                              _RemoteTelemetryText(
                                label: translate('Delay'),
                                value: delay,
                              ),
                              _RemoteTelemetryText(
                                label: translate('Speed'),
                                value: data.speed ?? '-',
                              ),
                              _RemoteTelemetryText(
                                label: translate('Display'),
                                value: _resolution(ffi),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            _RelativeMouseModeHint(tabController: widget.controller),
            if (state.tabs.length > 1)
              PopupMenuButton<String>(
                tooltip: translate('Sessions'),
                onSelected: (id) => widget.controller.jumpToByKey(id),
                color: const Color(0xFF282C34),
                itemBuilder: (context) => state.tabs
                    .map((item) => PopupMenuItem<String>(
                          value: item.key,
                          child: Text(
                            DesktopTab.tablabelGetter(item.key).value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.layers_outlined, size: 16),
                      const SizedBox(width: 5),
                      Text('${state.tabs.length}'),
                    ],
                  ),
                ),
              ),
            _RemoteTitleAction(
              tooltip: 'Back to chat',
              icon: Icons.chat_bubble_outline_rounded,
              onTap: () => _returnToConversation(peerId),
            ),
            _RemoteTitleAction(
              tooltip: 'New Connection',
              icon: Icons.add_rounded,
              onTap: () => luodaWinManager.call(
                WindowType.Main,
                kWindowMainWindowOnTop,
                '',
              ),
            ),
            _RemoteTitleAction(
              tooltip: 'More',
              icon: Icons.more_horiz_rounded,
              onTapDown: (details) => showRightMenu(
                (cancel) => widget.menuBuilder(peerId, cancel),
                target: details.globalPosition,
              ),
            ),
            if (!isMacOS && !kUseCompatibleUiMode) ...[
              _RemoteTitleAction(
                tooltip: 'Minimize',
                icon: Icons.remove_rounded,
                onTap: () =>
                    WindowController.fromWindowId(widget.windowId).minimize(),
              ),
              Obx(() => _RemoteTitleAction(
                    tooltip:
                        stateGlobal.isMaximized.isTrue ? 'Restore' : 'Maximize',
                    icon: stateGlobal.isMaximized.isTrue
                        ? Icons.filter_none_rounded
                        : Icons.crop_square_rounded,
                    onTap: () => toggleMaximize(false),
                  )),
              _RemoteTitleAction(
                tooltip: 'Close',
                icon: Icons.close_rounded,
                isClose: true,
                onTap: widget.onCloseWindow,
              ),
            ],
          ],
        );
      }),
    );
  }
}

class _RemoteTelemetryText extends StatelessWidget {
  final String label;
  final String value;

  const _RemoteTelemetryText({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Text.rich(
        TextSpan(
          text: '$label ',
          style: const TextStyle(color: Color(0xFF9299A6), fontSize: 11),
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Color(0xFFDDE1E7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        maxLines: 1,
      ),
    );
  }
}

class _RemoteTitleAction extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final bool isClose;

  const _RemoteTitleAction({
    required this.tooltip,
    required this.icon,
    this.onTap,
    this.onTapDown,
    this.isClose = false,
  });

  @override
  State<_RemoteTitleAction> createState() => _RemoteTitleActionState();
}

class _RemoteTitleActionState extends State<_RemoteTitleAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final background = !_hovered
        ? Colors.transparent
        : widget.isClose
            ? const Color(0xFFC42B1C)
            : const Color(0xFF343944);
    return Tooltip(
      message: translate(widget.tooltip),
      child: InkWell(
        onHover: (value) => setState(() => _hovered = value),
        onTap: widget.onTap,
        onTapDown: widget.onTapDown,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 41,
          alignment: Alignment.center,
          color: background,
          child: Icon(
            widget.icon,
            size: 17,
            color: const Color(0xFFDDE1E7),
          ),
        ),
      ),
    );
  }
}

/// A widget that displays a hint in the tab bar when relative mouse mode is active.
/// This helps users remember how to exit relative mouse mode.
class _RelativeMouseModeHint extends StatelessWidget {
  final DesktopTabController tabController;

  const _RelativeMouseModeHint({Key? key, required this.tabController})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Check if there are any tabs
      if (tabController.state.value.tabs.isEmpty) {
        return const SizedBox.shrink();
      }

      // Get current selected tab's RemotePage
      final selectedTabInfo = tabController.state.value.selectedTabInfo;
      if (selectedTabInfo.page is! RemotePage) {
        return const SizedBox.shrink();
      }

      final remotePage = selectedTabInfo.page as RemotePage;
      final String peerId = remotePage.id;

      // Use global state to check relative mouse mode (synced from InputModel).
      // This avoids timing issues with FFI registration.
      final isRelativeMouseMode =
          stateGlobal.relativeMouseModeState[peerId] ?? false;

      if (!isRelativeMouseMode) {
        return const SizedBox.shrink();
      }

      final isDark = Theme.of(context).brightness == Brightness.dark;
      final warningForeground =
          isDark ? const Color(0xFFFFC46B) : const Color(0xFF8A4B00);
      final warningBackground =
          isDark ? const Color(0xFF3A2B19) : const Color(0xFFFFF4E5);
      final warningBorder =
          isDark ? const Color(0xFF76552B) : const Color(0xFFF3C27B);

      return Container(
        constraints: const BoxConstraints(minHeight: 32, maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: warningBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: warningBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mouse_outlined,
              size: 16,
              color: warningForeground,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                translate(
                    'rel-mouse-exit-{${isMacOS ? "Cmd+G" : "Ctrl+Alt"}}-tip'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: warningForeground,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
