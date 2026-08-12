import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/remote_viewport_geometry.dart';

void main() {
  const remoteFrame = Size(2560, 1600);

  test('adaptive viewport maps a visible right click to the remote pixel', () {
    const viewport = RemoteViewportGeometry(
      globalOrigin: Offset(8, 152),
      size: Size(1600, 900),
    );
    final transform = RemoteFramebufferTransform.adaptive(
      viewportSize: viewport.size,
      remoteFrameSize: remoteFrame,
    );
    const expectedRemotePoint = Offset(1920, 480);
    final visiblePoint =
        viewport.globalOrigin + transform.remoteToViewport(expectedRemotePoint);

    expect(
      transform.viewportToRemote(viewport.globalToLocal(visiblePoint)),
      closeToOffset(expectedRemotePoint),
    );
  });

  test('maximizing recomputes origin and scale without coordinate drift', () {
    const normalViewport = RemoteViewportGeometry(
      globalOrigin: Offset(8, 152),
      size: Size(1600, 900),
    );
    const maximizedViewport = RemoteViewportGeometry(
      globalOrigin: Offset(0, 96),
      size: Size(1920, 1016),
    );
    const expectedRemotePoint = Offset(2048, 1120);

    for (final viewport in <RemoteViewportGeometry>[
      normalViewport,
      maximizedViewport,
    ]) {
      final transform = RemoteFramebufferTransform.adaptive(
        viewportSize: viewport.size,
        remoteFrameSize: remoteFrame,
      );
      final visiblePoint = viewport.globalOrigin +
          transform.remoteToViewport(expectedRemotePoint);
      expect(
        transform.viewportToRemote(viewport.globalToLocal(visiblePoint)),
        closeToOffset(expectedRemotePoint),
      );
    }
  });

  test('remote input consumes the live viewport render origin', () {
    final page = File('lib/desktop/pages/remote_page.dart').readAsStringSync();
    final input = File('lib/models/input_model.dart').readAsStringSync();

    expect(page, contains('renderObject.localToGlobal(Offset.zero)'));
    expect(page, contains('updateImageWidgetGeometry('));
    expect(input, contains('_imageViewport!.globalToLocal(Offset(x, y))'));
  });
}

Matcher closeToOffset(Offset expected) => predicate<Offset>(
      (actual) =>
          (actual.dx - expected.dx).abs() < 0.001 &&
          (actual.dy - expected.dy).abs() < 0.001,
      'is within 0.001 logical pixels of $expected',
    );
