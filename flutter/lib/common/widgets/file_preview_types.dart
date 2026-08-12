import 'package:flutter/material.dart';

enum FilePreviewKind {
  image,
  video,
  audio,
  pdf,
  document,
  spreadsheet,
  presentation,
  archive,
  executable,
  text,
  code,
  cad,
  other,
}

String fileExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

String fileExtensionLabel(String fileName) {
  final extension = fileExtension(fileName);
  if (extension.isEmpty) return 'FILE';
  return extension.substring(0, extension.length.clamp(0, 4)).toUpperCase();
}

FilePreviewKind filePreviewKindForName(String fileName) {
  final extension = fileExtension(fileName);
  if (const <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'svg',
    'heic',
    'heif',
  }.contains(extension)) {
    return FilePreviewKind.image;
  }
  if (const <String>{
    'mp4',
    'm4v',
    'avi',
    'mkv',
    'mov',
    'wmv',
    'flv',
    'webm',
  }.contains(extension)) {
    return FilePreviewKind.video;
  }
  if (const <String>{
    'mp3',
    'wav',
    'flac',
    'aac',
    'ogg',
    'wma',
    'm4a',
    'opus',
  }.contains(extension)) {
    return FilePreviewKind.audio;
  }
  if (extension == 'pdf') return FilePreviewKind.pdf;
  if (const <String>{'doc', 'docx', 'odt', 'rtf'}.contains(extension)) {
    return FilePreviewKind.document;
  }
  if (const <String>{'xls', 'xlsx', 'csv', 'ods'}.contains(extension)) {
    return FilePreviewKind.spreadsheet;
  }
  if (const <String>{'ppt', 'pptx', 'odp'}.contains(extension)) {
    return FilePreviewKind.presentation;
  }
  if (const <String>{
    'zip',
    'rar',
    '7z',
    'tar',
    'gz',
    'bz2',
    'xz',
  }.contains(extension)) {
    return FilePreviewKind.archive;
  }
  if (const <String>{
    'exe',
    'msi',
    'apk',
    'dmg',
    'pkg',
    'deb',
    'rpm',
  }.contains(extension)) {
    return FilePreviewKind.executable;
  }
  if (const <String>{
    'txt',
    'md',
    'log',
    'markdown',
  }.contains(extension)) {
    return FilePreviewKind.text;
  }
  if (const <String>{
    'dwg',
    'dxf',
    'dgn',
  }.contains(extension)) {
    return FilePreviewKind.cad;
  }
  if (const <String>{
    'json',
    'xml',
    'yaml',
    'yml',
    'toml',
    'ini',
    'dart',
    'js',
    'ts',
    'py',
    'rs',
    'c',
    'cpp',
    'h',
    'java',
    'kt',
    'swift',
    'html',
    'css',
    'sh',
    'bat',
    'ps1',
  }.contains(extension)) {
    return FilePreviewKind.code;
  }
  return FilePreviewKind.other;
}

IconData filePreviewIcon(String fileName) {
  return switch (filePreviewKindForName(fileName)) {
    FilePreviewKind.image => Icons.image_outlined,
    FilePreviewKind.video => Icons.movie_outlined,
    FilePreviewKind.audio => Icons.audiotrack_outlined,
    FilePreviewKind.pdf => Icons.picture_as_pdf_outlined,
    FilePreviewKind.document => Icons.description_outlined,
    FilePreviewKind.spreadsheet => Icons.table_chart_outlined,
    FilePreviewKind.presentation => Icons.slideshow_outlined,
    FilePreviewKind.archive => Icons.folder_zip_outlined,
    FilePreviewKind.executable => Icons.apps_outlined,
    FilePreviewKind.text => Icons.article_outlined,
    FilePreviewKind.code => Icons.code_outlined,
    FilePreviewKind.cad => Icons.architecture_outlined,
    FilePreviewKind.other => Icons.insert_drive_file_outlined,
  };
}

Color filePreviewColor(String fileName, [double opacity = 1]) {
  final color = switch (filePreviewKindForName(fileName)) {
    FilePreviewKind.image => const Color(0xFF2E9B50),
    FilePreviewKind.video => const Color(0xFFD94A73),
    FilePreviewKind.audio => const Color(0xFF8B5FC7),
    FilePreviewKind.pdf => const Color(0xFFD84A3A),
    FilePreviewKind.document => const Color(0xFF3978C6),
    FilePreviewKind.spreadsheet => const Color(0xFF27865A),
    FilePreviewKind.presentation => const Color(0xFFD9772B),
    FilePreviewKind.archive => const Color(0xFFA27618),
    FilePreviewKind.executable => const Color(0xFF267E87),
    FilePreviewKind.text => const Color(0xFF65727E),
    FilePreviewKind.code => const Color(0xFF7659A7),
    FilePreviewKind.cad => const Color(0xFFB3541E),
    FilePreviewKind.other => const Color(0xFF65727E),
  };
  return color.withOpacity(opacity);
}
