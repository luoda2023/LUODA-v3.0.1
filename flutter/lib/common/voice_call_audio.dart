import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'voice_call_codec.dart';

/// Manages mobile-side audio capture and playback for voice calls.
///
/// Capture chain:  record.startStream (pcm16bits) → Int16 → Float32 → Opus encode → onEncoded
/// Playback chain: onDecoded (Opus bytes) → Opus decode → Float32 PCM → flutter_sound.feedFromStream
class VoiceCallAudio {
  final VoiceCallCodec _codec = VoiceCallCodec();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  final _record = AudioRecorder();

  StreamSubscription<Uint8List>? _recordSub;
  bool _capturing = false;
  bool _playing = false;

  /// Callback when Opus bytes are ready to send to the peer (via Rust FFI).
  void Function(Uint8List opus)? onEncoded;

  /// Called when Opus bytes arrive from the peer (to decode and play).
  /// Set by the event listener.
  void Function(Uint8List opus)? onIncoming;

  /// Accumulator for partial PCM samples (record may deliver arbitrary chunk sizes).
  Int16List _pcmBuffer = Int16List(0);

  VoiceCallCodec get codec => _codec;

  /// Initialize codec and player. Call before starting capture/playback.
  Future<void> init() async {
    await _codec.init();
    if (!_playing) {
      await _player.openPlayer();
      // flutter_sound: 48kHz mono Float32 stream
      await _player.startPlayerFromStream(
        sampleRate: VoiceCallCodec.sampleRate,
        numChannels: VoiceCallCodec.channels,
        codec: Codec.pcmFloat32,
        interleaved: false,
        bufferSize: 1024,
      );
      _playing = true;
    }
  }

  /// Start capturing microphone and encoding to Opus.
  Future<void> startCapture() async {
    if (_capturing) return;
    _capturing = true;

    final hasPermission = await _record.hasPermission();
    if (!hasPermission) {
      debugPrint('VoiceCallAudio: RECORD_AUDIO permission denied');
      _capturing = false;
      return;
    }

    final stream = await _record.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: VoiceCallCodec.sampleRate,
        numChannels: VoiceCallCodec.channels,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );

    _recordSub = stream.listen((data) {
      _handlePcmChunk(data);
    });
  }

  void _handlePcmChunk(Uint8List chunk) {
    // Convert incoming bytes to Int16 samples
    final newSamples = Int16List.sublistView(chunk);

    // Append to buffer
    if (_pcmBuffer.isEmpty) {
      _pcmBuffer = newSamples;
    } else {
      final combined = Int16List(_pcmBuffer.length + newSamples.length);
      combined.setRange(0, _pcmBuffer.length, _pcmBuffer);
      combined.setRange(_pcmBuffer.length, combined.length, newSamples);
      _pcmBuffer = combined;
    }

    // Encode full frames (960 samples = 20ms@48kHz)
    final frameSize = VoiceCallCodec.samplesPerFrame;
    while (_pcmBuffer.length >= frameSize) {
      final frame = Float32List(frameSize);
      for (int i = 0; i < frameSize; i++) {
        // Int16 → Float32 (-1.0 to 1.0)
        frame[i] = _pcmBuffer[i] / 32768.0;
      }
      _pcmBuffer = Int16List.sublistView(
          _pcmBuffer.buffer.asUint8List(), frameSize * 2);

      try {
        final opus = _codec.encode(frame);
        onEncoded?.call(opus);
      } catch (e) {
        debugPrint('VoiceCallAudio: encode error: $e');
      }
    }
  }

/// Feed incoming Opus bytes from peer into decoder and play.
///
/// Supports two formats:
/// - Standard Opus packets (from desktop/mobile peers with real Opus encoder)
/// - Raw PCM f32 with "RAW1" magic prefix (from Android/iOS server peers
/// where Rust Opus is a stub and raw PCM is sent instead)
void feedIncomingOpus(Uint8List opus) {
 try {
 if (opus.length >= 4 &&
 opus[0] == 0x52 && opus[1] == 0x41 &&
 opus[2] == 0x57 && opus[3] == 0x31) {
 // Raw PCM f32 mode: skip 4-byte magic, play directly
 if (_playing && opus.length > 4) {
 final pcmBytes = Uint8List.sublistView(opus, 4);
 _player.feedFromStream(pcmBytes);
 }
 return;
 }
 final pcm = _codec.decode(opus);
 if (pcm != null && _playing) {
 // Float32 → bytes for flutter_sound
 final pcmBytes = pcm.buffer.asUint8List();
 _player.feedFromStream(pcmBytes);
 }
 } catch (e) {
 debugPrint('VoiceCallAudio: decode/play error: $e');
 }
 }

  /// Stop capturing and playing.
  Future<void> stop() async {
    _capturing = false;
    await _recordSub?.cancel();
    _recordSub = null;
    _pcmBuffer = Int16List(0);

    try {
      await _record.stop();
    } catch (_) {}

    if (_playing) {
      try {
        await _player.stopPlayer();
        await _player.closePlayer();
      } catch (_) {}
      _playing = false;
    }
  }

  /// Release all resources.
  Future<void> dispose() async {
    await stop();
    _codec.dispose();
  }

  /// Set the encoder bitrate (for adaptive quality).
  set bitrate(int bps) {
    _codec.bitrate = bps;
  }

  int get bitrate => _codec.bitrate;
}
