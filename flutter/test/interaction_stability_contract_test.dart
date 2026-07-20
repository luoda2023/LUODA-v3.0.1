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
  final remotePageSource =
      File('lib/desktop/pages/remote_page.dart').readAsStringSync();

  test('server status polling clears stale remote-control blocking state', () {
    expect(serverModelSource,
        contains('videoConnCount is int ? videoConnCount : 0'));
    expect(serverModelSource, contains('stateGlobal.videoConnCount.value'));
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
}
