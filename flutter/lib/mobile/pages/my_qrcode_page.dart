import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../common.dart';
import '../../common/direct_pairing.dart';
import '../../common/formatter/id_formatter.dart';
import '../../models/platform_model.dart';
import 'scan_page.dart';

/// 个人二维码页：显示自己的「加好友」二维码 + ID，并提供「扫一扫」入口。
/// 人与人当面时，对方扫本页二维码即可拿到我的 ID 发起会话。
class MyQrCodePage extends StatefulWidget {
  const MyQrCodePage({super.key});

  @override
  State<MyQrCodePage> createState() => _MyQrCodePageState();
}

class _MyQrCodePageState extends State<MyQrCodePage> {
  String _payload = '';
  String _myId = '';
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final id = (await bind.mainGetMyId()).trim();
    final payload = await DirectPairingStore.buildFriendPayload();
    var name = '';
    try {
      final profile = Map<String, dynamic>.from(
        jsonDecode(bind.mainGetLocalOption(key: 'user_info')) as Map,
      );
      name =
          (profile['display_name'] ?? profile['name'] ?? '').toString().trim();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _myId = id;
      _displayName = name;
      _payload = payload;
    });
  }

  Future<void> _copyId() async {
    if (_myId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _myId));
    if (mounted) showToast(translate('Copied'));
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ScanPage()),
    );
    // 扫码可能新增了联系人，回来刷新自己的账号二维码（绑定账号变化时）。
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = const Color(0xFF07C160);
    final cardBg = dark ? const Color(0xFF1E2024) : Colors.white;
    final muted = dark ? const Color(0xFF9AA0A8) : const Color(0xFF8A9099);

    return Scaffold(
      appBar: AppBar(
        title: Text(translate('My QR code')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const SizedBox(height: 24),
            // 头像占位（首字）
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  _displayName.isNotEmpty
                      ? _displayName[0].toUpperCase()
                      : '#',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF07C160),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _displayName.isNotEmpty ? _displayName : translate('DotChat user'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            // 二维码卡片
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: dark ? const Color(0xFF3A3D43) : const Color(0xFFE8E8E8),
                  width: 0.8,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(dark ? 0.3 : 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_payload.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    )
                  else
                    QrImageView(
                      data: _payload,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                      gapless: false,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    '${translate('ID')}: ${formatID(_myId)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: dark ? const Color(0xFFEDEDED) : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    translate('Scan to add me as a friend'),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // 底部操作
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyId,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(translate('Copy ID')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openScanner,
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: Text(translate('Scan')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
