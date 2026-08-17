import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/wechat_ui_tokens.dart';
import '../../common/bt_service.dart';
import '../../common/direct_pairing.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/chat_model.dart';

const _kBluetoothScan = 'android.permission.BLUETOOTH_SCAN';
const _kBluetoothConnect = 'android.permission.BLUETOOTH_CONNECT';
const _kFineLocation = 'android.permission.ACCESS_FINE_LOCATION';

/// 蓝牙聊天/传文件入口页（手机端）。
///
/// 连接成功后在联系人列表里保存 `bt:<mac>` 好友，消息走现有
/// LDESK_CHAT_V1 信封协议，在气泡上方自动标注「蓝牙」来源。
class BluetoothChatPage extends StatefulWidget {
  const BluetoothChatPage({super.key});

  @override
  State<BluetoothChatPage> createState() => _BluetoothChatPageState();
}

class _BluetoothChatPageState extends State<BluetoothChatPage> {
  final _bt = BluetoothService.instance;

  bool _supported = false;
  bool _enabled = false;
  bool _checking = true;
  bool _scanning = false;
  String? _connectingMac;
  String? _errorText;

  List<BtDevice> _paired = const <BtDevice>[];
  final List<BtDevice> _found = <BtDevice>[];
  BtDevice? _active;

