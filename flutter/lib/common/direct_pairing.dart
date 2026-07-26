import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/platform_model.dart';

class DirectPairing {
  const DirectPairing({
    required this.peerId,
    required this.displayName,
    required this.lanEndpoint,
    required this.publicEndpoint,
    required this.fingerprint,
    required this.updatedAt,
    this.companion = false,
    this.syncSecret = '',
    this.avatar = '',
    this.ddnsEndpoint = '',
  });

  final String peerId;
  final String displayName;
  final String lanEndpoint;
  final String publicEndpoint;
  final String fingerprint;
  final DateTime updatedAt;
  final bool companion;
  final String syncSecret;
  final String avatar;
  /// DDNS domain:port, e.g. my-pc.example.com:21116
  /// When set, the client resolves the domain via DNS AAAA (IPv6) first,
  /// then falls back to A record (IPv4). This enables direct P2P without
  /// relay when both sides have IPv6.
  final String ddnsEndpoint;

  List<String> get endpoints => <String>{
        if (ddnsEndpoint.isNotEmpty) ddnsEndpoint,
        if (lanEndpoint.isNotEmpty) lanEndpoint,
        if (publicEndpoint.isNotEmpty) publicEndpoint,
      }.toList(growable: false);

  String get preferredEndpoint =>
      ddnsEndpoint.isNotEmpty ? ddnsEndpoint
      : lanEndpoint.isNotEmpty ? lanEndpoint
      : publicEndpoint;

  String get connectionTarget {
    final key = fingerprint.replaceAll(':', '').replaceAll(' ', '');
    if (peerId.isEmpty || preferredEndpoint.isEmpty || key.isEmpty) {
      return preferredEndpoint;
    }
    final fallback = lanEndpoint.isNotEmpty &&
            publicEndpoint.isNotEmpty &&
            publicEndpoint != lanEndpoint
        ? '&fallback=$publicEndpoint'
        : '';
    final sync = companion && syncSecret.isNotEmpty
        ? '&sync=${Uri.encodeQueryComponent(syncSecret)}'
        : '';
    return '$peerId@$preferredEndpoint?key=$key$fallback$sync';
  }

  Map<String, dynamic> toJson({bool includeSecret = true}) => <String, dynamic>{
        'peer_id': peerId,
        'display_name': displayName,
        'lan_endpoint': lanEndpoint,
        'public_endpoint': publicEndpoint,
        'fingerprint': fingerprint,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'companion': companion,
        if (ddnsEndpoint.isNotEmpty) 'ddns_endpoint': ddnsEndpoint,
        if (avatar.isNotEmpty) 'avatar': avatar,
        if (includeSecret && syncSecret.isNotEmpty) 'sync_secret': syncSecret,
      };

  factory DirectPairing.fromJson(Map<String, dynamic> json) {
    return DirectPairing(
      peerId: (json['peer_id'] ?? '').toString().trim(),
      displayName: (json['display_name'] ?? '').toString().trim(),
      lanEndpoint: (json['lan_endpoint'] ?? '').toString().trim(),
      publicEndpoint: (json['public_endpoint'] ?? '').toString().trim(),
      fingerprint: (json['fingerprint'] ?? '').toString().trim(),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      companion: json['companion'] == true,
      syncSecret: (json['sync_secret'] ?? '').toString(),
      avatar: (json['avatar'] ?? '').toString(),
      ddnsEndpoint: (json['ddns_endpoint'] ?? '').toString().trim(),
    );
  }
}

class DirectPairingStore {
  DirectPairingStore._();

  static const storageKey = 'direct-pairings-v1';
  static const _companionSecretKey = 'direct-companion-secret-v1';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, DirectPairing> load() {
    try {
      final raw = bind.mainGetLocalOption(key: storageKey);
      if (raw.isEmpty) return <String, DirectPairing>{};
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final pairings = <String, DirectPairing>{};
      for (final entry in decoded.entries) {
        final pairing = DirectPairing.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (pairing.peerId.isNotEmpty && pairing.endpoints.isNotEmpty) {
          pairings[pairing.peerId] = pairing;
        }
      }
      return pairings;
    } catch (_) {
      return <String, DirectPairing>{};
    }
  }

