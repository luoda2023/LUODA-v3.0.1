import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../consts.dart';
import '../../models/chat_model.dart';

/// A compact status bar shown in the desktop toolbar area during a voice call.
///
/// Displays call duration, network quality indicator, and bitrate.
class VoiceCallStatusBar extends StatefulWidget {
  const VoiceCallStatusBar({Key? key, required this.chatModel})
      : super(key: key);

  final ChatModel chatModel;

  @override
  State<VoiceCallStatusBar> createState() => _VoiceCallStatusBarState();
}

class _VoiceCallStatusBarState extends State<VoiceCallStatusBar> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Color _qualityColor(String status) {
    if (status.contains('very_poor')) return Colors.red;
    if (status.contains('poor')) return Colors.orange;
    if (status.contains('fair')) return Colors.yellow.shade700;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final status = widget.chatModel.voiceCallStatus.value;
      if (status != VoiceCallStatus.connected &&
          status != VoiceCallStatus.waitingForResponse) {
        return const SizedBox.shrink();
      }
      final qualityStatus = widget.chatModel.voiceCallQualityStatus.value;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              status == VoiceCallStatus.waitingForResponse
                  ? Icons.hourglass_top
                  : Icons.phone_in_talk,
              color: status == VoiceCallStatus.waitingForResponse
                  ? Colors.orangeAccent
                  : Colors.greenAccent,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              status == VoiceCallStatus.waitingForResponse
                  ? translate('Calling...')
                  : _formatDuration(_seconds),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            if (qualityStatus.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _qualityColor(qualityStatus),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}