  StreamSubscription<BtDevice>? _foundSub;
  StreamSubscription<String>? _connectedSub;
  StreamSubscription<String>? _disconnectedSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    unawaited(_bt.init());
    _foundSub = _bt.onDeviceFound.listen(_onDeviceFound);
    _connectedSub = _bt.onConnected.listen(_onConnected);
    _disconnectedSub = _bt.onDisconnected.listen(_onDisconnected);
    _errorSub = _bt.onError.listen(_onError);
    unawaited(_refreshState());
  }

  @override
  void dispose() {
    _foundSub?.cancel();
    _connectedSub?.cancel();
    _disconnectedSub?.cancel();
    _errorSub?.cancel();
    unawaited(_bt.stopScan());
    super.dispose();
  }

  Future<void> _refreshState() async {
    final supported = await _bt.isSupported();
    final enabled = supported && await _bt.isEnabled();
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _enabled = enabled;
      _checking = false;
    });
    if (supported && enabled) {
      // BLUETOOTH_CONNECT is required on Android 12+ to read the paired
      // device list; asking once here avoids a false "read failed" error.
      await _ensureConnectPermission();
      final paired = await _bt.pairedDevices();
      if (mounted) setState(() => _paired = paired);
    }
  }

  /// Android 12+ requires BLUETOOTH_CONNECT to list paired devices and read
  /// discovered device names. The system remembers the grant, so asking once
  /// on page open is enough for every later launch.
  Future<void> _ensureConnectPermission() async {
    if (!_bt.isAndroidPlatform) return;
    if (await AndroidPermissionManager.check(_kBluetoothConnect)) return;
    await AndroidPermissionManager.request(_kBluetoothConnect);
  }

  Future<bool> _ensurePermission(String permission) async {
    if (!await AndroidPermissionManager.check(permission)) {
      return AndroidPermissionManager.request(permission);
    }
    return true;
  }

  void _onDeviceFound(BtDevice device) {
    if (!mounted) return;
    setState(() {
      if (!_found.any((d) => d.mac == device.mac)) {
        _found.add(device);
      }
      if (_paired.any((d) => d.mac == device.mac)) {
        _paired = <BtDevice>[
          for (final d in _paired)
            d.mac == device.mac ? d.copyWith(paired: true) : d,
        ];
      }
    });
  }

  Future<void> _onConnected(String mac) async {
    if (!mounted) return;
    final device = _found.firstWhereOrNull((d) => d.mac == mac) ??
        _paired.firstWhereOrNull((d) => d.mac == mac);
    if (device == null) return;
    try {
      await DirectPairingStore.saveBluetoothPeer(device.name, mac);
    } catch (error) {
      debugPrint('saveBluetoothPeer failed: $error');
    }
    if (!mounted) return;
    setState(() {
      _active = device;
      _connectingMac = null;
      _errorText = null;
    });
    gFFI.chatModel.changeCurrentKey(
      MessageKey(device.peerId, ChatModel.clientModeID),
    );
    showToast(translate('Connected'));
  }

  void _onDisconnected(String mac) {
    if (!mounted) return;
    setState(() {
      if (_active?.mac == mac) {
        _active = null;
      }
      if (_connectingMac == mac) {
        _connectingMac = null;
      }
    });
    if (_active == null) showToast(translate('Bluetooth disconnected'));
  }

  void _onError(String message) {
    if (!mounted) return;
    setState(() {
      _errorText = message;
      _connectingMac = null;
    });
  }

  Future<void> _toggleScan() async {
    if (_scanning) {
      await _bt.stopScan();
      if (mounted) setState(() => _scanning = false);
      return;
    }
    if (!_enabled) {
      await _bt.enable();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final enabled = await _bt.isEnabled();
      if (!enabled) {
        showToast(translate('Please turn on Bluetooth'));
        return;
      }
      if (mounted) setState(() => _enabled = true);
    }
    final scanOk = await _ensurePermission(_kBluetoothScan);
    if (!scanOk) {
      showToast(translate('Bluetooth scan permission required'));
      return;
    }
    // Android 12+ also requires BLUETOOTH_CONNECT to read discovered
    // device names; without it the scan callback crashes.
    final connectOk = await _ensurePermission(_kBluetoothConnect);
    if (!connectOk) {
      showToast(translate('Bluetooth connection permission required'));
      return;
    }
    await _ensurePermission(_kFineLocation);
    if (!mounted) return;
    // Permissions may have just been granted; refresh the paired list so a
    // stale "read failed" error from page load does not linger.
    final paired = await _bt.pairedDevices();
    if (!mounted) return;
    setState(() {
      _paired = paired;
      _found.clear();
      _scanning = true;
      _errorText = null;
    });
    await _bt.startScan();
    // Stop discovery after a reasonable window to save power.
    Future<void>.delayed(const Duration(seconds: 20), () async {
      if (_bt.scanning) {
        await _bt.stopScan();
        if (mounted) setState(() => _scanning = false);
      }
    });
  }

  Future<void> _connectDevice(BtDevice device) async {
    if (!_enabled) {
      await _bt.enable();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final enabled = await _bt.isEnabled();
      if (mounted) setState(() => _enabled = enabled);
      if (!_enabled) {
        showToast(translate('Please turn on Bluetooth'));
        return;
      }
    }
    final connectOk = await _ensurePermission(_kBluetoothConnect);
    if (!connectOk) {
      showToast(translate('Bluetooth connection permission required'));
      return;
    }
    if (!mounted) return;
    setState(() {
      _connectingMac = device.mac;
      _errorText = null;
    });
    await _bt.connect(device.mac, device.name);
  }

  void _openConversation(BtDevice device) {
    setState(() {
      _active = device;
      _errorText = null;
    });
    gFFI.chatModel.changeCurrentKey(
      MessageKey(device.peerId, ChatModel.clientModeID),
    );
  }

  void _disconnect() {
    final active = _active;
    if (active == null) return;
    unawaited(_bt.disconnect(active.mac));
    setState(() => _active = null);
  }

  /// Block or unblock a Bluetooth peer. Blocking stops incoming messages
  /// and drops the active link immediately.
  void _toggleBlock(BtDevice device) {
    final wasBlocked = gFFI.chatSettingsModel.isBlocked(device.peerId);
    unawaited(gFFI.chatSettingsModel.toggleBlock(device.peerId));
    if (!wasBlocked) {
      unawaited(_bt.disconnect(device.mac));
      if (mounted) setState(() => _active = null);
      showToast(translate('blocked_receive_tip'));
    } else {
      showToast(translate('unblocked_receive_tip'));
    }
  }

  Future<void> _attachFile() async {
    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    final files = picked?.files.where((f) => f.path != null).toList() ??
        const <PlatformFile>[];
    if (files.isEmpty || !mounted) return;
    for (final file in files) {
      final path = file.path!;
      try {
        await gFFI.chatModel.sendFileRecord(
          fileName: file.name,
          fileSize: File(path).lengthSync(),
          localPath: path,
        );
      } catch (error, stackTrace) {
        debugPrint('BT attach file failed: $error\n$stackTrace');
        showToast('${translate('Failed to send file')}: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = isDesktop && constraints.maxWidth >= 860;
        return Scaffold(
          backgroundColor: dark ? MyTheme.canvasDark : MyTheme.canvasLight,
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: !desktop && _active != null
                ? IconButton(
                    tooltip: translate('Back'),
                    onPressed: () => setState(() => _active = null),
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null,
            title: Text(
              translate('Bluetooth chat'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: <Widget>[
              if (!_checking)
                _buildAdapterStatus(
                  dark,
                  compact: constraints.maxWidth < 520,
                ),
              IconButton(
                tooltip:
                    _scanning ? translate('Stop') : translate('Bluetooth scan'),
                onPressed: _supported ? _toggleScan : null,
                icon: Icon(
                  _scanning
                      ? Icons.stop_circle_outlined
                      : Icons.bluetooth_searching_rounded,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: desktop
              ? _buildDesktopWorkspace()
              : _active == null
                  ? _buildDeviceExplorer()
                  : _buildConversation(),
        );
      },
    );
  }

  Widget _buildAdapterStatus(bool dark, {required bool compact}) {
    final ready = _supported && _enabled;
    final color = ready ? MyTheme.primary : Colors.orange;
    final label =
        ready ? translate('Bluetooth ready') : translate('Bluetooth is off');
    if (compact) {
      return Tooltip(
        message: label,
        child: Semantics(
          label: label,
          child: SizedBox(
            width: 40,
            height: 48,
            child: Center(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(dark ? 0.16 : 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: MobileText.caption,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopWorkspace() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 372,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark ? MyTheme.surfaceDark : MyTheme.surfaceLight,
            ),
            child: _buildDeviceExplorer(),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF3A3D43)
              : kWeChatDividerColor.withOpacity(0.5),
        ),
        Expanded(
          child: _active == null
              ? _buildConversationEmptyState()
              : _buildConversation(),
        ),
      ],
    );
  }

  Widget _buildConversationEmptyState() {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: MyTheme.primary.withOpacity(dark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.bluetooth_searching_rounded,
                  size: 34,
                  color: MyTheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                translate('Bluetooth chat'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                translate('Tap Scan to find Bluetooth devices around you.'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: theme.colorScheme.onSurface.withOpacity(0.58),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _supported ? _toggleScan : null,
                icon: const Icon(Icons.radar_rounded),
                label: Text(translate('Scan nearby Bluetooth')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceExplorer() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final canvas = dark ? MyTheme.canvasDark : MyTheme.canvasLight;
    return Container(
      color: canvas,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          _buildStatusCard(dark),
          if (_errorText != null && _errorText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorText!,
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: MobileText.bodySm,
                ),
              ),
            ),
          if (_supported && _enabled) _buildPairedSection(dark),
          if (_supported && _enabled) _buildScanSection(dark),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool dark) {
    final icon = _checking
        ? Icons.hourglass_top_rounded
        : _supported
            ? (_enabled
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_disabled_rounded)
            : Icons.bluetooth_disabled_rounded;
    final title = _checking
        ? translate('Checking Bluetooth')
        : !_supported
            ? translate('This device has no Bluetooth')
            : _enabled
                ? translate('Bluetooth ready')
                : translate('Bluetooth is off');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? MyTheme.surfaceDark : MyTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dark
              ? const Color(0xFF3A3D43)
              : kWeChatDividerColor.withOpacity(0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: MyTheme.primary, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: MobileText.bodyLg,
                fontWeight: FontWeight.w600,
                color: dark ? MyTheme.textDark : MyTheme.textLight,
              ),
            ),
          ),
          if (_supported && !_enabled)
            TextButton.icon(
              onPressed: () async {
                await _bt.enable();
                await Future<void>.delayed(const Duration(milliseconds: 800));
                final enabled = await _bt.isEnabled();
                if (mounted) setState(() => _enabled = enabled);
              },
              icon: const Icon(Icons.power_settings_new_rounded, size: 18),
              label: Text(translate('Enable')),
            ),
        ],
      ),
    );
  }

  Widget _buildPairedSection(bool dark) {
    return _SectionCard(
      dark: dark,
      title: translate('Paired devices'),
      trailing: _paired.isEmpty
          ? null
          : IconButton(
              tooltip: translate('Refresh'),
              onPressed: () async {
                final paired = await _bt.pairedDevices();
                if (mounted) setState(() => _paired = paired);
              },
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
      child: _paired.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                translate('No paired devices yet. Scan for nearby devices.'),
                style: TextStyle(
                  fontSize: MobileText.bodySm,
                  color: dark ? MyTheme.mutedDark : MyTheme.mutedLight,
                ),
              ),
            )
          : Column(
              children: <Widget>[
                for (final device in _paired) _deviceTile(device, dark),
              ],
            ),
    );
  }

  /// Robust scan toggle used on both phone and desktop. A plain
  /// TextButton.icon is not always painted on desktop builds, so this uses an
  /// explicit styled container to guarantee the action is always reachable.
  Widget _buildScanAction(bool dark) {
    final accent = dark ? MyTheme.accentDark : MyTheme.primary;
    return Semantics(
      button: true,
      label: _scanning ? translate('Stop') : translate('Bluetooth scan'),
      child: InkWell(
        onTap: _toggleScan,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  _scanning ? Icons.stop_rounded : Icons.radar_rounded,
                  size: 20,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Text(
                  _scanning ? translate('Stop') : translate('Scan'),
                  style: TextStyle(
                    fontSize: MobileText.body,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanSection(bool dark) {
    return _SectionCard(
      dark: dark,
      title: translate('Nearby devices'),
      trailing: _buildScanAction(dark),
      child: _found.isEmpty && !_scanning
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    translate('Tap Scan to find Bluetooth devices around you.'),
                    style: TextStyle(
                      fontSize: MobileText.bodySm,
                      color: dark ? MyTheme.mutedDark : MyTheme.mutedLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    translate('bt_dotchat_hint'),
                    style: TextStyle(
                      fontSize: MobileText.captionSm,
                      color: dark ? MyTheme.mutedDark : MyTheme.mutedLight,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _toggleScan,
                      style: FilledButton.styleFrom(
                        backgroundColor: MyTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.radar_rounded, size: 20),
                      label: Text(
                        translate('Scan nearby Bluetooth'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: <Widget>[
                if (_scanning)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: <Widget>[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          translate('Searching...'),
                          style: const TextStyle(fontSize: MobileText.bodySm),
                        ),
                      ],
                    ),
                  ),
                for (final device in _found) _deviceTile(device, dark),
              ],
            ),
    );
  }

  Widget _deviceTile(BtDevice device, bool dark) {
    final connecting = _connectingMac == device.mac;
    final connected = _bt.isConnected(device.mac);
    final selected = _active?.mac == device.mac;
    // 优先显示点聊昵称，附上设备 ID（灰字小号），与联系人列表风格一致。
    final nick = device.displayName.isNotEmpty
        ? device.displayName
        : (device.name.isEmpty ? translate('Unknown device') : device.name);
    final deviceName = device.deviceId.isNotEmpty
        ? '$nick  (${device.deviceId})'
        : nick;
    final onTap = connecting
        ? null
        : connected
            ? () => _openConversation(device)
            : () => _connectDevice(device);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '$deviceName, ${connected ? translate('Connected') : translate('Connect')}',
      child: Material(
        color: selected
            ? MyTheme.primary.withOpacity(dark ? 0.16 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: MyTheme.primary.withOpacity(dark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      connected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_rounded,
                      color: MyTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          deviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: MobileText.bodyLg,
                            fontWeight: FontWeight.w600,
                            color: dark ? MyTheme.textDark : MyTheme.textLight,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          device.mac,
                          style: TextStyle(
                            fontSize: MobileText.caption,
                            color:
                                dark ? MyTheme.mutedDark : MyTheme.mutedLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (connecting)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (connected)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          translate('Connected'),
                          style: const TextStyle(
                            color: MyTheme.primary,
                            fontSize: MobileText.caption,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: MyTheme.primary,
                          size: 20,
                        ),
                      ],
                    )
                  else
                    Text(
                      translate('Connect'),
                      style: const TextStyle(
                        color: MyTheme.primary,
                        fontSize: MobileText.bodySm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConversation() {
    final active = _active;
    if (active == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final connected = _bt.isConnected(active.mac);
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: dark ? MyTheme.surfaceDark : MyTheme.surfaceLight,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context)
                    .dividerColor
                    .withOpacity(dark ? 0.42 : 0.3),
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (connected ? MyTheme.primary : Colors.orange)
                      .withOpacity(dark ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  connected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_disabled_rounded,
                  color: connected ? MyTheme.primary : Colors.orange,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      active.name.isEmpty
                          ? translate('Unknown device')
                          : active.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: MobileText.bodyLg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      active.mac,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: MobileText.captionSm,
                        color: dark ? MyTheme.mutedDark : MyTheme.mutedLight,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _toggleBlock(active),
                tooltip: gFFI.chatSettingsModel.isBlocked(active.peerId)
                    ? translate('Unblock')
                    : translate('Stop receiving'),
                icon: Icon(
                  gFFI.chatSettingsModel.isBlocked(active.peerId)
                      ? Icons.block_rounded
                      : Icons.volume_off_rounded,
                  size: 20,
                  color: gFFI.chatSettingsModel.isBlocked(active.peerId)
                      ? Colors.redAccent
                      : Colors.grey,
                ),
              ),
              IconButton(
                onPressed: connected ? _disconnect : null,
                tooltip: translate('Disconnect'),
                icon: const Icon(Icons.link_off_rounded, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: ChatPage(
            type: ChatPageType.mobileMain,
            onAttachFile: _attachFile,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.dark,
    required this.title,
    required this.child,
    this.trailing,
  });

  final bool dark;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: MobileText.body,
                    fontWeight: FontWeight.w700,
                    color: dark ? MyTheme.mutedDark : MyTheme.mutedLight,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
