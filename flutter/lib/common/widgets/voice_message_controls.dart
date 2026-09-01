import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart'
    if (dart.library.html) '../record_stub.dart';
import 'package:uuid/uuid.dart';

import '../../common.dart';
import '../../models/chat_model.dart';
import '../direct_voice_storage.dart';

/// 长按录音按钮。录音时，在按钮正下方弹出一个**小**卡片，显示录音时间
/// 以及发送 / 取消按钮；不覆盖整个屏幕，也不显示难看的拼写红线。
class VoiceMessageRecorderButton extends StatefulWidget {
  const VoiceMessageRecorderButton({
    super.key,
    required this.chatModel,
    required this.enabled,
    this.onInteractionStart,
    this.bigMode = false,
  });

  final ChatModel chatModel;
  final bool enabled;
  final VoidCallback? onInteractionStart;

  /// 微信“按住 说话”大按钮模式：显示一个圆角大按钮，按住录音/松开发送。
  final bool bigMode;

  @override
  State<VoiceMessageRecorderButton> createState() =>
      _VoiceMessageRecorderButtonState();
}

class _VoiceMessageRecorderButtonState
    extends State<VoiceMessageRecorderButton> {
  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _elapsed = Stopwatch();
  final GlobalKey _buttonKey = GlobalKey();
  Timer? _timer;
  String? _messageId;
  bool _recording = false;
  bool _busy = false;
  bool _cancelling = false;
  Offset? _pressOrigin;
  OverlayEntry? _overlayEntry;
  StateSetter? _overlaySetState;

  static const Duration _maxDuration = Duration(minutes: 3);
  static const double _cancelThreshold = 80;

  @override
  void dispose() {
    _hideOverlay();
    _timer?.cancel();
    if (_recording) unawaited(_recorder.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  // ── Overlay ────────────────────────────────────────────────────────

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _overlaySetState = null;
  }

  /// 在屏幕中央插入微信风格全屏录音浮层。
  void _showOverlay() {
    _hideOverlay();
    final entry = OverlayEntry(
      builder: (_) => _buildRecordingCard(left: 0, top: 0),
    );
    _overlayEntry = entry;
    Overlay.of(context).insert(entry);
  }

  Widget _buildRecordingCard({required double left, required double top}) {
    // 微信风格录音浮层：全屏半透明深色背景 + 中央大圆点 + 计时 + 提示语。
    return Material(
      color: Colors.transparent,
      child: StatefulBuilder(
        builder: (context, setOverlayState) {
          _overlaySetState = setOverlayState;
          final seconds = _elapsed.elapsed.inSeconds;
          final mm = (seconds ~/ 60).toString().padLeft(2, '0');
          final ss = (seconds % 60).toString().padLeft(2, '0');
          final hint = _cancelling
              ? translate('Release to cancel')
              : translate('Release to send, swipe up to cancel');

          return Stack(
            children: <Widget>[
              // 全屏半透明背景
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Container(
                    color: Colors.black.withOpacity(_cancelling ? 0.55 : 0.35),
                  ),
                ),
              ),
              // 中央浮层
              Center(
                child: Container(
                  width: 160,
                  padding: const EdgeInsets.symmetric(
                      vertical: 22, horizontal: 16),
                  decoration: BoxDecoration(
                    color: _cancelling
                        ? const Color(0xFFFA5151)
                        : const Color(0xFF2B2D32),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 86,
                        height: 86,
                        child: Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFA5151),
                                shape: BoxShape.circle,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: const Color(0xFFFA5151)
                                        .withOpacity(0.4),
                                    blurRadius: 18,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.mic_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        mm + ":" + ss,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.85),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

    // ── Recording lifecycle ────────────────────────────────────────────

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _recorder.hasPermission()) {
        showToast(translate('Microphone permission is required'));
        return;
      }
      final messageId = const Uuid().v4();
      final path = await DirectVoiceStorage.instance.pathFor(messageId);
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _messageId = messageId;
      _elapsed..reset()..start();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_elapsed.elapsed >= _maxDuration) {
          unawaited(_stopAndSend());
        } else {
          setState(() {});
          _overlaySetState?.call(() {});
        }
      });
      if (mounted) {
        setState(() => _recording = true);
        _showOverlay();
      }
    } catch (error) {
      debugPrint('Failed to start voice message recording: $error');
      showToast(translate('Failed to start voice recording'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopAndSend() async {
    if (!_recording || _busy) return;
    setState(() => _busy = true);
    _timer?.cancel();
    _timer = null;
    _elapsed.stop();
    final durationMs = _elapsed.elapsedMilliseconds;
    final messageId = _messageId;
    _hideOverlay();
    try {
      final path = await _recorder.stop();
      if (path == null || messageId == null) return;
      if (durationMs < 500) {
        await DirectVoiceStorage.instance.delete(messageId);
        showToast(translate('Voice message is too short'));
        return;
      }
      await widget.chatModel.sendVoiceClip(
        messageId: messageId,
        durationMs: durationMs,
      );
    } catch (error) {
      debugPrint('Failed to send voice message: $error');
      showToast(translate('Failed to send voice message'));
    } finally {
      _messageId = null;
      _elapsed.reset();
      _cancelling = false;
      if (mounted) {
        setState(() {
          _recording = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    _timer = null;
    _elapsed.stop();
    _hideOverlay();
    if (_recording) {
      final messageId = _messageId;
      try {
        await _recorder.cancel();
        if (messageId != null) {
          await DirectVoiceStorage.instance.delete(messageId);
        }
      } catch (error) {
        debugPrint('Failed to cancel voice recording: $error');
      }
    }
    _messageId = null;
    _elapsed.reset();
    _cancelling = false;
    _pressOrigin = null;
    if (mounted) {
      setState(() {
        _recording = false;
        _busy = false;
      });
    }
  }

  // ── Pointer events (长按交互保持不变) ──────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || _busy) return;
    widget.onInteractionStart?.call();
    _pressOrigin = event.position;
    _cancelling = false;
    unawaited(_start());
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_recording || _pressOrigin == null) return;
    final dy = event.position.dy - _pressOrigin!.dy;
    final cancelling = dy < -_cancelThreshold;
    if (cancelling != _cancelling) {
      setState(() => _cancelling = cancelling);
      _overlaySetState?.call(() {});
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_recording) return;
    if (_cancelling) {
      unawaited(_cancelRecording());
    } else {
      unawaited(_stopAndSend());
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (!_recording) return;
    unawaited(_cancelRecording());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bigMode) {
      // 微信“按住 说话”大按钮。
      return Tooltip(
        message: translate(_recording
            ? 'Release to send, drag up to cancel'
            : 'Record voice message'),
        child: Listener(
          key: _buttonKey,
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _recording
                  ? const Color(0xFF2B2D32)
                  : Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF3A3D43)
                      : const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _recording
                    ? const Color(0xFFFA5151)
                    : Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF4A4D53)
                        : const Color(0xFFE2E2E2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.mic_rounded,
                  size: 20,
                  color: _recording
                      ? const Color(0xFFFA5151)
                      : Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFFCCCCCC)
                          : const Color(0xFF555555),
                ),
                const SizedBox(width: 6),
                Text(
                  translate(_recording
                      ? 'Release to send, drag up to cancel'
                      : 'Hold to talk'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _recording
                        ? const Color(0xFFFA5151)
                        : Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFFCCCCCC)
                            : const Color(0xFF333333),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: translate(_recording
          ? 'Release to send, drag up to cancel'
          : 'Record voice message'),
      child: SizedBox(
        key: _buttonKey,
        width: 40,
        height: 36,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Icon(
            Icons.mic_none_rounded,
            size: 22,
            color: _recording
                ? const Color(0xFFFA5151)
                : widget.enabled
                    ? null
                    : Theme.of(context).disabledColor,
          ),
        ),
      ),
    );
  }
}

/// 录音弹窗内使用的圆形小图标按钮。
class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 28,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(size / 2),
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size * 0.55, color: color),
      ),
    );
  }
}

