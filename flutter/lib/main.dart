import 'runtime_logger.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common/widgets/overlay.dart';
import 'package:luoda_flutter/desktop/pages/desktop_tab_page.dart';
import 'package:luoda_flutter/desktop/pages/install_page.dart';
import 'package:luoda_flutter/desktop/pages/server_page.dart';
import 'package:luoda_flutter/desktop/screen/desktop_file_transfer_screen.dart';
import 'package:luoda_flutter/desktop/screen/desktop_view_camera_screen.dart';
import 'package:luoda_flutter/desktop/screen/desktop_port_forward_screen.dart';
import 'package:luoda_flutter/desktop/screen/desktop_remote_screen.dart';
import 'package:luoda_flutter/desktop/screen/desktop_terminal_screen.dart';
import 'package:luoda_flutter/desktop/pages/file_preview_page.dart';
import 'package:luoda_flutter/desktop/widgets/refresh_wrapper.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/chat_notifier.dart';
import 'package:luoda_flutter/common/bt_service.dart';
import 'package:luoda_flutter/common/relay_bridge.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:luoda_flutter/models/ai_config_model.dart';
import 'package:luoda_flutter/utils/multi_window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'common.dart';
import 'common/sqflite_init.dart';
import 'consts.dart';
import 'mobile/pages/home_page.dart';
import 'mobile/pages/server_page.dart';
import 'models/chat_model.dart';
import 'models/platform_model.dart';

import 'package:luoda_flutter/plugin/handlers.dart'
    if (dart.library.html) 'package:luoda_flutter/web/plugin/handlers.dart';

/// Basic window and launch properties.
int? kWindowId;
WindowType? kWindowType;
late List<String> kBootArgs;

Future<void> main(List<String> args) async {
 earlyAssert();
 WidgetsFlutterBinding.ensureInitialized();
 // Initialize the SQLite database factory for the current platform.
 // Desktop (Windows/Linux) uses sqflite_common_ffi (dart:ffi + native
 // SQLite C library — same approach as WeChat's WCDB). Mobile uses the
 // native sqflite plugin. The conditional import picks the right one.
 await initSqfliteForPlatform();
 // 限制图片解码缓存：聊天软件高频收发图片，Flutter 默认 1000 张会持续
 // 吃内存。200 张 + 80MB 足够滚动回看，又能避免长时间运行内存膨胀。
 PaintingBinding.instance.imageCache.maximumSize = 200;
 PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20;
 await RuntimeLogger.instance.init();
  RuntimeLogger.instance.installErrorHooks();
  RuntimeLogger.instance.info('BOOT', 'Launch arguments: $args');

  debugPrint("launch args: $args");
  kBootArgs = List.from(args);

  if (!isDesktop) {
    runMobileApp();
    return;
  }
// main window
if (args.isNotEmpty && args.first == 'multi_window') {
 kWindowId = int.parse(args[1]);
 stateGlobal.setWindowId(kWindowId!);
 final argument = args[2].isEmpty
 ? <String, dynamic>{}
 : jsonDecode(args[2]) as Map<String, dynamic>;
 int type = argument['type'] ?? -1;
 // to-do: No need to parse window id ?
 // Because stateGlobal.windowId is a global value.
 argument['windowId'] = kWindowId;
 kWindowType = type.windowType;
 // File preview windows keep the native OS title bar so the user can
 // drag, resize, maximize, minimize, and close via standard window
 // chrome. Session windows hide the title bar and use a custom one.
 if (!isMacOS && kWindowType != WindowType.FilePreview) {
 WindowController.fromWindowId(kWindowId!).showTitleBar(false);
 }
 switch (kWindowType) {
      case WindowType.RemoteDesktop:
        desktopType = DesktopType.remote;
        runMultiWindow(
          argument,
          kAppTypeDesktopRemote,
        );
        break;
      case WindowType.FileTransfer:
        desktopType = DesktopType.fileTransfer;
        runMultiWindow(
          argument,
          kAppTypeDesktopFileTransfer,
        );
        break;
      case WindowType.ViewCamera:
        desktopType = DesktopType.viewCamera;
        runMultiWindow(
          argument,
          kAppTypeDesktopViewCamera,
        );
        break;
      case WindowType.PortForward:
        desktopType = DesktopType.portForward;
        runMultiWindow(
          argument,
          kAppTypeDesktopPortForward,
        );
        break;
      case WindowType.Terminal:
        desktopType = DesktopType.terminal;
        runMultiWindow(
          argument,
          kAppTypeDesktopTerminal,
        );
        break;
      case WindowType.FilePreview:
        runMultiWindow(
          argument,
          kAppTypeDesktopFilePreview,
        );
        break;
      default:
        break;
    }
  } else if (args.isNotEmpty && args.first == '--cm') {
    debugPrint("--cm started");
    desktopType = DesktopType.cm;
    await windowManager.ensureInitialized();
    runConnectionManagerScreen();
  } else if (args.contains('--install')) {
    runInstallPage();
  } else {
    desktopType = DesktopType.main;
    await windowManager.ensureInitialized();
    windowManager.setPreventClose(true);
    if (isMacOS) {
      disableWindowMovable(kWindowId);
    }
    runMainApp(true);
  }
}

