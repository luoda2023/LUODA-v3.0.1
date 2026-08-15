import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/favorites_model.dart';
import 'package:luoda_flutter/common/widgets/file_viewer.dart';
import 'package:luoda_flutter/common/widgets/location_detail_page.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:luoda_flutter/models/peer_model.dart';
import 'package:luoda_flutter/models/platform_model.dart';

/// 收藏页（PC / 手机共用）：微信式收藏，支持分类查看图片 / 文件 / 位置 /
/// 文字 / 语音 / 联系人，以及搜索与删除。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String _category = 'all';
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  FavoritesModel get _fav => FavoritesModel.instance;

  static const List<(String, IconData)> _categories = <(String, IconData)>[
    ('all', Icons.apps_rounded),
    ('image', Icons.image_rounded),
    ('file', Icons.insert_drive_file_outlined),
    ('location', Icons.location_on_outlined),
    ('text', Icons.notes_rounded),
    ('voice', Icons.mic_rounded),
    ('contact', Icons.people_alt_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _fav.load();
    _fav.addListener(_onChanged);
    // 联系人收藏模型（测试环境无全局 FFI 时忽略）。
    try {
      gFFI.favoritePeersModel.addListener(_onChanged);
    } catch (_) {}
  }

  @override
  void dispose() {
    _fav.removeListener(_onChanged);
    try {
      gFFI.favoritePeersModel.removeListener(_onChanged);
    } catch (_) {}
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<FavoriteItem> _messageItems() {
    var items = _fav.byType(_category == 'all' ? null : _category);
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      items = items
          .where((e) =>
              (e.title ?? '').toLowerCase().contains(q) ||
              (e.subtitle ?? '').toLowerCase().contains(q) ||
              e.peerName.toLowerCase().contains(q))
          .toList();
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  List<Peer> _contactItems() {
    List<Peer> source;
    try {
      source = List<Peer>.from(gFFI.favoritePeersModel.peers);
    } catch (_) {
      source = <Peer>[];
    }
    final peers = source;
    peers.sort((a, b) => a.getId().compareTo(b.getId()));
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      return peers
          .where((p) =>
              p.getId().toLowerCase().contains(q) ||
              p.id.toLowerCase().contains(q))
          .toList();
    }
    return peers;
  }

  bool _showContacts() => _category == 'contact' || _category == 'all';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF1C1E23) : Colors.white;
    final messages = _messageItems();
    final contacts = _showContacts() ? _contactItems() : const <Peer>[];

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF15171B) : const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: dark ? Colors.white : Colors.black87,
        elevation: 0.5,
        title: Text(
          translate('Favorites'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: translate('Search'),
            icon: const Icon(Icons.search_rounded),
            onPressed: () => _focusSearch(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildSearchBar(dark),
          _buildCategoryTabs(dark),
          Expanded(
            child: (messages.isEmpty && contacts.isEmpty)
                ? _buildEmpty(dark)
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: <Widget>[
                      for (final item in messages) _buildMessageTile(item, dark),
                      for (final peer in contacts)
                        _buildContactTile(peer, dark),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _focusSearch() {
    // 简单实现：弹出搜索输入框
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            Theme.of(ctx).brightness == Brightness.dark
                ? const Color(0xFF1C1E23)
                : Colors.white,
        title: Text(translate('Search favorites')),
        content: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: translate('Search favorites'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            Navigator.pop(ctx, v);
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(translate('Cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, _searchController.text.trim()),
            child: Text(translate('Search')),
          ),
        ],
      ),
    ).then((value) {
      if (value == null) return;
      setState(() => _query = value);
    });
  }

  Widget _buildSearchBar(bool dark) {
    if (_query.isEmpty) return const SizedBox.shrink();
    return Container(
      color: dark ? const Color(0xFF1C1E23) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded,
              size: 18, color: dark ? Colors.white54 : Colors.black45),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: dark ? Colors.white70 : Colors.black87),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () {
              _searchController.clear();
              setState(() => _query = '');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(bool dark) {
    return Container(
      color: dark ? const Color(0xFF1C1E23) : Colors.white,
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (key, icon) = _categories[index];
          final selected = _category == key;
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _category = key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? (dark ? const Color(0xFF2B6B45) : const Color(0xFFE8F7EE))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon,
                      size: 16,
                      color: selected
                          ? (dark ? const Color(0xFF4CAF50) : const Color(0xFF07C160))
                          : (dark ? Colors.white54 : Colors.black54)),
                  const SizedBox(width: 5),
                  Text(
                    translate('favorites_cat_$key'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? (dark ? const Color(0xFF4CAF50) : const Color(0xFF07C160))
                          : (dark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(bool dark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.star_border_rounded,
              size: 56, color: dark ? Colors.white24 : Colors.black26),
          const SizedBox(height: 12),
          Text(
            translate('favorites_empty'),
            style: TextStyle(
              fontSize: 14,
              color: dark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 消息收藏项
  // ------------------------------------------------------------------
  Widget _buildMessageTile(FavoriteItem item, bool dark) {
    final subtitle = item.subtitle ?? '';
    final time = _formatTime(item.createdAt);
    final secondary = <String>[
      item.peerName,
      if (subtitle.isNotEmpty) subtitle,
      time,
    ].join(' · ');

    return InkWell(
      onTap: () => _openFavorite(item),
      onLongPress: () => _showDeleteMenu(item),
      child: Container(
        color: dark ? const Color(0xFF1C1E23) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildLeading(item, dark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _itemTitle(item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      color: dark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: dark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: dark ? Colors.white24 : Colors.black26),
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(FavoriteItem item, bool dark) {
    const double size = 54;
    switch (item.type) {
      case FavoriteItemType.image:
        final path = item.localPath;
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: 160,
              errorBuilder: (_, __, ___) => _iconBox(
                  Icons.image_outlined, dark, size),
            ),
          );
        }
        return _iconBox(Icons.image_outlined, dark, size);
      case FavoriteItemType.file:
        return _iconBox(Icons.insert_drive_file_outlined, dark, size,
            color: const Color(0xFF3B82F6));
      case FavoriteItemType.location:
        return _iconBox(Icons.location_on_rounded, dark, size,
            color: const Color(0xFF07C160));
      case FavoriteItemType.voice:
        return _iconBox(Icons.mic_rounded, dark, size,
            color: const Color(0xFF07C160));
      case FavoriteItemType.forward:
        return _iconBox(Icons.forward_rounded, dark, size,
            color: const Color(0xFF8B5CF6));
      default:
        return _iconBox(Icons.notes_rounded, dark, size,
            color: const Color(0xFFF59E0B));
    }
  }

  Widget _iconBox(IconData icon, bool dark, double size,
      {Color color = const Color(0xFF07C160)}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 26, color: color),
    );
  }

  String _itemTitle(FavoriteItem item) {
    switch (item.type) {
      case FavoriteItemType.image:
        return '[${translate('favorites_cat_image')}] '
            '${_fav.fileNameOf(item)}';
      case FavoriteItemType.file:
        return '[${translate('favorites_cat_file')}] '
            '${_fav.fileNameOf(item)}';
      case FavoriteItemType.location:
        return '[${translate('favorites_cat_location')}] '
            '${item.title ?? translate('Location')}';
      case FavoriteItemType.voice:
        return '[${translate('favorites_cat_voice')}] '
            '${item.title ?? translate('Voice message')}';
      case FavoriteItemType.forward:
        return '[${translate('favorites_cat_text')}] '
            '${item.title ?? ''}';
      default:
        return item.title ?? '';
    }
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final sameDay = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    if (sameDay) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    final sameYear = dt.year == now.year;
    if (sameYear) {
      return '${dt.month}月${dt.day}日';
    }
    return '${dt.year}/${dt.month}/${dt.day}';
  }

  Future<void> _openFavorite(FavoriteItem item) async {
    switch (item.type) {
      case FavoriteItemType.image:
      case FavoriteItemType.file:
      case FavoriteItemType.voice:
        final path = item.localPath;
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          await showFileViewer(
            context,
            fileName: _fav.fileNameOf(item),
            fileSize: item.fileSize,
            localPath: path,
          );
        } else {
          _showMissingFile(item);
        }
        break;
      case FavoriteItemType.location:
        final lat = double.tryParse('${item.extra['lat'] ?? ''}');
        final lng = double.tryParse('${item.extra['lng'] ?? ''}');
        if (lat != null && lng != null) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LocationDetailPage(
                location: DirectChatLocation(
                  latitude: lat,
                  longitude: lng,
                  name: (item.extra['name'] ?? item.title ?? '').toString(),
                  address:
                      (item.extra['address'] ?? item.subtitle ?? '').toString(),
                ),
              ),
            ),
          );
        } else {
          _showMissingFile(item);
        }
        break;
      case FavoriteItemType.forward:
      case FavoriteItemType.text:
        await _showTextDetail(item);
        break;
      default:
        break;
    }
  }

  Future<void> _showTextDetail(FavoriteItem item) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark
            ? const Color(0xFF1C1E23)
            : Colors.white,
        title: Text(
          '${item.peerName} · ${_formatTime(item.createdAt)}',
          style: const TextStyle(fontSize: 15),
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            item.title ?? '',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Theme.of(ctx).brightness == Brightness.dark
                  ? Colors.white70
                  : Colors.black87,
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: item.title ?? ''));
              Navigator.pop(ctx);
              showToast(translate('Copied'));
            },
            child: Text(translate('Copy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(translate('Close')),
          ),
        ],
      ),
    );
  }

  void _showMissingFile(FavoriteItem item) {
    showToast(translate('File not found on this device'));
  }

  Future<void> _showDeleteMenu(FavoriteItem item) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1C1E23)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                translate('Delete favorite'),
                style: const TextStyle(color: Color(0xFFFA5151)),
              ),
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFFA5151)),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
            ListTile(
              title: Text(translate('Cancel')),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
    if (result == 'delete') {
      await _fav.remove(item.id);
    }
  }

  // ------------------------------------------------------------------
  // 联系人收藏项（复用原有收藏联系人）
  // ------------------------------------------------------------------
  Widget _buildContactTile(Peer peer, bool dark) {
    return InkWell(
      onTap: () => _openContact(peer),
      onLongPress: () => _showContactDeleteMenu(peer),
      child: Container(
        color: dark ? const Color(0xFF1C1E23) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 26,
              backgroundColor:
                  (dark ? const Color(0xFF2B6B45) : const Color(0xFFE8F7EE)),
              child: Text(
                peer.getId().isNotEmpty ? peer.getId().characters.first : '?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF07C160),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    peer.getId(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: dark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    peer.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: dark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: dark ? Colors.white24 : Colors.black26),
          ],
        ),
      ),
    );
  }

  void _openContact(Peer peer) {
    gFFI.chatModel.changeCurrentKey(
      MessageKey(peer.id, ChatModel.clientModeID),
    );
    Navigator.of(context).maybePop();
  }

  Future<void> _showContactDeleteMenu(Peer peer) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1C1E23)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                translate('Remove from Favorites'),
                style: const TextStyle(color: Color(0xFFFA5151)),
              ),
              leading: const Icon(Icons.star_outline_rounded,
                  color: Color(0xFFFA5151)),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
            ListTile(
              title: Text(translate('Cancel')),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
    if (result == 'remove') {
      final favs = (await bind.mainGetFav()).toList();
      favs.remove(peer.id);
      await bind.mainStoreFav(favs: favs);
    }
  }
}
