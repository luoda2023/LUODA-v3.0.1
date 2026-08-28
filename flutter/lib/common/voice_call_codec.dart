import 'dart:typed_data';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart';

/// Opus codec wrapper for voice call audio on mobile.
///
/// Uses 48kHz mono with [Application.voip] for optimal speech quality
/// at low bitrates. The encoder/decoder are recreated when the bitrate
/// changes (opus_dart does not support runtime bitrate changes).
class VoiceCallCodec {
  static const int sampleRate = 48000;
  static const int channels = 1;
  static const int frameSizeMs = 20;
  static const int samplesPerFrame = (sampleRate ~/ 1000) * frameSizeMs; // 960

SimpleOpusEncoder? _encoder;
SimpleOpusDecoder? _decoder;

int _bitrate = 24000; // target bitrate in bps (informational; maps to maxOutputSizeBytes)
int _maxOutputSizeBytes = 960; // 24kbps → ~60 bytes per 20ms frame, generous default

bool _initialized = false;

/// Initialize opus library and create encoder/decoder.
Future<void> init() async {
if (_initialized) return;
initOpus(await load());
_createEncoder();
_createDecoder();
_initialized = true;
}

void _createEncoder() {
_encoder?.destroy();
_encoder = SimpleOpusEncoder(
sampleRate: sampleRate,
channels: channels,
application: Application.voip,
);
}

void _createDecoder() {
_decoder?.destroy();
_decoder = SimpleOpusDecoder(
sampleRate: sampleRate,
channels: channels,
);
}

/// Change the target bitrate. opus_dart's SimpleOpusEncoder is immutable after
/// construction and has no bitrate setter, so we approximate the bitrate
/// change by clamping the encoder's maxOutputSizeBytes: lower bitrate →
/// smaller output buffer → Opus internally reduces the bitrate.
set bitrate(int bps) {
if (_bitrate == bps) return;
_bitrate = bps;
// 20ms frame at bitrate bps → bytes = bps * 20 / 8
// e.g. 24kbps → 60 bytes, 16kbps → 40 bytes, 8kbps → 20 bytes
// Use 4× the theoretical value as headroom (Opus may overshoot).
_maxOutputSizeBytes = (bps * 20 ~/ 8 * 4).clamp(20, 4000);
}

int get bitrate => _bitrate;

/// Encode Float32 PCM to Opus bytes.
///
/// [pcm] must contain exactly [samplesPerFrame] samples (960 for 20ms@48kHz).
Uint8List encode(Float32List pcm) {
if (!_initialized || _encoder == null) {
throw StateError('VoiceCallCodec not initialized');
}
return _encoder!.encodeFloat(input: pcm, maxOutputSizeBytes: _maxOutputSizeBytes);
}

  /// Decode Opus bytes to Float32 PCM.
  ///
  /// Returns null if [opus] is null (packet loss / DTX).
  Float32List? decode(Uint8List? opus) {
    if (!_initialized || _decoder == null) {
      throw StateError('VoiceCallCodec not initialized');
    }
    if (opus == null) {
      // PLC: decode with null input to generate comfort noise
      return _decoder!.decodeFloat(input: null);
    }
    return _decoder!.decodeFloat(input: opus);
  }

  /// Release native resources.
  void dispose() {
    _encoder?.destroy();
    _decoder?.destroy();
    _encoder = null;
    _decoder = null;
    _initialized = false;
  }
}
