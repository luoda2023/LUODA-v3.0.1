import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/widgets/animated_rotation_widget.dart';
import 'package:luoda_flutter/common/widgets/chat_page.dart';
import 'package:luoda_flutter/common/widgets/join_viewer_page.dart';
import 'package:luoda_flutter/common/widgets/custom_password.dart';
import 'package:luoda_flutter/common/widgets/peer_tab_page.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/desktop/pages/connection_page.dart';
import 'package:luoda_flutter/desktop/pages/desktop_setting_page.dart';
import 'package:luoda_flutter/desktop/pages/desktop_tab_page.dart';
import 'package:luoda_flutter/desktop/widgets/update_progress.dart';
import 'package:luoda_flutter/desktop/widgets/desktop_primary_rail.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:luoda_flutter/models/file_model.dart';
import 'package:luoda_flutter/models/model.dart';
import 'package:luoda_flutter/models/peer_model.dart';
import 'package:luoda_flutter/models/platform_model.dart';
import 'package:luoda_flutter/models/server_model.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:luoda_flutter/plugin/ui_manager.dart';
import 'package:luoda_flutter/utils/multi_window_manager.dart';
import 'package:luoda_flutter/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';
import '../../common/direct_pairing.dart';
import '../../common/direct_viewer_invite.dart';
import '../../common/wechat_ui_tokens.dart';

class DesktopHomePage extends StatefulWidget {
  /// 如果为 true，只显示左侧内容（客户端专用版）
  final bool isClientOnly;
  const DesktopHomePage({Key? key, this.isClientOnly = false})
      : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

enum _ConversationAction { fileTransfer, remoteAssist, camera, terminal, port }

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  Timer? _directChatKeepAliveTimer;
  bool isCardClosed = false;
  String _lastIp = '';
  String _lastLanIp = '';
  String _lastPort = '';
  bool _passwordVisible = false;
  String _selectedRailId = 'chat';
  Peer? _selectedContact;
  String? _selectedConversationPeerId;
  bool _openingViewerInvite = false;
  final Map<String, FFI> _directChatSessions = <String, FFI>{};
  final Map<String, FFI> _directFileSessions = <String, FFI>{};
  String? _activeDirectChatPeerId;
  final RxBool _settingsHover = false.obs;
  final RxBool _relayHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  // ---- 客户端专用版：ID输入框 ----
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _contactSearchController =
      TextEditingController();
  final FocusNode _clientIdFocusNode = FocusNode();

