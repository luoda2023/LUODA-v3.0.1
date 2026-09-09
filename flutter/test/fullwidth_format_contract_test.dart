import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 全角字符混用防回归契约（LUODA）：
/// 时间/时长/ID/端口等机器可读格式一律使用半角字符（`:` `-` `.` 数字），
/// 禁止全角冒号（：）、全角数字（０-９）与中间点（·）混入格式上下文。
///
/// 允许的例外（本测试显式放行）：
/// - 注释/文档中的中文文案（中文标点合法）；
/// - src/lang/*.rs 翻译文件（中文/加泰罗尼亚语等语言的合法标点与语言字符）；
/// - 运行时单字符 `Text('·')`（消息状态标签分隔点，微信同款）与键盘输入
///   法字符 `chr == '·'`（keyboard.rs）；
/// - direct_chat.dart 解析旧数据的正则 ` [·-] `（兼容历史记录，非生成格式）。
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path.replaceAll('\\', '/'));

  test('运行时字符串无全角冒号邻接数字（时间/ID/端口格式）', () {
    final offenders = <String>[];
    for (final path in dartFiles) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = _stripComments(lines[i]);
        // 全角冒号：前后邻接数字（如 12：34 / ：80 / 42：）
        if (RegExp(r'\d：|：\d').hasMatch(code)) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '发现时间/ID/端口格式混入全角冒号：\n${offenders.join('\n')}');
  });

  test('运行时字符串无全角数字（０-９）', () {
    final offenders = <String>[];
    for (final path in dartFiles) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = _stripComments(lines[i]);
        if (RegExp(r'[０-９]').hasMatch(code)) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: '发现全角数字混入代码：\n${offenders.join('\n')}');
  });

  test('运行时无空格包裹的中间点（ ` · ` 分隔符）', () {
    final offenders = <String>[];
    for (final path in dartFiles) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = _stripComments(lines[i]);
        if (code.contains(' · ') || code.contains('· ')) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    // 白名单：direct_chat.dart 解析旧记录的正则（兼容历史数据，非生成格式）。
    final whitelisted = offenders
        .where((o) => o.contains('direct_chat.dart') && o.contains('·-'))
        .toList();
    for (final w in whitelisted) {
      offenders.remove(w);
    }
    expect(offenders, isEmpty,
        reason: '发现 ` · ` 分隔符混入：\n${offenders.join('\n')}');
  });

  test('通话记录灰气泡格式保持半角连字符', () {
    final src = File('lib/common/direct_chat.dart').readAsStringSync();
    expect(src, contains("' - '"));
    expect(src, isNot(contains("' · '")));
  });

  test('Rust 侧非翻译代码无全角冒号邻接数字/全角数字', () {
    final offenders = <String>[];
    final rustFiles = Directory('../src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) {
      if (!f.path.endsWith('.rs')) return false;
      final p = f.path.replaceAll('\\', '/');
      // 翻译文件（中文/加泰罗尼亚语等）的全角标点与语言字符合法。
      return !p.contains('/lang/');
    }).map((f) => f.path.replaceAll('\\', '/'));
    for (final path in rustFiles) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = _stripComments(lines[i]);
        if (RegExp(r'\d：|：\d|[０-９]').hasMatch(code)) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Rust 侧发现全角格式混用：\n${offenders.join('\n')}');
  });

  test('桌面原生代码（windows/macos）无全角冒号邻接数字/全角数字/中间点', () {
    final offenders = <String>[];
    // 扫描 windows/ 和 macos/ 原生代码（排除 ephemeral 生成文件）。
    final desktopDirs = [
      Directory('../flutter/windows'),
      Directory('../flutter/macos'),
    ];
    for (final dir in desktopDirs) {
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final p = entity.path.replaceAll('\\', '/');
        if (p.contains('/ephemeral/') ||
            p.contains('.pub-cache/') ||
            p.contains('GeneratedPluginRegistrant.')) continue;
        final ext = p.split('.').last.toLowerCase();
        const allowedExts = [
          'cpp',
          'cc',
          'c',
          'h',
          'hpp',
          'hxx',
          'm',
          'mm',
          'swift',
          'cmake',
          'txt',
          'plist',
          'json'
        ];
        if (!allowedExts.contains(ext)) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = _stripComments(lines[i]);
          if (RegExp(r'\d：|：\d').hasMatch(code)) {
            offenders.add('$p:${i + 1}: ${lines[i].trim()}');
          }
          if (RegExp(r'[０-９]').hasMatch(code)) {
            offenders.add('$p:${i + 1}: ${lines[i].trim()}');
          }
          if (code.contains(' · ') || code.contains('· ')) {
            offenders.add('$p:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '桌面原生代码（windows/macos）发现全角格式混用：\n${offenders.join('\n')}');
  });

  test('桌面 CMakeLists.txt 无全角数字/全角冒号', () {
    final offenders = <String>[];
    final cmakeFiles = Directory('../flutter/windows')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.cmake') || f.path.endsWith('CMakeLists.txt'))
        .map((f) => f.path.replaceAll('\\', '/'));
    for (final path in cmakeFiles) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = _stripComments(lines[i]);
        if (RegExp(r'\d：|：\d|[０-９]').hasMatch(code)) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'CMake 文件发现全角格式混用：\n${offenders.join('\n')}');
  });

  test('桌面 macOS Info.plist 无全角数字/全角冒号', () {
    final offenders = <String>[];
    final plistFiles = Directory('../flutter/macos')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.plist'))
        .map((f) => f.path.replaceAll('\\', '/'));
    for (final path in plistFiles) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = _stripComments(lines[i]);
        if (RegExp(r'\d：|：\d|[０-９]').hasMatch(code)) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'macOS plist 文件发现全角格式混用：\n${offenders.join('\n')}');
  });
}

/// 去掉行注释（// 及块注释残留），保留字符串字面量等代码部分。
String _stripComments(String line) {
  final s = line.trim();
  if (s.startsWith('//') || s.startsWith('///') || s.startsWith('/*')) {
    return '';
  }
  final idx = line.indexOf('//');
  return idx < 0 ? line : line.substring(0, idx);
}
