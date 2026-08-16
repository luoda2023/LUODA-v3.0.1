import 'dart:async';

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/system_announcement.dart';

/// 系统通知列表页：拉取服务器发布的通知，显示未读红点与详情。
class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({super.key});

  @override
  State<AnnouncementPage> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SystemAnnouncementStore.instance.load();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await SystemAnnouncementStore.instance.refresh();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    // 离开页面视为已读。
    unawaited(SystemAnnouncementStore.instance.markAllRead());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final store = SystemAnnouncementStore.instance;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xFF1C1E23) : Colors.white,
        title: Text(translate('System notices')),
        actions: <Widget>[
          IconButton(
            tooltip: translate('Refresh'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: store.revision,
        builder: (context, _, __) {
          if (_loading && store.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (store.items.isEmpty) {
            return Center(
              child: Text(
                translate('No system notices'),
                style: TextStyle(
                  color: dark ? MyTheme.mutedDark : MyTheme.mutedLight,
                ),
              ),
            );
          }
          final lastRead = store.lastReadId;
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: store.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final a = store.items[index];
              return _AnnouncementCard(
                announcement: a,
                unread: a.id > lastRead,
                dark: dark,
              );
            },
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends StatefulWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.unread,
    required this.dark,
  });

  final SystemAnnouncement announcement;
  final bool unread;
  final bool dark;

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    final primary = a.important ? const Color(0xFFFA5151) : const Color(0xFF07C160);
    final cardColor = widget.dark ? const Color(0xFF26282E) : Colors.white;
    final muted = widget.dark ? MyTheme.mutedDark : MyTheme.mutedLight;
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // 点击进入独立详情页查看完整内容。
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AnnouncementDetailPage(announcement: a),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.unread ? primary : Colors.transparent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (a.important) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFA5151).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        translate('Important'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFFA5151),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (a.pinned)
                    Icon(Icons.push_pin_rounded, size: 14, color: muted),
                  Expanded(
                    child: Text(
                      a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            widget.unread ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: muted),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _formatTime(a.createdAt),
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 8),
              Text(
                a.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color:
                      widget.dark ? const Color(0xFFC8CCD3) : const Color(0xFF3B3F45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final d = DateTime(local.year, local.month, local.day);
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final diff = day.difference(d).inDays;
    if (diff == 0) return '$hh:$mm';
    if (diff == 1) return '${translate('Yesterday')} $hh:$mm';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }
}

/// 系统通知详情页：全屏查看标题、时间与完整内容。
class AnnouncementDetailPage extends StatefulWidget {
  const AnnouncementDetailPage({super.key, required this.announcement});

  final SystemAnnouncement announcement;

  @override
  State<AnnouncementDetailPage> createState() => _AnnouncementDetailPageState();
}

class _AnnouncementDetailPageState extends State<AnnouncementDetailPage> {
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = widget.announcement;
    final primary =
        a.important ? const Color(0xFFFA5151) : const Color(0xFF07C160);
    final muted = dark ? MyTheme.mutedDark : MyTheme.mutedLight;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF1C1E23) : const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xFF1C1E23) : Colors.white,
        title: Text(translate('Notice detail')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (a.important) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      translate('Important'),
                      style: TextStyle(
                        fontSize: 11,
                        color: primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (a.pinned)
                  Icon(Icons.push_pin_rounded, size: 16, color: muted),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              a.title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.35,
                color: dark ? Colors.white : const Color(0xFF1B1D21),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatFullTime(a.createdAt),
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF26282E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                a.content,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.7,
                  color:
                      dark ? const Color(0xFFC8CCD3) : const Color(0xFF3B3F45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFullTime(DateTime t) {
    final local = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
