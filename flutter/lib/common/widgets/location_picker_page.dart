// 微信风格“发送位置”选择页。
//
// 布局（自上而下）：
//   1. 高德瓦片地图（无 key，GCJ-02），中心绿色大头针，拖动地图即选点；
//   2. “搜索地点”输入框：点击聚焦后可输入关键词搜索（需高德 key，
//      未配置 key 时仍可用，只是没有结果，不影响基础选点）；
//   3. 地点列表：第一项固定为“我的位置”，下方为周边地点（需 key）。
//
// 底部“发送”把选中的 GCJ-02 坐标 + 名称 + 地址返回给调用方。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../common.dart';
import '../geo_service.dart';
import '../geo_utils.dart';

/// 用户最终选中的位置（GCJ-02 坐标 + 名称 + 详细地址）。
class PickedLocation {
  const PickedLocation({
    required this.latitude,
    required this.longitude,
    this.name = '',
    this.address = '',
  });

  final double latitude;
  final double longitude;
  final String name;
  final String address;
}

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({
    super.key,
    required this.gpsLat,
    required this.gpsLng,
  });

  /// 当前 GPS 位置（WGS-84），用于初始定位“我的位置”。
  final double gpsLat;
  final double gpsLng;

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  late final MapController _mapController;
  late final LatLng _myLocation; // GCJ-02（显示用）
  LatLng? _picked; // 当前中心选择点（GCJ-02）
  final TextEditingController _searchController = TextEditingController();
  bool _placesLoading = false;
  List<GeoPlace> _places = const <GeoPlace>[];
  String _currentName = ''; // 当前选中点地名（逆地理编码 POI 名，随地图移动更新）
  String _currentAddress = ''; // 当前选中点的逆地理编码地址
  String _selectedName = ''; // 当前选中点名称（POI 名；拖动地图时清空）
  bool _addressLoading = false;
  bool _fromCache = false; // 当前地名是否来自缓存（提示可手动刷新）
  bool _quotaLimited = false; // 地图服务配额耗尽（友好提示）
  Timer? _addressDebounce; // 拖动地图防抖，避免连续请求超 Nominatim 限流
  int _addressSeq = 0; // 只应用最后一次解析结果，防竞态乱序

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // GPS → GCJ-02，保证“我的位置”在高德/腾讯地图上准确。
    final gcj = wgs84ToGcj02(widget.gpsLat, widget.gpsLng).$1;
    _myLocation = LatLng(gcj.x, gcj.y);
    _picked = _myLocation;
    _loadNearby(_myLocation);
    _resolveAddress(_myLocation);
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNearby(LatLng center, {String? keyword}) async {
    if (!AmapService.instance.hasKey) return;
    setState(() => _placesLoading = true);
    final places = await AmapService.instance.searchNearby(
      center.latitude,
      center.longitude,
      keyword: keyword,
      radius: 3000,
    );
    if (!mounted) return;
    setState(() {
      _places = places;
      _placesLoading = false;
    });
  }

  Future<void> _resolveAddress(LatLng center, {bool forceRefresh = false}) async {
    // 无需判断 hasKey：有 key 用高德，无 key 自动回退 OSM Nominatim。
    final seq = ++_addressSeq;
    setState(() {
      _addressLoading = true;
      if (forceRefresh) {
        _fromCache = false;
        _quotaLimited = false;
      }
    });
    final result = await AmapService.instance.reverseGeocodeDetail(
      center.latitude,
      center.longitude,
      forceRefresh: forceRefresh,
    );
    if (!mounted || seq != _addressSeq) return;
    setState(() {
      // 地名随地图移动实时更新（微信样式：“我的位置”显示实际地名）。
      if (result.name.isNotEmpty) _currentName = result.name;
      if (result.address.isNotEmpty) _currentAddress = result.address;
      _fromCache = result.fromCache;
      _quotaLimited = result.quotaLimited;
      _addressLoading = false;
    });
  }

  /// 手动刷新地名（跳过缓存直接请求）。
  void _refreshAddress() {
    final picked = _picked ?? _myLocation;
    _resolveAddress(picked, forceRefresh: true);
  }

  void _backToMyLocation() {
    _mapController.move(_myLocation, 16);
    setState(() {
      _picked = _myLocation;
      _selectedName = '';
      _currentName = '';
    });
    _searchController.clear();
    _loadNearby(_myLocation);
    _resolveAddress(_myLocation);
  }

  void _onMapMoved(LatLng center) {
    setState(() {
      _picked = center;
      // 拖动地图即表示选择自定义点，清空已选地点名，避免列表残留高亮。
      _selectedName = '';
      _currentName = ''; // 地名稍后由逆地理编码刷新
    });
    // 拖动停止 400ms 后才查询，避免连续拖动打爆 Nominatim/高德限流。
    _addressDebounce?.cancel();
    _addressDebounce = Timer(const Duration(milliseconds: 400), () {
      _loadNearby(center);
      _resolveAddress(center);
    });
  }

  void _pickPlace(GeoPlace place, {bool isMyLocation = false}) {
    final target = isMyLocation
        ? _myLocation
        : (place.latitude != 0 || place.longitude != 0
            ? LatLng(place.latitude, place.longitude)
            : _picked ?? _myLocation);
    _mapController.move(target, 16);
    setState(() {
      _picked = target;
      _selectedName = isMyLocation ? '' : place.name;
      _currentName = isMyLocation ? '' : place.name;
      _searchController.clear();
    });
    _loadNearby(target);
    _resolveAddress(target);
  }

  Future<void> _submitSearch(String text) async {
    final keyword = text.trim();
    if (keyword.isEmpty) {
      return;
    }
    if (!AmapService.instance.hasKey) {
      showToast(translate('Map service key not configured'));
      return;
    }
    setState(() => _placesLoading = true);
    final results =
        await AmapService.instance.searchByKeyword(keyword, maxResults: 15);
    if (!mounted) return;
    setState(() {
      _places = results;
      _placesLoading = false;
    });
  }

  void _confirm() {
    final picked = _picked;
    if (picked == null) return;
    // 发送的名字优先用选中地点名，否则用逆地理编码出的实际地名，
    // 都不再显示笼统的“我的位置”。
    final name = _selectedName.isNotEmpty
        ? _selectedName
        : (_currentName.isNotEmpty ? _currentName : translate('My Location'));
    Navigator.of(context).pop(
      PickedLocation(
        latitude: picked.latitude,
        longitude: picked.longitude,
        name: name,
        address: _currentAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cardBg = dark ? const Color(0xFF26292F) : Colors.white;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF1E2024) : const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          translate('Send location'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _confirm,
            child: Text(
              translate('Send'),
              style: const TextStyle(
                color: Color(0xFF07C160),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 搜索框（微信布局：标题栏下方，地图上方）。
          Container(
            color: cardBg,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: _submitSearch,
              decoration: InputDecoration(
                isDense: true,
                hintText: translate('Search places'),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: dark
                    ? const Color(0xFF1E2024)
                    : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ),
          // 地图区：约 42% 高度（微信样式：地图在上、列表在下，
          // 底部留出更多空间给地点列表，不再大段空白）。
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.42,
            child: Stack(
              children: <Widget>[
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _myLocation,
                    initialZoom: 16,
                    minZoom: 3,
                    maxZoom: 19,
                    onPositionChanged: (camera, hasGesture) {
                      if (hasGesture) _onMapMoved(camera.center);
                    },
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: <Widget>[
                    TileLayer(
                      urlTemplate:
                          'https://webrd0{s}.is.autonavi.com/appmaptile'
                          '?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                      subdomains: const <String>['1', '2', '3', '4'],
                      userAgentPackageName: 'com.luoda.remote',
                      maxNativeZoom: 19,
                    ),
                  ],
                ),
                // 地图中心定位点（微信风格：拖动地图即选择该点）。
                IgnorePointer(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.location_on_rounded,
                          size: 40,
                          color: const Color(0xFF07C160),
                          shadows: const <Shadow>[
                            Shadow(color: Colors.white, blurRadius: 8),
                          ],
                        ),
                        Transform.translate(
                          offset: const Offset(0, -22),
                          child: Container(
                            width: 1,
                            height: 14,
                            color: const Color(0xFF07C160),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 左上角：当前选中点地址（逆地理编码，有 key 时）。
                if (_addressLoading)
                  const Positioned(
                    left: 12,
                    top: 12,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_quotaLimited)
                  // 配额耗尽友好提示：地名暂时无法获取。
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7E6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF5C97B)),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: Colors.black12, blurRadius: 6),
                        ],
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: Color(0xFFE6A23C)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              translate('Map service quota exhausted, '
                                  'place name temporarily unavailable'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: Color(0xFF8A6D3B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: _refreshAddress,
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.refresh_rounded,
                                  size: 16, color: Color(0xFF8A6D3B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_currentAddress.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                      decoration: BoxDecoration(
                        color: cardBg.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: Colors.black12, blurRadius: 6),
                        ],
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  _currentAddress,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: dark
                                        ? Colors.white
                                        : const Color(0xFF444444),
                                  ),
                                ),
                                if (_fromCache) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    translate('Cached place name, tap to '
                                        'refresh'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: dark
                                          ? Colors.white38
                                          : const Color(0xFF999999),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // 手动刷新（跳过缓存重新解析）。
                          IconButton(
                            tooltip: translate('Refresh place name'),
                            onPressed: _refreshAddress,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.refresh_rounded,
                                size: 18, color: Color(0xFF07C160)),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 右下角：回到我的位置。
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Material(
                    color: cardBg,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      tooltip: translate('My location'),
                      onPressed: _backToMyLocation,
                      icon: Icon(
                        Icons.my_location_rounded,
                        color: const Color(0xFF07C160),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 地点列表：我的位置 + 周边/搜索结果。
          Expanded(
            child: _placesLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: <Widget>[
                      _locationTile(
                        icon: Icons.navigation_rounded,
                        // 微信样式：第一项显示实际地名（随地图移动实时变化），
                        // 逆地理编码未返回时才回退到“我的位置”。
                        title: _currentName.isNotEmpty
                            ? _currentName
                            : translate('My Location'),
                        subtitle: _currentAddress.isNotEmpty
                            ? _currentAddress
                            : '${_myLocation.latitude.toStringAsFixed(5)}, '
                                '${_myLocation.longitude.toStringAsFixed(5)}',
                        isMyLocation: true,
                      ),
                      for (final place in _places)
                        _locationTile(
                          icon: Icons.place_rounded,
                          title: place.name,
                          subtitle: [
                            if (place.distanceLabel.isNotEmpty)
                              place.distanceLabel,
                            if (place.address.isNotEmpty) place.address,
                          ].join(' | '),
                          place: place,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 当前是否选中了该项（用于列表选中高亮）。
  bool _isPicked({
    GeoPlace? place,
    bool isMyLocation = false,
  }) {
    if (isMyLocation) {
      return _selectedName.isEmpty && _picked == _myLocation;
    }
    final picked = _picked;
    if (picked == null || _selectedName.isEmpty) return false;
    return place != null && place.name == _selectedName;
  }

  Widget _locationTile({
    required IconData icon,
    required String title,
    required String subtitle,
    GeoPlace? place,
    bool isMyLocation = false,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final selected = _isPicked(place: place, isMyLocation: isMyLocation);
    final primary = const Color(0xFF07C160);
    return InkWell(
      onTap: () => _pickPlace(place ?? GeoPlace(name: title), isMyLocation: isMyLocation),
      child: Container(
        color: selected
            ? (dark ? primary.withOpacity(0.12) : primary.withOpacity(0.06))
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(icon,
                size: 22,
                color: selected ? primary : (dark ? Colors.white54 : const Color(0xFF9AA0A6))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? primary
                          : (dark ? Colors.white : const Color(0xFF222222)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: dark ? Colors.white60 : const Color(0xFF888888),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  size: 18, color: Color(0xFF07C160))
            else
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }
}
