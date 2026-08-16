// 百度逆地理解析逻辑测试：内置公开 key 兜底的地名/地址提取。
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/geo_service.dart';

void main() {
  test('parses business district as name and formatted address', () {
    final decoded = <String, dynamic>{
      'status': 0,
      'result': <String, dynamic>{
        'business': '人民广场,南京西路,南京东路',
        'formatted_address': '上海市黄浦区南京东路街道人民大道200号',
        'addressComponent': <String, dynamic>{'district': '黄浦区'},
      },
    };
    final (name, address) = AmapService.parseBaiduResponse(decoded);
    expect(name, '人民广场');
    expect(address, '上海市黄浦区南京东路街道人民大道200号');
  });

  test('falls back to district when business is empty', () {
    final decoded = <String, dynamic>{
      'status': 0,
      'result': <String, dynamic>{
        'business': '',
        'formatted_address': '上海市浦东新区',
        'addressComponent': <String, dynamic>{'district': '浦东新区'},
      },
    };
    final (name, address) = AmapService.parseBaiduResponse(decoded);
    expect(name, '浦东新区');
    expect(address, '上海市浦东新区');
  });

  test('returns empty on non-zero status', () {
    final decoded = <String, dynamic>{'status': 102, 'message': 'key stopped'};
    final (name, address) = AmapService.parseBaiduResponse(decoded);
    expect(name, isEmpty);
    expect(address, isEmpty);
  });

  test('returns empty when result is missing', () {
    final decoded = <String, dynamic>{'status': 0};
    final (name, address) = AmapService.parseBaiduResponse(decoded);
    expect(name, isEmpty);
    expect(address, isEmpty);
  });

  group('GeoReverseResult', () {
    test('empty result flags isEmpty', () {
      const r = GeoReverseResult.empty();
      expect(r.isEmpty, isTrue);
      expect(r.fromCache, isFalse);
      expect(r.quotaLimited, isFalse);
    });

    test('cache hit result carries fromCache flag', () {
      const r = GeoReverseResult(name: '人民广场', address: '上海市黄浦区', fromCache: true);
      expect(r.isEmpty, isFalse);
      expect(r.fromCache, isTrue);
      expect(r.quotaLimited, isFalse);
    });

    test('quota limited result carries quotaLimited flag', () {
      const r = GeoReverseResult(
        name: '',
        address: '',
        quotaLimited: true,
      );
      expect(r.isEmpty, isTrue);
      expect(r.quotaLimited, isTrue);
    });
  });
}
