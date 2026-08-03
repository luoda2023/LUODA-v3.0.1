import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common.dart';

void main() {
  test('server config sharing preserves Unicode values', () {
    final source = ServerConfig(
      idServer: '例子.测试:21116',
      relayServer: '中继.测试:21117',
      apiServer: 'https://接口.测试',
      key: '密钥-𠮷-😀',
    );

    final restored = ServerConfig.decode(source.encode());

    expect(restored.idServer, source.idServer);
    expect(restored.relayServer, source.relayServer);
    expect(restored.apiServer, source.apiServer);
    expect(restored.key, source.key);
  });
}