/// 把 ChatModel 的收发能力注入蓝牙中继桥（PC/手机共用）。
void _wireRelayBridge() {
  RelayBridge.wire(
    myIdProvider: () => gFFI.chatModel.me.id,
    receive: (envelopeLine, {conversationId}) =>
        gFFI.chatModel.receiveRelayedEnvelope(
      envelopeLine,
      conversationId: conversationId,
    ),
    sendWire: (peerId, envelopeLine) =>
        gFFI.chatModel.sendWireRelayed(peerId, envelopeLine),
  );
}

/// 把本机蓝牙名广播为 `LD:<昵称>:<ID>`，让安装了点聊的设备之间才能
/// 互相被发现（扫描端只显示带 LD: 前缀的点聊设备）。
///
/// 启动早期本机 ID / 昵称可能还没就绪（服务器还没返回），所以带重试：
/// 每 3 秒尝试一次，直到成功或到达上限。
void _advertiseBluetoothIdentity() {
  const int maxAttempts = 10;
  Future<void> attempt(int round) async {
    if (round > maxAttempts) return;
    try {
      final id = (await bind.mainGetMyId()).trim();
      var nick = gFFI.userModel.displayNameOrUserName.trim();
      // 昵称还没就绪时用 ID 兜底，保证蓝牙广播名始终是 LD:<昵称>:<ID>。
      if (nick.isEmpty) nick = id;
      if (id.isNotEmpty) {
        await BluetoothService.instance.setAdvertisedName(nick, id);
        return;
      }
    } catch (error) {
      debugPrint('advertise bluetooth identity failed: $error');
    }
    // 身份或调用失败：稍后重试（启动早期 ID/昵称可能还没就绪）。
    Future<void>.delayed(const Duration(seconds: 3), () => attempt(round + 1));
  }

  Future<void>.delayed(const Duration(seconds: 2), () => attempt(0));
}

Future<void> initEnv(String appType) async {
  // global shared preference
  await platformFFI.init(appType);
  // global FFI, use this **ONLY** for global configuration
  // for convenience, use global FFI on mobile platform
  // focus on multi-ffi on desktop first
  await initGlobalFFI();
  // await Firebase.initializeApp();
  _registerEventHandler();
  // Update the system theme.
  updateSystemWindowTheme();
}

