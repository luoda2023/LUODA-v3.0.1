class DirectChatStorage {
  /// Web stub: no filesystem, so external-process change detection is N/A.
  Future<DateTime?> modifiedTime() async => null;

  String? _value;

  Future<String?> read() async => _value;

Future<void> write(String value) async {
_value = value;
}

Future<void> renameToBackup() async {
_value = null;
}

Future<String> update(
    Future<String> Function(String? current) transform,
  ) async {
    _value = await transform(_value);
    return _value!;
  }
}
