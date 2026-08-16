// 地图服务多 key 自动轮换机制测试：
// - 用户可配置多个 key（逗号/分号/换行分隔），主 key 配额耗尽自动切换备用 key；
// - 高德配额类错误码判定（决定是否轮换）；
// - 百度 AK 多 key 存储。
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/geo_service.dart';

void main() {
  setUp(() async {
    // 重置用户 key，避免测试间相互影响。
    await AmapService.instance.saveApiKey('');
    await AmapService.instance.saveBaiduApiKeys('');
  });

  test('saveApiKey splits multiple keys for rotation', () async {
    final svc = AmapService.instance;
    await svc.saveApiKey('key1, key2；key3\nkey4');
    final keys = svc.apiKeys;
    expect(keys.contains('key1'), isTrue);
    expect(keys.contains('key2'), isTrue);
    expect(keys.contains('key3'), isTrue);
    expect(keys.contains('key4'), isTrue);
  });

  test('apiKeys dedups builtin key and keeps user key first', () async {
    final svc = AmapService.instance;
    await svc.saveApiKey(
        '8b18ef3d43e35c791e0b80dfb830c5c2, userkey1');
    final keys = svc.apiKeys;
    // 内置 key 与用户 key 相同时只出现一次（去重）。
    expect(
      keys.where((k) => k == '8b18ef3d43e35c791e0b80dfb830c5c2').length,
      1,
    );
    // 用户 key 排在内置 key 之前（轮换顺序：用户 > 内置）。
    expect(keys.first, '8b18ef3d43e35c791e0b80dfb830c5c2');
    expect(keys.contains('userkey1'), isTrue);
  });

  test('baiduUserKeys stores multiple AKs', () async {
    final svc = AmapService.instance;
    await svc.saveBaiduApiKeys('ak1, ak2；ak3');
    expect(svc.baiduUserKeys, ['ak1', 'ak2', 'ak3']);
  });

  test('amap quota statuses trigger key rotation', () {
    // 配额/权限类错误码：应轮换到下一个 key。
    expect(AmapService.isAmapQuotaStatus('10001'), isTrue); // 非正确 key
    expect(AmapService.isAmapQuotaStatus('10003'), isTrue); // 服务未开通
    expect(AmapService.isAmapQuotaStatus('10008'), isTrue); // key 过期
    expect(AmapService.isAmapQuotaStatus('10009'), isTrue); // key 状态异常
    expect(AmapService.isAmapQuotaStatus('10012'), isTrue); // 日配额超限
    expect(AmapService.isAmapQuotaStatus('10013'), isTrue); // QPS 超限
    // 非配额错误：不应轮换。
    expect(AmapService.isAmapQuotaStatus('1'), isFalse); // 成功
    expect(AmapService.isAmapQuotaStatus('0'), isFalse);
    expect(AmapService.isAmapQuotaStatus('10002'), isFalse);
    expect(AmapService.isAmapQuotaStatus('10004'), isFalse);
  });
}