void runMainApp(bool startService) async {
  // register uni links
  await initEnv(kAppTypeMain);
  // checkUpdate(); // disabled: no auto update
  // trigger connection status updater
  unawaited(bind.mainCheckConnectStatus());
  if (startService) {
    gFFI.serverModel.startService();
    bind.pluginSyncUi(syncTo: kAppTypeMain);
    bind.pluginListReload();
  }
  // LUODA: enable the classic Bluetooth (RFCOMM) bridge on Windows PC too,
  // so bt:<mac> conversations work on both PC and phone. The native bridge
  // is registered in the Windows runner (bt_windows.cpp) at startup.
  if (isWindows) {
    unawaited(BluetoothService.instance.init());
    _wireRelayBridge();
  }
  await Future.wait([gFFI.abModel.loadCache(), gFFI.groupModel.loadCache()]);
  gFFI.userModel.refreshCurrentUser();
  _advertiseBluetoothIdentity();
  runApp(App());

  bool? alwaysOnTop;
  if (isDesktop) {
    alwaysOnTop =
        bind.mainGetBuildinOption(key: "main-window-always-on-top") == 'Y';
  }

  // Set window option.
  WindowOptions windowOptions = getHiddenTitleBarWindowOptions(
      isMainWindow: true, alwaysOnTop: alwaysOnTop);
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (bind.isCustomClient()) {
      await windowManager.setMinimumSize(kCustomClientWindowSize);
      await windowManager.setMaximumSize(kCustomClientWindowSize);
      await windowManager.setSize(kCustomClientWindowSize);
    } else if (!bind.isIncomingOnly()) {
      await windowManager.setMinimumSize(const Size(900, 600));
    }
    // Restore the location of the main window before window hide or show.
    await restoreWindowPosition(WindowType.Main);
    // Check the startup argument, if we successfully handle the argument, we keep the main window hidden.
    final handledByUniLinks = await initUniLinks();
    debugPrint("handled by uni links: $handledByUniLinks");
    if (handledByUniLinks || handleUriLink(cmdArgs: kBootArgs)) {
      windowManager.hide();
    } else {
      // LUODA FIX: wait for the first frame to paint before showing the
      // window, so the OS default black background never flashes.
      await WidgetsBinding.instance.endOfFrame;
      windowManager.show();
      windowManager.focus();
      // Move registration of active main window here to prevent from async visible check.
      luodaWinManager.registerActiveWindow(kWindowMainId);
    }
    windowManager.setOpacity(1);
    windowManager.setTitle(getWindowName());
    // Do not use `windowManager.setResizable()` here.
    setResizable(!bind.isIncomingOnly() && !bind.isCustomClient());
  });
}

void runMobileApp() async {
 await initEnv(kAppTypeMain);
 // LUODA: Enable edge-to-edge layout (WeChat-style): the app's
 // background extends to the very top of the screen, covering the
 // area behind the system status bar. The AppBarTheme in common.dart
 // sets a transparent status bar so icons (time, battery) are drawn
 // over the app's own background color.
 if (isAndroid || isIOS) {
 await SystemChrome.setEnabledSystemUIMode(
 SystemUiMode.edgeToEdge,
 );
 }
  // checkUpdate(); // disabled: no auto update
  if (isAndroid) androidChannelInit();
  if (isAndroid) platformFFI.syncAndroidServiceAppDirConfigPath();
  if (isAndroid) unawaited(applyStableAndroidDeviceId());
  // LUODA: register the Bluetooth wire sink so bt:<mac> conversations are
  // routed over the RFCOMM link app-wide.
  if (isAndroid) {
    unawaited(BluetoothService.instance.init());
    _wireRelayBridge();
  }
  draggablePositions.load();
  await Future.wait([gFFI.abModel.loadCache(), gFFI.groupModel.loadCache()]);
  gFFI.userModel.refreshCurrentUser();
  // 手机端消息横幅通知（微信式）
  unawaited(ChatNotifier.instance.init());
  _advertiseBluetoothIdentity();
  runApp(App());
  await initUniLinks();
  if (isAndroid) {
    // LUODA: once the user has authorized the service once, auto-start it on
    // every launch so no manual toggle is needed.
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      unawaited(gFFI.serverModel.maybeAutoStartService());
    });
  }
}

