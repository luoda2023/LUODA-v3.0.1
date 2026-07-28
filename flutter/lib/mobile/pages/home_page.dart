import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/mobile/pages/server_page.dart';
import 'package:luoda_flutter/mobile/pages/settings_page.dart';
import 'package:luoda_flutter/web/settings_page.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../common.dart';
import '../../common/direct_pairing.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/chat_model.dart';
import '../../models/file_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'connection_page.dart';
import 'first_run_wizard.dart';
import 'scan_page.dart';

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  final List<PageShape> _pages = [];
  int _chatPageTabIndex = -1;
  int _contactsPageTabIndex = -1;
  bool _chatDetailOpen = false;
  FFI? _directFileSession;
  String _directFilePeerId = '';
  FFI? _companionSyncSession;
  String _companionSyncPeerId = '';
  Timer? _directPairingSyncTimer;
  bool get isChatPageCurrentTab => isMobile && _chatDetailOpen;

  void selectChatPage() {
    if (_chatPageTabIndex < 0) return;
    if (_selectedIndex != _chatPageTabIndex) {
      setState(() => _selectedIndex = _chatPageTabIndex);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openCurrentConversation());
    });
  }

  void _selectContactsPage() {
    if (_contactsPageTabIndex < 0 || _selectedIndex == _contactsPageTabIndex) {
      return;
    }
    setState(() => _selectedIndex = _contactsPageTabIndex);
  }

  void _openConversation(MessageKey key) {
    gFFI.chatModel.changeCurrentKey(key);
    gFFI.chatModel.mobileClearClientUnread(key.connId);
    unawaited(_openCurrentConversation());
  }

  Future<void> _openCurrentConversation() async {
    final key = gFFI.chatModel.currentKey;
    if (!mounted || _chatDetailOpen || key.peerId.isEmpty) return;
    _chatDetailOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AnimatedBuilder(
            animation: gFFI.chatModel,
            builder: (context, __) {
              final user = gFFI.chatModel.currentUser;
              final currentKey = gFFI.chatModel.currentKey;
              final name = (user?.firstName ?? '').trim();
              return Scaffold(
                appBar: AppBar(
                  centerTitle: true,
                  elevation: 0,
                  title: Text(
                    name.isEmpty ? currentKey.peerId : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.search_rounded),
                      tooltip: translate('Search Messages'),
                      onPressed: () {
                        gFFI.chatModel.toggleChatSearch();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.image_outlined),
                      tooltip: translate('Send Image'),
                      onPressed: _pickImageOrFile,
                    ),
                    PopupMenuButton<String>(
                      tooltip: translate('More'),
                      onSelected: (action) {
                        final peerId = gFFI.chatModel.currentKey.peerId;
                        if (action == 'mute') {
                          gFFI.chatSettingsModel.toggleMute(peerId);
                        } else if (action == 'block') {
                          gFFI.chatSettingsModel.toggleBlock(peerId);
                        }
                      },
                      itemBuilder: (context) {
                        final peerId = gFFI.chatModel.currentKey.peerId;
                        return [
                          PopupMenuItem(
                            value: 'mute',
                            child: Text(
                              gFFI.chatSettingsModel.isMuted(peerId)
                                  ? translate('Unmute')
                                  : translate('Mute'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'block',
                            child: Text(
                              gFFI.chatSettingsModel.isBlocked(peerId)
                                  ? translate('Unblock')
                                  : translate('Block'),
                            ),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
                body: ChatPage(
                  type: ChatPageType.mobileMain,
                  onAttachFile: _sendDirectChatFiles,
                  onRemoteAssist: _startRemoteFromChat,
                ),
              );
            },
          ),
        ),
      );
    } finally {
      _chatDetailOpen = false;
    }
  }

  Future<void> syncPairingsNow() => _syncLatestPairing();

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    initPages();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncLatestPairing());
      // Show one-time permission wizard on first install (Android only)
      if (isAndroid) {
        unawaited(FirstRunPermissionWizard.showIfNeeded(context));
      }
    });
    _directPairingSyncTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(_syncLatestPairing()),
    );
  }

  void initPages() {
    _pages.clear();
    if (isMobile) {
      _chatPageTabIndex = _pages.length;
      _pages.add(_MobileMessagesPage(
        onOpenConversation: _openConversation,
        onNewConversation: _selectContactsPage,
      ));
    }
    if (!bind.isIncomingOnly()) {
      _contactsPageTabIndex = _pages.length;
      _pages.add(ConnectionPage(
        appBarActions: [
          IconButton(
            tooltip: translate('Pair phone'),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () async {
              final pairing = await Navigator.of(context).push<DirectPairing>(
                MaterialPageRoute(builder: (_) => ScanPage()),
              );
              if (pairing != null) await _syncLatestPairing();
            },
          ),
        ],
      ));
    } else {
      _contactsPageTabIndex = -1;
    }
    if (isMobile && isAndroid && !bind.isOutgoingOnly()) {
      _pages.add(ServerPage());
    }
    _pages.add(SettingsPage());
  }

  void _startRemoteFromChat() {
    final peerId = gFFI.chatModel.currentKey.peerId.trim();
    if (peerId.isEmpty) return;
    final endpoint = DirectPairingStore.resolveConnectionTarget(peerId);
    if (endpoint == null) {
      showToast(translate(
        'Direct endpoint required. Scan the PC QR code or enter IP:port.',
      ));
      return;
    }
    connect(context, endpoint, forceRelay: false);
  }

  Future<void> _syncLatestPairing() async {
    if (!mounted || !isMobile) return;
    if (bind.mainGetLocalOption(key: 'direct-chat-always-on') != 'Y') return;
    await gFFI.serverModel.updateClientState();
    if (!mounted) return;
    final pairing = DirectPairingStore.latestCompanion();
    if (pairing == null) return;
    final existing = _companionSyncSession;
    if (existing != null &&
        !existing.closed &&
        _companionSyncPeerId == pairing.peerId &&
        existing.ffiModel.pi.isSet.isTrue &&
        existing.ffiModel.direct == true) {
      await existing.chatModel.requestCompanionSync(
        peerId: pairing.peerId,
        connId: ChatModel.clientModeID,
      );
      return;
    }
    if (existing != null) {
      await existing.close();
    }
    final ffi = FFI(const Uuid().v4obj());
    ffi.suppressConnectionDialogs = true;
    _companionSyncSession = ffi;
    _companionSyncPeerId = pairing.peerId;
    ffi.chatModel.changeCurrentKey(
      MessageKey(pairing.peerId, ChatModel.clientModeID),
    );
    ffi.chatModel.updatePeerIdentity(
      pairing.peerId,
      displayName: pairing.displayName,
      avatar: '',
    );
    ffi.start(
      pairing.connectionTarget,
      isChat: true,
      forceRelay: false,
    );
  }

  /// Show WeChat-style bottom sheet: Take Photo / Gallery / File
  Future<void> _pickImageOrFile() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: Text(translate('Take Photo')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(translate('Choose from Gallery')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_rounded),
              title: Text(translate('Send File')),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'file') {
      await _sendDirectChatFiles();
    } else {
      final type = action == 'camera' ? FileType.camera : FileType.image;
      final picked = await FilePicker.platform.pickFiles(type: type, allowMultiple: true);
      final files = picked?.files.where((f) => f.path != null).toList() ?? [];
      if (files.isEmpty) return;
      await _sendPickedFiles(files);
    }
  }

  Future<void> _sendDirectChatFiles() async {
    final currentKey = gFFI.chatModel.currentKey;
    final peerId = currentKey.peerId.trim();
    final connected = currentKey.isOut
        ? gFFI.connType == ConnType.chat &&
            gFFI.ffiModel.pi.isSet.isTrue &&
            gFFI.ffiModel.direct == true
        : gFFI.serverModel.clients.any(
            (client) =>
                client.id == currentKey.connId &&
                client.isChat &&
                !client.disconnected,
          );
    if (peerId.isEmpty || !connected) {
      showToast(translate('Connect to the contact before sending files.'));
      return;
    }

    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    final files = picked?.files.where((file) => file.path != null).toList() ??
        <PlatformFile>[];
    if (files.isEmpty || !mounted) return;
    await _sendPickedFiles(files);
  }

  Future<void> _sendPickedFiles(List<PlatformFile> files) async {
    final currentKey = gFFI.chatModel.currentKey;
    final peerId = currentKey.peerId.trim();
    final connected = currentKey.isOut
        ? gFFI.connType == ConnType.chat &&
            gFFI.ffiModel.pi.isSet.isTrue &&
            gFFI.ffiModel.direct == true
        : gFFI.serverModel.clients.any(
            (client) =>
                client.id == currentKey.connId &&
                client.isChat &&
                !client.disconnected,
          );
    if (peerId.isEmpty || !connected) {
      showToast(translate('Connect to the contact before sending files.'));
      return;
    }
    // File size guard: reject individual files > 500 MB or total > 2 GB
    const kMaxSingleFileBytes = 500 * 1024 * 1024;
    const kMaxTotalBytes = 2 * 1024 * 1024 * 1024;
    var totalBytes = 0;
    for (final f in files) {
      if (f.size > kMaxSingleFileBytes) {
        showToast(translate('File too large') + ': ${f.name} (${_fmtSize(f.size)})');
        return;
      }
      totalBytes += f.size;
    }
    if (totalBytes > kMaxTotalBytes) {
      showToast(translate('Total size exceeds 2 GB limit'));
      return;
    }
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
    if (gFFI.chatModel.currentKey.peerId.trim() == peerId) {
      for (final file in files) {
        await gFFI.chatModel.sendFileRecord(
          fileName: file.name,
          fileSize: file.size,
          localPath: file.path!,
        );
      }
    }
    showToast(translate('Direct file transfer started.'));
  }

  Future<FFI?> _ensureDirectFileSession(String peerId) async {
    // ... existing code ...

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<FFI?> _ensureDirectFileSession(String peerId) async {
    final existing = _directFileSession;
    if (existing != null &&
        _directFilePeerId == peerId &&
        !existing.closed &&
        existing.ffiModel.pi.isSet.isTrue &&
        existing.ffiModel.direct == true) {
      return existing;
    }
    if (existing != null) {
      _directFileSession = null;
      _directFilePeerId = '';
      await _disposeDirectFileSession(existing);
    }

    final endpoint = DirectPairingStore.resolveConnectionTarget(peerId);
    if (endpoint == null) {
      showToast(translate(
        'Direct endpoint required. Scan the PC QR code or enter IP:port.',
      ));
      return null;
    }
    final ffi = FFI(const Uuid().v4obj());
    ffi.suppressConnectionDialogs = true;
    _directFileSession = ffi;
    _directFilePeerId = peerId;
    ffi.start(endpoint, isFileTransfer: true, forceRelay: false);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (ffi.ffiModel.pi.isSet.isTrue) {
        ffi.dialogManager.dismissAll();
        if (ffi.ffiModel.direct != true) {
          _directFileSession = null;
          _directFilePeerId = '';
          await _disposeDirectFileSession(ffi);
          showToast(
            translate('Direct connection failed. File relay is disabled.'),
          );
          return null;
        }
        if (await _waitForFileDirectories(ffi)) return ffi;
        break;
      }
      if (ffi.closed || (ffi.ffiModel.lastConnectionError ?? '').isNotEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    ffi.dialogManager.dismissAll();
    if (_directFileSession == ffi) {
      _directFileSession = null;
      _directFilePeerId = '';
    }
    final error = ffi.ffiModel.lastConnectionError;
    await _disposeDirectFileSession(ffi);
    showToast(
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

  Future<void> _disposeDirectFileSession(FFI ffi) async {
    if (ffi.closed) return;
    try {
      await ffi.fileModel.close();
    } finally {
      await ffi.close();
    }
  }

  @override
  void dispose() {
    _directPairingSyncTimer?.cancel();
    final fileSession = _directFileSession;
    _directFileSession = null;
    if (fileSession != null) {
      unawaited(_disposeDirectFileSession(fileSession));
    }
    final companionSession = _companionSyncSession;
    _companionSyncSession = null;
    if (companionSession != null && !companionSession.closed) {
      unawaited(companionSession.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          if (_selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
          } else {
            return true;
          }
          return false;
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? MyTheme.canvasDark
              : const Color(0xFFEDEDED),
          appBar: AppBar(
            centerTitle: true,
            toolbarHeight: 52,
            elevation: 0,
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? MyTheme.surfaceDark
                : const Color(0xFFEDEDED),
            title: appTitle(),
            actions: _pages.elementAt(_selectedIndex).appBarActions,
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: BottomNavigationBar(
              key: navigationBarKey,
              items: _pages
                  .map((page) => BottomNavigationBarItem(
                        icon: page.icon,
                        label: page.title,
                      ))
                  .toList(),
              currentIndex: _selectedIndex,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? MyTheme.surfaceDark
                  : const Color(0xFFF7F7F7),
              selectedItemColor: MyTheme.accent,
              unselectedItemColor:
                  Theme.of(context).brightness == Brightness.dark
                      ? MyTheme.mutedDark
                      : const Color(0xFF5D687A),
              selectedFontSize: 12,
              unselectedFontSize: 12,
              selectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
              iconSize: 24,
              elevation: 0,
              onTap: (index) => setState(() {
                // close chat overlay when go chat page
                if (_selectedIndex != index) {
                  _selectedIndex = index;
                  if (_selectedIndex == _chatPageTabIndex) {
                    gFFI.chatModel.hideChatIconOverlay();
                    gFFI.chatModel.hideChatWindowOverlay();
                    gFFI.chatModel.mobileClearClientUnread(
                        gFFI.chatModel.currentKey.connId);
                  }
                }
              }),
            ),
          ),
          body: _pages.elementAt(_selectedIndex),
        ));
  }

  Widget appTitle() {
    return Text(
      _pages.elementAt(_selectedIndex).title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

}

class _MobileMessagesPage extends StatefulWidget implements PageShape {
  const _MobileMessagesPage({
    required this.onOpenConversation,
    required this.onNewConversation,
  });

  final ValueChanged<MessageKey> onOpenConversation;
  final VoidCallback onNewConversation;

  @override
  String get title => translate('Messages');

  @override
  Widget get icon => unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum);

  @override
  List<Widget> get appBarActions => <Widget>[
        IconButton(
          tooltip: translate('New conversation'),
          onPressed: onNewConversation,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ];

  @override
  State<_MobileMessagesPage> createState() => _MobileMessagesPageState();
}

class _MobileMessagesPageState extends State<_MobileMessagesPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime _latestMessageTime(MapEntry<MessageKey, MessageBody> entry) {
    final messages = entry.value.chatMessages;
    if (messages.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return messages
        .map((message) => message.createdAt)
        .reduce((latest, value) => value.isAfter(latest) ? value : latest);
  }

  String _messagePreview(MapEntry<MessageKey, MessageBody> entry) {
    if (entry.value.chatMessages.isEmpty) {
      return translate('Start a conversation');
    }
    final message = entry.value.chatMessages.reduce(
      (latest, value) =>
          value.createdAt.isAfter(latest.createdAt) ? value : latest,
    );
    final properties = message.customProperties;
    if (properties?['ldesk_kind'] == 'file') {
      final fileName = (properties?['ldesk_file_name'] ?? '').toString();
      return fileName.isEmpty ? translate('File Transfer') : fileName;
    }
    return message.text.trim().isEmpty
        ? translate('Message')
        : message.text.trim();
  }

  IconData? _fileIconForEntry(MapEntry<MessageKey, MessageBody> entry) {
    final messages = entry.value.chatMessages;
    if (messages.isEmpty) return null;
    final message = messages.reduce(
      (latest, value) =>
          value.createdAt.isAfter(latest.createdAt) ? value : latest,
    );
    final properties = message.customProperties;
    if (properties?['ldesk_kind'] != 'file') return null;
    final fileName = (properties?['ldesk_file_name'] ?? '').toString();
    if (fileName.isEmpty) return null;
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'jpg': case 'jpeg': case 'png': case 'gif':
      case 'bmp': case 'webp': case 'svg':
        return Icons.image_outlined;
      case 'mp4': case 'avi': case 'mkv': case 'mov':
      case 'wmv': case 'flv':
        return Icons.movie_outlined;
      case 'mp3': case 'wav': case 'flac': case 'aac':
        return Icons.audiotrack_outlined;
      case 'pdf': return Icons.picture_as_pdf_outlined;
      case 'doc': case 'docx': return Icons.description_outlined;
      case 'xls': case 'xlsx': case 'csv': return Icons.table_chart_outlined;
      case 'ppt': case 'pptx': return Icons.slideshow_outlined;
      case 'zip': case 'rar': case '7z': case 'tar': case 'gz':
        return Icons.folder_zip_outlined;
      case 'txt': case 'md': case 'log': return Icons.article_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  String _timeLabel(DateTime value) {
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

  Widget _avatar(MapEntry<MessageKey, MessageBody> entry) {
    final user = entry.value.chatUser;
    final name = (user.firstName ?? user.id).trim();
    final initial = name.isEmpty ? '?' : name.characters.first;
    final fallback = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: str2color(name),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return buildAvatarWidget(
          avatar: user.profileImage ?? '',
          size: 48,
          borderRadius: 8,
          fallback: fallback,
        ) ??
        fallback;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ChangeNotifierProvider.value(
      value: gFFI.chatModel,
      child: ListenableBuilder(
        listenable: Listenable.merge([gFFI.chatModel, gFFI.chatSettingsModel]),
        builder: (context, _) {
          final model = gFFI.chatModel;
          final query = _searchController.text.trim().toLowerCase();
          final entries = model.messages.entries.where((entry) {
            if (entry.key.peerId.isEmpty) return false;
            if (query.isEmpty) return true;
            final user = entry.value.chatUser;
            return entry.key.peerId.toLowerCase().contains(query) ||
                (user.firstName ?? '').toLowerCase().contains(query) ||
                _messagePreview(entry).toLowerCase().contains(query);
          }).toList(growable: false)
            ..sort(
              (a, b) => _latestMessageTime(b).compareTo(_latestMessageTime(a)),
            );
          return ColoredBox(
            color: dark ? MyTheme.canvasDark : const Color(0xFFEDEDED),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: translate('Search'),
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        filled: true,
                        fillColor: dark ? MyTheme.surfaceDark : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.forum_outlined,
                                  size: 60,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.18),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  translate('No conversations yet'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed: widget.onNewConversation,
                                  icon: const Icon(
                                    Icons.person_add_alt_1_rounded,
                                    size: 18,
                                  ),
                                  label: Text(translate('Contacts')),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 74,
                            color: Theme.of(context).dividerColor,
                          ),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final user = entry.value.chatUser;
                            final name = (user.firstName ?? '').trim();
                            final client =
                                gFFI.serverModel.clients.firstWhereOrNull(
                              (client) =>
                                  client.peerId == entry.key.peerId &&
                                  client.isChat &&
                                  !client.disconnected,
                            );
                            final isMuted = gFFI.chatSettingsModel.isMuted(entry.key.peerId);
                            final isBlocked = gFFI.chatSettingsModel.isBlocked(entry.key.peerId);
                            final fileIcon = _fileIconForEntry(entry);
                            return Material(
                              color: dark ? MyTheme.surfaceDark : Colors.white,
                              child: ListTile(
                                minLeadingWidth: 48,
                                horizontalTitleGap: 12,
                                minVerticalPadding: 10,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                leading: _avatar(entry),
                                title: Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        name.isEmpty ? entry.key.peerId : name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: isBlocked
                                              ? Theme.of(context).colorScheme.error
                                              : null,
                                        ),
                                      ),
                                    ),
                                    if (isMuted)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: Icon(
                                          Icons.volume_off_rounded,
                                          size: 14,
                                          color: muted,
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _timeLabel(_latestMessageTime(entry)),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Row(
                                  children: <Widget>[
                                    if (fileIcon != null)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 5),
                                        child: Icon(fileIcon, size: 14, color: muted),
                                      ),
                                    if (isBlocked)
                                      Text(
                                        translate('Blocked'),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Theme.of(context).colorScheme.error,
                                        ),
                                      )
                                    else
                                      Expanded(
                                        child: Text(
                                          _messagePreview(entry),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                    if (!isBlocked && client != null)
                                      unreadMessageCountBuilder(
                                        client.unreadChatMessageCount,
                                      ).marginOnly(left: 8),
                                  ],
                                ),
                                onTap: () =>
                                    widget.onOpenConversation(entry.key),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          bind.mainGetAppNameSync(),
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0),
        ),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "luoda://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTerminal: isTerminal,
          password: password);
    }
  }
}
