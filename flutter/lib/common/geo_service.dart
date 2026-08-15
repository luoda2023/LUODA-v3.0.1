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
import 'geo_utils.dart';

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

  /// 内置默认高德 Web 服务 key（软件自带，所有用户免配置）。
  /// 多个 key 轮询以分散每日配额；空列表时回退到腾讯/OSM。
  static const List<String> _builtinAmapKeys = <String>[
    // TODO: 填入真实申请的高德 Web 服务 key（32 位）。
  ];

  /// 内置默认腾讯位置服务 key（第二回退，GCJ-02 坐标系，与高德一致）。
  static const List<String> _builtinTencentKeys = <String>[
    // TODO: 填入真实申请的腾讯位置服务 key。
  ];

  String? _cachedKey;
  DateTime? _lastFetch;

  /// 用户自定义 key（设置页填写），优先于内置 key。
  String? get _userKey {
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

  /// 解析顺序：用户自定义 key > 内置高德 key。
  String? get apiKey => _userKey ?? _firstKey(_builtinAmapKeys);

  String? _firstKey(List<String> keys) {
    for (final k in keys) {
      if (k.trim().isNotEmpty) return k.trim();
    }
    return null;
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

  /// 高德或腾讯有内置 key 时，就认为有地名解析能力。
  bool get hasAnyBuiltinKey =>
      hasKey || _builtinTencentKeys.any((k) => k.trim().isNotEmpty);

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

  /// 逆地理编码：GCJ-02 坐标 → 中文地址。
  /// 优先高德（需 key），失败/无 key 时回退到 OSM Nominatim（免 key）。
  Future<String> reverseGeocode(double lat, double lng) async {
    final data = await _get('/v3/geocode/regeo', <String, String>{
      'location': '${lng.toStringAsFixed(6)},${lat.toStringAsFixed(6)}',
      'extensions': 'base',
    });
    if (data != null) {
      final regeocode = data['regeocode'];
      if (regeocode is Map<String, dynamic>) {
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
                  ? ((ac['streetNumber'] as Map<String, dynamic>)['street'] ??
                      '')
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
      }
    }
    // 回退：腾讯（内置 key）→ OSM Nominatim（海外）。
    final tencent = await _tencentReverse(lat, lng);
    if (tencent.$2.isNotEmpty) return tencent.$2;
    return (await _nominatimReverse(lat, lng)).$2;
  }

  /// 逆地理编码（详情版）：返回（POI 地名，完整地址）。
  /// 用 extensions=all 拿最近的 POI 名称作为地名（如“协和双语学校”），
  /// formatted_address 作为完整地址（如“上海市浦东新区xx路xx号”）。
  /// 无 key / 失败时回退到 OSM Nominatim（免 key），不再返回空串。
  Future<(String, String)> reverseGeocodeDetail(double lat, double lng) async {
    final data = await _get('/v3/geocode/regeo', <String, String>{
      'location': '${lng.toStringAsFixed(6)},${lat.toStringAsFixed(6)}',
      'extensions': 'all',
    });
    if (data != null) {
      final regeocode = data['regeocode'];
      if (regeocode is Map<String, dynamic>) {
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
                    ? ((ac['streetNumber'] as Map<String, dynamic>)['street'] ??
                        '')
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
        if (name.isNotEmpty || formatted.isNotEmpty) {
          return (name, formatted);
        }
      }
    }
    // 回退：腾讯（内置 key）→ OSM Nominatim（海外）。
    final tencent = await _tencentReverse(lat, lng);
    if (tencent.$1.isNotEmpty || tencent.$2.isNotEmpty) return tencent;
    return _nominatimReverse(lat, lng);
  }

  /// 腾讯位置服务逆地理编码（GCJ-02，与高德一致），内置 key 时的第二回退。
  /// 返回（地名, 完整地址）；失败返回 (空, 空)。
  Future<(String, String)> _tencentReverse(double lat, double lng) async {
    final key = _firstKey(_builtinTencentKeys);
    if (key == null) return ('', '');
    final uri = Uri.parse('https://apis.map.qq.com/ws/geocoder/v1/')
        .replace(queryParameters: <String, String>{
      'location': '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
      'key': key,
    });
    try {
      final resp = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return ('', '');
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return ('', '');
      if ((decoded['status'] ?? 1) != 0) return ('', '');
      final result = decoded['result'];
      if (result is! Map<String, dynamic>) return ('', '');
      // 地名：优先 landmark_l1（如“协和双语学校”）。
      var name = '';
      final ref = result['address_reference'];
      if (ref is Map<String, dynamic>) {
        final landmark = ref['landmark_l1'];
        if (landmark is Map<String, dynamic>) {
          name = (landmark['title'] ?? '').toString().trim();
        }
      }
      if (name.isEmpty) {
        final ad = result['ad_info'];
        if (ad is Map<String, dynamic>) {
          name = (ad['name'] ?? '').toString().trim();
        }
      }
      // 完整地址：address，回退到 formatted_addresses.recommend。
      var address = (result['address'] ?? '').toString().trim();
      if (address.isEmpty) {
        final fm = result['formatted_addresses'];
        if (fm is Map<String, dynamic>) {
          address =
              (fm['recommend'] ?? fm['rough'] ?? '').toString().trim();
        }
      }
      return (name, address);
    } catch (_) {
      return ('', '');
    }
  }

  /// 无需 key 的逆地理编码：OSM Nominatim 公共服务。
  /// 输入 GCJ-02 坐标（与高德一致），内部转 WGS-84 后查询。
  /// 返回（地名, 完整地址）；失败返回 (空, 空)。
  Future<(String, String)> _nominatimReverse(double lat, double lng) async {
    final wgs = gcj02ToWgs84(lat, lng).$1;
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse')
        .replace(queryParameters: <String, String>{
      'format': 'jsonv2',
      'lat': wgs.x.toStringAsFixed(7),
      'lon': wgs.y.toStringAsFixed(7),
      'zoom': '18',
      'addressdetails': '1',
      'accept-language': 'zh-CN',
    });
    try {
      final resp = await http.get(
        uri,
        headers: const <String, String>{
          // Nominatim 使用政策要求标识 UA，否则会被限流/拒绝。
          'User-Agent': 'DotChat/3.1.1 (dotchat client)',
        },
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return ('', '');
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return ('', '');
      // 地名：优先 name，其次 address 里的 POI 类字段（建筑/设施/商店等）。
      var name = (decoded['name'] ?? '').toString().trim();
      final addr = decoded['address'];
      if (name.isEmpty && addr is Map<String, dynamic>) {
        for (final k in const <String>[
          'building',
          'amenity',
          'shop',
          'tourism',
          'leisure',
          'office',
          'place_of_worship',
        ]) {
          final v = (addr[k] ?? '').toString().trim();
          if (v.isNotEmpty) {
            name = v;
            break;
          }
        }
      }
      // 完整地址：拼城市/区/街道，比 display_name 更友好、不冗余。
      var address = '';
      if (addr is Map<String, dynamic>) {
        final seen = <String>{};
        final parts = <String>[
          (addr['province'] ?? addr['state'] ?? ''),
          (addr['city'] ?? ''),
          (addr['district'] ?? addr['county'] ?? ''),
          (addr['suburb'] ?? ''),
          (addr['neighbourhood'] ?? ''),
          (addr['road'] ?? ''),
          (addr['house_number'] ?? ''),
        ].map((e) => e.toString().trim()).where((e) => e.isNotEmpty);
        final filtered = <String>[];
        for (final p in parts) {
          if (seen.contains(p)) continue;
          seen.add(p);
          filtered.add(p);
        }
        address = filtered.join('');
      }
      if (address.isEmpty) {
        address = (decoded['display_name'] ?? '').toString().trim();
      }
      return (name, address);
    } catch (_) {
      return ('', '');
    }
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