void runMultiWindow(
  Map<String, dynamic> argument,
  String appType,
) async {
  // File preview sub-windows only display local files via Image.file and
  // do not need the full Rust backend (service, event listeners, device
  // registration). But runMultiWindow calls MyTheme.currentThemeMode() and
  // getWindowName(), both of which call bind.*Sync() and crash with
  // LateInitializationError on _ffiBind when it has not been initialized.
  // initBindOnly loads the dylib and sets _ffiBind without starting any
  // background tasks, so the sub-window stays isolated from the main process.
  if (appType == kAppTypeDesktopFilePreview) {
    await platformFFI.initBindOnly(appType);
  } else {
    await initEnv(appType);
  }
  final title = getWindowName();
  // Session windows intercept close for confirmation. A preview has no session
  // state, so its native and toolbar close actions should close immediately.
  await WindowController.fromWindowId(kWindowId!).setPreventClose(
    appType != kAppTypeDesktopFilePreview,
  );
  if (isMacOS) {
    disableWindowMovable(kWindowId);
  }
  late Widget widget;
  switch (appType) {
    case kAppTypeDesktopRemote:
      draggablePositions.load();
      widget = DesktopRemoteScreen(
        params: argument,
      );
      break;
    case kAppTypeDesktopFileTransfer:
      widget = DesktopFileTransferScreen(
        params: argument,
      );
      break;
    case kAppTypeDesktopViewCamera:
      draggablePositions.load();
      widget = DesktopViewCameraScreen(
        params: argument,
      );
      break;
    case kAppTypeDesktopPortForward:
      widget = DesktopPortForwardScreen(
        params: argument,
      );
      break;
    case kAppTypeDesktopTerminal:
      widget = DesktopTerminalScreen(
        params: argument,
      );
      break;
    case kAppTypeDesktopFilePreview:
      widget = FilePreviewPage(
        windowId: argument['windowId'] as int? ?? kWindowId!,
        filePath: argument['file_path'] ?? '',
        fileName: argument['file_name'] ?? '',
        siblingPaths: argument['sibling_paths']?.cast<String>(),
      );
      break;
    default:
      // no such appType
      exit(0);
  }
  _runApp(
    title,
    widget,
    MyTheme.currentThemeMode(),
  );
  // we do not hide titlebar on win7 because of the frame overflow.
  if (kUseCompatibleUiMode) {
    WindowController.fromWindowId(kWindowId!).showTitleBar(true);
  }
  switch (appType) {
    case kAppTypeDesktopRemote:
      // If screen rect is set, the window will be moved to the target screen and then set fullscreen.
      if (argument['screen_rect'] == null) {
        // display can be used to control the offset of the window.
        await restoreWindowPosition(
          WindowType.RemoteDesktop,
          windowId: kWindowId!,
          peerId: argument['id'] as String?,
          display: argument['display'] as int?,
        );
      }
      break;
    case kAppTypeDesktopFileTransfer:
      await restoreWindowPosition(WindowType.FileTransfer,
          windowId: kWindowId!);
      break;
    case kAppTypeDesktopViewCamera:
      // If screen rect is set, the window will be moved to the target screen and then set fullscreen.
      if (argument['screen_rect'] == null) {
        // display can be used to control the offset of the window.
        await restoreWindowPosition(
          WindowType.ViewCamera,
          windowId: kWindowId!,
          peerId: argument['id'] as String?,
          // FIXME: fix display index.
          display: argument['display'] as int?,
        );
      }
      break;
    case kAppTypeDesktopPortForward:
      await restoreWindowPosition(WindowType.PortForward, windowId: kWindowId!);
      break;
    case kAppTypeDesktopTerminal:
      await restoreWindowPosition(WindowType.Terminal, windowId: kWindowId!);
      break;
    case kAppTypeDesktopFilePreview:
      // no position restore needed — each preview is a new window
      break;
    default:
      // no such appType
      exit(0);
  }
  // show window from hidden status
  WindowController.fromWindowId(kWindowId!).show();
}

void runConnectionManagerScreen() async {
  await initEnv(kAppTypeConnectionManager);
  _runApp(
    '',
    const DesktopServerPage(),
    MyTheme.currentThemeMode(),
  );
  final hide = await bind.cmGetConfig(name: "hide_cm") == 'true';
  gFFI.serverModel.hideCm = hide;
  await hideCmWindow(isStartup: true);
  await gFFI.serverModel.updateClientState();
  setResizable(false);
  // Start the uni links handler and redirect links to Native, not for Flutter.
  listenUniLinks(handleByFlutter: false);
}

bool _isCmReadyToShow = false;

