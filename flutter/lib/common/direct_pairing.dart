import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'backup_restore.dart';
import '../models/platform_model.dart';

class DirectEndpointObservation {
  const DirectEndpointObservation({
    required this.endpoint,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.connectionCount,
    required this.secure,
    required this.streamType,
  });

  final String endpoint;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int connectionCount;
  final bool secure;
  final String streamType;

  DirectEndpointObservation seenAgain(DateTime observedAt) =>
      DirectEndpointObservation(
        endpoint: endpoint,
        firstSeenAt: firstSeenAt,
        lastSeenAt: observedAt,
        connectionCount: connectionCount + 1,
        secure: secure,
        streamType: streamType,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'endpoint': endpoint,
        'first_seen_at': firstSeenAt.toUtc().toIso8601String(),
        'last_seen_at': lastSeenAt.toUtc().toIso8601String(),
        'connection_count': connectionCount,
        'secure': secure,
        'stream_type': streamType,
      };

  factory DirectEndpointObservation.fromJson(Map<String, dynamic> json) {
    final firstSeenAt =
        DateTime.tryParse((json['first_seen_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return DirectEndpointObservation(
      endpoint: (json['endpoint'] ?? '').toString().trim(),
      firstSeenAt: firstSeenAt,
      lastSeenAt: DateTime.tryParse((json['last_seen_at'] ?? '').toString()) ??
          firstSeenAt,
      connectionCount:
          (int.tryParse((json['connection_count'] ?? '').toString()) ?? 1)
              .clamp(1, 1 << 31)
              .toInt(),
      secure: json['secure'] == true,
      streamType: (json['stream_type'] ?? '').toString().trim(),
    );
  }
}

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
    this.accountId = '',
    this.deviceName = '',
    this.platform = '',
    this.endpointHistory = const <DirectEndpointObservation>[],
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
  final String accountId;
  final String deviceName;
  final String platform;
  final List<DirectEndpointObservation> endpointHistory;

  /// DDNS domain:port, e.g. my-pc.example.com:21116
  /// When set, the client resolves the domain via DNS AAAA (IPv6) first,
  /// then falls back to A record (IPv4). This enables direct P2P without
  /// relay when both sides have IPv6.
  final String ddnsEndpoint;

  String get conversationId => accountId.trim().isEmpty ? peerId : accountId;

  String get currentVerifiedEndpoint {
    final newest = _newestUsableEndpoint;
    if (newest != null) return newest.endpoint;
    if (publicEndpoint.isNotEmpty &&
        !DirectPairingStore.isLegacySharedDirectEndpoint(publicEndpoint)) {
      return publicEndpoint;
    }
    return lanEndpoint;
  }

  List<String> get endpoints => <String>{
        if (ddnsEndpoint.isNotEmpty) ddnsEndpoint,
        if (lanEndpoint.isNotEmpty) lanEndpoint,
        if (publicEndpoint.isNotEmpty) publicEndpoint,
      }.toList(growable: false);

  String get preferredEndpoint {
    final newest = _newestUsableEndpoint;
    if (newest != null) return newest.endpoint;
    for (final candidate in <String>[
      ddnsEndpoint,
      lanEndpoint,
      publicEndpoint
    ]) {
      if (candidate.isNotEmpty &&
          !DirectPairingStore.isLegacySharedDirectEndpoint(candidate)) {
        return candidate;
      }
    }
    // Every known endpoint uses a legacy shared direct port (21118-21128 /
    // 20830). Current builds listen on machine-unique ports (20000-39999), so
    // dialing these endpoints fails and the peer appears to "reject" messages.
    // Return an empty endpoint so the caller falls back to ID-based dialing
    // through the rendezvous mediator, which resolves the peer's current port.
    return '';
  }

  String get connectionTarget => connectionTargetForEndpoint(preferredEndpoint);

  String connectionTargetForEndpoint(String endpoint) {
    final normalizedEndpoint =
        DirectPairingStore.extractDirectEndpoint(endpoint);
    final key = fingerprint.replaceAll(':', '').replaceAll(' ', '');
    if (peerId.isEmpty || key.isEmpty) {
      return normalizedEndpoint;
    }
    final sync = companion && syncSecret.isNotEmpty
        ? '&sync=${Uri.encodeQueryComponent(syncSecret)}'
        : '';
    if (normalizedEndpoint.isEmpty) {
      // No usable direct endpoint: dial by ID so the rendezvous mediator
      // resolves the peer's current direct-access port instead of a dead one.
      return '$peerId?key=$key$sync';
    }
    final fallbackEndpoint = _verifiedFallbackFor(normalizedEndpoint) ??
        (normalizedEndpoint == lanEndpoint ? publicEndpoint : lanEndpoint);
    final fallback =
        fallbackEndpoint.isNotEmpty && fallbackEndpoint != normalizedEndpoint
            ? '&fallback=$fallbackEndpoint'
            : '';
    return '$peerId@$normalizedEndpoint?key=$key$fallback$sync';
  }

  /// Prefer the most recently verified endpoint that differs from the primary.
  /// A LAN device can move to a new DHCP address while the pairing's
  /// `lanEndpoint` still points at its previous address; the last verified
  /// endpoint is the safest alternate to try first.
  /// Newest verified endpoint by lastSeenAt. Order-independent: the Rust
  /// side prepends freshly verified endpoints to the history array, so the
  /// list order alone cannot be trusted.
  DirectEndpointObservation? get _newestUsableEndpoint {
    DirectEndpointObservation? best;
    for (final entry in endpointHistory) {
      if (DirectPairingStore.isLegacySharedDirectEndpoint(entry.endpoint)) {
        continue;
      }
      if (best == null || entry.lastSeenAt.isAfter(best.lastSeenAt)) {
        best = entry;
      }
    }
    return best;
  }

  String? _verifiedFallbackFor(String primary) {
    final normalized = primary.toLowerCase();
    DirectEndpointObservation? best;
    for (final entry in endpointHistory) {
      if (entry.endpoint.isEmpty) continue;
      if (DirectPairingStore.isLegacySharedDirectEndpoint(entry.endpoint)) {
        continue;
      }
      if (entry.endpoint.toLowerCase() == normalized) continue;
      if (best == null || entry.lastSeenAt.isAfter(best.lastSeenAt)) {
        best = entry;
      }
    }
    return best?.endpoint;
  }

  DirectPairing withAccountId(String value) => _copyWith(
        accountId: value.trim(),
        updatedAt: DateTime.now().toUtc(),
      );

  DirectPairing recordVerifiedEndpoint({
    required String endpoint,
    required DateTime observedAt,
    required bool secure,
    required String streamType,
  }) {
    final normalized = DirectPairingStore.extractDirectEndpoint(endpoint);
    if (normalized.isEmpty || !secure) return this;
    final nextHistory = endpointHistory.toList(growable: true);
    if (nextHistory.isNotEmpty &&
        nextHistory.last.endpoint.toLowerCase() == normalized.toLowerCase() &&
        nextHistory.last.secure == secure &&
        nextHistory.last.streamType == streamType) {
      nextHistory[nextHistory.length - 1] =
          nextHistory.last.seenAgain(observedAt);
    } else {
      nextHistory.add(DirectEndpointObservation(
        endpoint: normalized,
        firstSeenAt: observedAt,
        lastSeenAt: observedAt,
        connectionCount: 1,
        secure: secure,
        streamType: streamType,
      ));
    }
    final isPrivate = DirectPairingStore.isPrivateEndpoint(normalized);
    return _copyWith(
      lanEndpoint: isPrivate ? normalized : lanEndpoint,
      publicEndpoint: isPrivate ? publicEndpoint : normalized,
      endpointHistory: nextHistory,
      updatedAt: observedAt,
    );
  }

  DirectPairing _copyWith({
    String? displayName,
    String? lanEndpoint,
    String? publicEndpoint,
    DateTime? updatedAt,
    bool? companion,
    String? syncSecret,
    String? avatar,
    String? ddnsEndpoint,
    String? accountId,
    String? deviceName,
    String? platform,
    List<DirectEndpointObservation>? endpointHistory,
  }) =>
      DirectPairing(
        peerId: peerId,
        displayName: displayName ?? this.displayName,
        lanEndpoint: lanEndpoint ?? this.lanEndpoint,
        publicEndpoint: publicEndpoint ?? this.publicEndpoint,
        fingerprint: fingerprint,
        updatedAt: updatedAt ?? this.updatedAt,
        companion: companion ?? this.companion,
        syncSecret: syncSecret ?? this.syncSecret,
        avatar: avatar ?? this.avatar,
        ddnsEndpoint: ddnsEndpoint ?? this.ddnsEndpoint,
        accountId: accountId ?? this.accountId,
        deviceName: deviceName ?? this.deviceName,
        platform: platform ?? this.platform,
        endpointHistory: endpointHistory ?? this.endpointHistory,
      );

  Map<String, dynamic> toJson({
    bool includeSecret = true,
    bool includeHistory = true,
  }) =>
      <String, dynamic>{
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
        if (accountId.isNotEmpty) 'account_id': accountId,
        if (deviceName.isNotEmpty) 'device_name': deviceName,
        if (platform.isNotEmpty) 'platform': platform,
        if (includeHistory && endpointHistory.isNotEmpty)
          'endpoint_history':
              endpointHistory.map((entry) => entry.toJson()).toList(),
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
      accountId: (json['account_id'] ?? '').toString().trim(),
      deviceName: (json['device_name'] ?? '').toString().trim(),
      platform: (json['platform'] ?? '').toString().trim(),
      endpointHistory:
          ((json['endpoint_history'] as List<dynamic>?) ?? const <dynamic>[])
              .map((value) => DirectEndpointObservation.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ))
              .where((entry) => entry.endpoint.isNotEmpty)
              .toList(growable: false),
    );
  }
}

