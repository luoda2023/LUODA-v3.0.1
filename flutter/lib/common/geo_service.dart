// 高德地图 Web 服务 API 封装（免费）。
//
// - 地图瓦片：高德栅格瓦片（webrd01-04.is.autonavi.com），无需 key，直接可用。
// - 逆地理编码（坐标 → 中文地址）：restapi.amap.com/v3/geocode/regeo，需要免费 key。
// - 周边地点搜索（附近 POI）：restapi.amap.com/v3/place/around，需要免费 key。
// - 关键字地点搜索：restapi.amap.com/v3/place/text，需要免费 key。
//
// 免费 key 在高德开放平台（https://lbs.amap.com）注册个人开发者即可申请，
// 填到设置页「高德地图服务 Key」后，发送位置会显示详细地址和附近地点列表。
// 未配置 key 时功能自动降级：只显示坐标，不影响地图瓦片和基础选点。

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/platform_model.dart';

/// 一个地点/POI（GCJ-02 坐标，与高德一致）。
class GeoPlace {
  const GeoPlace({
    required this.name,
    this.address = '',
    this.distance = 0,
    this.latitude = 0,
    this.longitude = 0,
  });

  final String name;
  final String address;
  final int distance; // 距中心点米数（周边搜索返回）
  final double latitude;
  final double longitude;

  String get distanceLabel {
    if (distance <= 0) return '';
    if (distance < 1000) return '$distance m';
    return '${(distance / 1000).toStringAsFixed(1)} km';
  }
}

class AmapService {
  AmapService._();

  static final instance = AmapService._();

  static const _storageKey = 'amap-web-service-key';
  static const _base = 'https://restapi.amap.com';

  String? _cachedKey;
  DateTime? _lastFetch;

  /// 用户配置的高德 Web 服务 key（设置页填写，免费申请）。
  String? get apiKey {
    final now = DateTime.now();
    if (_cachedKey == null ||
        _lastFetch == null ||
        now.difference(_lastFetch!).inSeconds > 60) {
      _lastFetch = now;
      try {
        _cachedKey = bind.mainGetLocalOption(key: _storageKey).trim();
      } catch (_) {
        _cachedKey = '';
      }
    }
    return (_cachedKey == null || _cachedKey!.isEmpty) ? null : _cachedKey;
  }

  Future<void> saveApiKey(String value) async {
    _cachedKey = value.trim();
    _lastFetch = DateTime.now();
    try {
      await bind.mainSetLocalOption(key: _storageKey, value: value.trim());
    } catch (_) {
      // 本地配置写入失败时静默忽略。
    }
  }

  bool get hasKey => apiKey != null && apiKey!.isNotEmpty;

