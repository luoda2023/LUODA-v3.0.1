import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';
import 'package:luoda_flutter/models/chat_model.dart';

/// 移动端独立语音/视频通话页（复用点聊 P2P 连接时使用）。
///
/// 与 RemotePage（远程协助黑屏页）不同，本页是纯通话界面：
/// - 不依赖对端开启录屏/远程协助服务；
/// - 显示 呼叫中/通话计时/挂断，通话结束或被拒自动退出返回聊天页。
class VoiceCallPage extends StatefulWidget {
  const VoiceCallPage({Key? key, required this.peerId, required this.video, this.displayName})
      : super(key: key);

  final String peerId;
  final String? displayName; // 与聊天列表一致的显示名（由调用方解析）
  final bool video; // true=视频电话, false=语音通话
  @override
  State<VoiceCallPage> createState() => _VoiceCallPageState();
}

class _VoiceCallPageState extends State<VoiceCallPage> {
  Timer? _timer;
  int _seconds = 0;
  bool _exiting = false;

  VoiceCallStatus get _status => gFFI.chatModel.voiceCallStatus.value;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _status == VoiceCallStatus.connected) {
        setState(() => _seconds++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  void _hangUp() {
    if (_exiting) return;
    _exiting = true;
    gFFI.chatModel.closeVoiceCall();
    gFFI.pendingCallMode = null;
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  void _maybeAutoExit() {
    if (!mounted || _exiting) return;
    if (_status != VoiceCallStatus.notStarted) return;
    _exiting = true;
    debugPrint('[VoiceCallPage] call ended, auto exit');
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      Navigator.of(context).pop();
    });
  }

  String get _peerName {
    final fromCaller = (widget.displayName ?? '').trim();
    if (fromCaller.isNotEmpty) return fromCaller;
    // 兜底：与列表逻辑一致，优先 deviceName（OPPO-PFUM10），其次 displayName。
    final paired = DirectPairingStore.findForConversation(widget.peerId);
    if (paired != null) {
      final h = paired.deviceName.trim();
      if (h.isNotEmpty) return h;
      final d = paired.displayName.trim();
      if (d.isNotEmpty) return d;
    }
    return widget.peerId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10141A),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Obx(() {
                final status = gFFI.chatModel.voiceCallStatus.value;
                if (status == VoiceCallStatus.notStarted && !_exiting) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _maybeAutoExit();
                  });
                }
                final calling = status == VoiceCallStatus.waitingForResponse;
                final connected = status == VoiceCallStatus.connected;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        widget.video ? Icons.videocam : Icons.phone_in_talk,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _peerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      calling
                          ? translate('Calling...')
                          : connected
                              ? translate('Voice call') + ' - ' + _format(_seconds)
                              : translate('Voice call'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 15,
                      ),
                    ),
                  ],
                );
              }),
            ),
            Positioned(
              bottom: 64,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _hangUp,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_end,
                        color: Colors.white, size: 34),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