showCmWindow({bool isStartup = false}) async {
  if (isStartup) {
    WindowOptions windowOptions = getHiddenTitleBarWindowOptions(
        size: kConnectionManagerWindowSizeClosedChat, alwaysOnTop: true);
    await windowManager.waitUntilReadyToShow(windowOptions, null);
    bind.mainHideDock();
    await Future.wait([
      windowManager.show(),
      windowManager.focus(),
      windowManager.setOpacity(1)
    ]);
    // ensure initial window size to be changed
    await windowManager.setSizeAlignment(
        kConnectionManagerWindowSizeClosedChat, Alignment.topRight);
    _isCmReadyToShow = true;
  } else if (_isCmReadyToShow) {
    if (await windowManager.getOpacity() != 1) {
      await windowManager.setOpacity(1);
      await windowManager.focus();
      await windowManager.minimize(); //needed
      await windowManager.setSizeAlignment(
          kConnectionManagerWindowSizeClosedChat, Alignment.topRight);
      windowOnTop(null);
    }
  }
}

hideCmWindow({bool isStartup = false}) async {
  if (isStartup) {
    WindowOptions windowOptions = getHiddenTitleBarWindowOptions(
        size: kConnectionManagerWindowSizeClosedChat);
    windowManager.setOpacity(0);
    await windowManager.waitUntilReadyToShow(windowOptions, null);
    bind.mainHideDock();
    await windowManager.minimize();
    await windowManager.hide();
    _isCmReadyToShow = true;
  } else if (_isCmReadyToShow) {
    if (await windowManager.getOpacity() != 0) {
      await windowManager.setOpacity(0);
      bind.mainHideDock();
      await windowManager.minimize();
      await windowManager.hide();
    }
  }
}

void _runApp(
  String title,
  Widget home,
  ThemeMode themeMode,
) {
  final botToastBuilder = BotToastInit();
  runApp(RefreshWrapper(
    builder: (context) => GetMaterialApp(
      navigatorKey: globalKey,
      debugShowCheckedModeBanner: false,
      title: title,
      theme: MyTheme.lightTheme,
      darkTheme: MyTheme.darkTheme,
      themeMode: themeMode,
      home: home,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: supportedLocales,
      navigatorObservers: [
        // FirebaseAnalyticsObserver(analytics: analytics),
        BotToastNavigatorObserver(),
      ],
      builder: (context, child) {
        child = _keepScaleBuilder(context, child);
        child = botToastBuilder(context, child);
        return child;
      },
    ),
  ));
}

void runInstallPage() async {
  await windowManager.ensureInitialized();
  await initEnv(kAppTypeMain);
  _runApp('', const InstallPage(), MyTheme.currentThemeMode());
  WindowOptions windowOptions =
      getHiddenTitleBarWindowOptions(size: Size(800, 600), center: true);
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    windowManager.show();
    windowManager.focus();
    windowManager.setOpacity(1);
    windowManager.setAlignment(Alignment.center); // ensure
  });
}

WindowOptions getHiddenTitleBarWindowOptions(
    {bool isMainWindow = false,
    Size? size,
    bool center = false,
    bool? alwaysOnTop}) {
  var defaultTitleBarStyle = TitleBarStyle.hidden;
  // we do not hide titlebar on win7 because of the frame overflow.
  if (kUseCompatibleUiMode) {
    defaultTitleBarStyle = TitleBarStyle.normal;
  }
  return WindowOptions(
    size: size,
    center: center,
    // LUODA FIX: on Windows/Linux the native window ignores transparency and
    // shows black before Flutter paints. Use the app theme canvas color so no
    // black flash appears. macOS keeps its native transparent title bar.
    backgroundColor: (isMacOS && isMainWindow)
        ? null
        : (isMainWindow
            ? (MyTheme.currentThemeMode() == ThemeMode.dark
                ? MyTheme.canvasDark
                : MyTheme.canvasLight)
            : Colors.transparent),
    skipTaskbar: false,
    titleBarStyle: defaultTitleBarStyle,
    alwaysOnTop: alwaysOnTop,
  );
}

