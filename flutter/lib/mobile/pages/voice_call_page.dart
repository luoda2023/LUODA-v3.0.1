import 'dart:async';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';
import 'package:luoda_flutter/models/chat_model.dart';

/// 移动端独立语音/视频通话页（复用点聊 P2P 连接时使用）。
///
/// 与 RemotePage（远程协助黑屏页）不同，本页是纯通话界面：
/// - 不依赖对端开启录屏/远程协助服务；
/// - 显示 呼叫中/通话计时/挂断，通话结束或被拒自动退出返回聊天页。
///
/// UI 状态由 [ChatModel.voiceCallStatus] 的显式订阅驱动（而非 Obx 依赖
/// 构建），避免“音频已 connected 但页面仍停在 Calling...”的刷新丢失问题：
/// - [VoiceCallStatus.waitingForResponse] -> 显示“呼叫中…”；
/// - [VoiceCallStatus.connected]      -> 显示通话计时；
/// - [VoiceCallStatus.notStarted]     -> 通话已结束/被拒，自动退出。
/// 另加每秒 Timer 兜底同步状态与被动退出（页面在多层路由之上时，全局
/// 事件也能正确收敛回页面）。
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
  Timer? _syncTimer;
  StreamSubscription<VoiceCallStatus>? _statusSub;
  int _seconds = 0;
  bool _exiting = false;
  bool _everConnected = false;
  bool _backPressedHandled = false;

  VoiceCallStatus get _status => gFFI.chatModel.voiceCallStatus.value;

  @override
  void initState() {
    super.initState();
    debugPrint('[VoiceCallPage] initState status=${_status} video=${widget.video}');
    // 显式订阅状态流：任何一端（Rust 回调 / 全局事件 / 对端动作）改变
    // 状态都会触发这里的回调 -> setState 重建，而不是依赖 Obx 在
    // 深路由/全屏来电层之上的偶然重建。
    try {
      _statusSub = gFFI.chatModel.voiceCallStatus.listen((VoiceCallStatus status) {
        if (!mounted) return;
        debugPrint('[VoiceCallPage] status -> $status');
        if (status == VoiceCallStatus.connected) {
          _everConnected = true;
        }
        setState(() {
          _maybeAutoExit();
        });
      });
    } catch (e) {
      debugPrint('[VoiceCallPage] subscribe err: $e');
    }
    // 计时：仅在 connected 状态下累加秒数。
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_status == VoiceCallStatus.connected) {
        setState(() => _seconds++);
      }
    });
    // 兜底：某些平台事件回调可能不在主 Isolate 的同一帧内到达，或
    // connected 后 audio 初始化晚于状态切换。每秒对齐一次状态。
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final st = _status;
      if (st == VoiceCallStatus.connected && !_everConnected) {
        _everConnected = true;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _statusSub = null;
    _timer?.cancel();
    _timer = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    super.dispose();
  }

  String _format(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  /// 挂断：先通知 Rust（best-effort）并复位本地状态，再退出页面。
  void _hangUp() {
    if (_exiting) return;
    _exiting = true;
    debugPrint('[VoiceCallPage] hang up');
    try {
      gFFI.chatModel.closeVoiceCall();
    } catch (e) {
      debugPrint('[VoiceCallPage] closeVoiceCall err: $e');
    }
    try {
      gFFI.pendingCallMode = null;
    } catch (_) {}
    _popAfterExit();
  }

  /// 通话结束/被拒/超时自动退出。
  void _maybeAutoExit() {
    if (!mounted || _exiting) return;
    final st = _status;
    // connected 后短暂允许保持，只有回到 notStarted（对端挂断/被拒/
    // 超时）才自动退出。
    if (st == VoiceCallStatus.notStarted && (_everConnected || !_isWaitingNow())) {
      debugPrint('[VoiceCallPage] call ended (status=notStarted), auto exit');
      _exiting = true;
      _popAfterExit();
    }
  }

  bool _isWaitingNow() => _status == VoiceCallStatus.waitingForResponse;

  /// 弹出本页。页面可能压在多层路由之上（聊天详情/来电层/会议），
  /// 因此不能假设本页是栈顶：用 popUntil 回到第一个路由兜底，同时
  /// 保留 canPop 快路径。
  void _popAfterExit() {
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      try {
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.popUntil((route) => route.isFirst);
        }
      } catch (e) {
        debugPrint('[VoiceCallPage] pop err: $e');
      }
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
    final status = _status;
    final calling = status == VoiceCallStatus.waitingForResponse;
    final connected = status == VoiceCallStatus.connected;
    // incoming 状态（被叫方尚未决定）也当作呼叫中展示。
    final ringing = status == VoiceCallStatus.incoming;
    final connectedTitle = translate('Voice call') + ' - ' + _format(_seconds);
    final String subTitle;
    if (calling || ringing) {
      subTitle = translate('Calling...');
    } else if (connected) {
      subTitle = connectedTitle;
    } else {
      // notStarted：本页即将自动退出，短暂显示空串。
      subTitle = '';
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_backPressedHandled) return;
        _backPressedHandled = true;
        debugPrint('[VoiceCallPage] back pressed -> hang up');
        _hangUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10141A),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF16212E),
                        Color(0xFF10141A),
                      ],
                    ),
                  ),
                ),
              ),
              // 通话信息
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: connected
                              ? const Color(0xFF4CAF50)
                              : Colors.white24,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        widget.video ? Icons.videocam : Icons.phone_in_talk,
                        color: connected ? const Color(0xFF4CAF50) : Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        _peerName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      connected ? connectedTitle : subTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              // 挂断按钮（保留中间那个：用户只留一个挂断键）
              Positioned(
                bottom: 64,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _hangUp,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x66E53935),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
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
      ),
    );
  }
}
