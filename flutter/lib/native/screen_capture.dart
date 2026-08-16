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
      // 1) 优先使用编译好的 shot_overlay.exe（WinForms GUI 程序）：
      //    启动 <100ms（无 PowerShell 延迟）、无控制台窗口（不闪烁）、
      //    UTF-8 编译（中文提示不乱码）。找不到时先用 csc 现场编译一次
      //    并缓存到应用数据目录（首次 1-2 秒，之后复用）。
      final exe = await _ensureShotOverlayExe();
      if (exe != null) {
        try {
          final result = await Process.run(exe, ['-Out', target])
              .timeout(const Duration(seconds: 180));
          if (result.exitCode == 0 && await File(target).exists()) {
            return target;
          }
          // exitCode != 0 = 用户按 Esc 取消或脚本失败。
          return null;
        } catch (_) {
          // 运行失败时回退到 PowerShell 脚本。
        }
      }

      // 2) 回退：PowerShell overlay 脚本。写文件时加 UTF-8 BOM（否则
      //    PowerShell 5.1 按 ANSI 解析导致中文提示乱码），并以隐藏窗口
      //    方式启动（避免黑色控制台窗口闪现）。
      final scriptContent =
          await rootBundle.loadString('assets/scripts/shot_overlay.ps1');
      final script = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'luoda_shot_ov_$stamp.ps1',
      );
      final withBom = scriptContent.startsWith('\uFEFF')
          ? scriptContent
          : '\uFEFF$scriptContent';
      await script.writeAsString(withBom);
      try {
        // 用户框选期间等待其操作；长时间无操作自动放弃，避免永久挂起。
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle',
            'Hidden',
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

/// 定位构建期编译的 shot_overlay.exe（与 luoda.exe 同目录，或开发构建目录）。
Future<String?> _findShotOverlayExe() async {
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidate =
        '$exeDir${Platform.pathSeparator}shot_overlay.exe';
    if (File(candidate).existsSync()) return candidate;
  } catch (_) {}
  try {
    final cwd = Directory.current.path;
    final candidate = '$cwd${Platform.pathSeparator}build'
        '${Platform.pathSeparator}windows${Platform.pathSeparator}x64'
        '${Platform.pathSeparator}runner${Platform.pathSeparator}Release'
        '${Platform.pathSeparator}shot_overlay.exe';
    if (File(candidate).existsSync()) return candidate;
  } catch (_) {}
  return null;
}

/// 确保 shot_overlay.exe 可用：优先用构建期编译产物，找不到时用 .NET
/// Framework 自带的 csc.exe 现场编译一次（源码来自 assets，UTF-8 编译），
/// 缓存到应用数据目录，之后复用。全部失败返回 null（回退 PowerShell）。
Future<String?> _ensureShotOverlayExe() async {
  final existing = await _findShotOverlayExe();
  if (existing != null) return existing;
  try {
    final supportDir = await getApplicationSupportDirectory();
    final exePath = '${supportDir.path}${Platform.pathSeparator}shot_overlay.exe';
    if (File(exePath).existsSync()) return exePath;
    final cs =
        await rootBundle.loadString('assets/scripts/shot_overlay.cs');
    final csFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'luoda_shot_overlay_build.cs',
    );
    await csFile.writeAsString(cs);
    try {
      final result = await Process.run(
        r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
        [
          '-nologo',
          '-target:winexe',
          '-codepage:65001',
          '-optimize+',
          r'-r:C:/Windows/Microsoft.NET/Framework64/v4.0.30319/System.Windows.Forms.dll',
          r'-r:C:/Windows/Microsoft.NET/Framework64/v4.0.30319/System.Drawing.dll',
          '-out:$exePath',
          csFile.path,
        ],
      ).timeout(const Duration(seconds: 60));
      if (result.exitCode == 0 && File(exePath).existsSync()) {
        return exePath;
      }
    } finally {
      try {
        await csFile.delete();
      } catch (_) {}
    }
  } catch (_) {}
  return null;
}
