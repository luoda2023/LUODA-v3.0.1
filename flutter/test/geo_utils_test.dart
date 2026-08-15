// 坐标转换往返测试：WGS84 → GCJ-02 → WGS84 应回到原点（误差 < 1e-5 度，约 1 米）。
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/geo_utils.dart';

void main() {
  test('wgs84ToGcj02 then gcj02ToWgs84 round-trips within 1e-5 degrees',
      () async {
    final samples = <(double, double)>[
      (31.2304, 121.4737), // 上海人民广场
      (39.9087, 116.3975), // 北京天安门
      (22.5431, 114.0579), // 深圳
      (30.2741, 120.1551), // 杭州
      (34.3416, 108.9398), // 西安
    ];
    for (final (lat, lng) in samples) {
      final gcj = wgs84ToGcj02(lat, lng).$1;
      final back = gcj02ToWgs84(gcj.x, gcj.y).$1;
      final dLat = (back.x - lat).abs();
      final dLng = (back.y - lng).abs();
      expect(dLat, lessThan(1e-5), reason: 'lat round-trip too far at $lat,$lng');
      expect(dLng, lessThan(1e-5), reason: 'lng round-trip too far at $lat,$lng');
    }
  });

  test('conversions are stable and deterministic', () async {
    final a = gcj02ToWgs84(31.2304, 121.4737).$1;
    final b = gcj02ToWgs84(31.2304, 121.4737).$1;
    expect(a.x, b.x);
    expect(a.y, b.y);
    // 中国境内的 GCJ-02 与 WGS-84 应存在偏移（数百米量级），确保转换真的发生。
    final (gcjLat, gcjLng) = (a.x, a.y);
    expect((gcjLat - 31.2304).abs() + (gcjLng - 121.4737).abs(),
        greaterThan(1e-4),
        reason: 'GCJ-02 offset expected within China');
  });

  test('out-of-China coordinates are unchanged', () async {
    final (lat, lng) = (37.7749, -122.4194); // 旧金山
    final gcj = wgs84ToGcj02(lat, lng).$1;
    expect(gcj.x, closeTo(lat, 1e-9));
    expect(gcj.y, closeTo(lng, 1e-9));
    final back = gcj02ToWgs84(lat, lng).$1;
    expect(back.x, closeTo(lat, 1e-9));
    expect(back.y, closeTo(lng, 1e-9));
  });
}
