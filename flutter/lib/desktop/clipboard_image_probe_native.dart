import 'package:win32/win32.dart';

bool isWindowsClipboardImageAvailable() =>
    IsClipboardFormatAvailable(CLIPBOARD_FORMAT.CF_DIB) != 0 ||
    IsClipboardFormatAvailable(CLIPBOARD_FORMAT.CF_DIBV5) != 0;
