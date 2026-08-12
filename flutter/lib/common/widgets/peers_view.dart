import 'dart:async';
import 'dart:collection';

import 'package:dynamic_layouts/dynamic_layouts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/models/ab_model.dart';
import 'package:luoda_flutter/models/peer_tab_model.dart';
import 'package:luoda_flutter/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../direct_chat_policy.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import 'peer_card.dart';

typedef PeerFilter = bool Function(Peer peer);
typedef PeerCardBuilder = Widget Function(Peer peer);

class _PeerGroupHeader {
  const _PeerGroupHeader(this.label, this.count);

  final String label;
  final int count;
}

class _PeerGroup {
  const _PeerGroup(this.label, this.peers);

  final String label;
  final List<Peer> peers;
}

class PeerSortType {
  static const String remoteId = 'Remote ID';
  static const String remoteHost = 'Remote Host';
  static const String username = 'Username';
  static const String status = 'Status';

  static List<String> values = [
    PeerSortType.remoteId,
    PeerSortType.remoteHost,
    PeerSortType.username,
    PeerSortType.status,
  ];
}

class LoadEvent {
  static const String recent = 'load_recent_peers';
  static const String favorite = 'load_fav_peers';
  static const String lan = 'load_lan_peers';
  static const String addressBook = 'load_address_book_peers';
  static const String group = 'load_group_peers';
}

class PeersModelName {
  static const String recent = 'recent peer';
  static const String favorite = 'fav peer';
  static const String lan = 'discovered peer';
  static const String addressBook = 'address book peer';
  static const String group = 'group peer';
}

/// for peer search text, global obs value
final peerSearchText = "".obs;

/// for peer sort, global obs value
RxString? _peerSort;
RxString get peerSort {
  _peerSort ??= bind.getLocalFlutterOption(k: kOptionPeerSorting).obs;
  return _peerSort!;
}

// list for listener
RxList<RxString> get obslist => [peerSearchText, peerSort].obs;

final peerSearchTextController = TextEditingController(
  text: peerSearchText.value,
);

class _PeersView extends StatefulWidget {
  final Peers peers;
  final PeerFilter? peerFilter;
  final PeerCardBuilder peerCardBuilder;
  final PeerTabIndex peerTabIndex;
  final bool groupByDirectChatPolicy;
  final bool friendsOnly;

  const _PeersView({
    required this.peers,
    required this.peerCardBuilder,
    required this.peerTabIndex,
    required this.groupByDirectChatPolicy,
    required this.friendsOnly,
    this.peerFilter,
    Key? key,
  }) : super(key: key);

  @override
  _PeersViewState createState() => _PeersViewState();
}

