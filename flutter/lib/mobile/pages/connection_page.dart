import 'dart:async';

import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common/formatter/id_formatter.dart';
import 'package:luoda_flutter/common/widgets/connection_page_title.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:luoda_flutter/models/peer_model.dart';

import '../../common.dart';
import '../../common/direct_pairing.dart';
import '../../common/direct_viewer_invite.dart';
import '../../common/widgets/join_viewer_page.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../consts.dart';
import '../../models/chat_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';

/// Connection page for connecting to a remote peer.
enum _ConnectionMode { chat, remote, viewer }

class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, required this.appBarActions}) : super(key: key);

  @override
  final icon = const Icon(Icons.contacts_outlined);

  @override
  final title = translate("Contacts");

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage> {
  _ConnectionMode _connectionMode = _ConnectionMode.chat;
  bool _openingViewerInvite = false;

  /// Controller for the id input bar.
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  StreamSubscription? _uniLinksSubscription;

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  _ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

  @override
  void initState() {
    super.initState();
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
    return CustomScrollView(
      slivers: [
        SliverList(
            delegate: SliverChildListDelegate([
          if (!bind.isCustomClient() && !isIOS)
            Obx(() => _buildUpdateUI(stateGlobal.updateUrl.value)),
          _buildConnectionModeSwitch(),
          _buildRemoteIDTextField(),
          _buildPairedContacts(),
        ])),
        SliverFillRemaining(
          hasScrollBody: true,
          child: PeerTabPage(),
        )
      ],
    ).marginOnly(top: 2, left: 10, right: 10);
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  Future<void> onConnect() async {
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

  Widget _buildConnectionModeSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 2),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<_ConnectionMode>(
          segments: <ButtonSegment<_ConnectionMode>>[
            ButtonSegment<_ConnectionMode>(
              value: _ConnectionMode.chat,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: Text(translate('Chat')),
            ),
            ButtonSegment<_ConnectionMode>(
              value: _ConnectionMode.remote,
              icon: const Icon(Icons.desktop_windows_outlined, size: 18),
              label: Text(translate('Remote assistance')),
            ),
            ButtonSegment<_ConnectionMode>(
              value: _ConnectionMode.viewer,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: Text(translate('Join as Viewer')),
            ),
          ],
          selected: <_ConnectionMode>{_connectionMode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() => _connectionMode = selection.first);
          },
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
    final pairing = DirectPairingStore.find(id);
    final endpoint = DirectPairingStore.resolveConnectionTarget(id);
    if (endpoint == null) {
      showToast(translate(
        'Direct endpoint required. Scan the PC QR code or enter IP:port.',
      ));
      return;
    }
    final peerId = pairing?.peerId ?? id;
    final currentKey = gFFI.chatModel.currentKey;
    if (!gFFI.closed &&
        gFFI.connType == ConnType.chat &&
        currentKey.peerId == peerId) {
      HomePage.homeKey.currentState?.selectChatPage();
      return;
    }
    final incomingIndex = gFFI.serverModel.clients.lastIndexWhere((client) =>
        client.peerId.trim() == peerId &&
        client.authorized &&
        client.isChat &&
        !client.disconnected);
    if (incomingIndex >= 0) {
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
    gFFI.chatModel.changeCurrentKey(MessageKey(peerId, ChatModel.clientModeID));
    if (pairing != null) {
      gFFI.chatModel.updatePeerIdentity(
        peerId,
        displayName: pairing.displayName,
        avatar: pairing.avatar,
      );
    }
    gFFI.start(endpoint, isChat: true, forceRelay: false);
    HomePage.homeKey.currentState?.selectChatPage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (gFFI.closed) return;
      gFFI.dialogManager.showLoading(
        translate('Connecting...'),
        onCancel: () => gFFI.close(),
      );
    });
  }

  Widget _buildPairedContacts() {
    return ValueListenableBuilder<int>(
      valueListenable: DirectPairingStore.revision,
      builder: (context, _, __) {
        final pairings = DirectPairingStore.load().values.toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (pairings.isEmpty) return const SizedBox.shrink();
        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            gFFI.ffiModel,
            gFFI.serverModel,
          ]),
          builder: (context, _) => Container(
            margin: const EdgeInsets.fromLTRB(2, 8, 2, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var index = 0; index < pairings.length; index++) ...[
                  Builder(builder: (context) {
                    final pairing = pairings[index];
                    final status = _pairedMessageStatus(pairing);
                    return ListTile(
                      minVerticalPadding: 9,
                      leading: _pairedContactAvatar(pairing),
                      title: Text(
                        pairing.displayName.isEmpty
                            ? pairing.peerId
                            : pairing.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            pairing.preferredEndpoint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            translate(status.$1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: status.$2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _startDirectChat(pairing.peerId),
                    );
                  }),
                  if (index != pairings.length - 1)
                    const Divider(height: 1, indent: 70),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pairedContactAvatar(DirectPairing pairing) {
    final name = pairing.displayName.isEmpty
        ? pairing.peerId
        : pairing.displayName.trim();
    final initial = name.isEmpty ? '?' : name.characters.first;
    final fallback = Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: str2color(name),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return buildAvatarWidget(
          avatar: pairing.avatar,
          size: 46,
          borderRadius: 8,
          fallback: fallback,
        ) ??
        fallback;
  }

  (String, Color) _pairedMessageStatus(DirectPairing pairing) {
    final activeOutgoing = !gFFI.closed &&
        gFFI.connType == ConnType.chat &&
        gFFI.chatModel.currentKey.peerId == pairing.peerId &&
        gFFI.ffiModel.pi.isSet.isTrue &&
        gFFI.ffiModel.direct == true;
    final activeIncoming = gFFI.serverModel.clients.any(
      (client) =>
          client.peerId == pairing.peerId &&
          client.authorized &&
          client.isChat &&
          !client.disconnected,
    );
    if (activeOutgoing || activeIncoming) {
      return ('Messages allowed', const Color(0xFF238A57));
    }
    final isCurrent = gFFI.chatModel.currentKey.peerId == pairing.peerId;
    final error = isCurrent ? gFFI.ffiModel.lastConnectionError ?? '' : '';
    if (error.contains('Direct messages rejected')) {
      return ('Messages rejected', const Color(0xFFD84A4A));
    }
    if (isCurrent && !gFFI.closed && gFFI.connType == ConnType.chat) {
      return ('Connecting', const Color(0xFF4C6EA8));
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
              final url = 'https://dicad.cn/download';
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
  Widget _buildRemoteIDTextField() {
    final w = SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
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
                  padding: const EdgeInsets.only(left: 16, right: 16),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: MyTheme.idColor,
                        ),
                        decoration: InputDecoration(
                          labelText: translate('Paired ID / IP:port'),
                          // hintText: 'Enter your remote ID',
                          border: InputBorder.none,
                          helperStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: MyTheme.darkGray,
                          ),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            letterSpacing: 0,
                            color: MyTheme.darkGray,
                          ),
                        ),
                        inputFormatters: [IDTextInputFormatter()],
                        onSubmitted: (_) {
                          onConnect();
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
                width: 56,
                height: 48,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: MyTheme.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    tooltip: translate('Connect'),
                    icon: const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 22),
                    onPressed: onConnect,
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

  @override
  void dispose() {
    pendingViewerInvite.removeListener(_handlePendingViewerInvite);
    _uniLinksSubscription?.cancel();
    _idController.dispose();
    _idFocusNode.removeListener(onFocusChanged);
    _allPeersLoader.clear();
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }
}