  Future<Map<String, dynamic>?> _get(
    String path,
    Map<String, String> query,
  ) async {
    final key = apiKey;
    if (key == null || key.isEmpty) return null;
    final uri = Uri.parse('$_base$path')
        .replace(queryParameters: <String, String>{...query, 'key': key});
    try {
      final resp = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return null;
      if ((decoded['status'] ?? '0').toString() != '1') return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// 逆地理编码：GCJ-02 坐标 → 中文地址。失败返回空串。
  Future<String> reverseGeocode(double lat, double lng) async {
    final data = await _get('/v3/geocode/regeo', <String, String>{
      'location': '${lng.toStringAsFixed(6)},${lat.toStringAsFixed(6)}',
      'extensions': 'base',
    });
    if (data == null) return '';
    final regeocode = data['regeocode'];
    if (regeocode is! Map<String, dynamic>) return '';
    final formatted =
        (regeocode['formatted_address'] ?? '').toString().trim();
    if (formatted.isNotEmpty) return formatted;
    final ac = regeocode['addressComponent'];
    if (ac is Map<String, dynamic>) {
      final province = (ac['province'] ?? '').toString().trim();
      final city = (ac['city'] ?? '').toString().trim();
      final district = (ac['district'] ?? '').toString().trim();
      final township = (ac['township'] ?? '').toString().trim();
      final road = (ac['streetNumber'] is Map<String, dynamic>
              ? ((ac['streetNumber'] as Map<String, dynamic>)['street'] ?? '')
              : '')
          .toString()
          .trim();
      final parts = <String>[
        if (province.isNotEmpty && province != city) province,
        if (city.isNotEmpty) city,
        if (district.isNotEmpty) district,
        if (township.isNotEmpty) township,
        if (road.isNotEmpty) road,
      ];
      if (parts.isNotEmpty) return parts.join('');
    }
    return '';
  }

  /// 逆地理编码（详情版）：返回（POI 地名，完整地址）。
  /// 用 extensions=all 拿最近的 POI 名称作为地名（如“协和双语学校”），
  /// formatted_address 作为完整地址（如“上海市浦东新区xx路xx号”）。
  /// 无 key / 失败时返回 (空, 空)，调用方回退到坐标。
  Future<(String, String)> reverseGeocodeDetail(double lat, double lng) async {
    final data = await _get('/v3/geocode/regeo', <String, String>{
      'location': '${lng.toStringAsFixed(6)},${lat.toStringAsFixed(6)}',
      'extensions': 'all',
    });
    if (data == null) return ('', '');
    final regeocode = data['regeocode'];
    if (regeocode is! Map<String, dynamic>) return ('', '');
    // 1) 最近 POI 名（地名）：优先用 pois[0].name。
    var name = '';
    final pois = regeocode['pois'];
    if (pois is List && pois.isNotEmpty) {
      final first = pois.first;
      if (first is Map<String, dynamic>) {
        name = (first['name'] ?? '').toString().trim();
      }
    }
    // 2) 完整地址：formatted_address，回退到 addressComponent 拼接。
    var formatted =
        (regeocode['formatted_address'] ?? '').toString().trim();
    if (formatted.isEmpty) {
      final ac = regeocode['addressComponent'];
      if (ac is Map<String, dynamic>) {
        final province = (ac['province'] ?? '').toString().trim();
        final city = (ac['city'] ?? '').toString().trim();
        final district = (ac['district'] ?? '').toString().trim();
        final township = (ac['township'] ?? '').toString().trim();
        final road = (ac['streetNumber'] is Map<String, dynamic>
                ? ((ac['streetNumber'] as Map<String, dynamic>)['street'] ?? '')
                : '')
            .toString()
            .trim();
        final parts = <String>[
          if (province.isNotEmpty && province != city) province,
          if (city.isNotEmpty) city,
          if (district.isNotEmpty) district,
          if (township.isNotEmpty) township,
          if (road.isNotEmpty) road,
        ];
        formatted = parts.join('');
      }
    }
    return (name, formatted);
  }

  /// 周边地点搜索：返回距 [lat]/[lng] 半径内（默认 3000 米）的地点列表。
  Future<List<GeoPlace>> searchNearby(double lat, double lng,
      {int radius = 3000, String? keyword, int maxResults = 20}) async {
    final path = (keyword == null || keyword.trim().isEmpty)
        ? '/v3/place/around'
        : '/v3/place/around';
    final data = await _get(path, <String, String>{
      'location': '${lng.toStringAsFixed(6)},${lat.toStringAsFixed(6)}',
      'radius': radius.toString(),
      'extensions': 'base',
      'sortrule': 'distance',
      'offset': maxResults.toString(),
      'page': '1',
      if (keyword != null && keyword.trim().isNotEmpty) 'keywords': keyword.trim(),
    });
    if (data == null) return const <GeoPlace>[];
    final pois = data['pois'];
    if (pois is! List) return const <GeoPlace>[];
    final places = <GeoPlace>[];
    for (final item in pois) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final location = (item['location'] ?? '').toString().trim();
      double lat2 = 0;
      double lng2 = 0;
      final parts = location.split(',');
      if (parts.length == 2) {
        lng2 = double.tryParse(parts[0]) ?? 0;
        lat2 = double.tryParse(parts[1]) ?? 0;
      }
      places.add(GeoPlace(
        name: name,
        address: (item['address'] ?? '').toString().trim(),
        distance: int.tryParse((item['distance'] ?? '0').toString()) ?? 0,
        latitude: lat2,
        longitude: lng2,
      ));
      if (places.length >= maxResults) break;
    }
    return places;
  }

  /// 关键字搜索地点（全国范围，用于「搜索地点」框）。
  Future<List<GeoPlace>> searchByKeyword(String keyword, {int maxResults = 10}) async {
    final k = keyword.trim();
    if (k.isEmpty) return const <GeoPlace>[];
    final data = await _get('/v3/place/text', <String, String>{
      'keywords': k,
      'extensions': 'base',
      'offset': maxResults.toString(),
      'page': '1',
    });
    if (data == null) return const <GeoPlace>[];
    final pois = data['pois'];
    if (pois is! List) return const <GeoPlace>[];
    final places = <GeoPlace>[];
    for (final item in pois) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final location = (item['location'] ?? '').toString().trim();
      double lat2 = 0;
      double lng2 = 0;
      final parts = location.split(',');
      if (parts.length == 2) {
        lng2 = double.tryParse(parts[0]) ?? 0;
        lat2 = double.tryParse(parts[1]) ?? 0;
      }
      places.add(GeoPlace(
        name: name,
        address: (item['address'] ?? '').toString().trim(),
        latitude: lat2,
        longitude: lng2,
      ));
      if (places.length >= maxResults) break;
    }
    return places;
  }
}