/// State for the peer widget.
class _PeersViewState extends State<_PeersView>
    with WindowListener, WidgetsBindingObserver {
  static const int _maxQueryCount = 3;
  final HashMap<String, String> _emptyMessages = HashMap.from({
    LoadEvent.recent: 'empty_recent_tip',
    LoadEvent.favorite: 'empty_favorite_tip',
    LoadEvent.lan: 'empty_lan_tip',
    LoadEvent.addressBook: 'empty_address_book_tip',
  });
  final space = (isDesktop || isWebDesktop) ? 12.0 : 8.0;
  final _curPeers = <String>{};
  var _lastChangeTime = DateTime.now();
  var _lastQueryPeers = <String>{};
  var _lastQueryTime = DateTime.now();
  var _lastWindowRestoreTime = DateTime.now();
  var _queryCount = 0;
  var _exit = false;
  bool _isActive = true;

  final _scrollController = ScrollController();
  final _directChatAccess = DirectChatAccessController.instance;

  _PeersViewState() {
    _startCheckOnlines();
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    if (widget.groupByDirectChatPolicy || widget.friendsOnly) {
      _directChatAccess.load();
      _directChatAccess.addListener(_onDirectChatPolicyChanged);
    }
    _loadInitialPeers();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    if (widget.groupByDirectChatPolicy || widget.friendsOnly) {
      _directChatAccess.removeListener(_onDirectChatPolicyChanged);
    }
    _scrollController.dispose();
    _exit = true;
    super.dispose();
  }

  void _onDirectChatPolicyChanged() {
    if (mounted) setState(() {});
  }

  void _loadInitialPeers() {
    switch (widget.peers.loadEvent) {
      case LoadEvent.recent:
        unawaited(bind.mainLoadRecentPeers());
        break;
      case LoadEvent.favorite:
        unawaited(bind.mainLoadFavPeers());
        break;
      case LoadEvent.lan:
        unawaited(bind.mainLoadLanPeers());
        unawaited(bind.mainDiscover());
        break;
    }
  }

  @override
  void onWindowFocus() {
    _queryCount = 0;
    _isActive = true;
  }

  @override
  void onWindowBlur() {
    // We need this comparison because window restore (on Windows) also triggers `onWindowBlur()`.
    // Maybe it's a bug of the window manager, but the source code seems to be correct.
    //
    // Although `onWindowRestore()` is called after `onWindowBlur()` in my test,
    // we need the following comparison to ensure that `_isActive` is true in the end.
    if (isWindows &&
        DateTime.now().difference(_lastWindowRestoreTime) <
            const Duration(milliseconds: 300)) {
      return;
    }
    _queryCount = _maxQueryCount;
    _isActive = false;
  }

  @override
  void onWindowRestore() {
    // Window restore (on MacOS and Linux) also triggers `onWindowFocus()`.
    // But on Windows, it triggers `onWindowBlur()`, mybe it's a bug of the window manager.
    if (!isWindows) return;
    _queryCount = 0;
    _isActive = true;
    _lastWindowRestoreTime = DateTime.now();
  }

  @override
  void onWindowMinimize() {
    // Window minimize also triggers `onWindowBlur()`.
  }

  // This function is required for mobile.
  // `onWindowFocus` works fine for desktop.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (isDesktop || isWebDesktop) return;
    if (state == AppLifecycleState.resumed) {
      _isActive = true;
      _queryCount = 0;
    } else if (state == AppLifecycleState.inactive) {
      _isActive = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // We should avoid too many rebuilds. MacOS(m1, 14.6.1) on Flutter 3.19.6.
    // Continious rebuilds of `ChangeNotifierProvider` will cause memory leak.
    // Simple demo can reproduce this issue.
    return ChangeNotifierProvider<Peers>.value(
      value: widget.peers,
      child: Consumer<Peers>(
        builder: (context, peers, child) {
          if (peers.peers.isEmpty) {
            gFFI.peerTabModel.setCurrentTabCachedPeers([]);
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sentiment_very_dissatisfied_rounded,
                    color: Theme.of(context).tabBarTheme.labelColor,
                    size: 40,
                  ).paddingOnly(bottom: 10),
                  Text(
                    translate(
                      _emptyMessages[widget.peers.loadEvent] ?? 'Empty',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).tabBarTheme.labelColor,
                    ),
                  ),
                ],
              ),
            );
          } else {
            return _buildPeersView(peers);
          }
        },
      ),
    );
  }

  onVisibilityChanged(VisibilityInfo info) {
    final peerId = _peerId((info.key as ValueKey).value);
    if (info.visibleFraction > 0.00001) {
      _curPeers.add(peerId);
    } else {
      _curPeers.remove(peerId);
    }
    _lastChangeTime = DateTime.now();
  }

  String _cardId(String id) => widget.peers.name + id;
  String _peerId(String cardId) => cardId.replaceAll(widget.peers.name, '');

  Widget _buildPeersView(Peers peers) {
    final updateEvent = peers.event;
    final body = ObxValue<RxList>((filters) {
      var matchedPeers = matchPeers(
        filters[0].value,
        filters[1].value,
        peers.peers,
      );
      if (matchedPeers.length > 1000) {
        matchedPeers = matchedPeers.sublist(0, 1000);
      }
      gFFI.peerTabModel.setCurrentTabCachedPeers(matchedPeers);

      Widget buildOnePeer(Peer peer, bool isPortrait) {
        final visibilityChild = VisibilityDetector(
          key: ValueKey(_cardId(peer.id)),
          onVisibilityChanged: onVisibilityChanged,
          child: widget.peerCardBuilder(peer),
        );
        return !isPortrait
            ? Obx(
                () => peerCardUiType.value == PeerUiType.list
                    ? SizedBox(height: 45, child: visibilityChild)
                    : peerCardUiType.value == PeerUiType.grid
                        ? SizedBox(
                            width: 320,
                            height: 176,
                            child: visibilityChild,
                          )
                        : SizedBox(
                            width: 220,
                            height: 42,
                            child: visibilityChild,
                          ),
              )
            : visibilityChild;
      }

      final Widget child = Obx(() {
        if (stateGlobal.isPortrait.isTrue) {
          return _buildPortraitList(matchedPeers, buildOnePeer);
        }
        final uiType = peerCardUiType.value;
        if (widget.groupByDirectChatPolicy) {
          return _buildWideGroupedPeers(matchedPeers, uiType, buildOnePeer);
        }
        return uiType == PeerUiType.list
            ? ListView.builder(
                controller: _scrollController,
                itemCount: matchedPeers.length,
                itemBuilder: (BuildContext context, int index) {
                  return buildOnePeer(matchedPeers[index], false).marginOnly(
                    right: space,
                    top: index == 0 ? 0 : space / 2,
                    bottom: space / 2,
                  );
                },
              )
            : uiType == PeerUiType.grid
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 680 ? 2 : 1;
                      return GridView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.only(right: space),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: 1.55,
                          mainAxisSpacing: space,
                          crossAxisSpacing: space,
                        ),
                        itemCount: matchedPeers.length,
                        itemBuilder: (BuildContext context, int index) {
                          return buildOnePeer(matchedPeers[index], false);
                        },
                      );
                    },
                  )
                : DynamicGridView.builder(
                    gridDelegate: SliverGridDelegateWithWrapping(
                      mainAxisSpacing: space / 2,
                      crossAxisSpacing: space,
                    ),
                    itemCount: matchedPeers.length,
                    itemBuilder: (BuildContext context, int index) {
                      return buildOnePeer(matchedPeers[index], false);
                    },
                  );
      });

      if (updateEvent == UpdateEvent.load) {
        _curPeers
          ..clear()
          ..addAll(matchedPeers.map((peer) => peer.id));
        _queryOnlines(true);
      }
      return child;
    }, obslist);

    return body;
  }

  Widget _buildPortraitList(
    List<Peer> peers,
    Widget Function(Peer peer, bool isPortrait) buildOnePeer,
  ) {
    final rows = _mobileGroupedRows(peers);
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (BuildContext context, int index) {
        final row = rows[index];
        if (row is _PeerGroupHeader) {
          return Container(
            height: 34,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              '${translate(row.label)} (${row.count})',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.62),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        }
        final peer = row as Peer;
        return buildOnePeer(peer, true).marginOnly(
          top:
              index == 0 || rows[index - 1] is _PeerGroupHeader ? 0 : space / 2,
          bottom: space / 2,
        );
      },
    );
  }

  Widget _buildWideGroupedPeers(
    List<Peer> peers,
    PeerUiType uiType,
    Widget Function(Peer peer, bool isPortrait) buildOnePeer,
  ) {
    if (uiType == PeerUiType.list) {
      final rows = _groupedRows(peers);
      return ListView.builder(
        controller: _scrollController,
        itemCount: rows.length,
        itemBuilder: (BuildContext context, int index) {
          final row = rows[index];
          if (row is _PeerGroupHeader) return _buildPeerGroupHeader(row);
          return buildOnePeer(row as Peer, false).marginOnly(
            right: space,
            top: index == 0 || rows[index - 1] is _PeerGroupHeader
                ? 0
                : space / 2,
            bottom: space / 2,
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final groups = _peerGroups(peers);
        final slivers = <Widget>[];
        for (final group in groups) {
          slivers.add(
            SliverToBoxAdapter(
              child: _buildPeerGroupHeader(
                _PeerGroupHeader(group.label, group.peers.length),
              ),
            ),
          );
          slivers.add(
            SliverPadding(
              padding: EdgeInsets.only(right: space, bottom: space),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => buildOnePeer(group.peers[index], false),
                  childCount: group.peers.length,
                ),
                gridDelegate: uiType == PeerUiType.grid
                    ? SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.maxWidth >= 680 ? 2 : 1,
                        childAspectRatio: 1.55,
                        mainAxisSpacing: space,
                        crossAxisSpacing: space,
                      )
                    : SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisExtent: 42,
                        mainAxisSpacing: space / 2,
                        crossAxisSpacing: space,
                      ),
              ),
            ),
          );
        }
        return CustomScrollView(
          controller: _scrollController,
          slivers: slivers,
        );
      },
    );
  }

  Widget _buildPeerGroupHeader(_PeerGroupHeader row) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withOpacity(0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${translate(row.label)} (${row.count})',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  List<Object> _mobileGroupedRows(List<Peer> peers) {
    if (!widget.groupByDirectChatPolicy) return peers.cast<Object>();
    return _groupedRows(peers);
  }

  List<_PeerGroup> _peerGroups(List<Peer> peers) {
    final friends = peers
        .where((peer) => _directChatAccess.isFriend(peer.id))
        .toList(growable: false);
    final strangers = peers
        .where((peer) => !_directChatAccess.isFriend(peer.id))
        .toList(growable: false);
    return <_PeerGroup>[
      if (friends.isNotEmpty) _PeerGroup('Friends', friends),
      if (strangers.isNotEmpty) _PeerGroup('Strangers', strangers),
    ];
  }

  List<Object> _groupedRows(List<Peer> peers) {
    return <Object>[
      for (final group in _peerGroups(peers)) ...<Object>[
        _PeerGroupHeader(group.label, group.peers.length),
        ...group.peers,
      ],
    ];
  }

  var _queryInterval = const Duration(seconds: 20);

  void _startCheckOnlines() {
    () async {
      final p = await bind.mainIsUsingPublicServer();
      if (!p) {
        _queryInterval = const Duration(seconds: 6);
      }
      while (!_exit) {
        final now = DateTime.now();
        if (!setEquals(_curPeers, _lastQueryPeers)) {
          if (now.difference(_lastChangeTime) > const Duration(seconds: 1)) {
            _queryOnlines(false);
          }
        } else {
          final skipIfIsWeb =
              isWeb && !(stateGlobal.isWebVisible && stateGlobal.isInMainPage);
          final skipIfMobile =
              (isAndroid || isIOS) && !stateGlobal.isInMainPage;
          final skipIfNotActive = skipIfIsWeb || skipIfMobile || !_isActive;
          if (!skipIfNotActive && (_queryCount < _maxQueryCount || !p)) {
            if (now.difference(_lastQueryTime) >= _queryInterval) {
              if (_curPeers.isNotEmpty) {
                bind.queryOnlines(ids: _curPeers.toList(growable: false));
                _lastQueryTime = DateTime.now();
                _queryCount += 1;
              }
            }
          }
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }();
  }

  _queryOnlines(bool isLoadEvent) {
    if (_curPeers.isNotEmpty) {
      bind.queryOnlines(ids: _curPeers.toList(growable: false));
      _queryCount = 0;
    }
    _lastQueryPeers = {..._curPeers};
    if (isLoadEvent) {
      _lastChangeTime = DateTime.now();
    } else {
      _lastQueryTime = DateTime.now().subtract(_queryInterval);
    }
  }

  List<Peer> matchPeers(
    String searchText,
    String sortedBy,
    List<Peer> peers,
  ) {
    peers = peers.toList(growable: false);
    if (widget.peerFilter != null) {
      peers = peers.where((peer) => widget.peerFilter!(peer)).toList();
    }
    if (widget.friendsOnly) {
      peers =
          peers.where((peer) => _directChatAccess.isFriend(peer.id)).toList();
    }

    // fallback to id sorting
    if (!PeerSortType.values.contains(sortedBy)) {
      sortedBy = PeerSortType.remoteId;
      bind.setLocalFlutterOption(k: kOptionPeerSorting, v: sortedBy);
    }

    if (widget.peers.loadEvent != LoadEvent.recent) {
      switch (sortedBy) {
        case PeerSortType.remoteId:
          peers.sort((p1, p2) => p1.getId().compareTo(p2.getId()));
          break;
        case PeerSortType.remoteHost:
          peers.sort(
            (p1, p2) =>
                p1.hostname.toLowerCase().compareTo(p2.hostname.toLowerCase()),
          );
          break;
        case PeerSortType.username:
          peers.sort(
            (p1, p2) =>
                p1.username.toLowerCase().compareTo(p2.username.toLowerCase()),
          );
          break;
        case PeerSortType.status:
          peers.sort((p1, p2) {
            final onlineOrder =
                (p2.online ? 1 : 0).compareTo(p1.online ? 1 : 0);
            return onlineOrder != 0
                ? onlineOrder
                : p1.getId().compareTo(p2.getId());
          });
          break;
      }
    }

    searchText = searchText.trim();
    if (searchText.isEmpty) {
      return peers;
    }
    searchText = searchText.toLowerCase();
    return peers.where((peer) {
      if (peer.id.toLowerCase().contains(searchText) ||
          peer.hostname.toLowerCase().contains(searchText) ||
          peer.username.toLowerCase().contains(searchText) ||
          peer.alias.toLowerCase().contains(searchText)) {
        return true;
      }
      return peerTabShowNote(widget.peerTabIndex) &&
          peer.note.toLowerCase().contains(searchText);
    }).toList(growable: false);
  }
}

abstract class BasePeersView extends StatelessWidget {
  final PeerTabIndex peerTabIndex;
  final PeerFilter? peerFilter;
  final PeerCardBuilder peerCardBuilder;
  final bool groupByDirectChatPolicy;
  final bool friendsOnly;

  const BasePeersView({
    Key? key,
    required this.peerTabIndex,
    this.peerFilter,
    required this.peerCardBuilder,
    this.groupByDirectChatPolicy = false,
    this.friendsOnly = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Peers peers;
    switch (peerTabIndex) {
      case PeerTabIndex.recent:
        peers = gFFI.recentPeersModel;
        break;
      case PeerTabIndex.fav:
        peers = gFFI.favoritePeersModel;
        break;
      case PeerTabIndex.lan:
        peers = gFFI.lanPeersModel;
        break;
      case PeerTabIndex.ab:
        peers = gFFI.abModel.peersModel;
        break;
      case PeerTabIndex.group:
        peers = gFFI.groupModel.peersModel;
        break;
      case PeerTabIndex.vip:
        peers = gFFI.recentPeersModel;
        break;
    }
    return _PeersView(
      peers: peers,
      peerFilter: peerFilter,
      peerCardBuilder: peerCardBuilder,
      peerTabIndex: peerTabIndex,
      groupByDirectChatPolicy: groupByDirectChatPolicy,
      friendsOnly: friendsOnly,
    );
  }
}

class RecentPeersView extends BasePeersView {
  RecentPeersView({
    Key? key,
    EdgeInsets? menuPadding,
    ScrollController? scrollController,
  }) : super(
          key: key,
          peerTabIndex: PeerTabIndex.recent,
          groupByDirectChatPolicy: true,
          peerCardBuilder: (Peer peer) =>
              RecentPeerCard(peer: peer, menuPadding: menuPadding),
        );
}

class FavoritePeersView extends BasePeersView {
  FavoritePeersView({
    Key? key,
    EdgeInsets? menuPadding,
    ScrollController? scrollController,
  }) : super(
          key: key,
          peerTabIndex: PeerTabIndex.fav,
          groupByDirectChatPolicy: true,
          peerCardBuilder: (Peer peer) =>
              FavoritePeerCard(peer: peer, menuPadding: menuPadding),
        );
}

class DiscoveredPeersView extends BasePeersView {
  DiscoveredPeersView({
    Key? key,
    EdgeInsets? menuPadding,
    ScrollController? scrollController,
  }) : super(
          key: key,
          peerTabIndex: PeerTabIndex.lan,
          peerCardBuilder: (Peer peer) =>
              DiscoveredPeerCard(peer: peer, menuPadding: menuPadding),
        );
}

class AddressBookPeersView extends BasePeersView {
  AddressBookPeersView({
    Key? key,
    EdgeInsets? menuPadding,
    ScrollController? scrollController,
  }) : super(
          key: key,
          peerTabIndex: PeerTabIndex.ab,
          friendsOnly: true,
          peerFilter: (Peer peer) =>
              _hitTag(gFFI.abModel.selectedTags, peer.tags),
          peerCardBuilder: (Peer peer) =>
              AddressBookPeerCard(peer: peer, menuPadding: menuPadding),
        );

  static bool _hitTag(List<dynamic> selectedTags, List<dynamic> idents) {
    if (selectedTags.isEmpty) {
      return true;
    }
    // The result of a no-tag union with normal tags, still allows normal tags to perform union or intersection operations.
    final selectedNormalTags =
        selectedTags.where((tag) => tag != kUntagged).toList();
    if (selectedTags.contains(kUntagged)) {
      if (idents.isEmpty) return true;
      if (selectedNormalTags.isEmpty) return false;
    }
    if (gFFI.abModel.filterByIntersection.value) {
      for (final tag in selectedNormalTags) {
        if (!idents.contains(tag)) {
          return false;
        }
      }
      return true;
    } else {
      for (final tag in selectedNormalTags) {
        if (idents.contains(tag)) {
          return true;
        }
      }
      return false;
    }
  }
}

class MyGroupPeerView extends BasePeersView {
  MyGroupPeerView({
    Key? key,
    EdgeInsets? menuPadding,
    ScrollController? scrollController,
  }) : super(
          key: key,
          peerTabIndex: PeerTabIndex.group,
          peerFilter: filter,
          peerCardBuilder: (Peer peer) =>
              MyGroupPeerCard(peer: peer, menuPadding: menuPadding),
        );

  static bool filter(Peer peer) {
    final model = gFFI.groupModel;
    if (model.searchAccessibleItemNameText.isNotEmpty) {
      final text = model.searchAccessibleItemNameText.value.toLowerCase();
      final searchPeersOfUser = model.users.any(
        (user) =>
            user.name == peer.loginName &&
            (user.name.toLowerCase().contains(text) ||
                user.displayNameOrName.toLowerCase().contains(text)),
      );
      final searchPeersOfDeviceGroup =
          peer.device_group_name.toLowerCase().contains(text) &&
              model.deviceGroups.any((g) => g.name == peer.device_group_name);
      if (!searchPeersOfUser && !searchPeersOfDeviceGroup) {
        return false;
      }
    }
    if (model.selectedAccessibleItemName.isNotEmpty) {
      if (model.isSelectedDeviceGroup.value) {
        if (model.selectedAccessibleItemName.value != peer.device_group_name) {
          return false;
        }
      } else {
        if (model.selectedAccessibleItemName.value != peer.loginName) {
          return false;
        }
      }
    }
    return true;
  }
}
