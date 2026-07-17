import 'package:flutter/foundation.dart';

class ViewerSessionModel with ChangeNotifier {
  static const int _maxBroadcastMessages = 500;

  String? inviteTokenPayload;
  String? viewerListPayload;
  String? lastControlPayload;
  final List<String> broadcastChatPayloads = <String>[];

  int inviteRevision = 0;
  int viewerListRevision = 0;
  int broadcastRevision = 0;
  int controlRevision = 0;

  bool handleWireMessage(String value) {
    if (_consume(value, 'INVITE_TOKEN', (payload) {
      inviteTokenPayload = payload;
      inviteRevision++;
    })) {
      return true;
    }
    if (_consume(value, 'VIEWER_LIST', (payload) {
      viewerListPayload = payload;
      viewerListRevision++;
    })) {
      return true;
    }
    if (_consume(value, 'BROADCAST_CHAT', (payload) {
      broadcastChatPayloads.add(payload);
      if (broadcastChatPayloads.length > _maxBroadcastMessages) {
        broadcastChatPayloads.removeAt(0);
      }
      broadcastRevision++;
    })) {
      return true;
    }
    for (final prefix in const <String>[
      'KICK_VIEWER',
      'PROMOTE_VIEWER',
      'RAISE_HAND',
      'VIEWER_BADGE',
      'REQUEST_INVITE_TOKEN',
    ]) {
      if (_consume(value, prefix, (_) {
        lastControlPayload = value;
        controlRevision++;
      })) {
        return true;
      }
    }
    return false;
  }

  bool _consume(
    String value,
    String prefix,
    ValueChanged<String> onPayload,
  ) {
    final marker = '$prefix:';
    if (!value.startsWith(marker)) return false;
    onPayload(value.substring(marker.length));
    notifyListeners();
    return true;
  }

  void clear() {
    inviteTokenPayload = null;
    viewerListPayload = null;
    lastControlPayload = null;
    broadcastChatPayloads.clear();
    inviteRevision++;
    viewerListRevision++;
    broadcastRevision++;
    controlRevision++;
    notifyListeners();
  }
}
