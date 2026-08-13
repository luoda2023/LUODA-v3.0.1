// 微信风格“发送位置”选择页。
//
// 打开一张地图（高德瓦片，GCJ-02 坐标系，与国内地图 App 一致），
// 初始显示“我的位置”，地图中心有十字定位点：拖动地图即选择位置，
// 右上角“发送”把选中的坐标（GCJ-02）返回给调用方。
//
// 返回类型：SendLocationResult？—— null 表示取消。

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../common.dart';
import '../geo_utils.dart';

/// 用户最终选中的位置（GCJ-02 坐标）。
class PickedLocation {
  const PickedLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
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

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // GPS → GCJ-02，保证“我的位置”在高德/腾讯地图上准确。
    final gcj = wgs84ToGcj02(widget.gpsLat, widget.gpsLng).$1;
    _myLocation = LatLng(gcj.x, gcj.y);
    _picked = _myLocation;
  }

  void _backToMyLocation() {
    _mapController.move(_myLocation, 16);
    setState(() => _picked = _myLocation);
  }

  void _confirm() {
    final picked = _picked;
    if (picked == null) return;
    Navigator.of(context).pop(
      PickedLocation(latitude: picked.latitude, longitude: picked.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF1E2024) : Colors.white,
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xFF26292F) : Colors.white,
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
      body: Stack(
        children: <Widget>[
          // 地图主体（高德瓦片，无 key；GCJ-02 坐标系）。
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation,
              initialZoom: 16,
              minZoom: 3,
              maxZoom: 19,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  setState(() => _picked = camera.center);
                }
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
                      Shadow(
                        color: Colors.white,
                        blurRadius: 8,
                      ),
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
          // 右下角：回到我的位置。
          Positioned(
            right: 16,
            bottom: 130,
            child: Material(
              color: dark ? const Color(0xFF2A2D33) : Colors.white,
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
          // 底部：当前选择位置卡片 + 发送按钮。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF26292F) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Colors.black26, blurRadius: 10),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.location_on_rounded,
                    color: const Color(0xFF07C160),
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          translate('My Location'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: dark
                                ? Colors.white
                                : const Color(0xFF222222),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _picked == null
                              ? ''
                              : '${_picked!.latitude.toStringAsFixed(5)}, '
                                  '${_picked!.longitude.toStringAsFixed(5)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: dark
                                ? Colors.white54
                                : const Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF07C160),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      translate('Send'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
