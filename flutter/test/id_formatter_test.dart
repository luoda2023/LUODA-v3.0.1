import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/formatter/id_formatter.dart';

void main() {
  test('ID controller replaces malformed UTF-16 before rendering', () {
    final controller = IDTextEditingController();

    controller.id = String.fromCharCode(0xD800);

    expect(controller.text.codeUnits, <int>[0xFFFD]);
    controller.dispose();
  });
}
