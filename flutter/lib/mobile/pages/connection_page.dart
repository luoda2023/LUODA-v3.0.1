import 'dart:async';

import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common/formatter/id_formatter.dart';
import 'package:luoda_flutter/common/widgets/connection_page_title.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:luoda_flutter/models/peer_model.dart';

import '../../common.dart';
import '../../common/direct_chat_policy.dart';
import '../../common/direct_pairing.dart';
import '../../common/direct_viewer_invite.dart';
import '../../common/widgets/join_viewer_page.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../consts.dart';
import '../../models/chat_model.dart';
import '../../models/model.dart';
import '../../models/peer_tab_model.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';
import 'bt_chat_page.dart';
import 'scan_page.dart';

/// Connection page for connecting to a remote peer.
enum _ConnectionMode { chat, remote, viewer, bluetooth }

/// 一个人组：可能包含同一人的多个设备（PC、手机等）。
class _PersonContact {
  _PersonContact(this.key);

  /// 会话标识：有账号绑定时为 accountId，否则为设备 ID。
  final String key;
  final List<DirectPairing> devices = <DirectPairing>[];

  DirectPairing? deviceByFingerprint(DirectPairing candidate) {
    final fp = _normalizeContactFingerprint(candidate.fingerprint);
    if (fp.isEmpty) return null;
    for (final device in devices) {
      if (_normalizeContactFingerprint(device.fingerprint) == fp) {
        return device;
      }
    }
    return null;
  }

  void replaceDevice(DirectPairing previous, DirectPairing replacement) {
    final index = devices.indexOf(previous);
    if (index >= 0) devices[index] = replacement;
  }

  DirectPairing get latest {
    devices.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return devices.first;
  }

  bool get isMobile => devices.any((device) {
        final platform = device.platform.toLowerCase();
        return platform.contains('android') ||
            platform.contains('ios') ||
            platform.contains('phone');
      });

  bool get isDesktop => devices.any((device) {
        final platform = device.platform.toLowerCase();
        return platform.isNotEmpty &&
            !platform.contains('android') &&
            !platform.contains('ios') &&
            !platform.contains('phone');
      });

  /// Secondary line for the contacts list: the dialable ID (account id when
  /// bound, otherwise the device id) plus a reachable IP endpoint. The OS is
  /// deliberately NOT shown here — it is rendered as a tiny badge on the
  /// avatar's top-right corner instead.
  String get idIpSummary {
    final parts = <String>[];
    // ID: prefer the account id, fall back to the device id.
    final account = latest.accountId.trim();
    parts.add(account.isNotEmpty ? account : latest.peerId.trim());
    // IP endpoint: prefer the current verified LAN endpoint, then public
    // endpoint, then any observed endpoint.
    String? ip;
    for (final device in devices) {
      final lan = device.lanEndpoint.trim();
      if (lan.isNotEmpty && lan != '0.0.0.0:0') {
        ip = lan.split(':').first;
        break;
      }
    }
    ip ??= latest.publicEndpoint.trim().split(':').first;
    if (ip.isEmpty || ip == '0.0.0.0') {
      for (final device in devices) {
        for (final obs in device.endpointHistory) {
          final candidate = obs.endpoint.trim();
          if (candidate.isNotEmpty &&
              !candidate.startsWith('0.0.0.0') &&
              !candidate.contains(':')) {
            ip = candidate;
            break;
          }
        }
        if (ip != null) break;
      }
    }
    if (ip != null && ip.isNotEmpty) parts.add(ip);
    return parts.join(' · ');
  }
}

String _normalizeContactFingerprint(String value) =>
    value.toLowerCase().replaceAll(':', '').replaceAll(' ', '').trim();

bool _isMobilePairingPlatform(String platform) {
  final p = platform.toLowerCase();
  return p.contains('android') || p.contains('ios') || p.contains('phone');
}

/// 规范化手机配对签名 ID：将压缩后的设备名做平滑处理
String? _normalizeMobilePairingSignature(String value) {
  final v = value.trim().toLowerCase();
  if (v.isEmpty) return null;
  if (v == 'android' || v == 'localhost' || v == 'unknown' || v == 'phone') {
    return null;
  }
  final sig = v.replaceAll(RegExp(r'[\s:._\-]+'), '');
  return sig.length < 4 ? null : sig;
}

String? _mobilePairingSignature(DirectPairing pairing) {
  if (!_isMobilePairingPlatform(pairing.platform)) return null;
  return _normalizeMobilePairingSignature(pairing.deviceName);
}

class _MobileContactGroupHeader {
  const _MobileContactGroupHeader(this.label, this.count);

  final String label;
  final int count;
}

class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, this.appBarActions = const <Widget>[]})
      : super(key: key);

  @override
  final icon = const Icon(Icons.contacts_outlined);

  @override
  final title = translate("Contacts");

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => ConnectionPageState();
}

