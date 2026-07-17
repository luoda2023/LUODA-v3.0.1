import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_viewer_invite.dart';

void main() {
  test('viewer invite link carries a direct endpoint and invite code', () {
    final invite = ViewerInviteLink(
      endpoint: '203.0.113.8:21118',
      token: 'ABCD-EFGH-JKMN',
    );

    final uri = invite.toUri();

    expect(uri.toString(),
        'luoda://join/ABCD-EFGH-JKMN?endpoint=203.0.113.8%3A21118');
    expect(ViewerInviteLink.tryParse(uri), invite);
  });

  test('viewer invite rejects links without a direct endpoint', () {
    expect(
      ViewerInviteLink.tryParse(Uri.parse('luoda://join/ABCD-EFGH-JKMN')),
      isNull,
    );
    expect(
      ViewerInviteLink.tryParse(
        Uri.parse('luoda://join/ABCD-EFGH-JKMN?endpoint=peer-id'),
      ),
      isNull,
    );
  });
}
