import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:zxing2/qrcode.dart';

import '../../common.dart';
import '../../common/direct_pairing.dart';
import '../../common/formatter/id_formatter.dart';
import '../../models/platform_model.dart';
import '../widgets/dialog.dart';

class ScanPage extends StatefulWidget {
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  StreamSubscription? scanSubscription;
  bool _handlingScan = false;

  @override
  void reassemble() {
    super.reassemble();
    if (isAndroid && controller != null) {
      controller!.pauseCamera();
    } else if (controller != null) {
      controller!.resumeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('Scan PC pairing QR')),
        actions: [
          _buildImagePickerButton(),
          _buildFlashToggleButton(),
          _buildCameraSwitchButton(),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: DirectPairingStore.revision,
            builder: (context, _, __) {
              final pc = DirectPairingStore.companionDevice();
              if (pc == null) return const SizedBox.shrink();
              return _buildBoundPcBanner(context, pc);
            },
          ),
          Expanded(child: _buildQrView(context)),
        ],
      ),
    );
  }

  Widget _buildBoundPcBanner(BuildContext context, DirectPairing pc) {
    final name = pc.displayName.trim().isEmpty
        ? pc.peerId
        : pc.displayName.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MyTheme.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MyTheme.accent.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.desktop_windows_rounded,
              size: 22, color: MyTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translate('Bound PC'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: MyTheme.mutedLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (pc.accountId.isNotEmpty)
                  Text(
                    '${translate('ID')}: ${formatID(pc.accountId)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MyTheme.mutedLight,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrView(BuildContext context) {
    var scanArea = MediaQuery.of(context).size.width < 400 ||
            MediaQuery.of(context).size.height < 400
        ? 150.0
        : 300.0;
    return QRView(
      key: qrKey,
      onQRViewCreated: _onQRViewCreated,
      overlay: QrScannerOverlayShape(
        borderColor: MyTheme.accent,
        borderRadius: 8,
        borderLength: 28,
        borderWidth: 5,
        cutOutSize: scanArea,
      ),
      onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    setState(() {
      this.controller = controller;
    });
    scanSubscription = controller.scannedDataStream.listen((scanData) {
      if (scanData.code != null) {
        unawaited(_handleScannedValue(scanData.code!));
      }
    });
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    if (!p) {
      showToast(
        translate('Camera permission is required to scan pairing QR codes.'),
      );
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      try {
        var image = img.decodeImage(await File(file.path).readAsBytes())!;
        LuminanceSource source = RGBLuminanceSource(
          image.width,
          image.height,
          image.getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List(),
        );
        var bitmap = BinaryBitmap(HybridBinarizer(source));

        var reader = QRCodeReader();
        var result = reader.decode(bitmap);
        await _handleScannedValue(result.text);
      } catch (e) {
        showToast(translate('No QR code found'));
      }
    }
  }

  Widget _buildImagePickerButton() {
    return Tooltip(
      message: translate('Choose image'),
      child: IconButton(
        icon: const Icon(Icons.image_search_rounded),
        iconSize: 24,
        onPressed: _pickImage,
      ),
    );
  }

  Widget _buildFlashToggleButton() {
    return Tooltip(
      message: translate('Toggle flashlight'),
      child: IconButton(
        icon: const Icon(Icons.flash_on_rounded),
        iconSize: 24,
        onPressed: () async {
          await controller?.toggleFlash();
        },
      ),
    );
  }

  Widget _buildCameraSwitchButton() {
    return Tooltip(
      message: translate('Switch camera'),
      child: IconButton(
        icon: const Icon(Icons.cameraswitch_rounded),
        iconSize: 24,
        onPressed: () async {
          await controller?.flipCamera();
        },
      ),
    );
  }

  Widget _boundPcLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: MyTheme.mutedLight),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    controller?.dispose();
    super.dispose();
  }

  Future<void> _handleScannedValue(String data) async {
    if (_handlingScan) return;
    _handlingScan = true;
    try {
      final pairing = DirectPairingStore.parsePayload(data);
      if (pairing != null) {
        await controller?.pauseCamera();
        final existing = DirectPairingStore.companionDevice();
        if (existing != null && existing.peerId != pairing.peerId) {
          final replace = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(translate('Replace bound PC?')),
              content: Text(
                translate('Already bound to') +
                    ' ' +
                    (existing.displayName.trim().isEmpty
                        ? existing.peerId
                        : existing.displayName.trim()) +
                    '.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(translate('Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(translate('Replace')),
                ),
              ],
            ),
          );
          if (replace != true) {
            await controller?.resumeCamera();
            return;
          }
        }
        await DirectPairingStore.save(pairing);
        // LUODA: bind this phone to the person account advertised by the
        // scanned QR so its own QR/contacts carry the same id and PC+phone
        // conversations merge into one person row everywhere.
        if (pairing.accountId.isNotEmpty) {
          await DirectPairingStore.bindSelfDevice(accountId: pairing.accountId);
        }
        await bind.mainSetLocalOption(
          key: 'direct-chat-always-on',
          value: 'Y',
        );
        if (isAndroid) {
          await gFFI.invokeMethod('set_direct_chat_service', true);
        }
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(translate('PC paired for direct connection')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _boundPcLine(
                  translate('Device'),
                  pairing.displayName.trim().isEmpty
                      ? pairing.peerId
                      : pairing.displayName.trim(),
                ),
                if (pairing.peerId.isNotEmpty)
                  _boundPcLine(translate('ID'), formatID(pairing.peerId)),
                if (pairing.accountId.isNotEmpty)
                  _boundPcLine(translate('Account'), pairing.accountId),
                if (pairing.endpoints.isNotEmpty)
                  _boundPcLine(translate('Endpoint'), pairing.endpoints.join(', ')),
                const SizedBox(height: 6),
                Text(
                  translate('Direct endpoint only. Same LAN or forwarded port required.'),
                  style: const TextStyle(fontSize: 12, color: MyTheme.mutedLight),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(translate('Done')),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.pop(context, pairing);
        return;
      }
      if (data.startsWith(bind.mainUriPrefixSync())) {
        await controller?.pauseCamera();
        handleUriLink(uriString: data);
        return;
      }
      await _showServerSettingFromQr(data);
    } catch (error) {
      debugPrint('Failed to handle scanned QR code: $error');
      if (mounted) showToast(translate('Invalid QR code'));
    } finally {
      _handlingScan = false;
    }
  }

  Future<void> _showServerSettingFromQr(String data) async {
    closeConnection();
    await controller?.pauseCamera();
    if (!data.startsWith('config=')) {
      showToast(translate('Invalid QR code'));
      return;
    }
    try {
      final sc = ServerConfig.decode(data.substring(7));
      Timer(Duration(milliseconds: 60), () {
        showServerSettingsWithValue(sc, gFFI.dialogManager, null);
      });
    } catch (e) {
      showToast(translate('Invalid QR code'));
    }
  }
}
