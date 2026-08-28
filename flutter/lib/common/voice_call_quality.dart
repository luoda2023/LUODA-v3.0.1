import 'dart:async';

/// Network quality level for voice calls.
enum VoiceCallQualityLevel {
  /// Good: delay < 200ms, suitable for voice call
  good,
  /// Fair: delay 200-400ms, call may be choppy
  fair,
  /// Poor: delay > 400ms, not recommended
  poor,
}

/// Network quality assessment result before starting a call.
class VoiceCallQualityAssessment {
  final VoiceCallQualityLevel level;
  final int delayMs;
  final String speed;
  final String suggestion;

  VoiceCallQualityLevel get qualityLevel => level;

  VoiceCallQualityAssessment({
    required this.level,
    required this.delayMs,
    required this.speed,
    required this.suggestion,
  });

  /// Whether voice call is recommended.
  bool get recommended => level != VoiceCallQualityLevel.poor;
}

/// Monitors network quality during a voice call and adjusts Opus bitrate.
///
/// Uses the existing TestDelay mechanism (1-second sampling) via
/// [QualityMonitorModel] data. When delay degrades, the Opus encoder
/// bitrate is lowered to reduce bandwidth; when it recovers, bitrate
/// is raised back.
class VoiceCallQuality {
  static const int _checkIntervalMs = 3000; // check every 3s

  /// Callback to set the Opus encoder bitrate on the audio handler.
  void Function(int bitrate)? onBitrateChanged;

  /// Callback when the quality status string should be updated in UI.
  void Function(String status)? onQualityStatus;

  Timer? _timer;
  int _currentBitrate = 24000;
  int _badCount = 0;
  int _goodCount = 0;

  /// Current bitrate in bps.
  int get currentBitrate => _currentBitrate;

  /// Pre-call assessment based on current connection metrics.
  static VoiceCallQualityAssessment assess({int? delayMs, String? speed}) {
    final delay = delayMs ?? 0;
    final sp = speed ?? '';

    if (delay > 0 && delay < 200) {
      return VoiceCallQualityAssessment(
        level: VoiceCallQualityLevel.good,
        delayMs: delay,
        speed: sp,
        suggestion: '',
      );
    } else if (delay > 0 && delay <= 400) {
      return VoiceCallQualityAssessment(
        level: VoiceCallQualityLevel.fair,
        delayMs: delay,
        speed: sp,
        suggestion: 'fair_network_voice_call_tip',
      );
    } else {
      return VoiceCallQualityAssessment(
        level: VoiceCallQualityLevel.poor,
        delayMs: delay,
        speed: sp,
        suggestion: 'poor_network_voice_call_tip',
      );
    }
  }

  /// Start monitoring during an active call.
  /// [getDelay] returns the current delay in ms (from QualityMonitorModel).
  void start(int Function() getDelay) {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: _checkIntervalMs),
      (_) => _check(getDelay()),
    );
  }

  void _check(int delay) {
    if (delay <= 0) return;

    if (delay > 800) {
      _badCount++;
      _goodCount = 0;
      onQualityStatus?.call('very_poor_network_hangup_tip');
    } else if (delay > 500) {
      _badCount++;
      _goodCount = 0;
      _setBitrate(8000);
      onQualityStatus?.call('poor_network_voice_call_tip');
    } else if (delay > 300) {
      _badCount++;
      _goodCount = 0;
      _setBitrate(16000);
      onQualityStatus?.call('fair_network_voice_call_tip');
    } else {
      _goodCount++;
      _badCount = 0;
      if (_goodCount >= 2 && _currentBitrate < 24000) {
        _setBitrate(24000);
        onQualityStatus?.call('');
      }
    }
  }

  void _setBitrate(int bps) {
    if (_currentBitrate == bps) return;
    _currentBitrate = bps;
    onBitrateChanged?.call(bps);
  }

  /// Stop monitoring.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _badCount = 0;
    _goodCount = 0;
    _currentBitrate = 24000;
  }
}
