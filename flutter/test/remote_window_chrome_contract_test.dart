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

  test('remote window uses the dedicated two-level chrome and status bar', () {
    expect(remoteTabSource, contains('_RemoteWindowTitleBar('));
    expect(remoteTabSource, contains('topBarHeight: 42'));
    expect(remotePageSource, contains('RemoteToolbar.expandedHeight'));
    expect(remotePageSource, contains('_RemoteSessionStatusBar('));
    expect(remoteToolbarSource, contains('expandedHeight = 58'));
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

  test('remote chat can float or return to the main conversation', () {
    expect(remoteToolbarSource, contains('toggleChatOverlay('));
    expect(constantsSource, contains('kWindowEventOpenDirectChat'));
    expect(remoteTabSource, contains('kWindowEventOpenDirectChat'));
    expect(
        homePageSource, contains('call.method == kWindowEventOpenDirectChat'));
    expect(homePageSource, contains('await _startDirectChat(peerId)'));
  });
}