  void _onClientConnect(String id, BuildContext buildCtx) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    _connectDirect(buildCtx, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    // 客户端专用版：只显示左侧内容，不包含右侧输入框和历史列表
    if (widget.isClientOnly) {
      return _buildBlock(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildLeftPane(context),
            if (!isIncomingOnly) const VerticalDivider(width: 1),
          ],
        ),
      );
    }
    if (!isIncomingOnly) {
      return _buildBlock(child: _buildRemoteCenter(context));
    }
    return _buildBlock(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildLeftPane(context),
          if (!isIncomingOnly) const VerticalDivider(width: 1),
          if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
        ],
      ),
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
      block: _block,
      mask: true,
      use: canBeBlocked,
      child: child,
    );
  }

  Widget _buildRemoteCenter(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail = constraints.maxWidth >= 820;
        final contactsWidth = constraints.maxWidth >= 1240 ? 316.0 : 300.0;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return ColoredBox(
          color: dark ? const Color(0xFF191B20) : const Color(0xFFF7F7F8),
          child: Row(
            children: [
              if (showRail) _buildPrimaryRail(context),
              SizedBox(
                width: contactsWidth,
                child: _buildContactsPane(context),
              ),
              Expanded(child: _buildConversationWorkspace(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrimaryRail(BuildContext context) {
    const destinations = <DesktopRailDestination>[
      DesktopRailDestination(
        id: 'chat',
        label: 'Chat',
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_bubble_rounded,
      ),
      DesktopRailDestination(
        id: 'recent',
        label: 'Recent sessions',
        icon: Icons.history_rounded,
      ),
      DesktopRailDestination(
        id: 'favorites',
        label: 'Favorites',
        icon: Icons.star_outline_rounded,
        selectedIcon: Icons.star_rounded,
      ),
      DesktopRailDestination(
        id: 'discovered',
        label: 'Discovered',
        icon: Icons.radar_rounded,
      ),
      DesktopRailDestination(
        id: 'contacts',
        label: 'Address book',
        icon: Icons.contacts_outlined,
        selectedIcon: Icons.contacts_rounded,
      ),
      DesktopRailDestination(
        id: 'history',
        label: 'Access history devices',
        icon: Icons.devices_outlined,
        selectedIcon: Icons.devices_rounded,
      ),
      DesktopRailDestination(
        id: 'vip',
        label: 'VIP features',
        icon: Icons.workspace_premium_outlined,
        selectedIcon: Icons.workspace_premium_rounded,
      ),
    ];
    return DesktopPrimaryRail(
      destinations: destinations,
      selectedId: _selectedRailId,
      avatar: _buildLocalAvatar(44),
      onAvatarPressed: () => DesktopTabPage.onAddSetting(
        initialPage: SettingsTabKey.account,
      ),
      onSelected: (id) async {
        const indexes = <String, int>{
          'chat': 0,
          'recent': 0,
          'favorites': 1,
          'discovered': 2,
          'contacts': 3,
          'history': 4,
          'vip': 5,
        };
        setState(() => _selectedRailId = id);
        await PeerTabPage.selectDesktopTab(indexes[id] ?? 0);
        await _loadContactSection(id);
      },
      onSettings: DesktopTabPage.onAddSetting,
      onPairPhone: () => _showPairingQrDialog(context),
      onMore: () => _showToolsMenu(context),
    );
  }

  Widget _buildContactsPane(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final sectionTitle = switch (_selectedRailId) {
      'chat' => 'Messages',
      'recent' => 'Recent sessions',
      'favorites' => 'Favorites',
      'discovered' => 'Discovered',
      'contacts' => 'Contacts',
      'history' => 'Access history devices',
      'vip' => 'VIP features',
      _ => 'Contacts',
    };
    return ColoredBox(
      color: dark ? const Color(0xFF25272C) : kWeChatListSurfaceColor,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _contactSearchController,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (value) {
                        if (DirectPairingStore.resolveConnectionTarget(value) !=
                            null) {
                          _startDirectChat(value);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: translate(
                          _selectedRailId == 'chat'
                              ? 'Search conversations'
                              : 'Search',
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        filled: true,
                        fillColor:
                            dark ? const Color(0xFF32343A) : kWeChatCanvasColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: translate('Add'),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
                  onSelected: (value) {
                    switch (value) {
                      case 'connect':
                        _showDirectConnectDialog(context);
                        return;
                      case 'viewer':
                        _showJoinViewerPage(context);
                        return;
                      case 'pair-phone':
                        _showPairingQrDialog(context);
                        return;
                      case 'identity':
                        _showIdentityDialog(context);
                        return;
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'connect',
                      child: Text(translate('Connect by ID / IP')),
                    ),
                    PopupMenuItem<String>(
                      value: 'viewer',
                      child: Text(translate('Join as Viewer')),
                    ),
                    PopupMenuItem<String>(
                      value: 'pair-phone',
                      child: Text(translate('Pair phone')),
                    ),
                    PopupMenuItem<String>(
                      value: 'identity',
                      child: Text(translate('My Identity')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 20),
                Icon(
                  _selectedRailId == 'chat'
                      ? Icons.format_list_bulleted_rounded
                      : Icons.contacts_outlined,
                  size: 19,
                  color: theme.colorScheme.onSurface.withOpacity(0.56),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    translate(sectionTitle),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.64),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurface.withOpacity(0.56),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: dark ? const Color(0xFF3A3D43) : const Color(0xFFE5E5E7),
          ),
          Expanded(child: _buildContactSection(context)),
        ],
      ),
    );
  }

  void _showDirectConnectDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        void connect() {
          final target = _clientIdController.text.trim();
          if (target.isEmpty) return;
          Navigator.of(dialogContext).pop();
          _startDirectChat(target);
        }

        return AlertDialog(
          title: Text(translate('Connect by ID / IP')),
          content: SizedBox(
            width: 360,
            child: TextField(
              key: const ValueKey('direct-chat-address-field'),
              controller: _clientIdController,
              focusNode: _clientIdFocusNode,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => connect(),
              decoration: InputDecoration(
                labelText: translate('Paired ID / IP:port'),
                prefixIcon: const Icon(Icons.link_rounded, size: 20),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(translate('Cancel')),
            ),
            FilledButton(
              onPressed: connect,
              child: Text(translate('Connect')),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConversationWorkspace(BuildContext context) {
    final activeFfi = _activeDirectChatPeerId == null
        ? null
        : _directChatSessionFor(_activeDirectChatPeerId!);
    final activeModel = activeFfi?.chatModel ?? gFFI.chatModel;
    Widget workspace() => ChangeNotifierProvider.value(
          value: activeModel,
          child: Consumer<ChatModel>(
            builder: (context, model, _) {
              final user = model.currentUser;
              final selectedPeerId =
                  _selectedConversationPeerId ?? _selectedContact?.id ?? '';
              final userMatchesSelection = selectedPeerId.isEmpty ||
                  user?.id.trim() == selectedPeerId.trim();
              final peerId =
                  userMatchesSelection && user?.id.trim().isNotEmpty == true
                      ? user!.id.trim()
                      : selectedPeerId;
              final selectedName = _selectedContact == null
                  ? ''
                  : _contactName(_selectedContact!);
              final hasConversation =
                  user != null && userMatchesSelection && peerId.isNotEmpty;
              final canStartDirectSession =
                  DirectPairingStore.resolveConnectionTarget(peerId) != null;
              return ColoredBox(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1C1E23)
                    : kWeChatCanvasColor,
                child: Column(
                  children: <Widget>[
                    _buildConversationHeader(
                      context,
                      title: hasConversation &&
                              user?.firstName?.trim().isNotEmpty == true
                          ? user!.firstName!
                          : selectedName.isNotEmpty
                              ? selectedName
                              : translate('Direct chat'),
                      peerId: peerId,
                      hasConversation: hasConversation,
                      canStartDirectSession: canStartDirectSession,
                    ),
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    if (hasConversation)
                      _buildActiveTransferStrip(context, peerId),
                    Expanded(
                      child: hasConversation
                          ? ChatPage(
                              chatModel: model,
                              type: ChatPageType.desktopHome,
                              onAttachFile: () =>
                                  _sendFilesFromConversation(peerId),
                              onRemoteAssist: () =>
                                  _connectDirect(context, peerId),
                            )
                          : _buildEmptyConversation(
                              context,
                              contact: _selectedContact,
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
    return AnimatedBuilder(
      animation: activeFfi == null
          ? gFFI.serverModel
          : Listenable.merge(<Listenable>[
              activeFfi.ffiModel,
              gFFI.serverModel,
            ]),
      builder: (context, _) => workspace(),
    );
  }

  Widget _buildConversationHeader(
    BuildContext context, {
    required String title,
    required String peerId,
    required bool hasConversation,
    required bool canStartDirectSession,
  }) {
    final theme = Theme.of(context);
    final status = _directDeliveryStatus(peerId, contact: _selectedContact);
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (peerId.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 10),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: status.$2,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      translate(status.$1),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: status.$2,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _conversationActionButton(
              context,
              tooltip: translate('File Transfer'),
              icon: Icons.attach_file_rounded,
              onPressed: hasConversation
                  ? () => _sendFilesFromConversation(peerId)
                  : null,
            ),
            _conversationActionButton(
              context,
              tooltip: translate('Remote Desktop'),
              icon: Icons.desktop_windows_outlined,
              onPressed: canStartDirectSession
                  ? () => _connectDirect(context, peerId)
                  : null,
            ),
            PopupMenuButton<_ConversationAction>(
              tooltip: translate('More'),
              enabled: canStartDirectSession,
              onSelected: (action) =>
                  _handleConversationAction(context, action, peerId),
              itemBuilder: (context) => <PopupMenuEntry<_ConversationAction>>[
                PopupMenuItem(
                  value: _ConversationAction.camera,
                  child: Text(translate('View camera')),
                ),
                PopupMenuItem(
                  value: _ConversationAction.terminal,
                  child: Text(translate('Terminal')),
                ),
                PopupMenuItem(
                  value: _ConversationAction.port,
                  child: Text(translate('TCP tunneling')),
                ),
              ],
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationActionButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 21),
      ),
    );
  }

  Widget _buildActiveTransferStrip(BuildContext context, String peerId) {
    final ffi = _directFileSessions[peerId];
    if (ffi == null) return const SizedBox.shrink();
    return Obx(() {
      final jobs = ffi.fileModel.jobController.jobTable;
      if (jobs.isEmpty) return const SizedBox.shrink();
      final job = jobs.last;
      final color = switch (job.state) {
        JobState.done => const Color(0xFF238A57),
        JobState.error => const Color(0xFFD84A4A),
        _ => Theme.of(context).colorScheme.primary,
      };
      final cancellable = job.state != JobState.done &&
          job.state != JobState.error &&
          job.state != JobState.none;
      return Container(
        height: 46,
        padding: const EdgeInsets.only(left: 22, right: 12),
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          children: <Widget>[
            Icon(
              job.state == JobState.done
                  ? Icons.check_circle_outline_rounded
                  : job.state == JobState.error
                      ? Icons.error_outline_rounded
                      : Icons.upload_file_outlined,
              size: 19,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                job.fileName.isEmpty
                    ? translate('File Transfer')
                    : job.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 104,
              child: job.state == JobState.inProgress
                  ? LinearProgressIndicator(
                      value: job.totalSize > 0 ? job.percent : null,
                      minHeight: 3,
                      color: color,
                    )
                  : Text(
                      job.state.display(),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: color,
                          ),
                    ),
            ),
            const SizedBox(width: 8),
            if (cancellable)
              Tooltip(
                message: translate('Cancel'),
                child: IconButton(
                  onPressed: () => unawaited(
                    ffi.fileModel.jobController.cancelJob(job.id),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildEmptyConversation(BuildContext context, {Peer? contact}) {
    final theme = Theme.of(context);
    final contactName = contact == null ? '' : _contactName(contact);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                contact == null ? Icons.forum_outlined : Icons.person_rounded,
                size: 70,
                color: contact == null
                    ? theme.colorScheme.onSurface.withOpacity(0.13)
                    : str2color(contactName),
              ),
              const SizedBox(height: 20),
              Text(
                contact == null
                    ? translate('Start a direct conversation')
                    : contactName,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                contact == null
                    ? translate(
                        'Scan the PC QR code or enter an IP:port. No rendezvous or relay server is used.',
                      )
                    : '${contact.id}\n${contact.online ? translate('Online') : translate('Offline')}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.56),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: contact == null
                    ? () => _clientIdFocusNode.requestFocus()
                    : () => _startDirectChat(contact.id),
                icon: Icon(
                  contact == null
                      ? Icons.add_link_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 19,
                ),
                label: Text(
                  translate(
                    contact == null ? 'Connect by ID / IP' : 'Connect and chat',
                  ),
                ),
              ),
              if (contact != null) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => _sendFilesFromConversation(contact.id),
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: Text(translate('File Transfer')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _connectDirect(context, contact.id),
                      icon: const Icon(
                        Icons.desktop_windows_outlined,
                        size: 18,
                      ),
                      label: Text(translate('Remote Desktop')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactSection(BuildContext context) {
    if (_selectedRailId == 'chat') {
      return _buildConversationList(context);
    }
    if (_selectedRailId == 'vip') {
      return const PeerTabPage(showTabStrip: false);
    }
    final model = _contactModelFor(_selectedRailId);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        model,
        gFFI.serverModel,
        DirectPairingStore.revision,
      ]),
      builder: (context, _) {
        final query = _contactSearchController.text.trim().toLowerCase();
        final peers = query.isEmpty
            ? model.peers
            : model.peers.where((peer) {
                return _contactName(peer).toLowerCase().contains(query) ||
                    peer.id.toLowerCase().contains(query);
              }).toList();
        final peerIds = peers.map((peer) => peer.id).toSet();
        final standalonePairings =
            DirectPairingStore.load().values.where((pairing) {
          if (peerIds.contains(pairing.peerId)) return false;
          if (query.isEmpty) return true;
          return pairing.peerId.toLowerCase().contains(query) ||
              pairing.displayName.toLowerCase().contains(query) ||
              pairing.endpoints.any(
                (endpoint) => endpoint.toLowerCase().contains(query),
              );
        }).toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (peers.isEmpty && standalonePairings.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                translate('No contacts yet'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                    ),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: standalonePairings.length + peers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 1),
          itemBuilder: (context, index) {
            if (index < standalonePairings.length) {
              return _buildPairedContactItem(
                context,
                standalonePairings[index],
              );
            }
            return _buildContactItem(
              context,
              peers[index - standalonePairings.length],
            );
          },
        );
      },
    );
  }

  DateTime _conversationTime(MapEntry<MessageKey, MessageBody> entry) {
    final messages = entry.value.chatMessages;
    if (messages.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return messages
        .map((message) => message.createdAt)
        .reduce((latest, value) => value.isAfter(latest) ? value : latest);
  }

  String _conversationPreview(MapEntry<MessageKey, MessageBody> entry) {
    final messages = entry.value.chatMessages;
    if (messages.isEmpty) return translate('Start a conversation');
    final message = messages.reduce(
      (latest, value) =>
          value.createdAt.isAfter(latest.createdAt) ? value : latest,
    );
    final properties = message.customProperties;
    if (properties?['ldesk_kind'] == 'file') {
      final fileName = (properties?['ldesk_file_name'] ?? '').toString();
      return fileName.isEmpty
          ? translate('File Transfer')
          : '${translate('File Transfer')}: $fileName';
    }
    return message.text.trim().isEmpty
        ? translate('Message')
        : message.text.trim();
  }

  String _conversationTimeLabel(DateTime value) {
    if (value.millisecondsSinceEpoch == 0) return '';
    final now = DateTime.now();
    if (value.year == now.year &&
        value.month == now.month &&
        value.day == now.day) {
      return '${value.hour.toString().padLeft(2, '0')}:'
          '${value.minute.toString().padLeft(2, '0')}';
    }
    if (value.year == now.year) return '${value.month}/${value.day}';
    return '${value.year}/${value.month}/${value.day}';
  }

  void _openConversation(MapEntry<MessageKey, MessageBody> entry) {
    final peerId = entry.key.peerId.trim();
    if (peerId.isEmpty) return;
    final registered = _directChatSessionFor(peerId);
    final active = registered != null && !registered.closed ? registered : null;
    final incoming =
        active == null ? _incomingDirectChatClientFor(peerId) : null;
    final model = active?.chatModel ?? gFFI.chatModel;
    final contact = gFFI.recentPeersModel.peers.firstWhereOrNull(
      (peer) => peer.id == peerId,
    );
    setState(() {
      _selectedContact = contact;
      _selectedConversationPeerId = peerId;
      _activeDirectChatPeerId = active == null ? null : peerId;
    });
    model.changeCurrentKey(
      MessageKey(peerId, incoming?.id ?? ChatModel.clientModeID),
    );
    model.updatePeerIdentity(
      peerId,
      displayName: entry.value.chatUser.firstName ?? peerId,
      avatar: entry.value.chatUser.profileImage ?? '',
    );
    if (active == null && incoming == null) {
      unawaited(_startDirectChat(peerId));
    }
  }

  Widget _buildConversationList(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        gFFI.chatModel,
        gFFI.serverModel,
        DirectPairingStore.revision,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final query = _contactSearchController.text.trim().toLowerCase();
        final entries = gFFI.chatModel.messages.entries.where((entry) {
          final peerId = entry.key.peerId.trim();
          if (peerId.isEmpty) return false;
          if (query.isEmpty) return true;
          final name = (entry.value.chatUser.firstName ?? '').toLowerCase();
          return peerId.toLowerCase().contains(query) ||
              name.contains(query) ||
              _conversationPreview(entry).toLowerCase().contains(query);
        }).toList(growable: false)
          ..sort(
            (a, b) => _conversationTime(b).compareTo(_conversationTime(a)),
          );
        if (entries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.forum_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurface.withOpacity(0.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    translate('No conversations yet'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _clientIdFocusNode.requestFocus,
                    icon: const Icon(Icons.add_comment_outlined, size: 18),
                    label: Text(translate('New conversation')),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: entries.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 78,
            endIndent: 14,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF3A3D43)
                : kWeChatDividerColor,
          ),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final peerId = entry.key.peerId;
            final user = entry.value.chatUser;
            final name = (user.firstName ?? '').trim();
            final displayName = name.isEmpty ? peerId : name;
            final selected = _selectedConversationPeerId == peerId;
            final client = gFFI.serverModel.clients.firstWhereOrNull(
              (client) =>
                  client.peerId == peerId &&
                  client.isChat &&
                  !client.disconnected,
            );
            return Material(
              color: selected
                  ? Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF087A4E)
                      : kWeChatSelectedConversationColor
                  : Colors.transparent,
              child: InkWell(
                onTap: () => _openConversation(entry),
                onDoubleTap: () => _connectDirect(context, peerId),
                child: SizedBox(
                  height: 80,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 11,
                    ),
                    child: Row(
                      children: <Widget>[
                        _buildConversationAvatar(
                          avatar: user.profileImage ?? '',
                          name: displayName,
                          initial: displayName.characters.first,
                          size: 46,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodyLarge?.copyWith(
                                        color: selected ? Colors.white : null,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _conversationTimeLabel(
                                      _conversationTime(entry),
                                    ),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: selected
                                          ? Colors.white.withOpacity(0.82)
                                          : theme.colorScheme.onSurface
                                              .withOpacity(0.46),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      _conversationPreview(entry),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: selected
                                            ? Colors.white.withOpacity(0.88)
                                            : theme.colorScheme.onSurface
                                                .withOpacity(0.52),
                                        fontSize: 13,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                  if (client != null)
                                    unreadMessageCountBuilder(
                                      client.unreadChatMessageCount,
                                    ).marginOnly(left: 8),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPairedContactItem(
    BuildContext context,
    DirectPairing pairing,
  ) {
    final ffi = _directChatSessionFor(pairing.peerId);
    if (ffi != null) {
      return AnimatedBuilder(
        animation: ffi.ffiModel,
        builder: (context, _) => _buildPairedContactItemBody(context, pairing),
      );
    }
    return _buildPairedContactItemBody(context, pairing);
  }

  Widget _buildPairedContactItemBody(
    BuildContext context,
    DirectPairing pairing,
  ) {
    final theme = Theme.of(context);
    final name =
        pairing.displayName.isEmpty ? pairing.peerId : pairing.displayName;
    final selected = _selectedConversationPeerId == pairing.peerId;
    final delivery = _directDeliveryStatus(pairing.peerId);
    return Material(
      color: selected
          ? theme.colorScheme.onSurface.withOpacity(0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _startDirectChat(pairing.peerId),
        onDoubleTap: () => _connectDirect(context, pairing.peerId),
        child: SizedBox(
          height: 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: <Widget>[
                _buildConversationAvatar(
                  avatar: pairing.avatar,
                  name: name,
                  initial: name.characters.first,
                  size: 42,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              pairing.peerId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.48),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            translate(delivery.$1),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: delivery.$2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactItem(BuildContext context, Peer peer) {
    final ffi = _directChatSessionFor(peer.id);
    if (ffi != null) {
      return AnimatedBuilder(
        animation: ffi.ffiModel,
        builder: (context, _) => _buildContactItemBody(context, peer),
      );
    }
    return _buildContactItemBody(context, peer);
  }

  Widget _buildContactItemBody(BuildContext context, Peer peer) {
    final theme = Theme.of(context);
    final name = _contactName(peer);
    final selected = _selectedConversationPeerId == peer.id;
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;
    final delivery = _contactDeliveryStatus(peer);
    return Material(
      color: selected
          ? theme.colorScheme.onSurface.withOpacity(0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          final registered = _directChatSessionFor(peer.id);
          final active =
              registered != null && !registered.closed ? registered : null;
          final incoming =
              active == null ? _incomingDirectChatClientFor(peer.id) : null;
          setState(() {
            _selectedContact = peer;
            _selectedConversationPeerId = peer.id;
            _activeDirectChatPeerId = active == null ? null : peer.id;
          });
          final model = active?.chatModel ?? gFFI.chatModel;
          model.changeCurrentKey(
            MessageKey(
              peer.id,
              incoming?.id ?? ChatModel.clientModeID,
            ),
          );
          model.updatePeerIdentity(
            peer.id,
            displayName: _contactName(peer),
            avatar: peer.avatar,
          );
          if (active == null && incoming == null) {
            unawaited(_startDirectChat(peer.id));
          }
        },
        onDoubleTap: () => _connectDirect(context, peer.id),
        child: SizedBox(
          height: 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    _buildConversationAvatar(
                      avatar: peer.avatar,
                      name: name,
                      initial: initial,
                      size: 42,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: peer.online
                              ? const Color(0xFF2BB673)
                              : const Color(0xFFA7A9AF),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              peer.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.48),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            translate(delivery.$1),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: delivery.$2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (String, Color) _contactDeliveryStatus(Peer peer) {
    return _directDeliveryStatus(peer.id, contact: peer);
  }

  (String, Color) _directDeliveryStatus(String peerId, {Peer? contact}) {
    final ffi = _directChatSessionFor(peerId);
    final incoming = _incomingDirectChatClientFor(peerId);
    if ((ffi != null &&
            !ffi.closed &&
            ffi.ffiModel.pi.isSet.isTrue &&
            ffi.ffiModel.direct == true) ||
        incoming != null) {
      return ('Messages allowed', const Color(0xFF238A57));
    }
    if (ffi == null) {
      return contact?.online == true
          ? ('Online', const Color(0xFF238A57))
          : ('Offline', const Color(0xFF8A8D94));
    }
    final error = ffi.ffiModel.lastConnectionError ?? '';
    if (error.contains('Direct messages rejected')) {
      return ('Messages rejected', const Color(0xFFD84A4A));
    }
    if (ffi.closed) {
      return ('Offline', const Color(0xFF8A8D94));
    }
    return ('Connecting', const Color(0xFF4C6EA8));
  }

  String _contactName(Peer peer) {
    if (peer.alias.trim().isNotEmpty) return peer.alias.trim();
    if (peer.displayName.trim().isNotEmpty) return peer.displayName.trim();
    if (peer.hostname.trim().isNotEmpty) return peer.hostname.trim();
    if (peer.username.trim().isNotEmpty) return peer.username.trim();
    return peer.id;
  }

  Widget _buildConversationAvatar({
    required String avatar,
    required String name,
    required String initial,
    required double size,
  }) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: str2color(name),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
        ),
      ),
    );
    return buildAvatarWidget(
          avatar: avatar,
          size: size,
          borderRadius: 8,
          fallback: fallback,
        ) ??
        fallback;
  }

  Peers _contactModelFor(String section) {
    switch (section) {
      case 'favorites':
        return gFFI.favoritePeersModel;
      case 'discovered':
        return gFFI.lanPeersModel;
      case 'contacts':
        return gFFI.recentPeersModel;
      case 'history':
        return gFFI.recentPeersModel;
      case 'chat':
      case 'recent':
      default:
        return gFFI.recentPeersModel;
    }
  }

  Future<void> _loadContactSection(String section) async {
    switch (section) {
      case 'favorites':
        bind.mainLoadFavPeers();
        break;
      case 'discovered':
        bind.mainLoadLanPeers();
        bind.mainDiscover();
        break;
      case 'contacts':
        bind.mainLoadRecentPeers();
        break;
      case 'history':
        bind.mainLoadRecentPeers();
        break;
      case 'chat':
      case 'recent':
      default:
        bind.mainLoadRecentPeers();
        break;
    }
  }

  Future<void> _startDirectChat(
    String rawPeerId, {
    bool activate = true,
  }) async {
    final requestedId = rawPeerId.trim().replaceAll(' ', '');
    if (requestedId.isEmpty) return;
    final pairing = DirectPairingStore.find(requestedId);
    final endpoint = DirectPairingStore.resolveConnectionTarget(requestedId);
    if (endpoint == null) {
      _showConversationNotice(
        translate(
            'Direct endpoint required. Scan the PC QR code or enter IP:port.'),
      );
      return;
    }
    final peerId = pairing?.peerId ?? requestedId;
    final contact = _findContact(peerId);
    final existing = _directChatSessionFor(peerId);
    if (existing != null && !existing.closed) {
      if (activate) {
        existing.suppressConnectionDialogs = false;
        setState(() {
          _activeDirectChatPeerId = peerId;
          _selectedContact = contact;
          _selectedConversationPeerId = peerId;
        });
        existing.chatModel.requestChatInputFocus();
      }
      return;
    }
    final incoming = _incomingDirectChatClientFor(peerId);
    if (incoming != null) {
      if (activate) {
        gFFI.chatModel.changeCurrentKey(MessageKey(peerId, incoming.id));
        gFFI.chatModel.updatePeerIdentity(
          peerId,
          displayName: incoming.name.trim().isNotEmpty
              ? incoming.name.trim()
              : pairing?.displayName ??
                  (contact == null ? peerId : _contactName(contact)),
          avatar: incoming.avatar.isNotEmpty
              ? incoming.avatar
              : contact?.avatar ?? '',
        );
        setState(() {
          _activeDirectChatPeerId = null;
          _selectedContact = contact;
          _selectedConversationPeerId = peerId;
        });
        gFFI.chatModel.requestChatInputFocus();
      }
      return;
    }

    final ffi = FFI(null);
    ffi.suppressConnectionDialogs = !activate;
    ffi.chatModel.changeCurrentKey(MessageKey(peerId, ChatModel.clientModeID));
    ffi.chatModel.updatePeerIdentity(
      peerId,
      displayName: pairing?.displayName ??
          (contact == null ? peerId : _contactName(contact)),
      avatar: contact?.avatar ?? '',
    );
    ffi.start(endpoint, isChat: true, forceRelay: false);
    _directChatSessions[peerId] = ffi;
    if (mounted && activate) {
      setState(() {
        _activeDirectChatPeerId = peerId;
        _selectedContact = contact;
        _selectedConversationPeerId = peerId;
      });
    }
    if (!activate) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ffi.closed) return;
      ffi.dialogManager.showLoading(
        translate('Connecting...'),
        onCancel: () => _closeDirectChat(peerId),
      );
    });
  }

  Peer? _findContact(String peerId) {
    for (final model in <Peers>[
      gFFI.recentPeersModel,
      gFFI.favoritePeersModel,
      gFFI.lanPeersModel,
      gFFI.abModel.peersModel,
      gFFI.groupModel.peersModel,
    ]) {
      for (final peer in model.peers) {
        if (peer.id == peerId) return peer;
      }
    }
    return null;
  }

  FFI? _directChatSessionFor(String peerId) {
    final direct = _directChatSessions[peerId];
    if (direct != null) return direct;
    for (final ffi in _directChatSessions.values) {
      if (ffi.chatModel.currentKey.peerId == peerId) return ffi;
    }
    return null;
  }

  Client? _incomingDirectChatClientFor(String peerId) {
    final normalizedPeerId = peerId.trim();
    for (final client in gFFI.serverModel.clients.reversed) {
      if (client.peerId.trim() == normalizedPeerId &&
          client.authorized &&
          client.isChat &&
          !client.disconnected) {
        return client;
      }
    }
    return null;
  }

  Future<void> _maintainTrustedChatSessions() async {
    if (!mounted ||
        bind.mainGetLocalOption(key: 'direct-chat-always-on') != 'Y' ||
        bind.mainGetLocalOption(key: 'direct-chat-auto-reconnect') == 'N') {
      return;
    }
    Map<String, dynamic> policies = const <String, dynamic>{};
    try {
      final raw = bind.mainGetLocalOption(
        key: 'direct-chat-contact-policies',
      );
      if (raw.isNotEmpty) {
        policies = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}
    for (final pairing in DirectPairingStore.load().values) {
      if (!mounted ||
          pairing.companion ||
          policies[pairing.peerId] != 'allow') {
        continue;
      }
      final existing = _directChatSessionFor(pairing.peerId);
      final hasError =
          existing?.ffiModel.lastConnectionError?.isNotEmpty == true;
      if (existing != null && !existing.closed && hasError) {
        await existing.close();
      }
      if (existing == null || existing.closed || hasError) {
        await _startDirectChat(pairing.peerId, activate: false);
      }
    }
  }

  Future<void> _refreshDirectSessions() async {
    await _maintainTrustedChatSessions();
    await gFFI.chatModel.syncActiveCompanionSessions();
  }

  Future<void> _closeDirectChat(String peerId) async {
    var registryKey = peerId;
    var ffi = _directChatSessions[registryKey];
    if (ffi == null) {
      for (final entry in _directChatSessions.entries) {
        if (entry.value.chatModel.currentKey.peerId == peerId) {
          registryKey = entry.key;
          ffi = entry.value;
          break;
        }
      }
    }
    if (ffi == null) return;
    _directChatSessions.remove(registryKey);
    ffi.dialogManager.dismissAll();
    await ffi.close();
    if (mounted && _activeDirectChatPeerId == peerId) {
      setState(() => _activeDirectChatPeerId = null);
    }
  }

  Future<void> _sendFilesFromConversation(String peerId) async {
    final chatFfi = _directChatSessionFor(peerId);
    final outgoingReady = chatFfi != null &&
        !chatFfi.closed &&
        chatFfi.ffiModel.pi.isSet.isTrue &&
        chatFfi.ffiModel.direct == true;
    final incoming = _incomingDirectChatClientFor(peerId);
    if (!outgoingReady && incoming == null) {
      _showConversationNotice(
        translate('Connect to the contact before sending files.'),
      );
      return;
    }

    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    final files = picked?.files.where((file) => file.path != null).toList() ??
        <PlatformFile>[];
    if (files.isEmpty || !mounted) return;

    final ffi = await _ensureDirectFileSession(peerId);
    if (ffi == null || !mounted) return;

    final items = SelectedItems(isLocal: true);
    for (final file in files) {
      items.add(
        Entry()
          ..path = file.path!
          ..name = file.name
          ..size = file.size,
      );
    }

    await ffi.fileModel.localController.sendFiles(
      items,
      ffi.fileModel.remoteController.directoryData(),
    );
    final chatModel = outgoingReady ? chatFfi!.chatModel : gFFI.chatModel;
    chatModel.changeCurrentKey(
      MessageKey(
        peerId,
        outgoingReady ? ChatModel.clientModeID : incoming!.id,
      ),
    );
    for (final file in files) {
      await chatModel.sendFileRecord(
        fileName: file.name,
        fileSize: file.size,
      );
    }
    _showConversationNotice(translate('Direct file transfer started.'));
  }

  Future<FFI?> _ensureDirectFileSession(String peerId) async {
    final existing = _directFileSessions[peerId];
    if (existing != null &&
        !existing.closed &&
        existing.ffiModel.pi.isSet.isTrue &&
        existing.ffiModel.direct == true) {
      return existing;
    }
    if (existing != null) {
      _directFileSessions.remove(peerId);
      await _disposeFileSession(existing);
    }

    final ffi = FFI(null);
    _directFileSessions[peerId] = ffi;
    final endpoint = DirectPairingStore.resolveConnectionTarget(peerId);
    if (endpoint == null) {
      _directFileSessions.remove(peerId);
      _showConversationNotice(
        translate(
            'Direct endpoint required. Scan the PC QR code or enter IP:port.'),
      );
      return null;
    }
    ffi.start(endpoint, isFileTransfer: true, forceRelay: false);
    ffi.dialogManager.showLoading(
      translate('Preparing direct file transfer...'),
      onCancel: () async {
        _directFileSessions.remove(peerId);
        await _disposeFileSession(ffi);
      },
    );

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (ffi.ffiModel.pi.isSet.isTrue) {
        ffi.dialogManager.dismissAll();
        if (ffi.ffiModel.direct != true) {
          _directFileSessions.remove(peerId);
          await _disposeFileSession(ffi);
          _showConversationNotice(
            translate('Direct connection failed. File relay is disabled.'),
          );
          return null;
        }
        final ready = await _waitForFileDirectories(ffi);
        if (ready) return ffi;
        break;
      }
      if (ffi.closed || (ffi.ffiModel.lastConnectionError ?? '').isNotEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    ffi.dialogManager.dismissAll();
    _directFileSessions.remove(peerId);
    final error = ffi.ffiModel.lastConnectionError;
    await _disposeFileSession(ffi);
    _showConversationNotice(
      translate(
        error?.isNotEmpty == true
            ? error!
            : 'Direct file transfer connection timed out.',
      ),
    );
    return null;
  }

  Future<bool> _waitForFileDirectories(FFI ffi) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (ffi.closed) return false;
      final local = ffi.fileModel.localController.directory.value.path;
      final remote = ffi.fileModel.remoteController.directory.value.path;
      if (local.isNotEmpty && remote.isNotEmpty) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<void> _disposeFileSession(FFI ffi) async {
    if (ffi.closed) return;
    try {
      await ffi.fileModel.close();
    } finally {
      await ffi.close();
    }
  }

  void _showConversationNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _buildLocalAvatar(double size) {
    var avatar = '';
    try {
      final userInfo = jsonDecode(
        bind.mainGetLocalOption(key: 'user_info'),
      ) as Map<String, dynamic>;
      avatar = (userInfo['avatar'] ?? '').toString();
    } catch (_) {}
    return buildAvatarWidget(
          avatar: avatar,
          size: size,
          borderRadius: 8,
          fallback: Image.asset('assets/avatar.png', fit: BoxFit.cover),
        ) ??
        Image.asset('assets/avatar.png', fit: BoxFit.cover);
  }

  Future<void> _showIdentityDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 420,
          height: 620,
          child: _buildIdentityPane(dialogContext),
        ),
      ),
    );
  }

  Future<void> _showJoinViewerPage(
    BuildContext context, {
    ViewerInviteLink? invite,
  }) async {
    if (_openingViewerInvite) return;
    _openingViewerInvite = true;
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => JoinViewerPage(
            initialEndpoint: invite?.endpoint ?? _clientIdController.text,
            initialToken: invite?.token,
            initialDisplayName: gFFI.chatModel.me.firstName,
            onJoinRequested: ({
              required endpoint,
              required token,
              required viewerId,
              required displayName,
            }) async {
              await luodaWinManager.newRemoteDesktop(
                endpoint,
                viewerToken: token,
                viewerId: viewerId,
                viewerDisplayName: displayName,
              );
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
      if (mounted) _showJoinViewerPage(context, invite: invite);
    });
  }

  Future<void> _showPairingQrDialog(BuildContext context) async {
    bind.mainCheckConnectStatus();
    final payload = await DirectPairingStore.buildLocalPayload();
    final pairing = DirectPairingStore.parsePayload(payload);
    if (!mounted || pairing == null) {
      _showConversationNotice(
        translate(
            'Direct listener is not ready. Check the LAN address and port.'),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(translate('Pair phone directly')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                translate(
                  'Scan with LDesk on the phone. Pairing data stays on both devices.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 240,
                    gapless: true,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                pairing.preferredEndpoint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                translate('No rendezvous or relay server'),
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color: MyTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(translate('Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _connectDirect(
    BuildContext context,
    String peerIdOrEndpoint, {
    bool isFileTransfer = false,
    bool isViewCamera = false,
    bool isTerminal = false,
    bool isTcpTunneling = false,
  }) async {
    final endpoint =
        DirectPairingStore.resolveConnectionTarget(peerIdOrEndpoint);
    if (endpoint == null) {
      _showConversationNotice(
        translate(
            'Direct endpoint required. Scan the PC QR code or enter IP:port.'),
      );
      return;
    }
    try {
      await connect(
        context,
        endpoint,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal,
        isTcpTunneling: isTcpTunneling,
        forceRelay: false,
      );
    } on TimeoutException catch (error) {
      debugPrint('Direct connection window timed out: $error');
      _showConversationNotice(
        translate('Connection window timed out. Please try again.'),
      );
    } catch (error) {
      debugPrint('Failed to open direct connection window: $error');
      _showConversationNotice(
        translate('Unable to open the connection window.'),
      );
    }
  }

  Future<void> _showToolsMenu(BuildContext context) async {
    final id = _clientIdController.text.trim();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(translate('File Transfer')),
              enabled: id.isNotEmpty,
              onTap: id.isEmpty
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      _connectDirect(context, id, isFileTransfer: true);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(translate('View camera')),
              enabled: id.isNotEmpty,
              onTap: id.isEmpty
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      _connectDirect(context, id, isViewCamera: true);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.terminal_outlined),
              title: Text(translate('Terminal')),
              enabled: id.isNotEmpty,
              onTap: id.isEmpty
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      _connectDirect(context, id, isTerminal: true);
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _handleConversationAction(
    BuildContext context,
    _ConversationAction action,
    String peerId,
  ) {
    switch (action) {
      case _ConversationAction.fileTransfer:
        _sendFilesFromConversation(peerId);
        break;
      case _ConversationAction.remoteAssist:
        _connectDirect(context, peerId);
        break;
      case _ConversationAction.camera:
        _connectDirect(context, peerId, isViewCamera: true);
        break;
      case _ConversationAction.terminal:
        _connectDirect(context, peerId, isTerminal: true);
        break;
      case _ConversationAction.port:
        _connectDirect(context, peerId, isTcpTunneling: true);
        break;
    }
  }

  Widget _buildDeviceNav(BuildContext context, {required bool expanded}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = <int, (IconData, String)>{
      0: (Icons.history_rounded, 'Recent sessions'),
      1: (Icons.star_outline_rounded, 'Favorites'),
      2: (Icons.radar_rounded, 'Discovered'),
      3: (Icons.contact_page_outlined, 'Address book'),
      4: (Icons.devices_rounded, 'Access history devices'),
      5: (Icons.workspace_premium_outlined, 'VIP features'),
    };
    final model = gFFI.peerTabModel;
    final tabsFixed = isOptionFixed(kOptionPeerTabVisible);
    return Container(
      width: expanded ? 264 : 72,
      color: dark ? const Color(0xFF20252E) : Colors.white,
      padding: EdgeInsets.fromLTRB(
        expanded ? 16 : 10,
        18,
        expanded ? 16 : 10,
        12,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: MyTheme.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.public_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              if (expanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'LUODA',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 26),
          Expanded(
            child: AnimatedBuilder(
              animation: model,
              builder: (context, _) {
                final visibleIndexes = model.visibleEnabledOrderedIndexs;
                return ReorderableListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: visibleIndexes.length,
                  buildDefaultDragHandles: false,
                  onReorder: tabsFixed ? (_, __) {} : model.reorder,
                  itemBuilder: (context, index) {
                    final tabIndex = visibleIndexes[index];
                    final item = items[tabIndex]!;
                    final selected = model.currentTab == tabIndex;
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey('device-nav-$tabIndex'),
                      index: index,
                      enabled: !tabsFixed,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Tooltip(
                          message: expanded ? '' : translate(item.$2),
                          child: Material(
                            color: selected
                                ? MyTheme.accent.withOpacity(.10)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () =>
                                  PeerTabPage.selectDesktopTab(tabIndex),
                              child: SizedBox(
                                height: 44,
                                child: Row(
                                  mainAxisAlignment: expanded
                                      ? MainAxisAlignment.start
                                      : MainAxisAlignment.center,
                                  children: [
                                    if (expanded) const SizedBox(width: 12),
                                    Icon(
                                      item.$1,
                                      size: 20,
                                      color: selected
                                          ? MyTheme.accent
                                          : Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color
                                              ?.withOpacity(.72),
                                    ),
                                    if (expanded) ...[
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          translate(item.$2),
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: selected
                                                ? MyTheme.accent
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
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
          ),
          AnimatedBuilder(
            animation: model,
            builder: (context, _) => PopupMenuButton<int>(
              tooltip: translate('More'),
              enabled: !tabsFixed,
              onSelected: (tabIndex) => model.setTabVisible(
                tabIndex,
                !model.isVisibleEnabled[tabIndex],
              ),
              itemBuilder: (context) => [
                for (var tabIndex = 0; tabIndex < items.length; tabIndex++)
                  if (model.isEnabled[tabIndex])
                    CheckedPopupMenuItem<int>(
                      value: tabIndex,
                      checked: model.isVisibleEnabled[tabIndex],
                      child: Text(translate(items[tabIndex]!.$2)),
                    ),
              ],
              child: SizedBox(
                height: 40,
                child: Row(
                  mainAxisAlignment: expanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    if (expanded) const SizedBox(width: 12),
                    const Icon(Icons.tune_rounded, size: 20),
                    if (expanded) ...[
                      const SizedBox(width: 12),
                      Expanded(child: Text(translate('More'))),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 20),
          Tooltip(
            message: expanded ? '' : translate('Settings'),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: expanded ? 12 : 8,
              ),
              leading: const Icon(Icons.settings_outlined, size: 20),
              title: expanded ? Text(translate('Settings')) : null,
              onTap: DesktopTabPage.onAddSetting,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityPane(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final outgoingOnly = bind.isOutgoingOnly();
    return ColoredBox(
      color: dark ? const Color(0xFF20252E) : Colors.white,
      child: ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, _) {
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!outgoingOnly) ...[
                          Text(
                            translate('My Identity'),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          _buildIdentityCard(context, model),
                          const SizedBox(height: 22),
                        ],
                        Text(
                          translate('Quick Actions'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: ConnectionPage.focusRemoteId,
                            icon: const Icon(
                              Icons.add_rounded,
                              size: 20,
                            ),
                            label: Text(translate('Join Session')),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: OutlinedButton.icon(
                            onPressed: () => DesktopTabPage.onAddSetting(
                              initialPage: SettingsTabKey.safety,
                            ),
                            icon: const Icon(Icons.security_outlined, size: 19),
                            label: Text(translate('Security')),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (!outgoingOnly) buildPresetPasswordWarning(),
                        if (bind.isCustomClient())
                          Align(
                            alignment: Alignment.center,
                            child: loadPowered(context),
                          ),
                        Obx(() => buildHelpCards(stateGlobal.updateUrl.value)),
                        buildPluginEntry(),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 52, child: OnlineStatusWidget()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildIdentityCard(BuildContext context, ServerModel model) {
    final publicIP = bind.mainGetOptionSync(key: 'public-ip');
    final lanIP = bind.mainGetOptionSync(key: 'lan-ip');
    final port = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    final upnpStatus = bind.mainGetOptionSync(key: 'upnp-status');
    String address(String ip) {
      if (ip.isEmpty || port.isEmpty) return ip;
      final host = ip.contains(':') && !ip.startsWith('[') ? '[$ip]' : ip;
      return host + ':' + port;
    }

    final temporary = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF181C23) : const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _identityValue(
            context,
            translate('ID'),
            model.serverId.text,
            prominent: true,
            icon: Icons.copy_rounded,
            onTap: () => _copyValue(model.serverId.text),
          ),
          const SizedBox(height: 12),
          _identityValue(
            context,
            translate('One-time Password'),
            model.serverPasswd.text,
            icon:
                temporary ? Icons.refresh_rounded : Icons.lock_outline_rounded,
            onTap: temporary ? () => bind.mainUpdateTemporaryPassword() : null,
            onCopy: () => _copyValue(model.serverPasswd.text),
            obscure: true,
            revealed: _passwordVisible,
            onToggleVisibility: () {
              setState(() => _passwordVisible = !_passwordVisible);
            },
          ),
          const Divider(height: 22),
          _addressValue(
            context,
            translate('Public IP:port'),
            address(publicIP),
            status: upnpStatus,
            statusColor: _directStatusColor(upnpStatus),
            statusTooltip: translate(_directStatusTip(upnpStatus)),
          ),
          const SizedBox(height: 10),
          _addressValue(context, translate('LAN IP:port'), address(lanIP)),
        ],
      ),
    );
  }

  Widget _identityValue(
    BuildContext context,
    String label,
    String value, {
    required IconData icon,
    VoidCallback? onTap,
    VoidCallback? onCopy,
    VoidCallback? onToggleVisibility,
    bool obscure = false,
    bool revealed = true,
    bool prominent = false,
  }) {
    final available = value.isNotEmpty;
    final displayValue = !available
        ? translate('Not available')
        : obscure && !revealed
            ? List.filled(value.runes.length, '\u2022').join()
            : value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withOpacity(.65),
                ),
              ),
            ),
            if (onToggleVisibility != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: translate(
                  revealed ? 'Hide Password' : 'Show Password',
                ),
                onPressed: onToggleVisibility,
                icon: Icon(
                  revealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
              ),
            if (onCopy != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: translate('Copy to clipboard'),
                onPressed: available ? onCopy : null,
                icon: const Icon(Icons.copy_rounded, size: 17),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: translate(
                prominent
                    ? 'Copy to clipboard'
                    : onTap == null
                        ? 'Use permanent password'
                        : 'Refresh Password',
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Tooltip(
          message: displayValue,
          child: Text(
            displayValue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: prominent ? 20 : 15,
              fontWeight: FontWeight.w700,
              color: available ? null : Theme.of(context).disabledColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _addressValue(BuildContext context, String label, String value,
      {String? status, Color? statusColor, String? statusTooltip}) {
    final available = value.isNotEmpty;
    final displayValue = available ? value : translate('Not available');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withOpacity(.65),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: translate('Copy to clipboard'),
              onPressed: available ? () => _copyValue(value) : null,
              icon: const Icon(Icons.copy_rounded, size: 16),
            ),
            if (available && statusColor != null)
              Tooltip(
                message: statusTooltip ?? '',
                child: Semantics(
                  label: statusTooltip,
                  child: Icon(
                    _directStatusIcon(status ?? ''),
                    size: 15,
                    color: statusColor,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Tooltip(
          message: displayValue,
          child: Text(
            displayValue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: available ? null : Theme.of(context).disabledColor,
            ),
          ),
        ),
      ],
    );
  }

  void _copyValue(String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    showToast(translate('Copied'));
  }

  Color _directStatusColor(String status) {
    if (status == 'ok') return Colors.green;
    if (status == 'fail') return Colors.orange;
    if (status == 'unsupported') return Colors.blueGrey;
    return Colors.grey;
  }

  IconData _directStatusIcon(String status) {
    if (status == 'ok') return Icons.check_circle_outline_rounded;
    if (status == 'fail') return Icons.error_outline_rounded;
    if (status == 'disabled') return Icons.pause_circle_outline_rounded;
    if (status == 'unsupported') return Icons.info_outline_rounded;
    return Icons.help_outline_rounded;
  }

  String _directStatusTip(String status) {
    if (status == 'ok') return 'upnp_mapping_ready_tip';
    if (status == 'fail') return 'upnp_mapping_failed_tip';
    if (status == 'disabled') return 'direct_listener_disabled_tip';
    if (status == 'unsupported') return 'upnp_mapping_unsupported_tip';
    return 'upnp_mapping_unknown_tip';
  }

  Widget buildLeftPane(BuildContext context) {
    if (widget.isClientOnly) {
      return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: SizedBox(
          width: kCustomClientWindowSize.width,
          child: Column(
            children: [
              Expanded(
                child: Column(
                  key: _childKey,
                  children: [
                    // 圆形头像 + LUODA 远程协助标题
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 20, bottom: 8),
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                color: MyTheme.accent,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                "assets/avatar.png",
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, error, stackTrace) => Icon(
                                  Icons.computer,
                                  size: 32,
                                  color: MyTheme.accent,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            "LDesk ${translate('Remote assistance')}",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.titleLarge?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 本机ID
                    buildIDBoard(context),
                    SizedBox(height: 4),
                    // 密码
                    buildPasswordBoard(context),
                    SizedBox(height: 4),
                    // IP:端口
                    buildDirectAccessBoard(context),
                    Spacer(flex: 3),
                    // 底部连接状态 —— 加大间距防止紧贴 IP 栏
                    SizedBox(
                      height: 60,
                      child: OnlineStatusWidget(
                        onSvcStatusChanged: () {
                          if (isInHomePage()) {
                            Future.delayed(
                              const Duration(milliseconds: 300),
                              () {
                                _updateWindowSize();
                              },
                            );
                          }
                        },
                      ),
                    ).marginOnly(left: 6, right: 6, bottom: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      if (bind.isCustomClient())
        Align(alignment: Alignment.center, child: loadPowered(context)),
      // 圆形头像 + LUODA 远程协助
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 20, bottom: 8),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: MyTheme.accent, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/avatar.png',
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, error, stackTrace) =>
                      Icon(Icons.computer, size: 40, color: MyTheme.accent),
                ),
              ),
            ),
            Text(
              "LDesk ${translate('Remote assistance')}",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            SizedBox(height: 10),
          ],
        ),
      ),
      if (!isOutgoingOnly) buildIDBoard(context),
      if (!isOutgoingOnly) buildPasswordBoard(context),
      if (!isOutgoingOnly) buildDirectAccessBoard(context),
      FutureBuilder<Widget>(
        future: Future.value(
          Obx(() => buildHelpCards(stateGlobal.updateUrl.value)),
        ),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
      buildPluginEntry(),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6),
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;

    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: isIncomingOnly ? 300.0 : 220.0,
        color: Theme.of(context).colorScheme.background,
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(key: _childKey, children: children),
                ),
                Expanded(child: Container()),
              ],
            ),
            Positioned(
              bottom: 6,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  // 设置按钮
                  Expanded(
                    child: Obx(
                      () => InkWell(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.settings_outlined,
                              color: _settingsHover.value
                                  ? textColor
                                  : Colors.grey.withOpacity(0.5),
                              size: 18,
                            ),
                            Text(
                              translate("Settings"),
                              style: TextStyle(
                                fontSize: 10,
                                color: _settingsHover.value
                                    ? textColor
                                    : Colors.grey.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          if (DesktopSettingPage.tabKeys.isNotEmpty) {
                            DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0],
                            );
                          }
                        },
                        onHover: (value) => _settingsHover.value = value,
                      ),
                    ),
                  ),
                  // 中继服务器按钮
                  Expanded(
                    child: Obx(
                      () => InkWell(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_outlined,
                              color: _relayHover.value
                                  ? textColor
                                  : Colors.grey.withOpacity(0.5),
                              size: 18,
                            ),
                            Text(
                              translate("Network"),
                              style: TextStyle(
                                fontSize: 10,
                                color: _relayHover.value
                                    ? textColor
                                    : Colors.grey.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          DesktopSettingPage.switch2page(
                            SettingsTabKey.network,
                          );
                        },
                        onHover: (value) => _relayHover.value = value,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(key: ConnectionPage.pageKey),
    );
  }

  /// 客户端专用版：远程ID输入框，回车直接连接
  Widget _buildClientIDField() {
    return Container(
      margin: const EdgeInsets.only(left: 14, right: 14, top: 16),
      child: TextFormField(
        controller: _clientIdController,
        focusNode: _clientIdFocusNode,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          filled: true,
          fillColor: Theme.of(context).colorScheme.background.withOpacity(0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Theme.of(context).dividerColor),
          ),
          hintText: translate('Enter Remote ID'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
        onFieldSubmitted: (value) {
          _onClientConnect(value, context);
        },
      ),
    );
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      height: 62,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: MyTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ).marginOnly(top: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translate("ID"),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(
                            context,
                          ).textTheme.titleLarge?.color?.withOpacity(0.45),
                        ),
                      ).marginOnly(top: 8),
                    ],
                  ),
                  GestureDetector(
                    onDoubleTap: () {
                      Clipboard.setData(
                        ClipboardData(text: model.serverId.text),
                      );
                      showToast(translate("Copied"));
                    },
                    child: TextFormField(
                      controller: model.serverId,
                      readOnly: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        isDense: true,
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 0,
                      ),
                    ).workaroundFreezeLinuxMint(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, child) {
          return buildPasswordBoard2(context, model);
        },
      ),
    );
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 13, bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: MyTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor?.withOpacity(0.45),
                    ),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              Clipboard.setData(
                                ClipboardData(text: model.serverPasswd.text),
                              );
                              showToast(translate("Copied"));
                            }
                          },
                          child: TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).colorScheme.background.withOpacity(0.5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              isDense: true,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              letterSpacing: 0,
                            ),
                          ).workaroundFreezeLinuxMint(),
                        ),
                      ),
                      if (showOneTime)
                        AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Tooltip(
                            message: translate('Refresh Password'),
                            child: Obx(
                              () => RotatedBox(
                                quarterTurns: 2,
                                child: Icon(
                                  Icons.refresh,
                                  color: refreshHover.value
                                      ? textColor
                                      : Color(0xFFDDDDDD),
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          onHover: (value) => refreshHover.value = value,
                        ).marginOnly(right: 8, top: 4),
                      // 客户端版：不显示"修改密码"按钮
                      if (!bind.isDisableSettings() && !bind.isCustomClient())
                        InkWell(
                          child: Tooltip(
                            message: translate('Change Password'),
                            child: Obx(
                              () => Icon(
                                Icons.edit,
                                color: editHover.value
                                    ? textColor
                                    : Color(0xFFDDDDDD),
                                size: 22,
                              ).marginOnly(right: 8, top: 4),
                            ),
                          ),
                          onTap: () => DesktopSettingPage.switch2page(
                            SettingsTabKey.safety,
                          ),
                          onHover: (value) => editHover.value = value,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  buildDirectAccessBoard(BuildContext context) {
    final publicIP = bind.mainGetOptionSync(key: 'public-ip');
    final lanIP = bind.mainGetOptionSync(key: 'lan-ip');
    final directPort = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    // UPnP 状态：通过 option "upnp-status" 读取（在 rust 侧 direct_server 启动后设置）
    final upnpStatus = bind.mainGetOptionSync(key: 'upnp-status');
    final textColor = Theme.of(context).textTheme.titleLarge?.color;

    // 显示用："地址:端口"，没有则只显示地址，再没有则"Not available"
    String address(String ip) {
      if (ip.isEmpty || directPort.isEmpty) return ip;
      final host = ip.contains(':') && !ip.startsWith('[') ? '[$ip]' : ip;
      return host + ':' + directPort;
    }

    final publicAddr = address(publicIP);
    final lanAddr = address(lanIP);

    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            translate('Direct IP Access'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor?.withOpacity(0.45),
            ),
          ),
          SizedBox(height: 6),
          // 公网 IP 卡片 —— 独立蓝色竖线
          _ipCard(
            context: context,
            label: translate('Public network'),
            addr: publicAddr,
            hasAddr: publicAddr.isNotEmpty,
            textColor: textColor,
            upnpStatus: upnpStatus,
            showUpnp: true,
          ),
          SizedBox(height: 6),
          // 内网 IP 卡片 —— 独立蓝色竖线
          _ipCard(
            context: context,
            label: translate('Local network'),
            addr: lanAddr,
            hasAddr: lanAddr.isNotEmpty,
            textColor: textColor,
            upnpStatus: '',
            showUpnp: false,
          ),
        ],
      ),
    );
  }

  // 一行 IP 显示：左侧独立蓝色竖线 + 标签 + IP:端口
  //鼠标移到 IP 上时，Tooltip 弹窗显示完整地址（防止因宽度不够被截断）
  Widget _ipCard({
    required BuildContext context,
    required String label,
    required String addr,
    required bool hasAddr,
    required Color? textColor,
    required String upnpStatus,
    required bool showUpnp,
  }) {
    final naText = translate('Not available');
    final displayText = addr.isNotEmpty ? addr : naText;
    // Tooltip 完整文本，悬停弹窗显示用，UPnP 状态一并放入弹窗
    final tooltipText = showUpnp && addr.isNotEmpty
        ? '$addr\n${translate(_directStatusTip(upnpStatus))}'
        : (addr.isNotEmpty ? addr : naText);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 30,
          decoration: BoxDecoration(
            color: MyTheme.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor?.withOpacity(0.5),
            ),
          ),
        ),
        Expanded(
          child: Tooltip(
            message: tooltipText,
            preferBelow: false,
            waitDuration: Duration(milliseconds: 200),
            child: GestureDetector(
              onDoubleTap: () {
                if (addr.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: addr));
                  showToast(translate("Copied"));
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.background.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          letterSpacing: 0,
                          color:
                              hasAddr ? textColor : textColor?.withOpacity(0.4),
                        ),
                      ),
                    ),
                    if (showUpnp && addr.isNotEmpty) ...[
                      SizedBox(width: 4),
                      Semantics(
                        label: translate(_directStatusTip(upnpStatus)),
                        child: Icon(
                          _directStatusIcon(upnpStatus),
                          size: 13,
                          color: _directStatusColor(upnpStatus),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('luoda')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://dicad.cn/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
        "Status",
        "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
        btnText,
        onPressed,
        closeButton: true,
        help: isToUpdate ? 'Changelog' : null,
        link: isToUpdate
            ? 'https://github.com/luoda/luoda/releases/tag/${bind.mainGetNewVersion()}'
            : null,
      );
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      // Installation prompt removed for LUODA
      if (false && !bind.mainIsInstalled()) {
        return buildInstallCard(
          "",
          bind.isOutgoingOnly() ? "" : "install_tip",
          "Install",
          () async {
            await luodaWinManager.closeAllSubWindows();
            bind.mainGotoInstall();
          },
        );
      } else if (false && bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
          "Status",
          "Your installation is lower version.",
          "Click to upgrade",
          () async {
            await luodaWinManager.closeAllSubWindows();
            bind.mainUpdateMe();
          },
        );
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard(
          "Permissions",
          "config_screen",
          "Configure",
          () async {
            bind.mainIsCanScreenRecording(prompt: true);
            watchIsCanScreenRecording = true;
          },
          help: 'Help',
          link: translate("doc_mac_permission"),
        );
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard(
          "Permissions",
          "config_acc",
          "Configure",
          () async {
            bind.mainIsProcessTrusted(prompt: true);
            watchIsProcessTrust = true;
          },
          help: 'Help',
          link: translate("doc_mac_permission"),
        );
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard(
          "Permissions",
          "config_input",
          "Configure",
          () async {
            bind.mainIsCanInputMonitoring(prompt: true);
            watchIsInputMonitoring = true;
          },
          help: 'Help',
          link: translate("doc_mac_permission"),
        );
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(
            buildInstallCard(
              "Warning",
              "selinux_tip",
              "",
              () async {},
              marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
              help: 'Help',
              link: 'https://dicad.cn/docs/en/client/linux/#permissions-issue',
              closeButton: true,
              closeOption: keyShowSelinuxHelpTip,
            ),
          );
        }
      }
      // Wayland warnings removed per user request
      if (LinuxCards.isNotEmpty) {
        return Column(children: LinuxCards);
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(
    String title,
    String content,
    String btnText,
    GestureTapCallback onPressed, {
    double marginTop = 20.0,
    String? help,
    String? link,
    bool? closeButton,
    String? closeOption,
  }) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
            0,
            marginTop,
            0,
            bind.isIncomingOnly() ? marginTop : 0,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              ),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: (title.isNotEmpty
                      ? <Widget>[
                          Center(
                            child: Text(
                              translate(title),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ).marginOnly(bottom: 6),
                          ),
                        ]
                      : <Widget>[]) +
                  <Widget>[
                    if (content.isNotEmpty)
                      Text(
                        translate(content),
                        style: TextStyle(
                          height: 1.5,
                          color: Colors.white,
                          fontWeight: FontWeight.normal,
                          fontSize: 13,
                        ),
                      ).marginOnly(bottom: 20),
                  ] +
                  (btnText.isNotEmpty
                      ? <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FixedWidthButton(
                                width: 150,
                                padding: 8,
                                isOutline: true,
                                text: translate(btnText),
                                textColor: Colors.white,
                                borderColor: Colors.white,
                                textSize: 20,
                                radius: 10,
                                onTap: onPressed,
                                icon: btnText == 'Download'
                                    ? Icons.download
                                    : Icons.system_update,
                              ),
                            ],
                          ),
                        ]
                      : <Widget>[]) +
                  (help != null
                      ? <Widget>[
                          Center(
                            child: InkWell(
                              onTap: () async =>
                                  await launchUrl(Uri.parse(link!)),
                              child: Text(
                                translate(help),
                                style: TextStyle(
                                  decoration: TextDecoration.underline,
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ).marginOnly(top: 6),
                          ),
                        ]
                      : <Widget>[]),
            ),
          ),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    pendingViewerInvite.addListener(_handlePendingViewerInvite);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingViewerInvite();
    });
    bind.mainLoadRecentPeers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshDirectSessions());
    });
    _directChatKeepAliveTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(_refreshDirectSessions()),
    );
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        // When service starts (v becomes false), refresh the temporary password
        if (!v) {
          bind.mainGetTemporaryPassword();
        }
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // luodaWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
      // 1秒定时刷新IP:端口显示
      _refreshIpDisplay();
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    luodaWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse:
          return true;
      }

      return false;
    }

    luodaWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId",
        );
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
          (await window_size.getScreenList()).map(screenToMap).toList(),
        );
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await luodaWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await luodaWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
          viewerToken: call.arguments['viewerToken'],
          viewerId: call.arguments['viewerId'],
          viewerDisplayName: call.arguments['viewerDisplayName'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy'],
        );
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await luodaWinManager.moveTabToNewWindow(
            windowId,
            args[1],
            args[2],
            windowType,
          );
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await luodaWinManager.openMonitorSession(
          windowId,
          peerId,
          display,
          displayCount,
          screenRect,
          windowType,
        );
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
            await luodaWinManager.getOtherRemoteWindowCoords(windowId),
          );
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    if (widget.isClientOnly) return;
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  _refreshIpDisplay() {
    final ip = bind.mainGetOptionSync(key: 'public-ip');
    final lanIp = bind.mainGetOptionSync(key: 'lan-ip');
    final port = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    if (ip != _lastIp || lanIp != _lastLanIp || port != _lastPort) {
      _lastIp = ip;
      _lastLanIp = lanIp;
      _lastPort = port;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    pendingViewerInvite.removeListener(_handlePendingViewerInvite);
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    _directChatKeepAliveTimer?.cancel();
    for (final ffi in _directChatSessions.values) {
      unawaited(ffi.close());
    }
    _directChatSessions.clear();
    for (final ffi in _directFileSessions.values) {
      unawaited(_disposeFileSession(ffi));
    }
    _directFileSessions.clear();
    _clientIdController.dispose();
    _contactSearchController.dispose();
    _clientIdFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          }),
        ],
      ),
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: showStatusTipOnMobile ? 0.0 : 6.0),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: translate('Password'),
                      errorText: errMsg0.isNotEmpty ? errMsg0 : null,
                    ),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(height: showStatusTipOnMobile ? 0.0 : 8.0),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: translate('Confirmation'),
                      errorText: errMsg1.isNotEmpty ? errMsg1 : null,
                    ),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(
                    Icons.info,
                    color: Colors.amber,
                    size: 18,
                  ).marginOnly(right: 6),
                  Expanded(
                    child: Text(
                      statusTip,
                      style: const TextStyle(fontSize: 13, height: 1.1),
                    ),
                  ),
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(height: showStatusTipOnMobile ? 0.0 : 8.0),
            Obx(
              () => Wrap(
                runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                spacing: 4,
                children: rules.map((e) {
                  var checked = e.validate(rxPass.value.trim());
                  return Chip(
                    label: Text(
                      e.name,
                      style: TextStyle(
                        color: checked
                            ? const Color(0xFF0A9471)
                            : Color.fromARGB(255, 198, 86, 157),
                      ),
                    ),
                    backgroundColor: checked
                        ? const Color(0xFFD0F7ED)
                        : Color.fromARGB(255, 247, 205, 232),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok = await bind.mainSetPermanentPasswordWithResult(
              password: "",
            );
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
            backgroundColor: MaterialStatePropertyAll(Colors.red),
          ),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [cancelButton, if (localPasswordSet) removeButton, okButton];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}
