import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart'
    if (dart.library.html) '../record_stub.dart';
import 'package:uuid/uuid.dart';

import '../../common.dart';
import '../../models/chat_model.dart';
import '../direct_voice_storage.dart';

class VoiceMessageRecorderButton extends StatefulWidget {
  const VoiceMessageRecorderButton({
    super.key,
    required this.chatModel,
    required this.enabled,
    this.onInteractionStart,
  });

  final ChatModel chatModel;
  final bool enabled;
  final VoidCallback? onInteractionStart;

  @override
  State<VoiceMessageRecorderButton> createState() =>
      _VoiceMessageRecorderButtonState();
}

class _VoiceMessageRecorderButtonState
    extends State<VoiceMessageRecorderButton> {
  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _elapsed = Stopwatch();
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

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _overlaySetState = null;
  }

  void _showOverlay() {
    _hideOverlay();
    final entry = OverlayEntry(builder: (_) => _buildRecordingOverlay());
    _overlayEntry = entry;
    Overlay.of(context).insert(entry);
  }

  Widget _buildRecordingOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(color: Colors.black.withOpacity(0.28)),
            StatefulBuilder(
              builder: (context, setOverlayState) {
                _overlaySetState = setOverlayState;
                final seconds = _elapsed.elapsed.inSeconds;
                final mm = (seconds ~/ 60).toString().padLeft(2, '0');
                final ss = (seconds % 60).toString().padLeft(2, '0');
                final cancelling = _cancelling;
                return Container(
                  width: 220,
                  padding: const EdgeInsets.symmetric(
                      vertical: 28, horizontal: 18),
                  decoration: BoxDecoration(
                    color: cancelling ? const Color(0xFFFA5151) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        cancelling
                            ? Icons.keyboard_voice_rounded
                            : Icons.mic_rounded,
                        size: 46,
                        color: cancelling
                            ? Colors.white
                            : const Color(0xFFFA5151),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$mm:$ss',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: cancelling
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cancelling
                            ? translate('Release to cancel')
                            : translate(
                                'Release to send, slide up to cancel'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: cancelling
                              ? Colors.white
                              : const Color(0xFF7F7F7F),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _recorder.hasPermission()) {
        showToast(translate('Microphone permission is required'));
        _hideOverlay();
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
      _elapsed
        ..reset()
        ..start();
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
      _pressOrigin = null;
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
    return Tooltip(
      message: translate('Record voice message'),
      child: SizedBox(
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
            color: widget.enabled
                ? null
                : Theme.of(context).disabledColor,
          ),
        ),
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
                      ? '$seconds s'
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
