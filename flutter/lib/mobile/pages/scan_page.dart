import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:zxing2/qrcode.dart';

import '../../common.dart';
import '../../common/direct_pairing.dart';
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
      body: _buildQrView(context),
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

  @override
  void dispose() {
    scanSubscription?.cancel();
    controller?.dispose();
    super.dispose();
  }

  Future<void> _handleScannedValue(String data) async {
    if (_handlingScan) return;
    _handlingScan = true;
    final pairing = DirectPairingStore.parsePayload(data);
    if (pairing != null) {
      await controller?.pauseCamera();
      await DirectPairingStore.save(pairing);
      await bind.mainSetLocalOption(
        key: 'direct-chat-always-on',
        value: 'Y',
      );
      if (isAndroid) {
        await gFFI.invokeMethod('set_direct_chat_service', true);
      }
      if (!mounted) return;
      showToast(translate('PC paired for direct connection'));
      Navigator.pop(context, pairing);
      return;
    }
    if (data.startsWith(bind.mainUriPrefixSync())) {
      await controller?.pauseCamera();
      handleUriLink(uriString: data);
      _handlingScan = false;
      return;
    }
    await _showServerSettingFromQr(data);
    _handlingScan = false;
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
