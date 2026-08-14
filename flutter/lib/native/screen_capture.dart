// Local screen capture helpers (chat "screenshot" tool).
//
// Follows the same lightweight PowerShell / shell-script pattern used by the
// clipboard-image reader: no extra native plugin is required, and the image is
// saved to a temp PNG that the caller can insert into a conversation.

import 'dart:io';

import 'package:flutter/services.dart';
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

/// Windows 截图新流程：先框选、后截取区域。
///
/// 运行全屏框选遮罩脚本（assets/scripts/shot_overlay.ps1）：用户直接在
/// 实时屏幕上拖拽框选（或按住 Ctrl 自动选窗口），确认后只把选中的区域
/// 截取保存为 PNG。与微信截图一致——不是先截全屏再在截屏图上框选。
///
/// 调用方需先按需把应用窗口移出屏幕（避免出现在截图里），
/// 结束后恢复窗口位置。
///
/// 返回区域 PNG 路径；用户取消或失败返回 null。
Future<String?> captureRegionToFile() async {
  try {
    final supportDir = await getApplicationSupportDirectory();
    final imageDir = Directory(
      '${supportDir.path}${Platform.pathSeparator}screenshots',
    );
    await imageDir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target =
        '${imageDir.path}${Platform.pathSeparator}shot_$stamp.png';

    if (Platform.isWindows) {
      final scriptContent =
          await rootBundle.loadString('assets/scripts/shot_overlay.ps1');
      final script = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'luoda_shot_ov_$stamp.ps1',
      );
      await script.writeAsString(scriptContent);
      try {
        // 用户框选期间等待其操作；长时间无操作自动放弃，避免永久挂起。
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            script.path,
            '-Out',
            target,
          ],
        ).timeout(const Duration(seconds: 180));
        if (result.exitCode == 0 && await File(target).exists()) {
          return target;
        }
        // exitCode != 0 = 用户按 Esc 取消或脚本失败。
        return null;
      } finally {
        try {
          await script.delete();
        } catch (_) {}
      }
    }

    // 其它平台回退到原来的全屏截图流程。
    return await captureScreenToFile();
  } catch (_) {
    return null;
  }
}