class DirectPairingStore {
  DirectPairingStore._();

  static const storageKey = 'direct-pairings-v1';
  static const _companionSecretKey = 'direct-companion-secret-v1';
  static const _personDevicesKey = 'direct-person-devices-v1';

  /// PC 端绑定的手机（bound phone）记录 key。
  static const _boundPhoneKey = 'direct-bound-phone-v1';

  /// 按会话缓存的点聊密码（进入受密码保护的会话时使用）。
  /// key：规范化会话 id -> 密码。
  static const _chatPasswordsKey = 'direct-chat-passwords-v1';

  static void cacheChatPassword(String peerId, String password) {
    final canonical = canonicalConversationId(peerId);
    if (canonical.isEmpty) return;
    try {
      final raw = bind.mainGetLocalOption(key: _chatPasswordsKey);
      final Map<String, dynamic> map = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      final value = password.trim();
      if (value.isEmpty) {
        map.remove(canonical);
      } else {
        map[canonical] = value;
      }
      bind.mainSetLocalOption(
        key: _chatPasswordsKey,
        value: jsonEncode(map),
      );
    } catch (_) {
      // 本地配置写入失败时静默忽略。
    }
  }

  static String cachedChatPassword(String peerId) {
    final canonical = canonicalConversationId(peerId);
    if (canonical.isEmpty) return '';
    try {
      final raw = bind.mainGetLocalOption(key: _chatPasswordsKey);
      if (raw.isEmpty) return '';
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return '';
      final direct = decoded[canonical];
      if (direct is String && direct.isNotEmpty) return direct;
      for (final deviceId in conversationPeerIds(peerId)) {
        final value = decoded[deviceId];
        if (value is String && value.isNotEmpty) return value;
      }
    } catch (_) {
      // 本地配置解析失败时返回空密码。
    }
    return '';
  }