class VoiceMessageBubble extends StatefulWidget {
  const VoiceMessageBubble({
    super.key,
    required this.chatModel,
    required this.messageId,
    required this.durationMs,
  });

  final ChatModel chatModel;
  final String messageId;
  final int durationMs;

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completionSubscription;
  bool _available = false;
  bool _playing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    DirectVoiceStorage.instance.revision.addListener(_refresh);
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant VoiceMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId) unawaited(_refresh());
  }

  @override
  void dispose() {
    DirectVoiceStorage.instance.revision.removeListener(_refresh);
    _completionSubscription?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _refresh() async {
    final available =
        await DirectVoiceStorage.instance.exists(widget.messageId);
    if (!mounted) return;
    setState(() {
      _available = available;
      _loading = false;
    });
  }

  Future<void> _togglePlayback() async {
    if (_loading) return;
    if (!_available) {
      setState(() => _loading = true);
      await widget.chatModel.requestVoiceClip(widget.messageId);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _refresh();
      return;
    }
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    final bytes = await DirectVoiceStorage.instance.read(widget.messageId);
    if (bytes == null) {
      await _refresh();
      return;
    }
    await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
    if (mounted) setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (widget.durationMs / 1000).ceil().clamp(1, 60).toInt();
    final width = (92.0 + seconds * 2.0).clamp(94.0, 210.0).toDouble();
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: _togglePlayback,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: <Widget>[
              if (_loading)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  !_available
                      ? Icons.download_rounded
                      : _playing
                          ? Icons.stop_rounded
                          : Icons.graphic_eq_rounded,
                  size: 22,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _available
                      ? '${seconds}″'
                      : translate('Download voice message'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    letterSpacing: 0,
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
