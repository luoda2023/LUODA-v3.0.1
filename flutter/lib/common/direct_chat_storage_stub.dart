class DirectChatStorage {
  String? _value;

  Future<String?> read() async => _value;

  Future<void> write(String value) async {
    _value = value;
  }

  Future<String> update(
    Future<String> Function(String? current) transform,
  ) async {
    _value = await transform(_value);
    return _value!;
  }
}