  /// Person-account -> device id list. A phone that binds to a person account
  /// advertises the same account conversation but connects with its own
  /// DotChat id / device UUID; this map links all of a person's devices so
  /// replies can be routed back over the live incoming client channel even
  /// when no full pairing record (endpoint + fingerprint) exists yet.
  static Map<String, List<String>> loadPersonDevices() {
    try {
      final raw = bind.mainGetLocalOption(key: _personDevicesKey);
      if (raw.isEmpty) return <String, List<String>>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, List<String>>{};
      return decoded.map((account, devices) {
        final ids = <String>[];
        if (devices is List) {
          for (final device in devices) {
            final id = device.toString().trim();
            if (id.isNotEmpty) ids.add(id);
          }
        }
        return MapEntry(account.toString().trim(), ids);
      });
    } catch (_) {
      return <String, List<String>>{};
    }
  }

  /// Records that [devicePeerId] belongs to the person account
  /// [accountId]. Safe to call repeatedly; never removes existing links.
  static Future<void> rememberPersonDevice(
    String accountId,
    String devicePeerId, {
    String displayName = '',
    String platform = '',
  }) async {
    final account = accountId.trim();
    final device = devicePeerId.trim();
    if (account.isEmpty ||
        device.isEmpty ||
        account == device ||
        isUuidLike(account)) {
      return;
    }
    final devices = Map<String, List<String>>.of(loadPersonDevices());
    final list = devices.putIfAbsent(account, () => <String>[]);
    if (list.contains(device)) return;
    list.add(device);
    await bind.mainSetLocalOption(
      key: _personDevicesKey,
      value: jsonEncode(devices),
    );
    revision.value++;
  }

  /// True for version-4 style UUIDs (reinstalled mobile apps get a new
  /// device UUID every install). These are device identities, never person
  /// account conversation keys.
  static bool isUuidLike(String value) {
    final input = value.trim();
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(input);
  }

  /// Returns [value] when it looks like a stable person-account conversation
  /// (non-empty, not a device UUID, not an IP endpoint), otherwise ''.
  static String stableAccountConversationId(String value) {
    final input = value.trim().replaceAll(' ', '');
    if (input.isEmpty ||
        isUuidLike(input) ||
        extractDirectEndpoint(input).isNotEmpty) {
      return '';
    }
    return input;
  }