class App extends StatefulWidget {
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.window.onPlatformBrightnessChanged = () {
      final userPreference = MyTheme.getThemeModePreference();
      if (userPreference != ThemeMode.system) return;
      WidgetsBinding.instance.handlePlatformBrightnessChanged();
      final systemIsDark =
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark;
      final ThemeMode to;
      if (systemIsDark) {
        to = ThemeMode.dark;
      } else {
        to = ThemeMode.light;
      }
      Get.changeThemeMode(to);
      // Synchronize the window theme of the system.
      updateSystemWindowTheme();
      if (desktopType == DesktopType.main) {
        bind.mainChangeTheme(dark: to.toShortString());
      }
    };
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOrientation());
    AiConfig.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _updateOrientation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isMobile) return;
    if (state == AppLifecycleState.resumed) {
      // App returned to foreground — refresh connections and permissions
      gFFI.serverModel.checkAndroidPermission();
      // Refresh chat connections that may have been paused
      if (gFFI.chatModel.currentKey.peerId.isNotEmpty) {
        gFFI.chatModel.notifyListeners();
      }
    }
  }

  void _updateOrientation() {
    if (isDesktop) return;

    // Don't use `MediaQuery.of(context).orientation` in `didChangeMetrics()`,
    // my test (Flutter 3.19.6, Android 14) is always the reverse value.
    // https://github.com/flutter/flutter/issues/60899
    // stateGlobal.isPortrait.value =
    //     MediaQuery.of(context).orientation == Orientation.portrait;

    final orientation = View.of(context).physicalSize.aspectRatio > 1
        ? Orientation.landscape
        : Orientation.portrait;
    stateGlobal.isPortrait.value = orientation == Orientation.portrait;
  }

  @override
  Widget build(BuildContext context) {
    // final analytics = FirebaseAnalytics.instance;
    final botToastBuilder = BotToastInit();
    return RefreshWrapper(builder: (context) {
      return MultiProvider(
        providers: [
          // global configuration
          // use session related FFI when in remote control or file transfer page
          ChangeNotifierProvider.value(value: gFFI.ffiModel),
          ChangeNotifierProvider.value(value: gFFI.imageModel),
          ChangeNotifierProvider.value(value: gFFI.cursorModel),
          ChangeNotifierProvider.value(value: gFFI.canvasModel),
          ChangeNotifierProvider.value(value: gFFI.peerTabModel),
        ],
        child: GetMaterialApp(
          navigatorKey: globalKey,
          debugShowCheckedModeBanner: false,
          title: isWeb
              ? '${bind.mainGetAppNameSync()} Web Client V2 (Preview)'
              : bind.mainGetAppNameSync(),
          theme: MyTheme.lightTheme,
          darkTheme: MyTheme.darkTheme,
          themeMode: MyTheme.currentThemeMode(),
          home: isDesktop
              ? const DesktopTabPage()
              : isWeb
                  ? WebHomePage()
                  : HomePage(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: supportedLocales,
          navigatorObservers: [
            // FirebaseAnalyticsObserver(analytics: analytics),
            BotToastNavigatorObserver(),
          ],
          builder: isAndroid
              ? (context, child) => AccessibilityListener(
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(1.0),
                      ),
                      child: child ?? Container(),
                    ),
                  )
              : (context, child) {
                  child = _keepScaleBuilder(context, child);
                  child = botToastBuilder(context, child);
                  if ((isDesktop && desktopType == DesktopType.main) ||
                      isWebDesktop) {
                    child = keyListenerBuilder(context, child);
                  }
                  if (isLinux) {
                    return buildVirtualWindowFrame(context, child);
                  } else {
                    return workaroundWindowBorder(context, child);
                  }
                },
        ),
      );
    });
  }
}

Widget _keepScaleBuilder(BuildContext context, Widget? child) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(1.0),
    ),
    child: child ?? Container(),
  );
}

