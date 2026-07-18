enum AudioEncoder { wav }

class RecordConfig {
  const RecordConfig({
    this.encoder,
    this.sampleRate,
    this.numChannels,
  });

  final AudioEncoder? encoder;
  final int? sampleRate;
  final int? numChannels;
}

class AudioRecorder {
  Future<bool> hasPermission() async => false;

  Future<void> start(RecordConfig config, {String? path}) async {}

  Future<String?> stop() async => null;

  Future<void> cancel() async {}

  Future<void> dispose() async {}
}