  static Map<String, String> boundPhone() {
    try {
      final raw = bind.mainGetLocalOption(key: _boundPhoneKey);
      if (raw.isEmpty) return const <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, String>{};
      return Map<String, String>.from(
        decoded.map((key, value) => MapEntry('$key', '$value')),
      );
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// 记住已绑定的手机。
  static Future<void> rememberBoundPhone({
    required String peerId,
    required String displayName,
    String platform = '',
  }) async {
    final id = peerId.trim();
    if (id.isEmpty) return;
    final current = boundPhone();
    if (current['peerId'] == id) return;
    await bind.mainSetLocalOption(
      key: _boundPhoneKey,
      value: jsonEncode(<String, String>{
        'peerId': id,
        'displayName': displayName.trim(),
        'platform': platform,
        'boundAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    revision.value++;
  }

  /// 清除已绑定的手机与配套密钥。
  static Future<void> clearBoundPhone() async {
    await bind.mainSetLocalOption(key: _boundPhoneKey, value: '');
    await bind.mainSetLocalOption(key: _companionSecretKey, value: '');
    revision.value++;
  }

  /// companion 设备。
  static DirectPairing? companionDevice() {
    final values = _snapshot()
        .values
        .where((pairing) => pairing.companion)
        .toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values.isEmpty ? null : values.first;
  }

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// This device's own id (the "me" account). The person-devices map must
  /// never resolve another device to our own account: a stale mapping like
  /// {me: [otherDevice]} made every android/phone conversation show the local
  /// profile as the chat partner and rerouted incoming messages into the
  /// self conversation. Set once the local identity is known; null before
  /// that (no filtering, matching legacy behavior).
  static String? myId;

  /// True when [accountId] is this device's own account. Devices recorded
  /// under the local account are always a mistake (they are other people),
  /// so both the writer and the resolver must guard against it.
  static bool isSelfAccount(String accountId) {
    final mine = myId;
    if (mine == null || mine.isEmpty) return false;
    return accountId.trim().replaceAll(' ', '') == mine.trim();
  }

  static Map<String, DirectPairing>? _cache;

  static Map<String, DirectPairing> load() {
    final cached = _cache;
    if (cached != null) return Map<String, DirectPairing>.of(cached);
    try {
      final raw = bind.mainGetLocalOption(key: storageKey);
      if (raw.isEmpty) {
        _cache = <String, DirectPairing>{};
        return <String, DirectPairing>{};
      }
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
      _cache = pairings;
      return Map<String, DirectPairing>.of(pairings);
    } catch (_) {
      return <String, DirectPairing>{};
    }
  }

  /// Drop the cached pairing snapshot so the next read reloads from
  /// LocalConfig. Called when the Rust side self-heals an endpoint after a
  /// direct connection (e.g. a DHCP IP change or a randomized port refresh).
  static void invalidateCache() {
    _cache = null;
    revision.value++;
  }

  static Map<String, DirectPairing> _snapshot() {
    if (_cache == null) load();
    return _cache ?? const <String, DirectPairing>{};
  }

  static DirectPairing? find(String peerId) => _snapshot()[peerId.trim()];

  static DirectPairing? findForConversation(String value) {
    final pairings = _snapshot();
    final direct = _findValue(value.trim().replaceAll(' ', ''), pairings);
    if (direct != null) return direct;
    final devices = boundDevicesValue(value, pairings: pairings);
    return devices.isEmpty ? null : devices.first;
  }

  /// Find a pairing whose verified endpoint exactly matches [ipOrEndpoint].
  /// Used to merge IP-originated conversations into the paired device's chat.
  static DirectPairing? findByEndpoint(String ipOrEndpoint) {
    final target = extractDirectEndpoint(ipOrEndpoint).toLowerCase();
    if (target.isEmpty) return null;
    for (final pairing in _snapshot().values) {
      if (_matchesEndpoint(pairing, target)) return pairing;
    }
    return null;
  }

  static String canonicalConversationId(String value) =>
      canonicalConversationIdValue(value, pairings: _snapshot());

  static String canonicalConversationIdValue(
    String value, {
    required Map<String, DirectPairing> pairings,
  }) {
    final input = value.trim().replaceAll(' ', '');
    if (input.isEmpty) return '';
    final pairing = _findValue(input, pairings);
    if (pairing != null) return pairing.conversationId;
    final hasBoundDevices = pairings.values.any(
      (candidate) => candidate.accountId == input,
    );
    if (hasBoundDevices) return input;
    // LUODA: a device id recorded for a person account (person-devices map,
    // e.g. a phone or companion device bound to the PC account) resolves to
    // that account so every device conversation of one person merges into a
    // single chat row and the message source stays readable.
    for (final entry in loadPersonDevices().entries) {
      // Never resolve a device to our own account: {me: [device]} is stale
      // polluted data (a phone/emulator wrongly recorded under the local
      // account) and resolving it makes the chat show the local profile as
      // the partner while messages land in the self conversation.
      if (isSelfAccount(entry.key)) continue;
      if (entry.value.contains(input)) return entry.key;
    }
    return value.trim();
  }

  /// Returns the real device id for a conversation/contact id. When a list
  /// shows a stale id (e.g. a manually entered outdated id) but a direct
  /// pairing has already bridged that conversation to the real device, this
  /// returns the real device id for the id line under the display name.
  static String realDeviceId(String value) =>
      realDeviceIdValue(value, pairings: _snapshot());

  @visibleForTesting
  static String realDeviceIdValue(
    String value, {
    required Map<String, DirectPairing> pairings,
  }) {
    final input = value.trim().replaceAll(' ', '');
    if (input.isEmpty) return '';
    final direct = _findValue(input, pairings);
    if (direct != null && direct.peerId.isNotEmpty) return direct.peerId;
    final devices = boundDevicesValue(input, pairings: pairings);
    return devices.isEmpty ? input : devices.first.peerId;
  }

  static List<DirectPairing> boundDevices(String accountId) =>
      boundDevicesValue(accountId, pairings: _snapshot());

  static Set<String> conversationPeerIds(String value) =>
      conversationPeerIdsValue(value, pairings: _snapshot());

  @visibleForTesting
  static Set<String> conversationPeerIdsValue(
    String value, {
    required Map<String, DirectPairing> pairings,
  }) {
    final input = value.trim().replaceAll(' ', '');
    if (input.isEmpty) return const <String>{};
    final canonical = canonicalConversationIdValue(input, pairings: pairings);
    final ids = <String>{input, if (canonical.isNotEmpty) canonical};
    final direct = _findValue(input, pairings);
    if (direct != null) {
      ids.add(direct.peerId);
      if (direct.accountId.isNotEmpty) ids.add(direct.accountId);
    }
    for (final device in boundDevicesValue(canonical, pairings: pairings)) {
      ids.add(device.peerId);
      if (device.accountId.isNotEmpty) ids.add(device.accountId);
    }
    for (final device in loadPersonDevices()[canonical] ?? const <String>[]) {
      if (device.isNotEmpty) ids.add(device);
    }
    return ids;
  }

  @visibleForTesting
  static List<DirectPairing> boundDevicesValue(
    String accountId, {
    required Map<String, DirectPairing> pairings,
  }) {
    final normalized = accountId.trim();
    if (normalized.isEmpty) return const <DirectPairing>[];
    final devices = pairings.values
        .where((pairing) => pairing.accountId == normalized)
        .toList(growable: false);
    return devices..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<void> bindDevice({
    required String peerId,
    required String accountId,
  }) async {
    final current = find(peerId);
    final normalizedAccountId = accountId.trim();
    if (current == null || normalizedAccountId.isEmpty) return;
    await save(current.withAccountId(normalizedAccountId));
  }

  static Future<void> unbindDevice(String peerId) async {
    final current = find(peerId);
    if (current == null || current.accountId.isEmpty) return;
    await save(current.withAccountId(''));
  }

  /// Binds THIS device (my own peer id) to a person account id. Used when the
  /// phone scans a PC QR payload whose `acct` names the person's canonical id:
  /// the phone then advertises that same id in its own QR / contacts so any
  /// peer merges this phone into the same conversation as the PC.
  static Future<void> bindSelfDevice({required String accountId}) async {
    final normalized = accountId.trim();
    if (normalized.isEmpty) return;
    final myId = (await bind.mainGetMyId()).trim();
    if (myId.isEmpty || normalized == myId) return;
    final current = find(myId);
    if (current != null && current.accountId == normalized) return;
    final fingerprint = (await bind.mainGetFingerprint()).trim();
    if (!_validFingerprint(fingerprint)) return;
    final port = bind.mainGetOptionSync(key: 'direct-access-port').trim();
    final lan = _withPort(bind.mainGetOptionSync(key: 'lan-ip').trim(), port);
    final pub = bind.mainGetOptionSync(key: 'upnp-status') == 'ok'
        ? _withPort(bind.mainGetOptionSync(key: 'public-ip').trim(), port)
        : '';
    final pairing = DirectPairing(
      peerId: myId,
      displayName: current?.displayName ?? '',
      lanEndpoint: lan,
      publicEndpoint: pub,
      fingerprint: fingerprint,
      updatedAt: DateTime.now().toUtc(),
      companion: false,
      syncSecret: '',
      avatar: current?.avatar ?? '',
      ddnsEndpoint: current?.ddnsEndpoint ?? '',
      accountId: normalized,
      deviceName: current?.deviceName ?? '',
      platform: current?.platform ?? 'mobile',
    );
    await save(pairing);
  }

  /// The person id this device advertises in its pairing QR: the bound
  /// account id when set, otherwise its own peer id.
  static String selfAccountId(String myId) {
    final self = _snapshot()[myId.trim()];
    final bound = self?.accountId.trim() ?? '';
    return bound.isNotEmpty ? bound : myId.trim();
  }

  static DirectPairing? latest() {
    final values = _snapshot().values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values.isEmpty ? null : values.first;
  }

  static DirectPairing? latestCompanion() {
    final values = _snapshot()
        .values
        .where((pairing) => pairing.companion)
        .toList()
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
    _cache = Map<String, DirectPairing>.of(pairings);
    revision.value++;
    DotChatBackup.schedule();
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
    _cache = Map<String, DirectPairing>.of(pairings);
    revision.value++;
    DotChatBackup.schedule();
  }

  static List<Map<String, dynamic>> exportContacts() => _snapshot()
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
          ddnsEndpoint: incoming.ddnsEndpoint.isNotEmpty
              ? incoming.ddnsEndpoint
              : current?.ddnsEndpoint ?? '',
          accountId: incoming.accountId.isNotEmpty
              ? incoming.accountId
              : current?.accountId ?? '',
          deviceName: incoming.deviceName.isNotEmpty
              ? incoming.deviceName
              : current?.deviceName ?? '',
          platform: incoming.platform.isNotEmpty
              ? incoming.platform
              : current?.platform ?? '',
          endpointHistory: incoming.endpointHistory.isNotEmpty
              ? incoming.endpointHistory
              : current?.endpointHistory ?? const <DirectEndpointObservation>[],
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
    _cache = Map<String, DirectPairing>.of(pairings);
    revision.value++;
  }

  static bool acceptsCompanionSecret(String secret) {
    if (secret.isEmpty) return false;
    if (bind.mainGetLocalOption(key: _companionSecretKey) == secret) {
      return true;
    }
    return _snapshot().values.any(
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
      ddnsEndpoint: current.ddnsEndpoint,
      accountId: current.accountId,
      deviceName: current.deviceName,
      platform: current.platform,
      endpointHistory: current.endpointHistory,
    ));
  }

  /// After a direct connection reveals the real device id, try to migrate a
  /// stale pairing to the new id:
  /// 1. the conversation id (accountId) is itself an existing stale pairing;
  /// 2. any existing pairing has an identical fingerprint (same device, new id).
  /// Returns (migrated pairing, stale key to remove); (null, null) when no
  /// same-device pairing can be confirmed.
  @visibleForTesting
  static (DirectPairing?, String?) migrateStalePairingValue(
    Map<String, DirectPairing> pairings, {
    required String peerId,
    required String accountId,
    required String fingerprint,
  }) {
    final normalizedAccountId = accountId.trim();
    final normalizedFingerprint = _normalizeFingerprint(fingerprint);
    DirectPairing? stale;
    String? staleKey;
    if (normalizedAccountId.isNotEmpty &&
        normalizedAccountId != peerId &&
        pairings[normalizedAccountId] != null) {
      final candidate = pairings[normalizedAccountId]!;
      if (_sameDeviceForMerge(candidate, normalizedFingerprint)) {
        stale = candidate;
        staleKey = normalizedAccountId;
      }
    }
    if (stale == null && normalizedFingerprint.isNotEmpty) {
      for (final entry in pairings.entries) {
        if (entry.key == peerId) continue;
        final candidateFingerprint =
            _normalizeFingerprint(entry.value.fingerprint);
        if (candidateFingerprint.isNotEmpty &&
            candidateFingerprint == normalizedFingerprint) {
          stale = entry.value;
          staleKey = entry.key;
          break;
        }
      }
    }
    if (stale == null || staleKey == null) return (null, null);
    // Keep the user's manually set name/avatar/endpoint history, and keep the
    // old id as the conversation binding so existing chats keep working.
    return (
      DirectPairing(
        peerId: peerId,
        displayName: stale.displayName,
        lanEndpoint: stale.lanEndpoint,
        publicEndpoint: stale.publicEndpoint,
        fingerprint: fingerprint,
        updatedAt: DateTime.now().toUtc(),
        companion: stale.companion,
        syncSecret: stale.syncSecret,
        avatar: stale.avatar,
        ddnsEndpoint: stale.ddnsEndpoint,
        accountId: stale.accountId.isNotEmpty ? stale.accountId : staleKey,
        deviceName: stale.deviceName,
        platform: stale.platform,
        endpointHistory: stale.endpointHistory,
      ),
      staleKey,
    );
  }

  static bool _sameDeviceForMerge(
    DirectPairing candidate,
    String normalizedFingerprint,
  ) {
    return candidate.fingerprint.trim().isEmpty ||
        _normalizeFingerprint(candidate.fingerprint) == normalizedFingerprint;
  }

  static String _normalizeFingerprint(String value) =>
      value.toLowerCase().replaceAll(':', '').replaceAll(' ', '').trim();

  static Future<void> saveDiscovered({
    required String peerId,
    required String endpoint,
    required String fingerprint,
    required String displayName,
    required String avatar,
    String accountId = '',
    String deviceName = '',
    String platform = '',
    bool secure = false,
    String streamType = 'TCP',
  }) async {
    final normalizedEndpoint = extractDirectEndpoint(endpoint);
    if (peerId.isEmpty ||
        normalizedEndpoint.isEmpty ||
        !secure ||
        !_validFingerprint(fingerprint)) {
      return;
    }
    final pairings = load();
    final normalizedAccountId = accountId.trim();
    final (migrated, staleKey) = migrateStalePairingValue(
      pairings,
      peerId: peerId,
      accountId: normalizedAccountId,
      fingerprint: fingerprint,
    );
    final base = migrated ?? pairings[peerId];
    final isPrivate = isPrivateEndpoint(normalizedEndpoint);
    final pairing = DirectPairing(
      peerId: peerId,
      displayName:
          displayName.isEmpty ? base?.displayName ?? peerId : displayName,
      lanEndpoint: isPrivate ? normalizedEndpoint : base?.lanEndpoint ?? '',
      publicEndpoint:
          isPrivate ? base?.publicEndpoint ?? '' : normalizedEndpoint,
      fingerprint: fingerprint,
      updatedAt: DateTime.now().toUtc(),
      companion: base?.companion ?? false,
      syncSecret: base?.syncSecret ?? '',
      avatar: avatar.isEmpty ? base?.avatar ?? '' : avatar,
      ddnsEndpoint: base?.ddnsEndpoint ?? '',
      accountId: base?.accountId.isNotEmpty == true
          ? base!.accountId
          : normalizedAccountId,
      deviceName: deviceName.trim().isEmpty
          ? base?.deviceName ?? ''
          : deviceName.trim(),
      platform:
          platform.trim().isEmpty ? base?.platform ?? '' : platform.trim(),
      endpointHistory:
          base?.endpointHistory ?? const <DirectEndpointObservation>[],
    ).recordVerifiedEndpoint(
      endpoint: normalizedEndpoint,
      observedAt: DateTime.now().toUtc(),
      secure: true,
      streamType: streamType,
    );
    if (staleKey != null && staleKey != peerId) {
      pairings.remove(staleKey);
    }
    pairings[peerId] = pairing;
    await bind.mainSetLocalOption(
      key: storageKey,
      value: jsonEncode(
        pairings.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
    _cache = Map<String, DirectPairing>.of(pairings);
    revision.value++;
  }

  static String? resolveEndpoint(String value) {
    final input = value.trim().replaceAll(' ', '');
    final extracted = extractDirectEndpoint(input);
    if (extracted.isNotEmpty) return extracted;
    final pairings = _snapshot();
    final pairing = _findValue(input, pairings);
    if (pairing != null) return pairing.preferredEndpoint;
    final devices = boundDevicesValue(input, pairings: pairings);
    return devices.isEmpty ? null : devices.first.preferredEndpoint;
  }

  static String? resolveConnectionTarget(String value) {
    return resolveConnectionTargetValue(value, pairings: _snapshot());
  }

  @visibleForTesting
  static String? resolveConnectionTargetValue(
    String value, {
    required Map<String, DirectPairing> pairings,
  }) {
    final input = value.trim().replaceAll(' ', '');
    final endpoint = extractDirectEndpoint(input);
    var pairing = _findValue(input, pairings);
    if (pairing == null) {
      final devices = boundDevicesValue(input, pairings: pairings);
      if (devices.isNotEmpty) pairing = devices.first;
    }
    if (pairing != null) {
      return endpoint.isNotEmpty
          ? pairing.connectionTargetForEndpoint(endpoint)
          : pairing.connectionTarget;
    }
    if (endpoint.isNotEmpty) return endpoint;
    if (isDeviceId(input)) return input;
    // An account-bound person conversation may have device ids recorded from
    // an incoming chat client even before a full pairing exists; dial the
    // newest non-UUID device id so offline replies can still reconnect.
    final personDevices = loadPersonDevices()[
        canonicalConversationIdValue(input, pairings: pairings)];
    if (personDevices != null) {
      for (final device in personDevices.reversed) {
        if (!isUuidLike(device) && isDeviceId(device)) return device;
      }
    }
    return null;
  }

  static DirectPairing? _findValue(
    String value,
    Map<String, DirectPairing> pairings,
  ) {
    final direct = pairings[value];
    if (direct != null) return direct;
    final endpoint = extractDirectEndpoint(value).toLowerCase();
    if (endpoint.isNotEmpty) {
      for (final candidate in pairings.values) {
        if (_matchesEndpoint(candidate, endpoint)) return candidate;
      }
      return null;
    }
    final normalizedAlias = value.trim().toLowerCase();
    final aliases = pairings.values.where((candidate) {
      return candidate.displayName.trim().toLowerCase() == normalizedAlias ||
          candidate.deviceName.trim().toLowerCase() == normalizedAlias;
    }).toList(growable: false);
    return aliases.length == 1 ? aliases.single : null;
  }

  static bool _matchesEndpoint(DirectPairing pairing, String endpoint) {
    final normalized = endpoint.toLowerCase();
    return <String>{
      ...pairing.endpoints,
      ...pairing.endpointHistory.map((entry) => entry.endpoint),
    }.any((candidate) => candidate.toLowerCase() == normalized);
  }

  /// Legacy shared direct ports used by older builds (and copied configs).
  /// Current builds derive a machine-unique port in 20000..39999, so an
  /// endpoint on one of these ports is stale unless it was just re-verified.
  static bool isLegacySharedDirectEndpoint(String value) {
    final endpoint = extractDirectEndpoint(value);
    if (endpoint.isEmpty) return false;
    final portSeparator = endpoint.lastIndexOf(':');
    if (portSeparator <= 0) return false;
    final port = int.tryParse(endpoint.substring(portSeparator + 1));
    if (port == null) return false;
    return port == 20830 || (port >= 21118 && port <= 21128);
  }

  static String extractDirectEndpoint(String value) {
    final input = value.trim().replaceAll(' ', '');
    if (input.isEmpty) return '';
    final at = input.indexOf('@');
    final candidate =
        (at > 0 ? input.substring(at + 1) : input).split('?').first.trim();
    return isDirectEndpoint(candidate) ? candidate : '';
  }

  static bool isPrivateEndpoint(String value) {
    final host = _endpointHost(extractDirectEndpoint(value))?.toLowerCase();
    if (host == null || host.isEmpty) return false;
    if (host == 'localhost' ||
        host == '::1' ||
        host == '::' ||
        host.startsWith('127.') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.')) {
      return true;
    }
    final ipv4 = host.split('.');
    if (ipv4.length == 4) {
      final first = int.tryParse(ipv4[0]);
      final second = int.tryParse(ipv4[1]);
      if (first == 172 && second != null && second >= 16 && second <= 31) {
        return true;
      }
      if (first == 169 && second == 254) return true;
      return false;
    }
    return host.startsWith('fc') ||
        host.startsWith('fd') ||
        host.startsWith('fe8') ||
        host.startsWith('fe9') ||
        host.startsWith('fea') ||
        host.startsWith('feb');
  }

  /// Connection mode for a conversation/message:
  /// - 'id'      -> connected via rendezvous ID (relay or ID-based punch)
  /// - 'lan'     -> connected via a private/LAN IP endpoint
  /// - 'public'  -> connected via a public IP endpoint
  /// - 'ble'     -> connected via Bluetooth (reserved for future phone<->phone)
  static String classifyConnMode(String value) {
    final input = value.trim().replaceAll(' ', '').toLowerCase();
    if (input.startsWith('bt:')) return 'ble';
    if (input.contains('@')) return 'id';
    final endpoint = extractDirectEndpoint(value);
    if (endpoint.isEmpty) return 'id';
    return isPrivateEndpoint(endpoint) ? 'lan' : 'public';
  }

  /// Stable display endpoint stored with a message source. Direct IP routes
  /// keep host:port; ID routes keep only the dial ID; Bluetooth keeps its MAC.
  static String connEndpointOf(String value) {
    final input = value.trim().replaceAll(' ', '');
    if (input.isEmpty) return '';
    if (input.toLowerCase().startsWith('bt:')) {
      return input.substring(3).split('?').first.split('#').first.toUpperCase();
    }
    final endpoint = extractDirectEndpoint(input);
    if (endpoint.isNotEmpty && !input.contains('@')) return endpoint;
    final id = input
        .split('?')
        .first
        .split('#')
        .first
        .split('@')
        .first
        .split('/')
        .first
        .trim();
    return id;
  }

  /// Port of an "ip:port" conversation id (0 when it is not an endpoint).
  static int connPortOf(String value) {
    final endpoint = extractDirectEndpoint(value);
    final idx = endpoint.lastIndexOf(':');
    if (idx <= 0 || idx == endpoint.length - 1) return 0;
    return int.tryParse(endpoint.substring(idx + 1)) ?? 0;
  }

  /// Persists a Bluetooth peer so it appears as a contact and its messages
  /// are tagged with the 「蓝牙」 connection label. peerId is `bt:<mac>`.
  /// When [accountId] is known (the sender's person account revealed by its
  /// first chat envelope), it is stored so the Bluetooth row merges into the
  /// same contact as the device's network pairing instead of showing twice.
  static Future<DirectPairing> saveBluetoothPeer(
    String name,
    String mac, {
    String accountId = '',
  }) async {
    final normalizedMac = mac.trim().toUpperCase().replaceAll(':', '');
    if (normalizedMac.isEmpty) {
      throw const FormatException('Bluetooth MAC required');
    }
    final peerId = 'bt:$normalizedMac';
    final fingerprint = sha256.convert(utf8.encode(normalizedMac)).toString();
    final displayName = name.trim();
    final pairing = DirectPairing(
      peerId: peerId,
      displayName: displayName.isEmpty ? '蓝牙设备' : displayName,
      lanEndpoint: peerId,
      publicEndpoint: '',
      fingerprint: fingerprint,
      updatedAt: DateTime.now().toUtc(),
      accountId: accountId.trim(),
      deviceName: displayName,
      platform: 'Bluetooth',
    );
    await save(pairing);
    return pairing;
  }

  /// Normalizes a Bluetooth peer id (`bt:<mac>`) from either a peerId or a
  /// raw MAC, returning '' when the value is not a valid BT identifier.
  @visibleForTesting
  static String normalizeBluetoothPeerId(String macOrPeerId) {
    final upper =
        macOrPeerId.trim().toUpperCase().replaceAll(':', '').replaceAll(' ', '');
    if (upper.isEmpty) return '';
    final mac = upper.startsWith('BT') ? upper.substring(2) : upper;
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(mac)) return '';
    return 'bt:$mac';
  }

  /// Links a Bluetooth peer (`bt:<mac>`) to the person account it revealed in
  /// its first chat envelope (`sender_dial_id`). With the account stored, the
  /// pairing's conversationId becomes the person account, so contact lists
  /// merge the Bluetooth row with the same device's network pairing instead
  /// of showing the device twice. Self-heals on the next message; existing
  /// unlinked pairings stay separate until their peer sends again.
  static Future<void> linkBluetoothPeer(
    String macOrPeerId,
    String accountId, {
    String displayName = '',
  }) async {
    final peerId = normalizeBluetoothPeerId(macOrPeerId);
    if (peerId.isEmpty) return;
    final account = accountId.trim();
    if (account.isEmpty) return;
    final existing = find(peerId);
    if (existing == null) {
      // No pairing yet (the connect event was not persisted): create one from
      // the envelope's sender name so the row still appears and merges.
      if (displayName.trim().isEmpty) return;
      await saveBluetoothPeer(displayName.trim(), peerId.substring(3), accountId: account);
      return;
    }
    // Never overwrite a manually bound account with a different one.
    if (existing.accountId.trim().isNotEmpty &&
        existing.accountId.trim() != account) {
      return;
    }
    if (existing.accountId.trim() == account) return;
    await save(existing.withAccountId(account));
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
      final ownId = (await bind.mainGetMyId()).trim();
      final selfId = isSelfTargetValue(
        value,
        ownId: ownId,
        localAddresses: <String>[
          bind.mainGetOptionSync(key: 'lan-ip'),
          bind.mainGetOptionSync(key: 'public-ip'),
        ],
      );
      if (!selfId) return false;
      // When the ID matches our own but it is a person account (companion
      // sync) with linked devices, it is NOT self — it represents another
      // person's devices.  Block only when there are no linked devices,
      // which truly means "chatting with yourself".
      //
      // IMPORTANT: Exclude our own device from the bound list. If OPPO
      // phone's pairing has accountId == our own ID (due to companion sync),
      // boundDevices(ourId) returns both the phone AND ourselves — we must
      // count only non-self devices to decide.
      final input = value.trim().replaceAll(' ', '');
      final at = input.indexOf('@');
      final targetId = at > 0 ? input.substring(0, at) : input;
      final canonical = canonicalConversationId(targetId);
      final bound = boundDevices(canonical)
          .where((d) => d.peerId != ownId)
          .toList();
      if (bound.isNotEmpty) return false;
      final personDevices = loadPersonDevices()[canonical];
      if (personDevices != null && personDevices.isNotEmpty) return false;
      return true;
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
        'acct': selfAccountId(peerId),
        'ts': DateTime.now().toUtc().toIso8601String(),
      },
    ).toString();
  }

  /// 当面加好友的二维码：只携带 ID、显示名、账号，不含指纹/端点，
  /// 因为手机在移动网络下可能没有可直连的端点。扫码方只需拿到对方 ID
  /// 即可发起会话、加入最近联系人。
  static Future<String> buildFriendPayload() async {
    final peerId = (await bind.mainGetMyId()).trim();
    var displayName = '';
    try {
      final profile = Map<String, dynamic>.from(
        jsonDecode(bind.mainGetLocalOption(key: 'user_info')) as Map,
      );
      displayName =
          (profile['display_name'] ?? profile['name'] ?? '').toString().trim();
    } catch (_) {}
    return Uri(
      scheme: 'luoda',
      host: 'friend',
      queryParameters: <String, String>{
        'v': '1',
        'id': peerId,
        if (displayName.isNotEmpty) 'name': displayName,
        'acct': selfAccountId(peerId),
      },
    ).toString();
  }

  /// 解析「当面加好友」二维码，只需拿到非空 ID 即视为有效。
  static ({String peerId, String name, String accountId})?
      parseFriendPayload(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'luoda' ||
        uri.host.toLowerCase() != 'friend') {
      return null;
    }
    final id = (uri.queryParameters['id'] ?? '').trim();
    if (id.isEmpty) return null;
    return (
      peerId: id,
      name: (uri.queryParameters['name'] ?? '').trim(),
      accountId: (uri.queryParameters['acct'] ?? '').trim(),
    );
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
      accountId: (uri.queryParameters['acct'] ?? '').trim(),
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
