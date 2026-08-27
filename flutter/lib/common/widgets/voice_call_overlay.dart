import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../consts.dart';
import '../../models/chat_model.dart';

/// A semi-transparent bottom bar overlay shown during an active voice call.
///
/// Displays call duration, network quality status, and an end-call button.
/// Similar to WeChat's voice call overlay — doesn't block the remote screen.
class VoiceCallOverlay extends StatefulWidget {
  const VoiceCallOverlay({Key? key, required this.chatModel}) : super(key: key);

  final ChatModel chatModel;

  @override
  State<VoiceCallOverlay> createState() => _VoiceCallOverlayState();
}

class _VoiceCallOverlayState extends State<VoiceCallOverlay> {
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
      setState(() => _seconds++);
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

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Obx(() {
        final status = widget.chatModel.voiceCallStatus.value;
        if (status != VoiceCallStatus.connected &&
            status != VoiceCallStatus.waitingForResponse) {
          return const SizedBox.shrink();
        }
        final qualityStatus = widget.chatModel.voiceCallQualityStatus.value;
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                // Status icon
                if (status == VoiceCallStatus.waitingForResponse)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.orangeAccent,
                    ),
                  )
                else
                  const Icon(Icons.phone_in_talk,
                      color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                // Duration / status text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        status == VoiceCallStatus.waitingForResponse
                            ? translate('Calling...')
                            : translate('Voice call') +
                                ' · ${_formatDuration(_seconds)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (qualityStatus.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            translate(qualityStatus),
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // End call button
                GestureDetector(
                  onTap: () =>
                      widget.chatModel.closeVoiceCall(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.call_end,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          translate('End voice call'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
