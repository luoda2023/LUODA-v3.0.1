// 微信风格「位置详情」页。
//
// 聊天里点击位置卡片打开：全屏地图 + 红色大头针标记该位置，
// 底部信息卡显示地点名称 / 详细地址 / 坐标，底部操作栏提供
// 「导航」（调起高德/百度/腾讯地图 App 或网页）与「复制位置」。
//
// 地图瓦片使用高德栅格瓦片（免费、无需 key），坐标已为 GCJ-02，
// 与高德/腾讯/百度国内地图一致。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common.dart';
import '../direct_chat.dart';
import '../geo_service.dart';
import 'system_share.dart';

class LocationDetailPage extends StatefulWidget {
  const LocationDetailPage({super.key, required this.location});

  final DirectChatLocation location;

  @override
  State<LocationDetailPage> createState() => _LocationDetailPageState();
}

class _LocationDetailPageState extends State<LocationDetailPage> {
  late final LatLng _center;
  String? _address;

  DirectChatLocation get location => widget.location;

  @override
  void initState() {
    super.initState();
    _center = LatLng(location.latitude, location.longitude);
    _resolveAddress();
  }

  /// 有高德 key 时尝试解析详细地址；无 key 或失败时保留空白（显示坐标）。
  Future<void> _resolveAddress() async {
    final address =
        await AmapService.instance.reverseGeocode(_center.latitude, _center.longitude);
    if (!mounted || address.isEmpty) return;
    setState(() => _address = address);
  }

  String get _displayName {
    final name = location.name.trim();
    return name.isNotEmpty ? name : translate('Location');
  }

  void _navigate() async {
    final name = Uri.encodeComponent(_displayName);
    final lat = location.latitude.toStringAsFixed(6);
    final lng = location.longitude.toStringAsFixed(6);
    final options = <(IconData, String, String)>[
      (
        Icons.navigation_rounded,
        translate('Amap'),
        'https://uri.amap.com/navigation?to=$lng,$lat,$name&mode=car',
      ),
      (
        Icons.public_rounded,
        translate('Baidu Maps'),
        'https://api.map.baidu.com/direction?destination=latlng:$lat,$lng'
        '|name:$name&coord_type=gcj02&mode=driving',
      ),
      (
        Icons.location_city_rounded,
        translate('Tencent Maps'),
        'https://apis.map.qq.com/uri/v1/routeplan?type=drive&to=$lat,$lng'
        '&tocoord=$lat,$lng&referer=luoda',
      ),
    ];
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Text(
                translate('Navigate with'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            for (final option in options)
              ListTile(
                leading: Icon(option.$1, color: const Color(0xFF07C160)),
                title: Text(option.$2),
                onTap: () {
                  Navigator.pop(sheetContext, option.$3);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      await launchUrlString(picked, mode: LaunchMode.externalApplication);
    }
  }

  void _copyLocation() {
    final text = '$_displayName\n'
        '${location.latitude.toStringAsFixed(6)}, '
        '${location.longitude.toStringAsFixed(6)}';
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(translate('Copied'));
  }

  /// 分享位置文本（名称 + 坐标 + 地址）到系统分享面板（微信等）。
  Future<void> _shareLocation() async {
    final name = _displayName;
    final address = _address;
    final text = <String>[
      name,
      if (address != null && address.isNotEmpty) address,
      '${location.latitude.toStringAsFixed(6)}, '
          '${location.longitude.toStringAsFixed(6)}',
    ].join('\n');
    final ok = await shareTextToSystemApp(text, subject: name);
    if (!ok && mounted) {
      showToast(translate('Share failed'));
    }
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
          translate('Location'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 16,
                minZoom: 3,
                maxZoom: 19,
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
                  userAgentPackageName: 'com.dotchat.remote',
                  maxNativeZoom: 19,
                ),
                MarkerLayer(
                  markers: <Marker>[
                    Marker(
                      point: _center,
                      width: 56,
                      height: 56,
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 48,
                        color: Color(0xFFFF4D4F),
                        shadows: <Shadow>[
                          Shadow(color: Colors.white, blurRadius: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 底部信息卡：名称 / 地址 / 坐标 + 操作按钮。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF26292F) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Colors.black26, blurRadius: 12),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: dark ? Colors.white : const Color(0xFF222222),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _address ?? '${location.latitude.toStringAsFixed(6)}, '
                          '${location.longitude.toStringAsFixed(6)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: dark
                            ? Colors.white60
                            : const Color(0xFF888888),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _actionButton(
                            icon: Icons.navigation_rounded,
                            label: translate('Navigate'),
                            onTap: _navigate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.copy_rounded,
                            label: translate('Copy'),
                            onTap: _copyLocation,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.ios_share_rounded,
                            label: translate('Share'),
                            onTap: _shareLocation,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF3A3D43) : const Color(0xFFF2F3F5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 18, color: const Color(0xFF07C160)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF07C160),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