/// State for the connection page.
class ConnectionPageState extends State<ConnectionPage>
    with WidgetsBindingObserver {
  _ConnectionMode _connectionMode = _ConnectionMode.chat;
  bool _openingViewerInvite = false;

  /// Controller for the id input bar.
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  final AllPeersLoader _allPeersLoader = AllPeersLoader();
  final TextEditingController _contactSearchController =
      TextEditingController();

  StreamSubscription? _uniLinksSubscription;
  Timer? _chatKeepAliveTimer;

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];
  String _contactQuery = '';
  // Rendezvous-driven online states so contacts show online without needing
  // an active chat connection (matches the messages page behaviour).
  final Map<String, bool> _onlineByPeer = <String, bool>{};
  Timer? _onlineQueryTimer;
  static const String _onlineHandlerName = 'contacts_online';

  ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kLocalProfileOnly) {
      gFFI.peerTabModel.setCurrentTab(PeerTabIndex.ab.index);
    }
    // 发送消息若无可用连接时，由本页提供“建立直连会话”的能力，确保消息尽快送达。
    // 保活 / 空闲自动重连：按固定间隔对最近活跃会话恢复 isChat 连接以收发消息。
    _chatKeepAliveTimer = Timer.periodic(
      ChatModel.kChatReconnectInterval,
      (_) => unawaited(_maintainChatKeepAlive()),
    );
    platformFFI.registerEventHandler(
      'callback_query_onlines',
      _onlineHandlerName,
      (evt) async {
        final onlines = (evt['onlines'] as String? ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toSet();
        final offlines = (evt['offlines'] as String? ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toSet();
        if (onlines.isEmpty && offlines.isEmpty) return;
        var changed = false;
        for (final id in onlines) {
          if (_onlineByPeer[id] != true) {
            _onlineByPeer[id] = true;
            changed = true;
          }
        }
        for (final id in offlines) {
          if (_onlineByPeer[id] != false) {
            _onlineByPeer[id] = false;
            changed = true;
          }
        }
        if (changed && mounted) setState(() {});
      },
      replace: true,
    );
    _onlineQueryTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _queryOnlineStates());
    _queryOnlineStates();
    pendingViewerInvite.addListener(_handlePendingViewerInvite);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingViewerInvite();
    });
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 600 ? 24.0 : 12.0;
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: <Widget>[
            if (!bind.isCustomClient() && !isIOS)
              SliverToBoxAdapter(
                child: Obx(() => _buildUpdateUI(stateGlobal.updateUrl.value)),
              ),
            // 顶部：左上角在线标志 + 功能卡片，与联系人列表同宽（全宽铺开）。
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                6,
                horizontalPadding,
                4,
              ),
              sliver: SliverToBoxAdapter(
                child: _buildConnectionToolsPanel(),
              ),
            ),
            // 联系人列表：全宽铺开，背景与点聊列表完全一致。
            SliverToBoxAdapter(child: _buildPairedContacts()),
          ],
        );
      },
    );
  }

  /// 联系人页顶部：四个功能卡片（与会议页动作卡片一致），搜索图标与在线
  /// 状态都已上移至 AppBar（与点聊页一致），此处不再渲染顶栏。
  Widget _buildConnectionToolsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildQuickActions(),
      ],
    );
  }

  Widget _buildQuickActions() {
    final actions = <(IconData, String, String, VoidCallback)>[
      (
        Icons.qr_code_scanner_rounded,
        'Pair phone',
        'Scan & bind',
        _openPairPhone,
      ),
      (
        Icons.bluetooth_searching_rounded,
        'Bluetooth scan',
        'Nearby devices',
        _openBluetooth,
      ),
      (
        Icons.tune_rounded,
        'Connection',
        'ID / IP / port',
        _openConnectionAndIdentity,
      ),
      (
        Icons.devices_rounded,
        'Access history',
        'Recent devices',
        _openDeviceHistory,
      ),
    ];
    // 与会议页动作卡片同款：4 个卡片同一行排布，文字小一号。
    // 使用 LayoutBuilder 精确分配宽度，确保任意屏幕宽度下都不溢出。
    return LayoutBuilder(
      builder: (context, constraints) {
        // 超窄屏或大字体时退回 2 行 × 2 列，避免卡片挤压变形。
        // 手机页左右各 12dp 内边距，360dp 屏实际可用 336dp，因此阈值取 300。
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final wide = constraints.maxWidth >= 300 && textScale <= 1.6;
        final rowCount = wide ? 4 : 2;
        final rows = <Widget>[];
        for (var start = 0; start < actions.length; start += rowCount) {
          final end = (start + rowCount).clamp(0, actions.length);
          final gap = wide ? 8.0 : 12.0;
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (var index = start; index < end; index++) ...<Widget>[
                  if (index > start) SizedBox(width: gap),
                  Expanded(
                    child: _buildQuickAction(
                      icon: actions[index].$1,
                      title: actions[index].$2,
                      subtitle: actions[index].$3,
                      onTap: actions[index].$4,
                    ),
                  ),
                ],
              ],
            ),
          );
          if (end < actions.length) {
            rows.add(const SizedBox(height: 12));
          }
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: translate(title),
      child: Material(
        color: dark ? MyTheme.surfaceDark : MyTheme.surfaceLight,
        elevation: 0.5,
        // 阴影染背景色调（taste-skill 4.4）：纯黑投影在浅色底上显脏，
        // 用品牌绿的深色调替代，柔和且与主色一致；再加一道细描边分组。
        shadowColor: const Color(0xFF07C160).withOpacity(0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color:
                dark ? Colors.white.withOpacity(0.06) : const Color(0xFFEFEFEF),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            // 与会议页动作卡片同款，但文字小一号，保证 4 个并排不溢出。
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF07C160).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 19, color: const Color(0xFF07C160)),
                ),
                const SizedBox(height: 6),
                Text(
                  translate(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  translate(subtitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 悬浮搜索框：顶部搜索输入，下方实时过滤联系人（复用主列表的行渲染）。
  Future<void> openContactSearch() async {
    final myId = gFFI.serverModel.serverId.value.text.trim();
    final access = DirectChatAccessController.instance..load();
    final controller = TextEditingController(text: _contactQuery);
    final query = ValueNotifier<String>(_contactQuery);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: dark ? MyTheme.canvasDark : MyTheme.canvasLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        Widget searchField() {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: (value) => query.value = value,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: translate('Search'),
                prefixIcon: const Icon(Icons.search_rounded, size: 21),
                prefixIconConstraints: const BoxConstraints(minWidth: 44),
                suffixIcon: query.value.isEmpty
                    ? null
                    : IconButton(
                        tooltip: translate('Clear'),
                        onPressed: () {
                          controller.clear();
                          query.value = '';
                        },
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                filled: true,
                fillColor: dark ? MyTheme.surfaceDark : MyTheme.surfaceLight,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: dark ? MyTheme.borderDark : MyTheme.borderLight,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: MyTheme.primary, width: 1.5),
                ),
              ),
            ),
          );
        }

        return ValueListenableBuilder<String>(
          valueListenable: query,
          builder: (sheetContext, value, _) {
            final q = value.trim().toLowerCase();
            final allGroups = _buildContactGroups(myId);
            final groups = q.isEmpty
                ? allGroups
                : allGroups
                    .where((group) => _matchesContactQuery(group, q))
                    .toList(growable: false);
            final friends = groups
                .where((group) => access.isFriend(group.key))
                .toList(growable: false);
            final strangers = groups
                .where((group) => !access.isFriend(group.key))
                .toList(growable: false);
            final rows = <Object>[
              if (friends.isNotEmpty) ...<Object>[
                _MobileContactGroupHeader('Friends', friends.length),
                ...friends,
              ],
              if (strangers.isNotEmpty) ...<Object>[
                _MobileContactGroupHeader('Strangers', strangers.length),
                ...strangers,
              ],
            ];
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.85,
                child: Column(
                  children: <Widget>[
                    searchField(),
                    Expanded(
                      child: rows.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Text(
                                  translate('No results'),
                                  style: TextStyle(
                                    fontSize: MobileText.bodyLg,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.5),
                                  ),
                                ),
                              ),
                            )
                          : ListView(
                              children: <Widget>[
                                for (final row in rows) ...<Widget>[
                                  if (row is _MobileContactGroupHeader)
                                    _buildPairedGroupHeader(row)
                                  else
                                    _buildPairedContactRow(
                                      row as _PersonContact,
                                      access,
                                    ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    // 关闭后主列表恢复完整显示。
    if (mounted) {
      controller.dispose();
      setState(() {
        _contactQuery = '';
        _contactSearchController.clear();
      });
    }
  }

  Future<void> _openPairPhone() async {
    final pairing = await Navigator.of(context).push<DirectPairing>(
      MaterialPageRoute<DirectPairing>(builder: (_) => ScanPage()),
    );
    if (!mounted || pairing == null) return;
    _queryOnlineStates();
    setState(() {});
  }

  void _openBluetooth() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BluetoothChatPage()),
    );
  }

  void _openConnectionAndIdentity() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) {
          final dark = Theme.of(pageContext).brightness == Brightness.dark;
          return StatefulBuilder(
            builder: (pageContext, routeSetState) {
              return Scaffold(
                backgroundColor:
                    dark ? MyTheme.canvasDark : MyTheme.canvasLight,
                appBar: AppBar(
                  title: Text(
                    '${translate('Connection')} · ${translate('My Identity')}',
                  ),
                ),
                body: SafeArea(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: kMobilePageConstraints,
                        child: Column(
                          children: <Widget>[
                            _buildStatusCard(),
                            _buildConnectionModeSwitch(routeSetState),
                            _buildRemoteIDTextField(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openDeviceHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) {
          final dark = Theme.of(pageContext).brightness == Brightness.dark;
          return Scaffold(
            backgroundColor: dark ? MyTheme.canvasDark : MyTheme.canvasLight,
            appBar: AppBar(
              title: Text(translate('Access history devices')),
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: kMobilePageConstraints,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: PeerTabPage(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 公开入口：点聊/联系人右上角“+”菜单调用（复用扫码绑定页）。
  Future<void> openPairPhone() => _openPairPhone();

  /// 公开入口：蓝牙扫描页。
  void openBluetooth() => _openBluetooth();

  /// 公开入口：远程连接（ID / IP / 端口 + 身份卡片）。
  void openConnectionAndIdentity() => _openConnectionAndIdentity();

  /// 公开入口：访问历史设备。
  void openDeviceHistory() => _openDeviceHistory();

  /// Compact card showing this device's online status, ID and message policy.
  Widget _buildStatusCard() {
    final access = DirectChatAccessController.instance..load();
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        gFFI.serverModel,
        access,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        final status = gFFI.serverModel.connectStatus;
        final directPort =
            bind.mainGetOptionSync(key: kOptionDirectAccessPort).trim();
        final String statusText;
        final Color statusColor;
        if (status > 0) {
          statusText = translate('Online');
          statusColor = const Color(0xFF238A57);
        } else if (directPort.isNotEmpty) {
          statusText = translate('Direct listening');
          statusColor = const Color(0xFF238A57);
        } else if (status == 0) {
          statusText = translate('connecting_status');
          statusColor = const Color(0xFF07C160);
        } else {
          statusText = translate('Offline');
          statusColor = const Color(0xFF8A8D94);
        }
        final trustedOnly = access.audience == DirectChatAudience.friendsOnly;
        final policy = trustedOnly
            ? translate('Only friends can contact me anytime')
            : translate('Strangers can also chat with me directly');
        final id = gFFI.serverModel.serverId.value.text.trim();
        return Container(
          margin: const EdgeInsets.fromLTRB(2, 8, 2, 4),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1C2027) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: dark ? const Color(0xFF2B2D32) : const Color(0xFFE2ECE6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: MyTheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.phone_android_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: statusColor.withOpacity(0.5),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                statusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            Text(
                              translate('ID'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.55),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                id,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: translate('Copy'),
                              constraints: const BoxConstraints.tightFor(
                                width: 48,
                                height: 48,
                              ),
                              onPressed: () {
                                if (id.isNotEmpty) {
                                  Clipboard.setData(ClipboardData(text: id));
                                  showToast(translate('Copied'));
                                }
                              },
                              icon: Icon(
                                Icons.copy_rounded,
                                size: 19,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.65),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _statusChip(
                label: policy,
                icon: trustedOnly
                    ? Icons.lock_outline_rounded
                    : Icons.public_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusChip({required String label, required IconData icon}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF2A2D33)
            : const Color(0xFFF0F1F2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon,
              size: 12, color: theme.colorScheme.onSurface.withOpacity(0.6)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: MobileText.captionSm,
                  color: theme.colorScheme.onSurface.withOpacity(0.6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String text, Color color) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: MobileText.captionSm,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  Future<void> onConnect() async {
    if (_connectionMode == _ConnectionMode.bluetooth) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BluetoothChatPage()),
      );
      return;
    }
    final id = _idController.id.trim().replaceAll(' ', '');
    if (id.isEmpty) return;
    if (_connectionMode == _ConnectionMode.chat) {
      await _startDirectChat(id);
    } else if (_connectionMode == _ConnectionMode.remote) {
      final endpoint = DirectPairingStore.resolveConnectionTarget(id);
      if (endpoint == null) {
        showToast(translate(
          'Direct endpoint required. Scan the PC QR code or enter IP:port.',
        ));
        return;
      }
      connect(context, endpoint, forceRelay: false);
    } else {
      await _openJoinViewer(initialEndpoint: id);
    }
  }

  Widget _buildConnectionModeSwitch([StateSetter? routeSetState]) {
    const segments = <(_ConnectionMode, IconData, String)>[
      (_ConnectionMode.chat, Icons.chat_bubble_outline_rounded, 'Chat'),
      (
        _ConnectionMode.remote,
        Icons.desktop_windows_outlined,
        'Remote assistance'
      ),
      (_ConnectionMode.viewer, Icons.visibility_outlined, 'Join as Viewer'),
      (_ConnectionMode.bluetooth, Icons.bluetooth_rounded, 'Bluetooth'),
    ];
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final idleColor = dark ? const Color(0xFF9AA1AC) : const Color(0xFF8A8D94);
    return Container(
      margin: const EdgeInsets.fromLTRB(2, 10, 2, 2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF202227) : const Color(0xFFF0F1F2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final seg in segments)
              Semantics(
                button: true,
                selected: _connectionMode == seg.$1,
                label: translate(seg.$3),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (routeSetState != null) {
                        routeSetState(() => _connectionMode = seg.$1);
                      } else {
                        setState(() => _connectionMode = seg.$1);
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      constraints: const BoxConstraints(
                        minWidth: 112,
                        minHeight: 48,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _connectionMode == seg.$1
                            ? MyTheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            seg.$2,
                            size: 18,
                            color: _connectionMode == seg.$1
                                ? Colors.white
                                : idleColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            translate(seg.$3),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: MobileText.bodySm,
                              fontWeight: FontWeight.w600,
                              color: _connectionMode == seg.$1
                                  ? Colors.white
                                  : idleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openJoinViewer({
    String initialEndpoint = '',
    ViewerInviteLink? invite,
  }) async {
    if (_openingViewerInvite) return;
    _openingViewerInvite = true;
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => JoinViewerPage(
            initialEndpoint: invite?.endpoint.isNotEmpty == true
                ? invite!.endpoint
                : initialEndpoint,
            initialToken: invite?.token,
            initialDisplayName: gFFI.chatModel.me.firstName,
            onJoinRequested: ({
              required endpoint,
              required token,
              required viewerId,
              required displayName,
            }) async {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                connect(
                  context,
                  endpoint,
                  viewerToken: token,
                  viewerId: viewerId,
                  viewerDisplayName: displayName,
                );
              });
            },
          ),
        ),
      );
    } finally {
      _openingViewerInvite = false;
    }
  }

  void _handlePendingViewerInvite() {
    final invite = takePendingViewerInvite();
    if (invite == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openJoinViewer(invite: invite);
    });
  }

  Future<void> _startDirectChat(String id) async {
    final pairing = DirectPairingStore.find(id) ??
        DirectPairingStore.findByEndpoint(id) ??
        DirectPairingStore.findForConversation(id);
    final endpoint = DirectPairingStore.resolveConnectionTarget(id);
    if (endpoint == null) {
      showToast(translate(
        'Direct endpoint required. Scan the PC QR code or enter IP:port.',
      ));
      return;
    }
    // 统一到 canonical 会话：同一账号的 PC/手机/不同 IP 都归入同一会话，
    // 保证用 IP、旧 ID 或别名打开时能复用已授权的入站聊天连接。
    final peerId = DirectPairingStore.canonicalConversationId(id);
    if (peerId.isEmpty) return;
    if (ChatModel.isDialing(peerId)) return;
    final currentKey = gFFI.chatModel.currentKey;
    final hasStuckOutgoing = await gFFI.chatModel.hasPendingOutgoing(peerId);
    if (gFFI.connType == ConnType.chat &&
        currentKey.peerId == peerId &&
        isDirectChatSessionReady(
          closed: gFFI.closed,
          peerInfoReady: gFFI.ffiModel.pi.isSet.isTrue,
          connectionError: gFFI.ffiModel.lastConnectionError,
        ) &&
        !hasStuckOutgoing) {
      ChatModel.clearDialing(peerId);
      HomePage.homeKey.currentState?.selectChatPage();
      return;
    }
    final requestedIds = DirectPairingStore.conversationPeerIds(peerId);
    final incomingIndex = gFFI.serverModel.clients.lastIndexWhere((client) {
      if (!client.authorized || !client.isChat || client.disconnected) {
        return false;
      }
      final clientIds = DirectPairingStore.conversationPeerIds(client.peerId);
      return requestedIds.any(clientIds.contains);
    });
    if (incomingIndex >= 0) {
      ChatModel.clearDialing(peerId);
      final incoming = gFFI.serverModel.clients[incomingIndex];
      gFFI.chatModel.changeCurrentKey(MessageKey(peerId, incoming.id));
      gFFI.chatModel.updatePeerIdentity(
        peerId,
        displayName: incoming.name.trim().isNotEmpty
            ? incoming.name.trim()
            : pairing?.displayName ?? peerId,
        avatar: incoming.avatar,
      );
      HomePage.homeKey.currentState?.selectChatPage();
      gFFI.chatModel.requestChatInputFocus();
      return;
    }
    if (gFFI.ffiModel.pi.isSet.isTrue || gFFI.connType == ConnType.chat) {
      await gFFI.close();
    }
    ChatModel.markDialing(peerId);
    gFFI.chatModel.changeCurrentKey(MessageKey(peerId, ChatModel.clientModeID));
    if (pairing != null) {
      gFFI.chatModel.updatePeerIdentity(
        peerId,
        displayName: pairing.displayName,
        avatar: pairing.avatar,
      );
    }
    gFFI.suppressConnectionDialogs = true;
    gFFI.start(endpoint, isChat: true, forceRelay: false);
    HomePage.homeKey.currentState?.selectChatPage();
  }

  /// 移动端单连接保活：对最近活跃（或仍在保活窗口内）的会话保持 / 恢复 isChat 连接，
  /// 以便消息即时收发；空闲时按固定间隔重连拉取消息。正在远程控制时不抢占全局 gFFI。
  /// 仅在本页是当前可见 tab 时执行：HomePageState 有常驻的等效保活兜底，
  /// 避免 PageView 预构建相邻页时两个定时器重复拨号。
  Future<void> _maintainChatKeepAlive() async {
    if (!mounted) return;
    final home = HomePage.homeKey.currentState;
    if (home != null &&
        home.contactsPageTabIndex >= 0 &&
        home.selectedIndex != home.contactsPageTabIndex) {
      return;
    }
    // 正在远程控制会话中（默认连接类型且已建立会话），不抢占全局 gFFI。
    // 注意：空闲状态下 connType 也是 defaultConn（但 pi.isSet=false），
    // 不能仅以 connType 判断，否则保活永远不会拨号建立 isChat 会话。
    if (!gFFI.closed &&
        gFFI.connType == ConnType.defaultConn &&
        gFFI.ffiModel.pi.isSet.isTrue) {
      return;
    }
    var watchPeer = gFFI.chatModel.lastActiveChatPeerId;
    if (watchPeer == null || watchPeer.isEmpty) {
      // 重启后内存活跃记录清空：以待发送消息为准仍要重建连接。
      watchPeer = await gFFI.chatModel.firstPendingPeerId();
    }
    if (watchPeer == null || watchPeer.isEmpty) return;
    final access = DirectChatAccessController.instance..load();
    if (!access.shouldAutoReconnect(watchPeer)) return;
    // 无可用连接端点则不重建，避免周期性弹 toast。
    if (DirectPairingStore.resolveConnectionTarget(watchPeer) == null) return;
    final hasStuckOutgoing = await gFFI.chatModel.hasPendingOutgoing(watchPeer);
    // 已是健康的 isChat 连接且无未送达消息则无需重建。
    if (gFFI.connType == ConnType.chat &&
        gFFI.chatModel.currentKey.peerId == watchPeer &&
        isDirectChatSessionReady(
          closed: gFFI.closed,
          peerInfoReady: gFFI.ffiModel.pi.isSet.isTrue,
          connectionError: gFFI.ffiModel.lastConnectionError,
        ) &&
        !hasStuckOutgoing) {
      return;
    }
    await _startDirectChat(watchPeer);
    // 重连成功后补发该会话在离线期间滞留的待发送消息，避免漏发。
    unawaited(_flushPendingAfterDial(watchPeer));
  }

  /// 拨号后稍作等待（让会话建立完成），再补发未送达消息。
  Future<void> _flushPendingAfterDial(String peerId) async {
    if (peerId.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    await gFFI.chatModel.flushPendingOutgoing(peerId);
  }

  Widget _buildPairedContacts() {
    final access = DirectChatAccessController.instance..load();
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        DirectPairingStore.revision,
        access,
        gFFI.ffiModel,
        gFFI.serverModel,
      ]),
      builder: (context, _) {
        final myId = gFFI.serverModel.serverId.value.text.trim();
        final allGroups = _buildContactGroups(myId);
        final query = _contactQuery.trim().toLowerCase();
        final groups = query.isEmpty
            ? allGroups
            : allGroups
                .where((group) => _matchesContactQuery(group, query))
                .toList(growable: false);
        final friends = groups
            .where((group) => access.isFriend(group.key))
            .toList(growable: false);
        final strangers = groups
            .where((group) => !access.isFriend(group.key))
            .toList(growable: false);
        final rows = <Object>[
          if (friends.isNotEmpty) ...<Object>[
            _MobileContactGroupHeader('Friends', friends.length),
            ...friends,
          ],
          if (strangers.isNotEmpty) ...<Object>[
            _MobileContactGroupHeader('Strangers', strangers.length),
            ...strangers,
          ],
        ];
        // 与点聊列表同款背景：空状态 / 列表都全宽铺在浅灰 canvas 上，
        // 不套白色圆角卡片，保证整块背景与点聊页完全一致。
        final dark = Theme.of(context).brightness == Brightness.dark;
        return ColoredBox(
          color: dark ? MyTheme.canvasDark : MyTheme.canvasLight,
          child: groups.isEmpty
              ? _buildEmptyContactsCard(searching: allGroups.isNotEmpty)
              : Column(
                  children: <Widget>[
                    for (var index = 0;
                        index < rows.length;
                        index++) ...<Widget>[
                      if (rows[index]
                          case final _MobileContactGroupHeader group)
                        _buildPairedGroupHeader(group)
                      else
                        _buildPairedContactRow(
                            rows[index] as _PersonContact, access),
                    ],
                  ],
                ),
        );
      },
    );
  }

  bool _matchesContactQuery(_PersonContact group, String query) {
    if (group.key.toLowerCase().contains(query)) return true;
    return group.devices.any((device) {
      return <String>[
        device.peerId,
        device.accountId,
        device.displayName,
        device.deviceName,
        device.platform,
        ...device.endpoints,
      ].any((value) => value.toLowerCase().contains(query));
    });
  }

  Widget _buildEmptyContactsCard({bool searching = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: MyTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.person_search_rounded,
              size: 24,
              color: MyTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            translate(searching ? 'No results' : 'No contacts yet'),
            style: const TextStyle(
              fontSize: MobileText.bodyLg,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!searching) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              translate('Scan the PC QR code or enter IP:port.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: MobileText.caption,
                height: 1.5,
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 把聊天对象整理成人组：过滤本机、按指纹去重、同一账号多设备合并。
  List<_PersonContact> _buildContactGroups(String myId) {
    final groups = <String, _PersonContact>{};
    final signatureKeys = <String, String>{};
    for (final pairing in DirectPairingStore.load().values) {
      if (pairing.peerId.isEmpty || pairing.peerId == myId) continue;
      final key = pairing.conversationId;
      if (key.isEmpty) continue;
      final signature = _mobilePairingSignature(pairing);
      var group = groups[key];
      if (group == null &&
          signature != null &&
          signatureKeys.containsKey(signature)) {
        group = groups[signatureKeys[signature]];
      }
      group ??= groups[key] = _PersonContact(key);
      if (signature != null) {
        final resolved = group;
        signatureKeys.putIfAbsent(signature, () => resolved.key);
      }
      final sameDevice = group.deviceByFingerprint(pairing);
      if (sameDevice != null) {
        if (pairing.updatedAt.isAfter(sameDevice.updatedAt)) {
          group.replaceDevice(sameDevice, pairing);
        }
        continue;
      }
      group.devices.add(pairing);
    }
    final list = groups.values.toList()
      ..sort((a, b) => b.latest.updatedAt.compareTo(a.latest.updatedAt));
    return list;
  }

  Widget _buildPairedGroupHeader(_MobileContactGroupHeader group) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? MyTheme.mutedDark
        : MyTheme.mutedLight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: <Widget>[
          Text(
            translate(group.label),
            style: TextStyle(
              fontSize: MobileText.caption,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${group.count}',
            style: TextStyle(
              fontSize: MobileText.captionSm,
              color: muted.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairedContactRow(
    _PersonContact group,
    DirectChatAccessController access,
  ) {
    final pairing = group.latest;
    final status = _pairedMessageStatus(pairing);
    final isFriend = access.isFriend(group.key);
    final theme = Theme.of(context);
    final idIpSummary = group.idIpSummary;
    // Material ancestor is required for InkWell's grey tap highlight to
    // actually render — the contacts list sits on a bare ColoredBox, so
    // without this wrapper the WeChat-style press feedback never appears.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _startDirectChat(group.latest.peerId),
        // WeChat-style gray tap highlight, identical to the chats list rows.
        highlightColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF34373D)
            : const Color(0xFFE5E8E6),
        splashColor: Colors.transparent,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _pairedContactAvatar(pairing),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                pairing.displayName.isEmpty
                                    ? group.key
                                    : pairing.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: MobileText.bodyLg,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (group.devices.length > 1) ...<Widget>[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.devices_rounded,
                                size: 14,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.45),
                              ),
                            ],
                            const Spacer(),
                            _statusPill(translate(status.$1), status.$2),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                idIpSummary.isEmpty
                                    ? translate('P2P direct')
                                    : idIpSummary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: MobileText.caption,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.55),
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: translate('Message permission'),
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.55),
                              ),
                              onSelected: (value) => unawaited(
                                access.setPeerPolicy(group.key, value),
                              ),
                              itemBuilder: (_) => <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: isFriend ? 'ask' : 'allow',
                                  child: Text(
                                    translate(isFriend
                                        ? 'Move to strangers'
                                        : 'Add as friend'),
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'deny',
                                  child: Text(translate('Reject')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // WeChat-style hairline: starts at the avatar right edge.
            Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 76),
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF3A3D43)
                  : const Color(0x80E5E5E5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pairedContactAvatar(DirectPairing pairing) {
    final name = pairing.displayName.isEmpty
        ? pairing.peerId
        : pairing.displayName.trim();
    final initial = name.isEmpty ? '?' : name.characters.first;
    final fallback = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: str2color(name),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: MobileText.title,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final avatar = buildAvatarWidget(
          avatar: pairing.avatar,
          size: 48,
          borderRadius: 12,
          fallback: fallback,
        ) ??
        fallback;
    final online = _isPairedContactOnline(pairing);
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 0,
            top: 0,
            child: avatarWithPlatformBadge(
              child: avatar,
              platform: pairing.platform,
              badgeSize: 15,
              // WeChat-style OS indicator on the avatar's top-right corner,
              // clear of the online dot at the bottom-right.
              topRight: true,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color:
                    online ? const Color(0xFF238A57) : const Color(0xFF9AA1AC),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isPairedContactOnline(DirectPairing pairing) {
    final isCurrent = gFFI.chatModel.currentKey.peerId == pairing.peerId;
    final error = isCurrent ? gFFI.ffiModel.lastConnectionError ?? '' : '';
    final activeOutgoing = gFFI.connType == ConnType.chat &&
        isCurrent &&
        isDirectChatSessionReady(
          closed: gFFI.closed,
          peerInfoReady: gFFI.ffiModel.pi.isSet.isTrue,
          connectionError: error,
        );
    final requestedIds =
        DirectPairingStore.conversationPeerIds(pairing.conversationId);
    final activeIncoming = gFFI.serverModel.clients.any(
      (client) {
        if (!client.authorized || !client.isChat || client.disconnected) {
          return false;
        }
        final clientIds = DirectPairingStore.conversationPeerIds(client.peerId);
        return requestedIds.any(clientIds.contains);
      },
    );
    final rendezvousOnline =
        DirectPairingStore.conversationPeerIds(pairing.conversationId)
            .any((id) => _onlineByPeer[id] == true);
    return activeOutgoing || activeIncoming || rendezvousOnline;
  }

  (String, Color) _pairedMessageStatus(DirectPairing pairing) {
    if (_isPairedContactOnline(pairing)) {
      return ('Messages allowed', const Color(0xFF238A57));
    }
    final isCurrent = gFFI.chatModel.currentKey.peerId == pairing.peerId;
    final error = isCurrent ? gFFI.ffiModel.lastConnectionError ?? '' : '';
    if (isDirectChatPermissionDenied(error)) {
      return ('Messages rejected', const Color(0xFFD84A4A));
    }
    if (error.trim().isNotEmpty) {
      return ('Not connected', const Color(0xFF7B7E85));
    }
    if (isCurrent && !gFFI.closed && gFFI.connType == ConnType.chat) {
      return ('Connecting', const Color(0xFF07C160));
    }
    return ('Not connected', const Color(0xFF7B7E85));
  }

  void onFocusChanged() {
    _idEmpty.value = _idEditingController.text.isEmpty;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  /// UI for software update.
  /// If _updateUrl] is not empty, shows a button to update the software.
  Widget _buildUpdateUI(String updateUrl) {
    return updateUrl.isEmpty
        ? const SizedBox(height: 0)
        : InkWell(
            onTap: () async {
              final url = 'https://www.dotchat.app/download';
              // https://pub.dev/packages/url_launcher#configuration
              // https://developer.android.com/training/package-visibility/use-cases#open-urls-custom-tabs
              //
              // `await launchUrl(Uri.parse(url))` can also run if skip
              // 1. The following check
              // 2. `<action android:name="android.support.customtabs.action.CustomTabsService" />` in AndroidManifest.xml
              //
              // But it is better to add the check.
              await launchUrl(Uri.parse(url));
            },
            child: Container(
                alignment: AlignmentDirectional.center,
                width: double.infinity,
                color: Colors.pinkAccent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(translate('Download new version'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))));
  }

  /// UI for the remote ID TextField.
  /// Search for a peer and connect to it if the id exists.
  Widget _buildRemoteIDTextField({bool quickChatOnly = false}) {
    void submit() {
      if (quickChatOnly) {
        final id = _idController.id.trim().replaceAll(' ', '');
        if (id.isNotEmpty) unawaited(_startDirectChat(id));
      } else {
        unawaited(onConnect());
      }
    }

    final w = SizedBox(
      height: quickChatOnly ? 56 : 72,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: quickChatOnly ? 4 : 8,
          horizontal: 2,
        ),
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: EdgeInsets.only(
                    left: quickChatOnly ? 12 : 16,
                    right: quickChatOnly ? 8 : 16,
                  ),
                  child: RawAutocomplete<Peer>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') {
                        _autocompleteOpts = const Iterable<Peer>.empty();
                      } else if (_allPeersLoader.peers.isEmpty &&
                          !_allPeersLoader.isPeersLoaded) {
                        Peer emptyPeer = Peer(
                          id: '',
                          username: '',
                          hostname: '',
                          alias: '',
                          platform: '',
                          tags: [],
                          hash: '',
                          password: '',
                          forceAlwaysRelay: false,
                          rdpPort: '',
                          rdpUsername: '',
                          loginName: '',
                          device_group_name: '',
                          note: '',
                        );
                        _autocompleteOpts = [emptyPeer];
                      } else {
                        String textWithoutSpaces =
                            textEditingValue.text.replaceAll(" ", "");
                        if (int.tryParse(textWithoutSpaces) != null) {
                          textEditingValue = TextEditingValue(
                            text: textWithoutSpaces,
                            selection: textEditingValue.selection,
                          );
                        }
                        String textToFind = textEditingValue.text.toLowerCase();

                        _autocompleteOpts = _allPeersLoader.peers
                            .where((peer) =>
                                peer.id.toLowerCase().contains(textToFind) ||
                                peer.username
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.hostname
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.alias.toLowerCase().contains(textToFind))
                            .toList();
                      }
                      return _autocompleteOpts;
                    },
                    focusNode: _idFocusNode,
                    textEditingController: _idEditingController,
                    fieldViewBuilder: (BuildContext context,
                        TextEditingController fieldTextEditingController,
                        FocusNode fieldFocusNode,
                        VoidCallback onFieldSubmitted) {
                      updateTextAndPreserveSelection(
                          fieldTextEditingController, _idController.text);
                      return AutoSizeTextField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        minFontSize: 16,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        // keyboardType: TextInputType.number,
                        onChanged: (String text) {
                          _idController.id = text;
                        },
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: quickChatOnly
                              ? MobileText.title
                              : MobileText.display,
                          color: MyTheme.idColor,
                        ),
                        decoration: InputDecoration(
                          labelText: translate(quickChatOnly
                              ? 'Add by ID or IP:port'
                              : 'ID or IP:port'),
                          // hintText: 'Enter your remote ID',
                          border: InputBorder.none,
                          helperStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: MobileText.bodySm,
                            color: MyTheme.darkGray,
                          ),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: MobileText.bodySm,
                            letterSpacing: 0,
                            color: MyTheme.darkGray,
                          ),
                        ),
                        inputFormatters: [IDTextInputFormatter()],
                        onSubmitted: (_) {
                          submit();
                        },
                      );
                    },
                    onSelected: (option) {
                      setState(() {
                        _idController.id = option.id;
                        FocusScope.of(context).unfocus();
                      });
                    },
                    optionsViewBuilder: (BuildContext context,
                        AutocompleteOnSelected<Peer> onSelected,
                        Iterable<Peer> options) {
                      options = _autocompleteOpts;
                      double maxHeight = options.length * 50;
                      if (options.length == 1) {
                        maxHeight = 52;
                      } else if (options.length == 3) {
                        maxHeight = 146;
                      } else if (options.length == 4) {
                        maxHeight = 193;
                      }
                      maxHeight = maxHeight.clamp(0, 200);
                      return Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 5,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Material(
                                      elevation: 4,
                                      child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: maxHeight,
                                            maxWidth: 320,
                                          ),
                                          child: _allPeersLoader
                                                      .peers.isEmpty &&
                                                  !_allPeersLoader.isPeersLoaded
                                              ? Container(
                                                  height: 80,
                                                  child: Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  )))
                                              : ListView(
                                                  padding:
                                                      EdgeInsets.only(top: 5),
                                                  children: options
                                                      .map((peer) =>
                                                          AutocompletePeerTile(
                                                              onSelect: () =>
                                                                  onSelected(
                                                                      peer),
                                                              peer: peer))
                                                      .toList(),
                                                ))))));
                    },
                  ),
                ),
              ),
              Obx(() => Offstage(
                    offstage: _idEmpty.value,
                    child: IconButton(
                        onPressed: () {
                          setState(() {
                            _idController.clear();
                          });
                        },
                        icon: Icon(Icons.clear, color: MyTheme.darkGray)),
                  )),
              SizedBox(
                width: quickChatOnly ? 52 : 56,
                height: 48,
                child: Container(
                  margin: EdgeInsets.only(right: quickChatOnly ? 4 : 8),
                  decoration: BoxDecoration(
                    color: MyTheme.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    tooltip: translate('Connect'),
                    icon: const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 22),
                    onPressed: submit,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final child = Column(children: [
      if (isWebDesktop)
        getConnectionPageTitle(context, true)
            .marginOnly(bottom: 10, top: 15, left: 12),
      w
    ]);
    return Align(
        alignment: Alignment.topCenter,
        child: Container(constraints: kMobilePageConstraints, child: child));
  }

  void _queryOnlineStates() {
    if (!mounted) return;
    // PageView pre-builds adjacent tabs; only poll online states while this
    // contacts tab is the visible page.
    final home = HomePage.homeKey.currentState;
    if (home != null &&
        home.contactsPageTabIndex >= 0 &&
        home.selectedIndex != home.contactsPageTabIndex) {
      return;
    }
    final ids = <String>{
      for (final pairing in DirectPairingStore.load().values)
        ...DirectPairingStore.conversationPeerIds(pairing.conversationId),
    }.toList(growable: false);
    if (ids.isNotEmpty) {
      bind.queryOnlines(ids: ids);
    }
  }

  @override
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (paused) {
      _chatKeepAliveTimer?.cancel();
      _chatKeepAliveTimer = null;
      _onlineQueryTimer?.cancel();
      _onlineQueryTimer = null;
    } else if (_chatKeepAliveTimer == null) {
      // Only restart when this contacts tab is actually visible; otherwise
      // HomePageState's always-on keep-alive covers the resumed state.
      final home = HomePage.homeKey.currentState;
      final visible = home == null ||
          home.contactsPageTabIndex < 0 ||
          home.selectedIndex == home.contactsPageTabIndex;
      if (!visible) return;
      unawaited(_maintainChatKeepAlive());
      _chatKeepAliveTimer = Timer.periodic(
        ChatModel.kChatReconnectInterval,
        (_) => unawaited(_maintainChatKeepAlive()),
      );
      _onlineQueryTimer = Timer.periodic(
          const Duration(seconds: 10), (_) => _queryOnlineStates());
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pendingViewerInvite.removeListener(_handlePendingViewerInvite);
    _uniLinksSubscription?.cancel();
    _chatKeepAliveTimer?.cancel();
    _onlineQueryTimer?.cancel();
    platformFFI.unregisterEventHandler(
        'callback_query_onlines', _onlineHandlerName);
    _idController.dispose();
    _idFocusNode.removeListener(onFocusChanged);
    _allPeersLoader.clear();
    _idFocusNode.dispose();
    _idEditingController.dispose();
    _contactSearchController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }
}
