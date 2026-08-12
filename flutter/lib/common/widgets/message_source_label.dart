import '../../common.dart';
import '../direct_pairing.dart';

/// 消息来源标签：灰色小字标注每条消息来自哪个端口、哪种连接方式。
///
/// 支持的连接方式（PC 端与手机端一致）：
/// - ID 连接（id，格式 id@服务器）
/// - 局域网 IP（lan，私有网段直连）
/// - 公网 IP（public，公网直连）
/// - 蓝牙连接（ble，手机-手机 / 手机-PC）
///
/// [srcPlatform] 为空（升级前旧消息）时只显示连接方式，不显示设备。
/// [connMode]/[connEndpoint]/[connPort] 为空时从 [fallbackTarget]（当前会话
/// ID）推断，保证每条消息都有来源小字。
String messageSourceLabel({
  required String? srcPlatform,
  required String connMode,
  required String connEndpoint,
  required int connPort,
  required String fallbackTarget,
  String? ipSource,
}) {
  final platform = (srcPlatform ?? '').trim().toLowerCase();
  final mode = connMode.trim().toLowerCase();
  final endpoint = connEndpoint.trim();
  if (platform.isEmpty &&
      mode.isEmpty &&
      fallbackTarget.trim().isEmpty) {
    return translate('Source not recorded');
  }
  final effMode =
      mode.isEmpty || endpoint.isEmpty
          ? DirectPairingStore.classifyConnMode(fallbackTarget)
          : mode;
  if (platform.isEmpty && effMode.isEmpty) {
    return translate('Source not recorded');
  }

  final String device;
  switch (platform) {
    case 'desktop':
    case 'pc':
    case 'windows':
    case 'linux':
    case 'macos':
      device = translate('PC terminal');
      break;
    case 'mobile':
    case 'android':
    case 'ios':
      device = translate('Mobile terminal');
      break;
    default:
      // 平台缺失（旧消息）时不显示设备，仅显示连接方式。
      device = '';
  }

  final String conn;
  switch (effMode) {
    case 'id':
      conn = translate('ID connection');
      break;
    case 'lan':
      conn = translate('LAN IP');
      break;
    case 'public':
      conn = translate('Public IP');
      break;
    case 'ble':
      conn = translate('Bluetooth connection');
      break;
    default:
      conn = ipSource == 'ip' ? translate('IP connection') : '';
  }
  if (conn.isEmpty) return translate('Source not recorded');

  final details = <String>[
    if (device.isNotEmpty) device,
    conn,
  ];
  // 兜底：endpoint/port 缺失时从会话推断，避免显示空项。
  final effEndpoint =
      endpoint.isNotEmpty
          ? endpoint
          : DirectPairingStore.connEndpointOf(fallbackTarget);
  final effPort =
      connPort > 0
          ? connPort
          : DirectPairingStore.connPortOf(fallbackTarget);
  if (effEndpoint.isNotEmpty) details.add(effEndpoint);
  if (effMode == 'id' && effPort > 0) {
    details.add('${translate('Port')} $effPort');
  } else if (effEndpoint.isEmpty && effPort > 0) {
    details.add('${translate('Port')} $effPort');
  }
  return details.join(' · ');
}
