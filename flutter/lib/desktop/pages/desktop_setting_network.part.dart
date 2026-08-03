part of 'desktop_setting_page.dart';

class _Network extends StatefulWidget {
  const _Network({Key? key}) : super(key: key);

  @override
  State<_Network> createState() => _NetworkState();
}

class _NetworkState extends State<_Network> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool locked = !isWeb && bind.mainIsInstalled();
  bool _showAdvancedNetworkSettings = false;

  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(controller: scrollController, children: [
      _lock(locked, 'Unlock Network Settings', () {
        locked = false;
        setState(() => {});
      }),
      preventMouseKeyBuilder(
        block: locked,
        child: Column(children: [
          directMessaging(context),
          _advancedNetworkToggle(context),
          if (_showAdvancedNetworkSettings) network(context),
        ]),
      ),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget directMessaging(BuildContext context) {
    final access = DirectChatAccessController.instance..load();
    final alwaysOn = access.alwaysOn;
    final trustedOnly = access.audience == DirectChatAudience.friendsOnly;
    final autoReconnect = access.autoReconnect;

    Future<void> update(Future<void> operation) async {
      await operation;
      if (mounted) setState(() {});
    }

    Widget option({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) {
      return ListTile(
        minLeadingWidth: 0,
        horizontalTitleGap: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: _accentColor),
        title: Text(translate(title)),
        subtitle: Text(
          translate(subtitle),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Switch(value: value, onChanged: onChanged),
      );
    }

    return _Card(
      title: 'Direct messaging',
      children: <Widget>[
        option(
          icon: Icons.mark_chat_unread_outlined,
          title: 'Allow always-on direct messages',
          subtitle:
              'Keep the local direct port ready so approved contacts can deliver messages while no remote session is active.',
          value: alwaysOn,
          onChanged:
              locked ? null : (value) => update(access.setAlwaysOn(value)),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        option(
          icon: Icons.verified_user_outlined,
          title: 'Only trusted contacts can message me',
          subtitle:
              'Unknown peers must be approved before they can establish a persistent chat connection.',
          value: trustedOnly,
          onChanged: locked || !alwaysOn
              ? null
              : (value) => update(
                    access.setAudience(
                      value
                          ? DirectChatAudience.friendsOnly
                          : DirectChatAudience.everyone,
                    ),
                  ),
        ),
        if (_showAdvancedNetworkSettings)
          const Divider(height: 1, indent: 16, endIndent: 16),
        if (_showAdvancedNetworkSettings)
          option(
            icon: Icons.sync_rounded,
            title: 'Reconnect trusted contacts automatically',
            subtitle:
                'Reconnect to the saved IP address when the network becomes available again.',
            value: autoReconnect,
            onChanged: locked || !alwaysOn
                ? null
                : (value) => update(access.setAutoReconnect(value)),
          ),
        if (_showAdvancedNetworkSettings)
          const Divider(height: 1, indent: 16, endIndent: 16),
        if (_showAdvancedNetworkSettings)
          ListTile(
            minLeadingWidth: 0,
            horizontalTitleGap: 12,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(
              Icons.manage_accounts_outlined,
              color: _accentColor,
            ),
            title: Text(translate('Contact message permissions')),
            subtitle: Text(
              translate('Allow or reject always-on messages for each contact.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap:
                alwaysOn ? () => _showContactMessagePermissions(context) : null,
          ),
      ],
    );
  }

  Widget _advancedNetworkToggle(BuildContext context) {
    return _Card(
      title: 'Advanced settings',
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.tune_rounded, color: _accentColor),
          title: Text(translate('Network')),
          trailing: Icon(
            _showAdvancedNetworkSettings
                ? Icons.expand_less_rounded
                : Icons.expand_more_rounded,
          ),
          onTap: () => setState(
            () => _showAdvancedNetworkSettings = !_showAdvancedNetworkSettings,
          ),
        ),
      ],
    );
  }

  Future<void> _showContactMessagePermissions(BuildContext context) async {
    final access = DirectChatAccessController.instance..load();
    final policies = <String, String>{...access.peerPolicies};
    final peersById = <String, Peer>{};
    for (final peer in <Peer>[
      ...gFFI.recentPeersModel.peers,
      ...gFFI.favoritePeersModel.peers,
      ...gFFI.abModel.peersModel.peers,
      ...gFFI.groupModel.peersModel.peers,
    ]) {
      peersById[peer.id] = peer;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(translate('Contact message permissions')),
          content: SizedBox(
            width: 480,
            height: 420,
            child: peersById.isEmpty
                ? Center(
                    child: Text(
                      translate(
                        'A contact will appear here after the first direct connection.',
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: peersById.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final peer = peersById.values.elementAt(index);
                      final name = peer.alias.trim().isNotEmpty
                          ? peer.alias.trim()
                          : peer.hostname.trim().isNotEmpty
                              ? peer.hostname.trim()
                              : peer.username.trim().isNotEmpty
                                  ? peer.username.trim()
                                  : peer.id;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: str2color(name),
                          child: Text(
                            name.characters.first,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(peer.id),
                        trailing: DropdownButton<String>(
                          value: policies[peer.id] ?? 'ask',
                          underline: const SizedBox.shrink(),
                          items: <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'allow',
                              child: Text(translate('Allow')),
                            ),
                            DropdownMenuItem(
                              value: 'ask',
                              child: Text(translate('Ask every time')),
                            ),
                            DropdownMenuItem(
                              value: 'deny',
                              child: Text(translate('Reject')),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => policies[peer.id] = value);
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(translate('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(translate('Save')),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      for (final entry in policies.entries) {
        await access.setPeerPolicy(entry.key, entry.value);
      }
    }
  }

  Widget network(BuildContext context) {
    final serverlessDirectOnly = bind.mainGetOptionSync(
          key: kOptionServerlessDirectOnly,
        ) ==
        'Y';
    final hideServer =
        bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
    final hideProxy =
        isWeb || bind.mainGetBuildinOption(key: kOptionHideProxySetting) == 'Y';
    final hideWebSocket = isWeb ||
        bind.mainGetBuildinOption(key: kOptionHideWebSocketSetting) == 'Y';

    // Helper function to create network setting ListTiles
    Widget listTile({
      required IconData icon,
      required String title,
      String? subtitle,
      VoidCallback? onTap,
      Widget? trailing,
      bool showTooltip = false,
      String tooltipMessage = '',
    }) {
      final titleWidget = showTooltip
          ? Row(
              children: [
                Tooltip(
                  waitDuration: Duration(milliseconds: 1000),
                  message: translate(tooltipMessage),
                  child: Row(
                    children: [
                      Text(
                        translate(title),
                        style: TextStyle(fontSize: _kContentFontSize),
                      ),
                      SizedBox(width: 5),
                      Icon(
                        Icons.help_outline,
                        size: 14,
                        color: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Text(
              translate(title),
              style: TextStyle(fontSize: _kContentFontSize),
            );

      return ListTile(
        leading: Icon(icon, color: _accentColor),
        title: titleWidget,
        subtitle: subtitle == null ? null : Text(translate(subtitle)),
        enabled: !locked,
        onTap: onTap,
        trailing: trailing,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        minLeadingWidth: 0,
        horizontalTitleGap: 10,
      );
    }

    Widget switchWidget(IconData icon, String title, String tooltipMessage,
            String optionKey) =>
        listTile(
          icon: icon,
          title: title,
          showTooltip: true,
          tooltipMessage: tooltipMessage,
          trailing: Switch(
            value: mainGetBoolOptionSync(optionKey),
            onChanged: locked || isOptionFixed(optionKey)
                ? null
                : (value) {
                    mainSetBoolOption(optionKey, value);
                    setState(() {});
                  },
          ),
        );

    final outgoingOnly = bind.isOutgoingOnly();

    final divider = const Divider(height: 1, indent: 16, endIndent: 16);
    return _Card(
      title: 'Network',
      children: [
        Container(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              listTile(
                icon: Icons.shield_outlined,
                title: 'Serverless direct mode',
                subtitle:
                    'When enabled, device ID connections are disabled; IP, QR, and LAN connections stay direct. When disabled, device IDs try direct first and use encrypted TCP relay only if needed.',
                trailing: Switch(
                  value: serverlessDirectOnly,
                  onChanged:
                      locked || isOptionFixed(kOptionServerlessDirectOnly)
                          ? null
                          : (value) async {
                              await bind.mainSetOption(
                                key: kOptionServerlessDirectOnly,
                                value: value ? 'Y' : 'N',
                              );
                              if (mounted) setState(() {});
                            },
                ),
              ),
              if (!serverlessDirectOnly &&
                  (!hideServer || !hideProxy || !hideWebSocket))
                divider,
              if (!serverlessDirectOnly && !hideServer)
                listTile(
                  icon: Icons.dns_outlined,
                  title: 'ID/Relay Server',
                  onTap: () => showServerSettings(gFFI.dialogManager, setState),
                ),
              if (!serverlessDirectOnly && !hideProxy && !hideServer) divider,
              if (!serverlessDirectOnly && !hideProxy)
                listTile(
                  icon: Icons.network_ping_outlined,
                  title: 'Socks5/Http(s) Proxy',
                  onTap: changeSocks5Proxy,
                ),
              if (!serverlessDirectOnly &&
                  !hideWebSocket &&
                  (!hideServer || !hideProxy))
                divider,
              if (!serverlessDirectOnly && !hideWebSocket)
                switchWidget(
                    Icons.web_asset_outlined,
                    'Use WebSocket',
                    '${translate('websocket_tip')}\n\n${translate('server-oss-not-support-tip')}',
                    kOptionAllowWebSocket),
              if (!serverlessDirectOnly && !isWeb)
                futureBuilder(
                  future: bind.mainIsUsingPublicServer(),
                  hasData: (isUsingPublicServer) {
                    if (isUsingPublicServer) {
                      return Offstage();
                    } else {
                      return Column(
                        children: [
                          if (!hideServer || !hideProxy || !hideWebSocket)
                            divider,
                          switchWidget(
                              Icons.no_encryption_outlined,
                              'Allow insecure TLS fallback',
                              'allow-insecure-tls-fallback-tip',
                              kOptionAllowInsecureTLSFallback),
                          if (!outgoingOnly) divider,
                          if (!outgoingOnly)
                            listTile(
                              icon: Icons.lan_outlined,
                              title: 'Disable UDP',
                              showTooltip: true,
                              tooltipMessage:
                                  '${translate('disable-udp-tip')}\n\n${translate('server-oss-not-support-tip')}',
                              trailing: Switch(
                                value: bind.mainGetOptionSync(
                                        key: kOptionDisableUdp) ==
                                    'Y',
                                onChanged:
                                    locked || isOptionFixed(kOptionDisableUdp)
                                        ? null
                                        : (value) async {
                                            await bind.mainSetOption(
                                                key: kOptionDisableUdp,
                                                value: value ? 'Y' : 'N');
                                            setState(() {});
                                          },
                              ),
                            ),
                        ],
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
