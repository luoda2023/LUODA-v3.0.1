import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final remotePageSource =
      File('lib/desktop/pages/remote_page.dart').readAsStringSync();
  final remoteTabSource =
      File('lib/desktop/pages/remote_tab_page.dart').readAsStringSync();
  final remoteToolbarSource =
      File('lib/desktop/widgets/remote_toolbar.dart').readAsStringSync();
  final homePageSource =
      File('lib/desktop/pages/desktop_home_page.dart').readAsStringSync();
  final constantsSource = File('lib/consts.dart').readAsStringSync();
  final commonSource = File('lib/common.dart').readAsStringSync();
  final dialogSource =
      File('lib/common/widgets/dialog.dart').readAsStringSync();
  final chineseSource = File('../src/lang/cn.rs').readAsStringSync();

  test('remote window uses the dedicated two-level chrome and status bar', () {
    expect(remoteTabSource, contains('_RemoteWindowTitleBar('));
    expect(remoteTabSource, contains('topBarHeight: 42'));
    expect(remotePageSource, contains('RemoteToolbar.expandedHeight'));
    expect(remotePageSource, contains('_RemoteSessionStatusBar('));
    expect(remoteToolbarSource, contains('expandedHeight = 58'));
  });

  test('remote window shows the actual direct or relay transport', () {
    expect(
      remotePageSource,
      contains('ConnectionTypeState.find(widget.id)'),
    );
    expect(remotePageSource, contains('getConnectionText('));
    expect(remotePageSource, contains('connection.stream_type.value'));
    expect(remotePageSource, contains("translate('Connecting...')"));
    expect(
        remoteTabSource, contains("message: '\$msgConn\\n\$msgFingerprint'"));
    expect(commonSource, contains("if (streamType == 'Relay')"));
    expect(commonSource, contains("streamType = 'TCP'"));
    expect(
        chineseSource, contains('("Direct and encrypted connection", "加密直连")'));
    expect(
      chineseSource,
      contains('("Relayed and encrypted connection", "加密中继连接")'),
    );
  });

  test('high-frequency remote actions remain connected to real callbacks', () {
    expect(remoteToolbarSource, contains('_ControlMenu('));
    expect(remoteToolbarSource, contains('_DisplayMenu('));
    expect(remoteToolbarSource, contains('_KeyboardMenu('));
    expect(remoteToolbarSource, contains('_MonitorMenu('));
    expect(remoteToolbarSource, contains('_VoiceCallMenu('));
    expect(remoteToolbarSource, contains('_RecordMenu()'));
    expect(remoteToolbarSource, contains('isFileTransfer: true'));
    expect(remoteToolbarSource, contains('isTerminal: true'));
    expect(remoteToolbarSource, contains('sessionTakeScreenshot('));
    expect(remoteToolbarSource, contains("value: _option"));
  });

  test('multiple remote displays expose the self-service monitor switcher', () {
    final monitorGate = remoteToolbarSource
        .split('toolbarItems.add(Obx(() {')[1]
        .split('toolbarItems')[0];
    expect(monitorGate, contains('pi.displays.length > 1'));
    expect(monitorGate, isNot(contains('displaysCount')));
    expect(remoteToolbarSource, contains('openMonitorInTheSameTab('));
    expect(commonSource, contains('bind.sessionSwitchDisplay('));
    expect(
        remoteToolbarSource, contains('buildMonitorButton(kAllDisplayValue)'));
  });

  test('multiple Windows sessions remain switchable from the toolbar', () {
    expect(remoteToolbarSource, contains('_WindowsSessionMenu('));
    expect(remoteToolbarSource, contains('pi.windowsSessionsJson.isNotEmpty'));
    expect(remoteToolbarSource, contains('showWindowsSessionsSelector('));
    expect(remotePageSource, isNot(contains('windowsSessionsJson')));

    final modelSource = File('lib/models/model.dart').readAsStringSync();
    expect(modelSource, contains('windowsSessionsJson'));
    expect(modelSource, contains('_pi.windowsSessionsJson.value = sessions'));
    expect(modelSource, contains('void showWindowsSessionsSelector('));
    expect(dialogSource, contains('bind.sessionSendSelectedSessionId('));
    expect(remoteToolbarSource, contains('CurrentSessionState.find(id)'));
    expect(remoteToolbarSource, contains('sessionSendSelectedSessionId('));
    expect(remoteToolbarSource, contains('_sessions(pi.windowsSessionsJson.value)'));
  });

  test('remote chat can float or return to the main conversation', () {
    expect(remoteToolbarSource, contains('DesktopHomePage.selectSection'));
    expect(constantsSource, contains('kWindowEventOpenDirectChat'));
    expect(remoteTabSource, contains('kWindowEventOpenDirectChat'));
    expect(
        homePageSource, contains('call.method == kWindowEventOpenDirectChat'));
    expect(homePageSource, contains('await _startDirectChat(peerId)'));
  });
}
