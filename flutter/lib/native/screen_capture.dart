// Local screen capture helpers (chat "screenshot" tool).
//
// Follows the same lightweight PowerShell / shell-script pattern used by the
// clipboard-image reader: no extra native plugin is required, and the image is
// saved to a temp PNG that the caller can insert into a conversation.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Captures the full (virtual) screen and saves it as a PNG file.
///
/// Returns the absolute path of the saved image, or null on failure.
Future<String?> captureScreenToFile() async {
  try {
    final supportDir = await getApplicationSupportDirectory();
    final imageDir = Directory(
      '${supportDir.path}${Platform.pathSeparator}screenshots',
    );
    await imageDir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target =
        '${imageDir.path}${Platform.pathSeparator}screenshot_$stamp.png';

    if (Platform.isWindows) {
      final script = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'luoda_shot_$stamp.ps1',
      );
      final safePath = target.replaceAll('\\', '\\\\');
      final ps = StringBuffer()
        ..writeln('Add-Type -AssemblyName System.Windows.Forms;')
        ..writeln('Add-Type -AssemblyName System.Drawing;')
        ..writeln(
            r'$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen;')
        ..writeln(r'$bmp = New-Object System.Drawing.Bitmap $vs.Width, $vs.Height;')
        ..writeln(r'$g = [System.Drawing.Graphics]::FromImage($bmp);')
        ..writeln(r'$g.CopyFromScreen($vs.X, $vs.Y, 0, 0, $bmp.Size);')
        ..writeln(r'$bmp.Save("' +
            safePath +
            r'", [System.Drawing.Imaging.ImageFormat]::Png);')
        ..writeln(r'$g.Dispose(); $bmp.Dispose();');
      await script.writeAsString(ps.toString());
      try {
        // Timeout guards against PowerShell hanging (e.g. locked session),
        // which would otherwise leave the chat window hidden forever.
        final result = await Process.run(
          'powershell',
          ['-NoProfile', '-NonInteractive', '-File', script.path],
        ).timeout(const Duration(seconds: 20));
        if (result.exitCode == 0 && await File(target).exists()) {
          return target;
        }
      } finally {
        try {
          await script.delete();
        } catch (_) {}
      }
      return null;
    }

    if (Platform.isMacOS) {
      final result = await Process.run(
        'screencapture',
        ['-x', '-t', 'png', target],
      );
      if (result.exitCode == 0 && await File(target).exists()) return target;
      return null;
    }

    if (Platform.isLinux) {
      final result = await Process.run(
        'import',
        ['-window', 'root', target],
      );
      if (result.exitCode == 0 && await File(target).exists()) return target;
      return null;
    }
  } catch (_) {
    return null;
  }
  return null;
}
