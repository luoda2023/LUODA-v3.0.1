import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart';
import '../direct_pairing.dart';

String directConnectionRouteLabel(String conversationId) {
  final pairing = DirectPairingStore.findForConversation(conversationId);
  if (pairing == null || pairing.currentVerifiedEndpoint.isEmpty) {
    return translate('No verified direct route');
  }
  final observation =
      pairing.endpointHistory.isEmpty ? null : pairing.endpointHistory.last;
  if (observation?.secure == true) {
    return '${translate('P2P direct')} \u00b7 '
        '${pairing.currentVerifiedEndpoint} \u00b7 ${translate('Encrypted TCP')}';
  }
  return '${translate('P2P endpoint')} \u00b7 '
      '${pairing.currentVerifiedEndpoint} \u00b7 '
      '${translate('Awaiting identity verification')}';
}

Future<void> showDirectConnectionDetails(
  BuildContext context, {
  required String conversationId,
  String initialAlias = '',
  Future<void> Function(String alias)? onRename,
}) async {
  final normalized = conversationId.trim();
  if (normalized.isEmpty) return;
  final content = _DirectConnectionDetails(
    conversationId: normalized,
    initialAlias: initialAlias,
    onRename: onRename,
  );
  if (isMobile) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => FractionallySizedBox(heightFactor: 0.88, child: content),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: ConstrainedBox(
        // 桌面端弹窗加宽 1/2（620 → 930）：详情卡片横向铺开，
        // ID / 指纹 / IP 历史等字段不再拥挤换行，避免“太扁”。
        constraints: const BoxConstraints(maxWidth: 930, maxHeight: 760),
        child: content,
      ),
    ),
  );
}

class _DirectConnectionDetails extends StatelessWidget {
  const _DirectConnectionDetails({
    required this.conversationId,
    required this.initialAlias,
    required this.onRename,
  });

