import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final peerCardSource = File(
    'lib/common/widgets/peer_card.dart',
  ).readAsStringSync();
  final homePageSource = File(
    'lib/desktop/pages/desktop_home_page.dart',
  ).readAsStringSync();
  final addressBookSource = File(
    'lib/common/widgets/address_book.dart',
  ).readAsStringSync();

  test('peer card more action has a real keyboard activation callback', () {
    expect(peerCardSource, isNot(contains('onTap: () {}')));
    expect(peerCardSource, contains('onTap: () => _showPeerMenu(peer.id)'));
    expect(peerCardSource, contains('onTap: onTap'));
    expect(addressBookSource, contains('onTap: () => _showMenu(menuPos)'));
  });

  test(
    'unknown platform card fallback keeps dark text at WCAG AA contrast',
    () {
      const foreground = Color(0xFF17233A);
      const fallbackStartLightness = 0.70;

      expect(peerCardSource, contains('withLightness(.70)'));
      expect(peerCardSource, contains('withLightness(.80)'));

      for (var hue = 0; hue < 360; hue++) {
        final background = HSLColor.fromAHSL(
          1,
          hue.toDouble(),
          0.62,
          fallbackStartLightness,
        ).toColor();
        expect(
          _contrastRatio(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: 'Fallback hue $hue must remain readable',
        );
      }
    },
  );

  test('UPnP unsupported status uses the existing explicit translation', () {
    expect(
      homePageSource,
      contains(
        "if (status == 'unsupported') return 'upnp_mapping_unsupported_tip';",
      ),
    );
  });
}
