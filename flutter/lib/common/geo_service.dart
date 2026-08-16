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

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../models/platform_model.dart';
import 'geo_utils.dart';

/// 逆地理编码结果（地名 + 完整地址 + 来源信息）。
class GeoReverseResult {
  const GeoReverseResult({
    required this.name,
    required this.address,
    this.fromCache = false,
    this.quotaLimited = false,
  });

  /// 空结果：地名和地址都为空。
  const GeoReverseResult.empty()
      : name = '',
        address = '',
        fromCache = false,
        quotaLimited = false;

  final String name;
  final String address;

  /// 是否命中本地缓存（未发起网络请求）。
  final bool fromCache;

  /// 地图服务配额已耗尽（百度 4/302 等配额类错误码）。
  final bool quotaLimited;

  bool get isEmpty => name.isEmpty && address.isEmpty;
}

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
  static const _baiduStorageKey = 'baidu-web-service-ak';
  static const _base = 'https://restapi.amap.com';

  /// 内置默认高德 Web 服务 key（软件自带，所有用户免配置）。
  /// 由用户在高德开放平台（lbs.amap.com）申请、授权内置，用于逆地理编码
  /// 与周边地点搜索；若被停用，用户仍可在设置页填自己的 key，或由回退链
  /// 自动降级到百度公开 key / OSM。
  static const List<String> _builtinAmapKeys = <String>[
    '8b18ef3d43e35c791e0b80dfb830c5c2',
  ];

  /// 内置默认腾讯位置服务 key（第三回退，GCJ-02 坐标系，与高德一致）。
  /// 腾讯官方示例 key 与社区公开 key 均已失效（未开启/被停用 WebService），
  /// 保留结构以便后续填入有效 key。
  static const List<String> _builtinTencentKeys = <String>[
    // TODO: 填入真实申请的腾讯位置服务 key（需在控制台开启 WebServiceAPI）。
  ];

  /// 内置默认百度地图 Web 服务 key（第二回退，输入 GCJ-02 自动转 BD-09）。
  /// 来自开源项目公开分享的可用 key，作为免配置兑底；若被停用，
  /// 用户仍可在设置页填自定义 key，或由回退链自动降级到 OSM。
  static const List<String> _builtinBaiduKeys = <String>[
    'YY5lVvoVmMSw7AHA11VQvw57GVdA6fLp',
  ];

  List<String>? _cachedKeys;
  List<String>? _cachedBaiduKeys;
  DateTime? _lastFetch;

  /// 把用户输入的原始 key 文本拆成列表（支持逗号/分号/换行分隔多个 key，
  /// 主 key 配额耗尽时自动轮换到备用 key）。
  static List<String> _splitKeys(String raw) {
    return raw
        .split(RegExp(r'[,;，；\n\r]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 用户自定义高德 key 列表（设置页填写，支持多个，逗号分隔），优先于内置 key。
  List<String> get _userKeys {
    final now = DateTime.now();
    if (_cachedKeys == null ||
        _lastFetch == null ||
        now.difference(_lastFetch!).inSeconds > 60) {
      _lastFetch = now;
      try {
        _cachedKeys = _splitKeys(bind.mainGetLocalOption(key: _storageKey));
      } catch (_) {
        _cachedKeys = <String>[];
      }
    }
    return _cachedKeys!;
  }

  /// 用户自定义百度 AK 列表（设置页填写，支持多个）。
  List<String> get _userBaiduKeys {
    final now = DateTime.now();
    if (_cachedBaiduKeys == null ||
        _lastFetch == null ||
        now.difference(_lastFetch!).inSeconds > 60) {
      _lastFetch = now;
      try {
        _cachedBaiduKeys =
            _splitKeys(bind.mainGetLocalOption(key: _baiduStorageKey));
      } catch (_) {
        _cachedBaiduKeys = <String>[];
      }
    }
    return _cachedBaiduKeys!;
  }

  /// 解析顺序：用户自定义 key（可多个）> 内置高德 key（可多个）。
  /// 返回去重后的完整 key 列表，供逐 key 轮换。
  List<String> get apiKeys {
    final list = <String>[
      ..._userKeys,
      ..._builtinAmapKeys,
    ];
    final seen = <String>{};
    final result = <String>[];
    for (final k in list) {
      final t = k.trim();
      if (t.isEmpty || seen.contains(t)) continue;
      seen.add(t);
      result.add(t);
    }
    return result;
  }

  /// 第一个可用 key（兼容旧调用，展示用）。
  String? get apiKey {
    final keys = apiKeys;
    return keys.isEmpty ? null : keys.first;
  }

  /// 用户自定义百度 AK 列表（公开，设置页展示用）。
  List<String> get baiduUserKeys => _userBaiduKeys;

  String? _firstKey(List<String> keys) {
    for (final k in keys) {
      if (k.trim().isNotEmpty) return k.trim();
    }
    return null;
  }

  /// 逆地理结果缓存：按 0.001 度网格（约 111 米）+ 10 分钟 TTL 去重。
  /// 免费地图 key 的每日配额有限，用户反复拖动地图/重开定位页会快速打爆
  /// 配额，导致地名突然不显示。缓存同一小区域的结果，显著降低请求量。
  static final Map<String, (String, String)> _geoCache =
      <String, (String, String)>{};
  static final Map<String, DateTime> _geoCacheAt = <String, DateTime>{};
  static const Duration _geoCacheTtl = Duration(minutes: 10);
  static const int _geoCacheDigits = 3; // 0.001 度 ≈ 111 米

  static String _geoCacheKey(double lat, double lng) =>
      '${lat.toStringAsFixed(_geoCacheDigits)},'
      '${lng.toStringAsFixed(_geoCacheDigits)}';

  static (String, String)? _geoCacheGet(double lat, double lng) {
    final key = _geoCacheKey(lat, lng);
    final at = _geoCacheAt[key];
    if (at == null) return null;
    if (DateTime.now().difference(at) > _geoCacheTtl) {
      _geoCache.remove(key);
      _geoCacheAt.remove(key);
      return null;
    }
    return _geoCache[key];
  }

  static void _geoCachePut(double lat, double lng, (String, String) value) {
    // 失败结果（地名和地址都为空）不缓存，下次仍会重试。
    if (value.$1.isEmpty && value.$2.isEmpty) return;
    final key = _geoCacheKey(lat, lng);
    _geoCache[key] = value;
    _geoCacheAt[key] = DateTime.now();
    // 防止极端情况下缓存无限增长（同一时间只会有少量活跃网格）。
    if (_geoCache.length > 64) {
      final oldestKey = _geoCacheAt.keys.first;
      _geoCache.remove(oldestKey);
      _geoCacheAt.remove(oldestKey);
    }
  }

  Future<void> saveApiKey(String value) async {
    _cachedKeys = _splitKeys(value);
    _lastFetch = DateTime.now();
    try {
      await bind.mainSetLocalOption(key: _storageKey, value: value.trim());
    } catch (_) {
      // 本地配置写入失败时静默忽略。
    }
  }

  /// 保存用户百度 AK（支持逗号分隔多个，主 key 耗尽自动轮换备用）。
  Future<void> saveBaiduApiKeys(String value) async {
    _cachedBaiduKeys = _splitKeys(value);
    _lastFetch = DateTime.now();
    try {
      await bind.mainSetLocalOption(key: _baiduStorageKey, value: value.trim());
    } catch (_) {
      // 本地配置写入失败时静默忽略。
    }
  }

  bool get hasKey => apiKey != null && apiKey!.isNotEmpty;

  /// 高德/百度/腾讯有内置 key 时，就认为有地名解析能力。
  bool get hasAnyBuiltinKey =>
      hasKey ||
      _builtinBaiduKeys.any((k) => k.trim().isNotEmpty) ||
      _builtinTencentKeys.any((k) => k.trim().isNotEmpty);

  /// 高德 key 相关/配额类错误码：当前 key 无效或配额耗尽时轮换到下一个 key。
  /// 10001 非正确 key，10003 服务未开通，10008 key 过期，10009 key 状态异常，
  /// 10012 日配额超限，10013 QPS 超限。
  static bool isAmapQuotaStatus(String status) =>
      const <String>{
        '10001', '10003', '10008', '10009', '10012', '10013',
      }.contains(status);

  /// 带 key 轮换的 GET：主 key 配额耗尽/失效时自动切换备用 key，
  /// 全部 key 都失败才返回 null，保证地名解析不断档。
  Future<Map<String, dynamic>?> _get(
    String path,
    Map<String, String> query,
  ) async {
    final keys = apiKeys;
    if (keys.isEmpty) return null;
    for (final key in keys) {
      final uri = Uri.parse('$_base$path')
          .replace(queryParameters: <String, String>{...query, 'key': key});
      try {
        final resp = await http
            .get(uri)
            .timeout(const Duration(seconds: 8));
        // 401/403：当前 key 无效/被禁，直接换下一个 key。
        if (resp.statusCode == 401 || resp.statusCode == 403) continue;
        if (resp.statusCode != 200) return null;
        final decoded = jsonDecode(resp.body);
        if (decoded is! Map<String, dynamic>) continue;
        final status = (decoded['status'] ?? '0').toString();
        if (status != '1') {
          // 配额/权限类错误：换下一个 key；其他错误（参数等）直接失败。
          if (isAmapQuotaStatus(status)) continue;
          return null;
        }
        return decoded;
      } catch (_) {
        // 网络异常与 key 无关，不轮换，直接失败（避免无谓重试全部 key）。
        return null;
      }
    }
    return null;
  }

  /// 逆地理编码：GCJ-02 坐标 → 中文地址。
  /// 优先高德（需 key），失败/无 key 时回退到 OSM Nominatim（免 key）。
  Future<String> reverseGeocode(double lat, double lng) async {
    // 复用详情版逻辑（含缓存与回退链），只取地址部分。
    final result = await reverseGeocodeDetail(lat, lng);
    return result.address;
  }

  /// 逆地理编码（详情版）：返回地名 + 完整地址 + 来源信息。
  /// 用 extensions=all 拿最近的 POI 名称作为地名（如“协和双语学校”），
  /// formatted_address 作为完整地址（如“上海市浦东新区xx路xx号”）。
  /// 解析顺序：缓存 → 内置百度 key（免配置，目前唯一稳定可用）→ 高德（用户
  /// key）→ 腾讯（内置 key）→ OSM Nominatim（海外免 key）。结果按 111 米网格
  /// 缓存 10 分钟，避免打爆免费 key 的每日配额。
  ///
  /// [forceRefresh] 为 true 时跳过缓存直接请求（供“手动刷新”使用）。
  Future<GeoReverseResult> reverseGeocodeDetail(
    double lat,
    double lng, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _geoCacheGet(lat, lng);
      if (cached != null && (cached.$1.isNotEmpty || cached.$2.isNotEmpty)) {
        return GeoReverseResult(
          name: cached.$1,
          address: cached.$2,
          fromCache: true,
        );
      }
    }
    // 高德（用户 key 或内置 key）优先：正式 key 配额充足且国内稳定。
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
          final r = (name, formatted);
          _geoCachePut(lat, lng, r);
          return GeoReverseResult(name: name, address: formatted);
        }
      }
    }
    // 回退：百度（内置公开 key，免配置兑底）。
    final baidu = await _baiduReverse(lat, lng);
    if (baidu.$1.isNotEmpty || baidu.$2.isNotEmpty) {
      _geoCachePut(lat, lng, (baidu.$1, baidu.$2));
      return GeoReverseResult(name: baidu.$1, address: baidu.$2);
    }
    if (baidu.$3) {
      // 免费 key 配额耗尽：给用户友好提示，避免静默失败。
      return const GeoReverseResult(
        name: '',
        address: '',
        quotaLimited: true,
      );
    }
    // 回退：腾讯（内置 key）→ OSM Nominatim（海外）。
    final tencent = await _tencentReverse(lat, lng);
    if (tencent.$1.isNotEmpty || tencent.$2.isNotEmpty) {
      _geoCachePut(lat, lng, (tencent.$1, tencent.$2));
      return GeoReverseResult(name: tencent.$1, address: tencent.$2);
    }
    final nom = await _nominatimReverse(lat, lng);
    if (nom.$1.isNotEmpty || nom.$2.isNotEmpty) {
      _geoCachePut(lat, lng, (nom.$1, nom.$2));
      return GeoReverseResult(name: nom.$1, address: nom.$2);
    }
    return const GeoReverseResult.empty();
  }

  /// 解析百度逆地理响应为（地名, 完整地址）。公开便于单元测试。
  static (String, String) parseBaiduResponse(Map<String, dynamic> decoded) {
    if ((decoded['status'] ?? 1) != 0) return ('', '');
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) return ('', '');
    // 地名：优先商圈名（如“人民广场”），其次行政区名。
    var name = '';
    final business = (result['business'] ?? '').toString().trim();
    if (business.isNotEmpty) {
      name = business.split(',').first.trim();
    }
    if (name.isEmpty) {
      final ac = result['addressComponent'];
      if (ac is Map<String, dynamic>) {
        name = (ac['district'] ?? '').toString().trim();
      }
    }
    // 完整地址：formatted_address。
    final address = (result['formatted_address'] ?? '').toString().trim();
    return (name, address);
  }

  /// 百度地图逆地理编码（输入 GCJ-02，coordtype=gcj02ll 由百度内部转 BD-09）。
  /// 多 key 自动轮换：用户 AK（设置页可配多个）优先，其次内置 AK；
  /// 主 key 配额耗尽（status 4/302）时继续尝试下一个备用 key，
  /// 全部 key 都耗尽才返回 quotaLimited，保证地名解析不断档。
  /// 返回（地名, 完整地址, 是否配额耗尽）。
  Future<(String, String, bool)> _baiduReverse(double lat, double lng) async {
    var quotaLimited = false;
    final keys = <String>[..._userBaiduKeys, ..._builtinBaiduKeys];
    for (final key in keys) {
      final k = key.trim();
      if (k.isEmpty) continue;
      final result = await _baiduReverseOnce(k, lat, lng);
      if (result.$1.isNotEmpty || result.$2.isNotEmpty) return result;
      if (result.$3) {
        // 当前 key 配额耗尽：标记并切换下一个备用 key，不中断轮换。
        quotaLimited = true;
        continue;
      }
    }
    return ('', '', quotaLimited);
  }

  /// 单次百度逆地理请求；移动网络抖动常见，失败重试一次。
  /// 返回（地名, 完整地址, 是否配额耗尽）。
  Future<(String, String, bool)> _baiduReverseOnce(
      String key, double lat, double lng) async {
    final uri = Uri.parse('https://api.map.baidu.com/reverse_geocoding/v3/')
        .replace(queryParameters: <String, String>{
      'ak': key,
      'output': 'json',
      'coordtype': 'gcj02ll',
      'location': '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
      'pois': '1',
    });
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await http.get(uri).timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) {
          debugPrint('geo: baidu http ${resp.statusCode} (attempt $attempt)');
          continue;
        }
        final decoded = jsonDecode(resp.body);
        if (decoded is! Map<String, dynamic>) continue;
        final result = parseBaiduResponse(decoded);
        if (result.$1.isNotEmpty || result.$2.isNotEmpty) {
          return (result.$1, result.$2, false);
        }
        // 百度配额类错误码：4（配额超限）/ 302（天配额超限）。
        final status = (decoded['status'] ?? -1).toString();
        if (status == '4' || status == '302') {
          debugPrint('geo: baidu quota limited (status=$status)');
          return ('', '', true);
        }
        debugPrint('geo: baidu status=$status');
      } catch (e) {
        debugPrint('geo: baidu error $e (attempt $attempt)');
      }
    }
    return ('', '', false);
  }

  /// 腾讯位置服务逆地理编码（GCJ-02，与高德一致），内置 key 时的第三回退。
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