_registerEventHandler() {
  if (isDesktop && desktopType != DesktopType.main) {
    platformFFI.registerEventHandler('theme', 'theme', (evt) async {
      String? dark = evt['dark'];
      if (dark != null) {
        await MyTheme.changeDarkMode(MyTheme.themeModeFromString(dark));
      }
    });
    platformFFI.registerEventHandler('language', 'language', (_) async {
      reloadAllWindows();
    });
  }
  // Register native handlers.
  if (isDesktop) {
    platformFFI.registerEventHandler('native_ui', 'native_ui', (evt) async {
      NativeUiHandler.instance.onEvent(evt);
    });
  }
 // The Rust core self-heals stale direct endpoints after a successful direct
 // connection; refresh the Flutter-side pairing cache when it announces a change.
 platformFFI.registerEventHandler(
 'direct_pairings_changed',
 'direct_pairings_changed',
 (_) async {
 DirectPairingStore.invalidateCache();
 },
 );
 // LUODA FIX: the main app window never called updateEventListener (that
 // is only done in DesktopServerPage, which lives in the CM process).
 // Without these handlers, incoming chat events pushed by Rust via
 // push_global_event("main", ...) reach the event sink but _eventCallback is
 // null and no registered handler matches — the event is silently dropped,
 // so messages from the phone never appear on the PC screen.
 // Mobile also subscribes to the global "main" stream; the io_loop now
 // mirrors chat_client_mode there too, so register on mobile as well.
 if (!isDesktop || desktopType == DesktopType.main) {
 platformFFI.registerEventHandler(
 'chat_client_mode',
 'main_chat_client',
 (evt) async {
 final value = (evt['text'] ?? '').toString();
 RuntimeLogger.instance
 .info('CHAT-EVT', 'main client_mode len=${value.length}');
 final consumed =
 gFFI.viewerSessionModel.handleWireMessage(value);
 if (consumed != true) {
 gFFI.chatModel.receive(ChatModel.clientModeID, value);
 }
 },
 );
 platformFFI.registerEventHandler(
 'chat_server_mode',
 'main_chat_server',
 (evt) async {
 final value = (evt['text'] ?? '').toString();
 final id = int.tryParse('${evt['id']}') ?? 0;
 RuntimeLogger.instance.info(
 'CHAT-EVT', 'main server_mode id=$id len=${value.length}');
 final consumed =
 gFFI.viewerSessionModel.handleWireMessage(value);
 if (consumed != true) {
 gFFI.chatModel.receive(id, value);
 }
 },
 );
 }
}

Widget keyListenerBuilder(BuildContext context, Widget? child) {
  return RawKeyboardListener(
    focusNode: FocusNode(),
    child: child ?? Container(),
    onKey: (RawKeyEvent event) {
      if (event.logicalKey == LogicalKeyboardKey.shiftLeft) {
        if (event is RawKeyDownEvent) {
          gFFI.peerTabModel.setShiftDown(true);
        } else if (event is RawKeyUpEvent) {
          gFFI.peerTabModel.setShiftDown(false);
        }
      }
    },
  );
}

/// On Android, derive a stable device id from ANDROID_ID and apply it once
/// when the app is fresh (no chat history yet). A reinstall keeps the same
/// id so contacts, friends and chat history stay attached to this device.
Future<void> applyStableAndroidDeviceId() async {
  if (!isAndroid) return;
  try {
    const channel = MethodChannel('mChannel');
    final stable = await channel.invokeMethod<String>('get_stable_device_id');
    if (stable == null || stable.trim().isEmpty) return;
    if (bind.mainGetLocalOption(key: 'direct-chat-stable-id-applied') == 'Y') {
      return;
    }
    final history =
        await DirectChatRepository.instance.latestConversations();
    if (history.isNotEmpty) return;
    final current = await bind.mainGetMyId();
    if (current.trim() == stable.trim()) {
      bind.mainSetLocalOption(
          key: 'direct-chat-stable-id-applied', value: 'Y');
      return;
    }
    await bind.mainChangeId(newId: stable.trim());
    bind.mainSetLocalOption(key: 'direct-chat-stable-id-applied', value: 'Y');
    debugPrint('CHAT-ID: applied stable android device id=' + stable);
  } catch (error) {
    debugPrint('CHAT-ID: stable id apply failed: ' + error.toString());
  }
}