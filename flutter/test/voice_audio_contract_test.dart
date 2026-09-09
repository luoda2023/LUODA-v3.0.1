import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speaker route uses the Boolean accepted by Android', () {
    final source =
        File('lib/mobile/pages/voice_call_page.dart').readAsStringSync();
    expect(source, contains("invokeMethod('set_audio_speaker', on)"));
  });

  test('record keeps echo cancellation and noise suppression enabled', () {
    final source = File('lib/common/voice_call_audio.dart').readAsStringSync();
    expect(source, contains('echoCancel: true'));
    expect(source, contains('noiseSuppress: true'));
    expect(source, isNot(contains('autoGain: true')));
  });

  test('speaker and earpiece both use communication mode during calls', () {
    final source = File(
      'android/app/src/main/kotlin/com/dotchat/remote31/MainActivity.kt',
    ).readAsStringSync();
    final start = source.indexOf('"set_audio_speaker" ->');
    final end = source.indexOf('"start_proximity" ->', start);
    final routing = source.substring(start, end);
    expect(routing, contains('am.mode = AudioManager.MODE_IN_COMMUNICATION'));
    expect(routing, isNot(contains('AudioManager.MODE_NORMAL')));
    expect(routing, contains('am.isSpeakerphoneOn = on'));
  });

  test('mobile voice call has one microphone owner', () {
    final chat = File('lib/models/chat_model.dart').readAsStringSync();
    final audio = File('lib/common/voice_call_audio.dart').readAsStringSync();
    final native = File(
      'android/app/src/main/kotlin/com/dotchat/remote31/AudioRecordHandle.kt',
    ).readAsStringSync();

    // Dart owns call capture and sends PCM16/Opus. The call lifecycle must not
    // invoke the native Rust AUDIO_RAW recorder as a second producer.
    expect(chat, contains('await _voiceCallAudio!.startCapture();'));
    expect(chat, contains('do NOT invoke Kotlin on_voice_call_started'));
    expect(audio, contains('AndroidAudioSource.voiceCommunication'));
    expect(audio, contains('codec: Codec.pcm16'));
    expect(audio, contains('interleaved: false'));
    expect(audio, contains('feedInt16FromStream'));
    expect(audio, contains('VoiceCallCodec.samplesPerFrame * 2'));
    expect(audio, isNot(contains('_player.feedFromStream(')));
    expect(native, contains('Dart VoiceCallAudio owns mobile mic'));
    expect(native, contains('voiceCallActive = true'));
    expect(native, contains('if (voiceCallActive)'));
    expect(native, contains('startAudioRecorder skipped'));
    expect(native, contains('voiceCallActive = false'));
  });

  test('voice-state service callback stops native capture during calls', () {
    final source = File(
      'android/app/src/main/kotlin/com/dotchat/remote31/MainService.kt',
    ).readAsStringSync();
    final start = source.indexOf('"update_voice_call_state" ->');
    final end = source.indexOf('"stop_capture" ->', start);
    final stateHandler = source.substring(start, end);
    expect(stateHandler,
        contains('audioRecordHandle.onVoiceCallStarted(mediaProjection)'));
    expect(stateHandler, contains('if (inVoiceCall)'));
    expect(stateHandler, contains('else if (incomingVoiceCall)'));
    expect(stateHandler,
        contains('audioRecordHandle.onVoiceCallClosed(mediaProjection)'));
  });

  test('call close notifies native audio owner exactly after stopping audio',
      () {
    final source = File('lib/models/chat_model.dart').readAsStringSync();
    final close = source.indexOf('void onVoiceCallClosed(String reason)');
    final end = source.indexOf('/// 通话结束：', close);
    final lifecycle = source.substring(close, end);
    expect(lifecycle, contains('unawaited(_stopMobileVoiceCallAudio())'));
    expect(lifecycle, contains('invokeMethod("on_voice_call_closed")'));
  });
}