  static DirectPairing? find(String peerId) => load()[peerId.trim()];

  static DirectPairing? latest() {
    final values = load().values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values.isEmpty ? null : values.first;
  }

  static DirectPairing? latestCompanion() {
    final values = load().values.where((pairing) => pairing.companion).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values.isEmpty ? null : values.first;
  }

  static Future<void> save(DirectPairing pairing) async {
    if (pairing.peerId.isEmpty ||
        pairing.endpoints.isEmpty ||
        !_validFingerprint(pairing.fingerprint)) {
      throw const FormatException('Pairing requires an ID and direct endpoint');
    }
    final pairings = load()..[pairing.peerId] = pairing;
    await bind.mainSetLocalOption(
      key: storageKey,
      value: jsonEncode(
        pairings.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
    revision.value++;
  }

  static Future<void> removeAll(Iterable<String> peerIds) async {
    final ids =
        peerIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    final pairings = load();
    final previousLength = pairings.length;
    pairings.removeWhere((peerId, _) => ids.contains(peerId));
    if (pairings.length == previousLength) return;
    await bind.mainSetLocalOption(
      key: storageKey,
      value: jsonEncode(
        pairings.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
    revision.value++;
  }

  static List<Map<String, dynamic>> exportContacts() => load()
      .values
      .where((pairing) => !pairing.companion)
      .map((pairing) => pairing.toJson(includeSecret: false))
      .toList(growable: false);

  static Future<void> mergeContacts(Iterable<dynamic> values) async {
    final pairings = load();
    var changed = false;
    for (final value in values) {
      try {
        final incoming = DirectPairing.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        if (incoming.peerId.isEmpty ||
            incoming.endpoints.isEmpty ||
            !_validFingerprint(incoming.fingerprint)) {
          continue;
        }
        final current = pairings[incoming.peerId];
        if (current != null && current.updatedAt.isAfter(incoming.updatedAt)) {
          continue;
        }
        pairings[incoming.peerId] = DirectPairing(
          peerId: incoming.peerId,
          displayName: incoming.displayName,
          lanEndpoint: incoming.lanEndpoint,
          publicEndpoint: incoming.publicEndpoint,
          fingerprint: incoming.fingerprint,
          updatedAt: incoming.updatedAt,
          companion: current?.companion ?? false,
          syncSecret: current?.syncSecret ?? '',
          avatar: incoming.avatar.isNotEmpty
              ? incoming.avatar
              : current?.avatar ?? '',
        );
        changed = true;
      } catch (_) {}
    }
    if (!changed) return;
    await bind.mainSetLocalOption(
      key: storageKey,
      value: jsonEncode(
        pairings.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
    revision.value++;
  }

  static bool acceptsCompanionSecret(String secret) {
    if (secret.isEmpty) return false;
    if (bind.mainGetLocalOption(key: _companionSecretKey) == secret) {
      return true;
    }
    return load().values.any(
          (pairing) => pairing.companion && pairing.syncSecret == secret,
        );
  }

  static Future<void> updateIdentity(
    String peerId, {
    required String displayName,
    required String avatar,
  }) async {
    final current = find(peerId);
    if (current == null) return;
    final nextName =
        displayName.trim().isEmpty ? current.displayName : displayName.trim();
    final nextAvatar = avatar.trim().isEmpty ? current.avatar : avatar.trim();
    if (nextName == current.displayName && nextAvatar == current.avatar) return;
    await save(DirectPairing(
      peerId: current.peerId,
      displayName: nextName,
      lanEndpoint: current.lanEndpoint,
      publicEndpoint: current.publicEndpoint,
      fingerprint: current.fingerprint,
      updatedAt: DateTime.now().toUtc(),
      companion: current.companion,
      syncSecret: current.syncSecret,
      avatar: nextAvatar,
    ));
  }

  static Future<void> saveDiscovered({
    required String peerId,
    required String endpoint,
    required String fingerprint,
    required String displayName,
    required String avatar,
  }) async {
    if (peerId.isEmpty ||
        !isDirectEndpoint(endpoint) ||
        !_validFingerprint(fingerprint)) {
      return;
    }
    final current = find(peerId);
    await save(DirectPairing(
      peerId: peerId,
      displayName:
          displayName.isEmpty ? current?.displayName ?? peerId : displayName,
      lanEndpoint: endpoint,
      publicEndpoint: current?.publicEndpoint ?? '',
      fingerprint: fingerprint,
      updatedAt: DateTime.now().toUtc(),
      companion: current?.companion ?? false,
      syncSecret: current?.syncSecret ?? '',
      avatar: avatar.isEmpty ? current?.avatar ?? '' : avatar,
    ));
  }

  static String? resolveEndpoint(String value) {
    final input = value.trim().replaceAll(' ', '');
    if (isDirectEndpoint(input)) return input;
    return find(input)?.preferredEndpoint;
  }

  static String? resolveConnectionTarget(String value) {
    final input = value.trim().replaceAll(' ', '');
    if (isDirectEndpoint(input)) return input;
    return find(input)?.connectionTarget ?? (isDeviceId(input) ? input : null);
  }

  /// Device IDs are resolved by the rendezvous/direct-punching core when no
  /// local pairing record is available. Keep that path open for first contact.
  static bool isDeviceId(String value) {
    final input = value.trim().replaceAll(' ', '');
    return RegExp(r'^[A-Za-z0-9_-]{3,64}(?:/r)?$').hasMatch(input) &&
        !isDirectEndpoint(input);
  }

  static bool isDirectEndpoint(String value) {
    final input = value.trim();
    if (input.isEmpty || input.contains(RegExp(r'\s'))) return false;
    final bracketedIpv6 =
        RegExp(r'^\[[0-9a-fA-F:]+\]:([0-9]{1,5})$').firstMatch(input);
    if (bracketedIpv6 != null) {
      return _validPort(bracketedIpv6.group(1));
    }
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
    return false;
  }

  static Future<bool> isSelfTarget(String value) async {
    try {
      return isSelfTargetValue(
        value,
        ownId: await bind.mainGetMyId(),
        localAddresses: <String>[
          bind.mainGetOptionSync(key: 'lan-ip'),
          bind.mainGetOptionSync(key: 'public-ip'),
        ],
      );
    } catch (error) {
      debugPrint('Unable to check local connection target: $error');
      return false;
    }
  }

  @visibleForTesting
  static bool isSelfTargetValue(
    String value, {
    required String ownId,
    Iterable<String> localAddresses = const <String>[],
  }) {
    final input = value.trim().replaceAll(' ', '');
    if (input.isEmpty) return false;

    final at = input.indexOf('@');
    final targetId = at > 0 ? input.substring(0, at) : input;
    final normalizedOwnId = _withoutRelaySuffix(
      ownId.trim().replaceAll(' ', ''),
    );
    if (normalizedOwnId.isNotEmpty &&
        _withoutRelaySuffix(targetId) == normalizedOwnId) {
      return true;
    }

    final endpoint =
        (at > 0 ? input.substring(at + 1) : input).split('?').first;
    final host = _endpointHost(endpoint);
    if (host == null) return false;
    final normalizedHost = host.toLowerCase();
    if (normalizedHost == 'localhost' ||
        normalizedHost == '::1' ||
        normalizedHost == '::' ||
        normalizedHost == '0.0.0.0' ||
        normalizedHost.startsWith('127.')) {
      return true;
    }

    for (final address in localAddresses) {
      final localHost = _endpointHost(address.trim())?.toLowerCase();
      if (localHost != null &&
          localHost.isNotEmpty &&
          localHost == normalizedHost) {
        return true;
      }
    }
    return false;
  }

  static String _withoutRelaySuffix(String value) {
    return value.toLowerCase().endsWith('/r')
        ? value.substring(0, value.length - 2)
        : value;
  }

  static String? _endpointHost(String value) {
    final endpoint = value.trim();
    if (endpoint.isEmpty) return null;
    if (endpoint.startsWith('[')) {
      final closingBracket = endpoint.indexOf(']');
      if (closingBracket <= 1) return null;
      return endpoint.substring(1, closingBracket);
    }
    if (endpoint.split(':').length > 2) return endpoint;
    final portSeparator = endpoint.lastIndexOf(':');
    return portSeparator > 0 ? endpoint.substring(0, portSeparator) : endpoint;
  }

  static bool _validPort(String? raw) {
    final port = int.tryParse(raw ?? '');
    return port != null && port > 0 && port <= 65535;
  }

  static Future<String> buildLocalPayload() async {
    final peerId = (await bind.mainGetMyId()).trim();
    final port = bind.mainGetOptionSync(key: 'direct-access-port').trim();
    final lanEndpoint = _withPort(
      bind.mainGetOptionSync(key: 'lan-ip').trim(),
      port,
    );
    final publicEndpoint = bind.mainGetOptionSync(key: 'upnp-status') == 'ok'
        ? _withPort(
            bind.mainGetOptionSync(key: 'public-ip').trim(),
            port,
          )
        : '';
    var displayName = '';
    try {
      final profile = Map<String, dynamic>.from(
        jsonDecode(bind.mainGetLocalOption(key: 'user_info')) as Map,
      );
      displayName =
          (profile['display_name'] ?? profile['name'] ?? '').toString().trim();
    } catch (_) {}
    final fingerprint = (await bind.mainGetFingerprint()).trim();
    final syncSecret = await _getOrCreateCompanionSecret();
    return Uri(
      scheme: 'luoda',
      host: 'pair',
      queryParameters: <String, String>{
        'v': '2',
        'id': peerId,
        if (displayName.isNotEmpty) 'name': displayName,
        if (lanEndpoint.isNotEmpty) 'lan': lanEndpoint,
        if (publicEndpoint.isNotEmpty) 'wan': publicEndpoint,
        if (fingerprint.isNotEmpty) 'fp': fingerprint,
        'role': 'companion',
        'sync': syncSecret,
        'ts': DateTime.now().toUtc().toIso8601String(),
      },
    ).toString();
  }

  static DirectPairing? parsePayload(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'luoda' ||
        uri.host.toLowerCase() != 'pair' ||
        !<String>{'1', '2'}.contains(uri.queryParameters['v'])) {
      return null;
    }
    final pairing = DirectPairing(
      peerId: (uri.queryParameters['id'] ?? '').trim(),
      displayName: (uri.queryParameters['name'] ?? '').trim(),
      lanEndpoint: (uri.queryParameters['lan'] ?? '').trim(),
      publicEndpoint: (uri.queryParameters['wan'] ?? '').trim(),
      fingerprint: (uri.queryParameters['fp'] ?? '').trim(),
      updatedAt: DateTime.tryParse(uri.queryParameters['ts'] ?? '') ??
          DateTime.now().toUtc(),
      companion: uri.queryParameters['role'] == 'companion',
      syncSecret: (uri.queryParameters['sync'] ?? '').trim(),
    );
    if (pairing.peerId.isEmpty ||
        !_validFingerprint(pairing.fingerprint) ||
        (pairing.companion && pairing.syncSecret.isEmpty) ||
        pairing.endpoints.isEmpty ||
        pairing.endpoints.any((item) => !isDirectEndpoint(item))) {
      return null;
    }
    return pairing;
  }

  static String _withPort(String host, String port) {
    if (host.isEmpty || port.isEmpty) return '';
    if (host.contains(':') && !host.startsWith('[')) return '[$host]:$port';
    return '$host:$port';
  }

  static Future<String> _getOrCreateCompanionSecret() async {
    final current = bind.mainGetLocalOption(key: _companionSecretKey).trim();
    if (current.isNotEmpty) return current;
    final secret =
        '${const Uuid().v4()}${const Uuid().v4()}'.replaceAll('-', '');
    await bind.mainSetLocalOption(key: _companionSecretKey, value: secret);
    return secret;
  }

  static bool _validFingerprint(String value) {
    final normalized = value.replaceAll(':', '').replaceAll(' ', '');
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(normalized);
  }
}
