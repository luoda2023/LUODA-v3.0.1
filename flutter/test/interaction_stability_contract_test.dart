import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String methodBody(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'missing $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  final serverModelSource =
      File('lib/models/server_model.dart').readAsStringSync();
  final desktopHomeSource =
      File('lib/desktop/pages/desktop_home_page.dart').readAsStringSync();
  final mobileConnectionSource =
      File('lib/mobile/pages/connection_page.dart').readAsStringSync();
  final mobileHomeSource =
      File('lib/mobile/pages/home_page.dart').readAsStringSync();
  final scanSource = File('lib/mobile/pages/scan_page.dart').readAsStringSync();
  final modelSource = File('lib/models/model.dart').readAsStringSync();
  final chatPageSource =
      File('lib/common/widgets/chat_page.dart').readAsStringSync();
  final sharedStateSource =
      File('lib/common/shared_state.dart').readAsStringSync();
  final flutterFfiSource =
      File('../src/flutter_ffi.rs').readAsStringSync();
  final hbbCommonLibSource =
      File('../libs/hbb_common/src/lib.rs').readAsStringSync();
  final remotePageSource =
      File('lib/desktop/pages/remote_page.dart').readAsStringSync();
  final viewCameraPageSource =
      File('lib/desktop/pages/view_camera_page.dart').readAsStringSync();
  final multiWindowSource =
      File('lib/utils/multi_window_manager.dart').readAsStringSync();
  final androidBuildSource =
      File('android/app/build.gradle.kts').readAsStringSync();
  final androidManifestSource =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final adaptiveIconSource = File(
    'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
  ).readAsStringSync();
  final androidIconScriptSource =
      File('../res/resize_for_apk.py').readAsStringSync();
  final pubspecSource = File('pubspec.yaml').readAsStringSync();

  test('server status polling clears stale remote-control blocking state', () {
    expect(serverModelSource,
        contains('videoConnCount is int ? videoConnCount : 0'));
    expect(serverModelSource, contains('stateGlobal.videoConnCount.value'));
  });

  test('desktop start service restores both installed and in-process hosts', () {
    final startService = methodBody(
      flutterFfiSource,
      'pub fn main_start_service()',
      'pub fn main_update_temporary_password()',
    );
    expect(
      startService,
      contains('Config::set_option("stop-service".into(), "".into())'),
    );
    expect(startService, contains('crate::platform::is_installed()'));
    expect(
      startService,
      contains('crate::ipc::set_option("stop-service", "")'),
    );
    expect(
      startService,
      contains('RendezvousMediator::restart()'),
    );
  });

  test('debug logging tolerates an already installed runtime logger', () {
    final initLog = methodBody(
      hbbCommonLibSource,
      'pub fn init_log(',
      '#[derive(Debug, Default, Deserialize, Serialize)]',
    );
    expect(initLog, contains('.try_init()'));
    expect(initLog, isNot(contains('init_from_env(')));
  });

  test('desktop direct chat connects without a blocking dialog', () {
    final startChat = methodBody(
      desktopHomeSource,
      'Future<void> _startDirectChat(',
      'Peer? _findContact(',
    );
    expect(startChat, contains('suppressConnectionDialogs = true'));
    expect(startChat, isNot(contains('showLoading(')));
    expect(startChat, isNot(contains('suppressConnectionDialogs = false')));
  });

  test('mobile direct chat connects without a blocking dialog', () {
    final startChat = methodBody(
      mobileConnectionSource,
      'Future<void> _startDirectChat(',
      'Widget _buildPairedContacts()',
    );
    expect(startChat, contains('gFFI.suppressConnectionDialogs = true'));
    expect(startChat, isNot(contains('showLoading(')));
  });

  test('direct file transports connect in the background', () {
    final desktopFile = methodBody(
      desktopHomeSource,
      'Future<FFI?> _ensureDirectFileSession(',
      'Future<bool> _waitForFileDirectories(',
    );
    final mobileFile = methodBody(
      mobileHomeSource,
      'Future<FFI?> _ensureDirectFileSession(',
      'Future<bool> _waitForFileDirectories(',
    );
    for (final source in <String>[desktopFile, mobileFile]) {
      expect(source, contains('suppressConnectionDialogs = true'));
      expect(source, isNot(contains('showLoading(')));
    }
  });

  test('remote mouse window bounds use the actual window height', () {
    expect(
      modelSource,
      contains('final h = _windowRect!.height / devicePixelRatio;'),
    );
    expect(
      modelSource,
      isNot(contains('final h = _windowRect!.width / devicePixelRatio;')),
    );
  });

  test('mobile QR scanning always releases its in-flight guard', () {
    final scanHandler = methodBody(
      scanSource,
      'Future<void> _handleScannedValue(',
      'Future<void> _showServerSettingFromQr(',
    );
    expect(scanHandler, contains('try {'));
    expect(scanHandler, contains('finally'));
    expect(scanHandler, contains('_handlingScan = false;'));
  });

  test('remote page disposal cannot block the tab lifecycle', () {
    expect(remotePageSource, contains('void dispose()'));
    expect(
        remotePageSource, contains('unawaited(_finishDispose(closeSession))'));
    expect(remotePageSource, contains('.timeout(const Duration(seconds: 5))'));
    expect(remotePageSource, contains('removeSharedStates(widget.id)'));
  });

  test('desktop session manager rejects self targets before window creation',
      () {
    final newSession = methodBody(
      multiWindowSource,
      'Future<MultiWindowCallResult> newSession(',
      'Future<MultiWindowCallResult> newRemoteDesktop(',
    );
    final guard =
        newSession.indexOf('await DirectPairingStore.isSelfTarget(remoteId)');
    final probe = newSession.indexOf('for (final windowId');
    expect(guard, greaterThanOrEqualTo(0));
    expect(probe, greaterThan(guard));
    expect(
      newSession,
      contains(
          "'This is the current device. You cannot connect to or message yourself.'"),
    );
    expect(newSession, contains('return MultiWindowCallResult(-1, false);'));
  });

  test('chat message flex participates directly in the row layout', () {
    expect(chatPageSource, contains('final messageColumn = Flexible('));
    expect(chatPageSource, isNot(contains('child: Flexible(')));
  });

  test('desktop conversations exclude the local device identity', () {
    expect(
      desktopHomeSource,
      contains(
        'if (peerId.isEmpty || peerId == gFFI.chatModel.me.id) return false;',
      ),
    );
  });

  test('remote shared state is reference counted per mounted session', () {
    expect(sharedStateSource, contains('_sharedStateReferenceCounts'));
    expect(sharedStateSource, contains('final count ='));
    expect(sharedStateSource, contains('if (count > 0)'));
    expect(sharedStateSource, contains('if (count > 1)'));

    final remoteInitState = methodBody(
      remotePageSource,
      'void initState()',
      'void _cancelPointerLockCenterDebounceTimer()',
    );
    expect(remoteInitState, contains('initSharedStates(widget.id);'));
    expect(remoteInitState, contains('_initStates(widget.id);'));

    final cameraInitState = methodBody(
      viewCameraPageSource,
      'void initState()',
      'void onWindowBlur()',
    );
    expect(cameraInitState, contains('initSharedStates(widget.id);'));
  });

  test('remote connection errors are retained for the inline error state', () {
    final handleMsgBox = methodBody(
      modelSource,
      'handleMsgBox(Map<String, dynamic> evt, SessionID sessionId, String peerId)',
      'bool shouldAutoReconnectDirectChat(',
    );
    expect(
      handleMsgBox,
      contains(
        'parent.target?.connType == ConnType.chat &&\n'
        "          _isEnvironmentError(text?.toString() ?? '')",
      ),
    );
    expect(handleMsgBox, contains('_lastConnectionError = text?.toString();'));
    expect(handleMsgBox, contains('notifyListeners();'));
  });

  test('android packaging refuses to omit the luoda native library', () {
    expect(androidBuildSource, contains('requiredLuodaAbis'));
    expect(androidBuildSource, contains('verifyLuodaNativeLibraries'));
    expect(androidBuildSource, contains('libluoda.so'));
    expect(androidBuildSource, contains('dependsOn(verifyLuodaNativeLibraries)'));
  });

  test('launcher icons use the padded LUODA artwork on every platform', () {
    expect(pubspecSource, contains('image_path: "../res/icon_padded.png"'));
    expect(
      androidManifestSource,
      contains('android:roundIcon="@mipmap/ic_launcher_round"'),
    );
    expect(
      adaptiveIconSource,
      contains('@mipmap/ic_launcher_monochrome'),
    );
    expect(
      androidIconScriptSource,
      contains('os.path.join(repo_root, "res", "icon_padded.png")'),
    );
  });
}
