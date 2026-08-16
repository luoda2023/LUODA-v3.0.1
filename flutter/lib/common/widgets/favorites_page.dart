import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/favorites_model.dart';
import 'package:luoda_flutter/common/favorites_send.dart';
import 'package:luoda_flutter/common/widgets/favorite_chat_history_page.dart';
import 'package:luoda_flutter/common/widgets/file_viewer.dart';
import 'package:luoda_flutter/common/widgets/location_detail_page.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:luoda_flutter/models/peer_model.dart';
import 'package:luoda_flutter/models/platform_model.dart';

/// 收藏页（PC / 手机共用）：微信式收藏，支持分类查看图片 / 文件 / 位置 /
/// 文字 / 语音 / 联系人，以及搜索与删除。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({
    super.key,
    this.detailPane = false,
    this.onClose,
  });

  /// 桌面端使用左右分栏（左侧列表 + 右侧详情），手机端保持单列点击跳转。
  final bool detailPane;

  /// 嵌入主内容区时的关闭回调（AppBar 返回按钮）。
  final VoidCallback? onClose;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String _category = 'all';
  String _query = '';
  FavoriteItem? _selected;
  Peer? _selectedPeer;
  final TextEditingController _searchController = TextEditingController();

  FavoritesModel get _fav => FavoritesModel.instance;

  static const List<(String, IconData)> _categories = <(String, IconData)>[
    ('all', Icons.apps_rounded),
    ('image', Icons.image_rounded),
    ('file', Icons.insert_drive_file_outlined),
    ('location', Icons.location_on_outlined),
    ('chat', Icons.chat_bubble_outline_rounded),
    ('voice', Icons.mic_rounded),
    ('text', Icons.notes_rounded),
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

    final listPane = Column(
      children: <Widget>[
        _buildSearchBar(dark),
        _buildCategoryTabs(dark),
        Expanded(
          child: (messages.isEmpty && contacts.isEmpty)
              ? _buildEmpty(dark)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                  children: <Widget>[
                    for (final item in messages) _buildMessageTile(item, dark),
                    for (final peer in contacts) _buildContactTile(peer, dark),
                  ],
                ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF15171B) : const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: dark ? Colors.white : Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        leading: widget.onClose == null
            ? null
            : IconButton(
                tooltip: translate('Back'),
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onClose,
              ),
        title: Text(
          translate('Favorites'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: widget.detailPane
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 左侧：收藏列表（固定宽），与点聊主界面一致的列表形式。
                SizedBox(width: 300, child: listPane),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: dark ? const Color(0xFF2A2D33) : const Color(0xFFEDEDED),
                ),
                // 右侧：选中项的详情。
                Expanded(child: _buildDetailPane(dark)),
              ],
            )
          : listPane,
    );
  }

  // ------------------------------------------------------------------
  // 顶部：搜索条（内嵌圆角）+ 分类 tab（微信风格下划线）
  // ------------------------------------------------------------------
  Widget _buildSearchBar(bool dark) {
    final inputColor =
        dark ? const Color(0xFF2A2D33) : const Color(0xFFF2F3F5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: inputColor,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 10),
            Icon(Icons.search_rounded,
                size: 18, color: dark ? Colors.white38 : Colors.black38),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: TextStyle(
                  fontSize: 14,
                  color: dark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: translate('Search favorites'),
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: dark ? Colors.white30 : Colors.black26,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            if (_query.isNotEmpty)
              IconButton(
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(Icons.cancel_rounded,
                    size: 16,
                    color: dark ? Colors.white30 : Colors.black26),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(bool dark) {
    final primary = const Color(0xFF07C160);
    // 分类全部可见：Wrap 自动换行，无需横向滚动（避免末尾分类点不到）。
    return Container(
      color: dark ? const Color(0xFF1C1E23) : Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final cat in _categories)
            _buildCategoryChip(cat.$1, cat.$2, dark, primary),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String key, IconData icon, bool dark, Color primary) {
    final selected = _category == key;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _category = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? primary.withOpacity(dark ? 0.22 : 0.12)
              : (dark
                  ? const Color(0xFF2A2D33)
                  : const Color(0xFFF2F3F5)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 118),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 14,
                color: selected
                    ? primary
                    : (dark ? Colors.white54 : Colors.black45),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  translate('favorites_cat_$key'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? primary
                        : (dark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool dark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: (dark ? Colors.white : const Color(0xFF07C160))
                  .withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.star_rounded,
              size: 36,
              color: dark ? Colors.white24 : const Color(0xFF07C160).withOpacity(0.35),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            translate('favorites_empty'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: dark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 右侧详情面板（仅桌面端左右分栏使用）
  // ------------------------------------------------------------------
  Widget _buildDetailPane(bool dark) {
    final peer = _selectedPeer;
    final item = _selected;
    if (peer == null && item == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.star_rounded,
              size: 52,
              color: dark ? Colors.white24 : const Color(0xFF07C160).withOpacity(0.3),
            ),
            const SizedBox(height: 14),
            Text(
              translate('Pick a favorite to view details'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: dark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }
    if (peer != null) return _buildPeerDetail(peer, dark);
    return _buildItemDetail(item!, dark);
  }

  Widget _buildPeerDetail(Peer peer, bool dark) {
    final id = peer.getId();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          CircleAvatar(
            radius: 44,
            backgroundColor:
                dark ? const Color(0xFF2B6B45) : const Color(0xFFE8F7EE),
            child: Text(
              id.isNotEmpty ? id.characters.first : '?',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: Color(0xFF07C160),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            id,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: dark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            translate('favorites_cat_contact'),
            style: TextStyle(
              fontSize: 13,
              color: dark ? Colors.white38 : Colors.black45,
            ),
          ),
          const Spacer(),
          _detailActions(
            dark,
            onOpen: () => _openContact(peer),
            onDelete: () => _showContactDeleteMenu(peer),
          ),
        ],
      ),
    );
  }

  Widget _buildItemDetail(FavoriteItem item, bool dark) {
    final primary = const Color(0xFF07C160);
    final typeLabel = translate('favorites_cat_${item.type}');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _buildLeading(item, dark),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _itemTitle(item),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: dark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        typeLabel,
                        item.peerName,
                      ].where((e) => e.isNotEmpty).join(' · '),
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
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${translate('Saved at')} ${_formatFullTime(item.createdAt)}',
            style: TextStyle(
              fontSize: 12,
              color: dark ? Colors.white30 : Colors.black38,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _buildDetailContent(item, dark)),
          _detailActions(
            dark,
            onOpen: () => _openFavorite(item),
            onDelete: () => _showDeleteMenu(item),
          ),
        ],
      ),
    );
  }

  /// 详情内容区（按收藏类型展示预览）。
  Widget _buildDetailContent(FavoriteItem item, bool dark) {
    switch (item.type) {
      case FavoriteItemType.image:
        final path = item.localPath;
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          return Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _detailFallback(dark,
                    Icons.image_outlined, translate('favorites_cat_image')),
              ),
            ),
          );
        }
        return _detailFallback(
            dark, Icons.image_outlined, translate('favorites_cat_image'));
      case FavoriteItemType.file:
        return _detailFallback(
            dark, Icons.insert_drive_file_outlined, _itemTitle(item),
            subtitle: _fmtSize(item.fileSize));
      case FavoriteItemType.location:
        return _detailFallback(
            dark, Icons.location_on_rounded, item.title ?? translate('Location'),
            subtitle: item.subtitle ?? '');
      case FavoriteItemType.voice:
        return _detailFallback(
            dark, Icons.mic_rounded, item.title ?? translate('Voice message'),
            subtitle: item.subtitle ?? '');
      case FavoriteItemType.forward:
        final msgs = item.chatMessages;
        if (msgs.isEmpty) {
          return _detailFallback(dark, Icons.forward_rounded,
              item.title ?? translate('Chat history'));
        }
        return Container(
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1C1E23) : const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dark ? const Color(0xFF2A2D33) : const Color(0xFFEDEDED),
            ),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: msgs.length,
            separatorBuilder: (_, __) => const Divider(height: 12),
            itemBuilder: (_, i) {
              final m = msgs[i];
              final sender = (m['sender'] ?? '').toString();
              final text = (m['text'] ?? '').toString();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    sender,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF07C160),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: dark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      case FavoriteItemType.text:
      default:
        return SingleChildScrollView(
          child: Text(
            item.title ?? '',
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: dark ? Colors.white : Colors.black87,
            ),
          ),
        );
    }
  }

  Widget _detailFallback(bool dark, IconData icon, String title,
          {String? subtitle}) =>
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: const Color(0xFF07C160).withOpacity(0.5)),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: dark ? Colors.white70 : Colors.black87,
              ),
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: dark ? Colors.white38 : Colors.black45,
                ),
              ),
            ],
          ],
        ),
      );

  Widget _detailActions(
    bool dark, {
    required VoidCallback onOpen,
    required VoidCallback onDelete,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_full_rounded, size: 17),
            label: Text(translate('Open')),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF07C160),
              side: const BorderSide(color: Color(0xFF07C160)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            label: Text(translate('Delete')),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFA5151),
              side: const BorderSide(color: Color(0x66FA5151)),
            ),
          ),
        ),
      ],
    );
  }

  String _formatFullTime(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ------------------------------------------------------------------
  // 卡片
  // ------------------------------------------------------------------
  Widget _card({required bool dark, required Widget child, bool selected = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF07C160).withOpacity(dark ? 0.16 : 0.06)
            : dark
                ? const Color(0xFF1C1E23)
                : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? const Color(0xFF07C160)
              : dark
                  ? const Color(0xFF2A2D33)
                  : const Color(0xFFEDEDED),
          width: selected ? 1.2 : 0.8,
        ),
      ),
      child: child,
    );
  }

  // ------------------------------------------------------------------
  // 消息收藏项
  // ------------------------------------------------------------------
  Widget _buildMessageTile(FavoriteItem item, bool dark) {
    final secondary = <String>[
      item.peerName,
      if ((item.subtitle ?? '').isNotEmpty) item.subtitle!,
    ].join(' · ');
    final time = _formatTime(item.createdAt);

    final selected = widget.detailPane && _selected?.id == item.id;
    return _card(
      dark: dark,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (widget.detailPane) {
            setState(() {
              _selected = item;
              _selectedPeer = null;
            });
          } else {
            _openFavorite(item);
          }
        },
        onLongPress: () => _showDeleteMenu(item),
        child: Padding(
          padding: const EdgeInsets.all(10),
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
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: dark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 5),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11,
                      color: dark ? Colors.white30 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(FavoriteItem item, bool dark) {
    const double size = 60;
    switch (item.type) {
      case FavoriteItemType.image:
        final path = item.localPath;
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: 180,
              errorBuilder: (_, __, ___) => _iconBox(
                  Icons.image_outlined, dark, size,
                  bg: const Color(0xFFEAF2FF), fg: const Color(0xFF3B82F6)),
            ),
          );
        }
        return _iconBox(Icons.image_outlined, dark, size,
            bg: const Color(0xFFEAF2FF), fg: const Color(0xFF3B82F6));
      case FavoriteItemType.file:
        return _iconBox(Icons.insert_drive_file_outlined, dark, size,
            bg: const Color(0xFFEAF2FF), fg: const Color(0xFF3B82F6));
      case FavoriteItemType.location:
        return _iconBox(Icons.location_on_rounded, dark, size,
            bg: const Color(0xFFE8F7EE), fg: const Color(0xFF07C160));
      case FavoriteItemType.voice:
        return _iconBox(Icons.mic_rounded, dark, size,
            bg: const Color(0xFFE8F7EE), fg: const Color(0xFF07C160));
      case FavoriteItemType.forward:
        return _iconBox(Icons.forward_rounded, dark, size,
            bg: const Color(0xFFF3EDFF), fg: const Color(0xFF8B5CF6));
      default:
        return _iconBox(Icons.notes_rounded, dark, size,
            bg: const Color(0xFFFFF4E5), fg: const Color(0xFFF59E0B));
    }
  }

  Widget _iconBox(IconData icon, bool dark, double size,
      {required Color bg, required Color fg}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? bg.withOpacity(0.16) : bg,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 28, color: fg),
    );
  }

  String _itemTitle(FavoriteItem item) {
    switch (item.type) {
      case FavoriteItemType.image:
      case FavoriteItemType.file:
        final name = _fav.fileNameOf(item);
        return name.isNotEmpty ? name : item.title ?? '';
      case FavoriteItemType.location:
        return item.title?.isNotEmpty == true
            ? item.title!
            : translate('Location');
      case FavoriteItemType.voice:
        return item.title?.isNotEmpty == true
            ? item.title!
            : translate('Voice message');
      case FavoriteItemType.forward:
        return item.title?.isNotEmpty == true ? item.title! : '';
      default:
        return item.title ?? '';
    }
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    final diff = today.difference(day).inDays;
    if (diff == 0) return hm;
    if (diff == 1) return '${translate('Yesterday')} $hm';
    if (dt.year == now.year) return '${dt.month}月${dt.day}日';
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
        if (item.chatMessages.isNotEmpty) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FavoriteChatHistoryPage(item: item),
            ),
          );
        } else {
          await _showTextDetail(item);
        }
        break;
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
              title: Text(translate('Send to chat')),
              leading: const Icon(Icons.send_rounded,
                  color: Color(0xFF07C160)),
              onTap: () => Navigator.pop(sheetContext, 'send'),
            ),
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
    if (result == 'send') {
      await _sendToCurrentChat(item);
    } else if (result == 'delete') {
      await _fav.remove(item.id);
    }
  }

  /// 把收藏项作为消息发送到当前打开的会话（PC/手机主会话）。
  Future<void> _sendToCurrentChat(FavoriteItem item) async {
    try {
      await sendFavoriteItemToChat(
        gFFI.chatModel,
        item,
      );
      if (mounted) showToast(translate('Sent'));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) showToast('${translate('Send failed')}: $e');
    }
  }

  // ------------------------------------------------------------------
  // 联系人收藏项（复用原有收藏联系人）
  // ------------------------------------------------------------------
  Widget _buildContactTile(Peer peer, bool dark) {
    final id = peer.getId();
    final avatarColor =
        dark ? const Color(0xFF2B6B45) : const Color(0xFFE8F7EE);
    final selected = widget.detailPane && _selectedPeer?.getId() == id;
    return _card(
      dark: dark,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (widget.detailPane) {
            setState(() {
              _selectedPeer = peer;
              _selected = null;
            });
          } else {
            _openContact(peer);
          }
        },
        onLongPress: () => _showContactDeleteMenu(peer),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 30,
                backgroundColor: avatarColor,
                child: Text(
                  id.isNotEmpty ? id.characters.first : '?',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF07C160),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: dark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 5),
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
