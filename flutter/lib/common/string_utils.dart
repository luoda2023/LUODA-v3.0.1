String sanitizeInvalidUtf16(String input) {
  final units = input.codeUnits;
  final sanitized = <int>[];
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 < units.length &&
          units[i + 1] >= 0xDC00 &&
          units[i + 1] <= 0xDFFF) {
        sanitized
          ..add(unit)
          ..add(units[++i]);
      } else {
        sanitized.add(0xFFFD);
      }
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      sanitized.add(0xFFFD);
    } else {
      sanitized.add(unit);
    }
  }
  return String.fromCharCodes(sanitized);
}
