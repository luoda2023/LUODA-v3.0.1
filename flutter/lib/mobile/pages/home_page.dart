import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/mobile/pages/server_page.dart';
import 'package:luoda_flutter/mobile/pages/settings_page.dart';
import 'package:luoda_flutter/web/settings_page.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/file_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'connection_page.dart';

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
  FFI? _directFileSession;
  String _directFilePeerId = '';
  bool get isChatPageCurrentTab =>
      isMobile && _selectedIndex == _chatPageTabIndex;

  void selectChatPage() {
    if (_chatPageTabIndex < 0 || _selectedIndex == _chatPageTabIndex) return;
    setState(() => _selectedIndex = _chatPageTabIndex);
  }

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    initPages();
  }

  void initPages() {
    _pages.clear();
    if (!bind.isIncomingOnly()) {
      _pages.add(ConnectionPage(
        appBarActions: [],
      ));
    }
    if (isMobile) {
      _chatPageTabIndex = _pages.length;
      _pages.add(ChatPage(
        type: ChatPageType.mobileMain,
        onAttachFile: _sendDirectChatFiles,
        onRemoteAssist: _startRemoteFromChat,
      ));
      if (isAndroid && !bind.isOutgoingOnly()) {
        _pages.add(ServerPage());
      }
    }
    _pages.add(SettingsPage());
  }

  void _startRemoteFromChat() {
    final peerId = gFFI.chatModel.currentKey.peerId.trim();
    if (peerId.isEmpty) return;
    connect(context, peerId);
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
      gFFI.chatModel.sendText(
        '${translate('Sent file')}: ${files.map((file) => file.name).join(', ')}',
      );
    }
    showToast(translate('Direct file transfer started.'));
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

    final ffi = FFI(null);
    _directFileSession = ffi;
    _directFilePeerId = peerId;
    ffi.start(peerId, isFileTransfer: true, forceRelay: false);
    ffi.dialogManager.showLoading(
      translate('Preparing direct file transfer...'),
      onCancel: () async {
        if (_directFileSession == ffi) {
          _directFileSession = null;
          _directFilePeerId = '';
        }
        await _disposeDirectFileSession(ffi);
      },
    );

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
    final fileSession = _directFileSession;
    _directFileSession = null;
    if (fileSession != null) {
      unawaited(_disposeDirectFileSession(fileSession));
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
          // backgroundColor: MyTheme.grayBg,
          appBar: AppBar(
            centerTitle: true,
            title: appTitle(),
            actions: _pages.elementAt(_selectedIndex).appBarActions,
          ),
          bottomNavigationBar: BottomNavigationBar(
            key: navigationBarKey,
            items: _pages
                .map((page) =>
                    BottomNavigationBarItem(icon: page.icon, label: page.title))
                .toList(),
            currentIndex: _selectedIndex,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: MyTheme.accent, //
            unselectedItemColor: MyTheme.darkGray,
            onTap: (index) => setState(() {
              // close chat overlay when go chat page
              if (_selectedIndex != index) {
                _selectedIndex = index;
                if (isChatPageCurrentTab) {
                  gFFI.chatModel.hideChatIconOverlay();
                  gFFI.chatModel.hideChatWindowOverlay();
                  gFFI.chatModel.mobileClearClientUnread(
                      gFFI.chatModel.currentKey.connId);
                }
              }
            }),
          ),
          body: _pages.elementAt(_selectedIndex),
        ));
  }

  Widget appTitle() {
    final currentUser = gFFI.chatModel.currentUser;
    final currentKey = gFFI.chatModel.currentKey;
    if (isChatPageCurrentTab &&
        currentUser != null &&
        currentKey.peerId.isNotEmpty) {
      final connected = currentKey.isOut
          ? gFFI.ffiModel.pi.isSet.isTrue
          : gFFI.serverModel.clients.any((e) => e.id == currentKey.connId);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Tooltip(
            message: currentKey.isOut
                ? translate('Outgoing connection')
                : translate('Incoming connection'),
            child: Icon(
              currentKey.isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${currentUser.firstName}   ${currentUser.id}",
                  ),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 133, 246, 199)),
                    ).marginSymmetric(horizontal: 2),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Text(bind.mainGetAppNameSync());
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
