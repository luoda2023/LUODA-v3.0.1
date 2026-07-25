import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/chat_model.dart';

/// Reads a PNG image from the system clipboard (e.g. a screenshot or a copied
/// picture) and writes it to a temporary file. Returns the file path, or null
/// when there is no image on the clipboard or reading fails for any reason.
Future<String?> readClipboardImagePath() async {
  try {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;
    final reader = await clipboard.read();
    if (!reader.canProvide(Formats.png)) return null;

    final dir = await getTemporaryDirectory();
    final target = File(p.join(
      dir.path,
      'luoda_clipboard_${DateTime.now().microsecondsSinceEpoch}.png',
    ));
    final completer = Completer<String>();
    reader.getFile(Formats.png, (virtualFile) async {
      try {
        final bytes = <int>[];
        await for (final chunk in virtualFile.getStream()) {
          bytes.addAll(chunk);
        }
        await target.writeAsBytes(bytes);
        completer.complete(target.path);
      } catch (e) {
        completer.completeError(e);
      }
    });
    return await completer.future;
  } catch (_) {
    return null;
  }
}

/// Pastes an image from the clipboard into the active direct chat as an image
/// file message. Shows a toast when the clipboard has no image.
Future<void> pasteImageToChat(ChatModel chatModel) async {
  final path = await readClipboardImagePath();
  if (path == null) {
    showToast(translate('No image found in clipboard'));
    return;
  }
  final file = File(path);
  final size = await file.length();
  final name = 'clipboard_${DateTime.now().millisecondsSinceEpoch}.png';
  await chatModel.sendFileRecord(
    fileName: name,
    fileSize: size,
    localPath: path,
  );
  showToast(translate('Image sent'));
}