  final String conversationId;
  final String initialAlias;
  final Future<void> Function(String alias)? onRename;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DirectPairingStore.revision,
      builder: (context, _) {
        final canonical =
            DirectPairingStore.canonicalConversationId(conversationId);
        final bound = DirectPairingStore.boundDevices(canonical);
        final direct = DirectPairingStore.findForConversation(conversationId);
        final devices = bound.isNotEmpty
            ? bound
            : direct == null
                ? const <DirectPairing>[]
                : <DirectPairing>[direct];
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Column(
          children: <Widget>[
            _Header(
              accountId: canonical,
              routeLabel: directConnectionRouteLabel(conversationId),
              initialAlias: initialAlias,
              onRename: onRename,
            ),
            Expanded(
              child: devices.isEmpty
                  ? _EmptyState()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
                          child: Row(
                            children: <Widget>[
                              const Icon(
                                Icons.devices_rounded,
                                size: 18,
                                color: MyTheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  translate('Linked devices'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                '${devices.length}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.55),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        for (final pairing in devices)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _DeviceCard(
                              pairing: pairing,
                              accountId: canonical,
                            ),
                          ),
                      ],
                    ),
            ),
            if (dark) const SizedBox(height: 4),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.devices_other_rounded,
            size: 44,
            color: theme.colorScheme.onSurface.withOpacity(0.22),
          ),
          const SizedBox(height: 10),
          Text(
            translate('No verified device'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.accountId,
    required this.routeLabel,
    required this.initialAlias,
    required this.onRename,
  });

  final String accountId;
  final String routeLabel;
  final String initialAlias;
  final Future<void> Function(String alias)? onRename;

  @override
  Widget build(BuildContext context) {
    final secure = routeLabel.contains(translate('Encrypted TCP'));
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0FAF57), Color(0xFF07C160)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  size: 24,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      translate('P2P connection details'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      translate('Connection & identity'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: translate('Close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ID card: white rounded card floating on the gradient.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: MyTheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'ID',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectableText(
                    accountId,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: translate('Copy'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: accountId));
                    showToast(translate('Copied'));
                  },
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: MyTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Route status pill.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  secure ? Icons.lock_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: Colors.white.withOpacity(0.9),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    routeLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withOpacity(0.92),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (onRename != null) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Text(
                  '${translate('Alias')}:',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.75),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    initialAlias.isEmpty
                        ? translate('Not available')
                        : initialAlias,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: translate('Rename'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _rename(context),
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: initialAlias);
    final alias = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(translate('Alias')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: InputDecoration(hintText: translate('input note here')),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(translate('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(translate('Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (alias == null) return;
    await onRename?.call(alias.trim());
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.pairing, required this.accountId});

  final DirectPairing pairing;
  final String accountId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final title = pairing.deviceName.isNotEmpty
        ? pairing.deviceName
        : pairing.displayName.isNotEmpty
            ? pairing.displayName
            : pairing.peerId;
    final publicHistory = pairing.endpointHistory
        .where(
          (entry) => !DirectPairingStore.isPrivateEndpoint(entry.endpoint),
        )
        .toList(growable: false);
    final muted = dark ? MyTheme.mutedDark : MyTheme.mutedLight;
    return Container(
      decoration: BoxDecoration(
        color: dark ? MyTheme.surfaceDark : MyTheme.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.25 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MyTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _platformIcon(pairing.platform),
                    size: 20,
                    color: MyTheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        pairing.platform.isEmpty
                            ? pairing.peerId
                            : '${pairing.platform} \u00b7 ${pairing.peerId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (pairing.accountId.isEmpty)
                  TextButton.icon(
                    onPressed: () => _bind(context),
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: Text(translate('Bind device')),
                  )
                else
                  IconButton(
                    tooltip: translate('Unbind device'),
                    onPressed: () => _unbind(context),
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Column(
              children: <Widget>[
                _DetailRow(
                    label: translate('Device ID'), value: pairing.peerId),
                _DetailRow(
                  label: translate('Fingerprint'),
                  value: _fingerprintSuffix(pairing.fingerprint),
                ),
                _DetailRow(
                  label: translate('Current IP'),
                  value: pairing.currentVerifiedEndpoint.isEmpty
                      ? translate('Not available')
                      : pairing.currentVerifiedEndpoint,
                ),
                _DetailRow(
                  label: translate('Last active'),
                  value: _formatTime(pairing.updatedAt),
                ),
                _DetailRow(
                  label: translate('IP history count'),
                  value: publicHistory.length.toString(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  translate('Verified public IP history'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 4),
                if (publicHistory.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      translate('No verified public IP history'),
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  )
                else
                  ...publicHistory.reversed.map(
                    (entry) => _HistoryRow(observation: entry),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _bind(BuildContext context) async {
    final controller = TextEditingController(
      text: accountId == pairing.peerId ? '' : accountId,
    );
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(translate('Bind device')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: InputDecoration(labelText: translate('Chat ID')),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(translate('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(translate('Bind')),
          ),
        ],
      ),
    );
    controller.dispose();
    final normalized = selected?.trim() ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{3,64}$').hasMatch(normalized)) return;
    await DirectPairingStore.bindDevice(
      peerId: pairing.peerId,
      accountId: normalized,
    );
  }

  Future<void> _unbind(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(translate('Unbind device')),
        content: Text(translate(
          'Existing messages and IP history will be kept. Future messages from this device will use a separate conversation.',
        )),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(translate('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(translate('Unbind')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DirectPairingStore.unbindDevice(pairing.peerId);
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? MyTheme.mutedDark
        : MyTheme.mutedLight;
    final valueText = SelectableText(
      value,
      style: TextStyle(
        fontSize: 12.5,
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w500,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: constraints.maxWidth < 300
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: TextStyle(fontSize: 12.5, color: muted)),
                  const SizedBox(height: 3),
                  valueText,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 104,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ),
                  Expanded(child: valueText),
                ],
              ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.observation});

  final DirectEndpointObservation observation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? MyTheme.mutedDark
        : MyTheme.mutedLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: MyTheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.public_rounded,
              size: 14,
              color: MyTheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SelectableText(
                  observation.endpoint,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${_formatTime(observation.firstSeenAt)} - '
                  '${_formatTime(observation.lastSeenAt)} \u00b7 '
                  '${observation.connectionCount} ${translate('connections')}',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _platformIcon(String platform) {
  final value = platform.toLowerCase();
  if (value.contains('android') || value.contains('ios')) {
    return Icons.smartphone_rounded;
  }
  return Icons.computer_rounded;
}

String _fingerprintSuffix(String fingerprint) {
  final normalized = fingerprint.replaceAll(':', '').replaceAll(' ', '');
  if (normalized.isEmpty) return translate('Not available');
  final suffix = normalized.length <= 12
      ? normalized
      : normalized.substring(normalized.length - 12);
  return '...${suffix.toUpperCase()}';
}

String _formatTime(DateTime value) {
  final local = value.toLocal().toString();
  return local.length > 19 ? local.substring(0, 19) : local;
}
