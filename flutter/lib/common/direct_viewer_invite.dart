import 'package:flutter/foundation.dart';

class ViewerInviteLink {
  const ViewerInviteLink({
    required this.endpoint,
    required this.token,
  });

  final String endpoint;
  final String token;

  Uri toUri() => Uri(
        scheme: 'luoda',
        host: 'join',
        pathSegments: <String>[token],
        queryParameters: <String, String>{'endpoint': endpoint},
      );

  static ViewerInviteLink? tryParse(Uri uri) {
    if (uri.scheme.toLowerCase() != 'luoda' ||
        uri.host.toLowerCase() != 'join' ||
        uri.pathSegments.isEmpty) {
      return null;
    }
    final token = uri.pathSegments.first.trim();
    final endpoint = uri.queryParameters['endpoint']?.trim() ?? '';
    if (token.isEmpty || !isViewerConnectionTarget(endpoint)) return null;
    return ViewerInviteLink(endpoint: endpoint, token: token);
  }

  @override
  bool operator ==(Object other) =>
      other is ViewerInviteLink &&
      other.endpoint == endpoint &&
      other.token == token;

  @override
  int get hashCode => Object.hash(endpoint, token);
}

final ValueNotifier<ViewerInviteLink?> pendingViewerInvite =
    ValueNotifier<ViewerInviteLink?>(null);

bool publishViewerInvite(Uri uri) {
  final invite = ViewerInviteLink.tryParse(uri);
  if (invite == null) return false;
  pendingViewerInvite.value = invite;
  return true;
}

ViewerInviteLink? takePendingViewerInvite() {
  final invite = pendingViewerInvite.value;
  pendingViewerInvite.value = null;
  return invite;
}

bool isViewerConnectionTarget(String value) {
  final input = value.trim();
  if (input.isEmpty || input.contains(RegExp(r'\s'))) return false;

  final bracketedIpv6 =
      RegExp(r'^\[[0-9a-fA-F:]+\]:([0-9]{1,5})$').firstMatch(input);
  if (bracketedIpv6 != null) return _validPort(bracketedIpv6.group(1));

  final ipv4 = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?::(\d{1,5}))?$',
  ).firstMatch(input);
  if (ipv4 != null) {
    final octets = <int>[
      for (var i = 1; i <= 4; i++) int.tryParse(ipv4.group(i)!) ?? 256,
    ];
    return octets.every((octet) => octet >= 0 && octet <= 255) &&
        (ipv4.group(5) == null || _validPort(ipv4.group(5)));
  }

  final hostPort = RegExp(r'^[A-Za-z0-9.-]+:([0-9]{1,5})$').firstMatch(input);
  if (hostPort != null) return _validPort(hostPort.group(1));
  if (input.contains(':') && input.split(':').length > 2) return true;
  return RegExp(r'^[A-Za-z0-9_-]{3,64}(?:/r)?$').hasMatch(input);
}

bool _validPort(String? raw) {
  final port = int.tryParse(raw ?? '');
  return port != null && port > 0 && port <= 65535;
}
