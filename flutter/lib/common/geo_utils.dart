// WGS84 (GPS) → GCJ-02 (国测局火星坐标) 转换。
//
// 高德/腾讯/百度地图在国内使用 GCJ-02 加密坐标系，GPS 原始坐标（WGS84）
// 直接叠加会偏移数百米。此文件实现标准的 WGS84→GCJ-02 算法（约 0.1 米精度），
// 用于在地图上正确显示“我的位置”，发送给好友的位置也用 GCJ-02（与微信一致，
// 对方点击卡片用高德/百度/腾讯地图打开时位置准确）。

import 'dart:math' as math;

const double _a = 6378245.0;
const double _ee = 0.00669342162296594323;

double _outOfChina(double lat, double lng) {
  if (lng < 72.004 || lng > 137.8347) return 1;
  if (lat < 0.8293 || lat > 55.8271) return 1;
  return 0;
}

double _transformLat(double x, double y) {
  double ret = -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * math.pi) +
          20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) *
      2.0 /
      3.0;
  ret += (160.0 * math.sin(y / 12.0 * math.pi) +
          320 * math.sin(y * math.pi / 30.0)) *
      2.0 /
      3.0;
  return ret;
}

double _transformLng(double x, double y) {
  double ret = 300.0 +
      x +
      2.0 * y +
      0.1 * x * x +
      0.1 * x * y +
      0.1 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * math.pi) +
          20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) *
      2.0 /
      3.0;
  ret += (150.0 * math.sin(x / 12.0 * math.pi) +
          300.0 * math.sin(x / 30.0 * math.pi)) *
      2.0 /
      3.0;
  return ret;
}

/// 把 WGS-84 坐标转换为 GCJ-02 坐标。返回 (lat, lng)。
(math.Point<double>, math.Point<double>) wgs84ToGcj02(
    double wgsLat, double wgsLng) {
  if (_outOfChina(wgsLat, wgsLng) == 1) {
    return (math.Point(wgsLat, wgsLng), math.Point(wgsLat, wgsLng));
  }
  var dLat = _transformLat(wgsLng - 105.0, wgsLat - 35.0);
  var dLng = _transformLng(wgsLng - 105.0, wgsLat - 35.0);
  final radLat = wgsLat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - _ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  dLat = (dLat * 180.0) /
      ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi);
  dLng = (dLng * 180.0) / (_a / sqrtMagic * math.cos(radLat) * math.pi);
  final mgLat = wgsLat + dLat;
  final mgLng = wgsLng + dLng;
  return (math.Point(mgLat, mgLng), math.Point(mgLat, mgLng));
}

/// 把 GCJ-02 坐标转换回 WGS-84 坐标（迭代逼近，精度 < 1e-6 度）。返回 (lat, lng)。
///
/// 用于调用无 key 的 OSM/Nominatim 逆地理编码（它使用 WGS-84），
/// 把高德/腾讯地图上的 GCJ-02 选点转回真实坐标后再查询。
(math.Point<double>, math.Point<double>) gcj02ToWgs84(
    double gcjLat, double gcjLng) {
  if (_outOfChina(gcjLat, gcjLng) == 1) {
    return (math.Point(gcjLat, gcjLng), math.Point(gcjLat, gcjLng));
  }
  var wgsLat = gcjLat;
  var wgsLng = gcjLng;
  for (var i = 0; i < 8; i++) {
    final (gcj2, _) = wgs84ToGcj02(wgsLat, wgsLng);
    final dLat = gcj2.x - gcjLat;
    final dLng = gcj2.y - gcjLng;
    wgsLat -= dLat;
    wgsLng -= dLng;
    if (dLat.abs() < 1e-9 && dLng.abs() < 1e-9) break;
  }
  return (math.Point(wgsLat, wgsLng), math.Point(wgsLat, wgsLng));
}
