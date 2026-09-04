// LUODA 3.1.24 - AI meeting minutes card (meeting group panel section).
//
// Reads the meeting group's chat history and lets the host generate a
// structured AI summary (with an offline rule-based fallback), preview it,
// copy it, and share it back into the meeting chat.

import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:luoda_flutter/models/meeting_group_model.dart';
import 'package:luoda_flutter/models/meeting_minutes_model.dart';

class MeetingMinutesCard extends StatefulWidget {
  const MeetingMinutesCard({super.key, required this.group});

  final MeetingGroup group;

  @override
  State<MeetingMinutesCard> createState() => _MeetingMinutesCardState();
}

class _MeetingMinutesCardState extends State<MeetingMinutesCard> {
  bool _generating = false;

  MeetingGroup get _group => widget.group;

  @override
  void initState() {
    super.initState();
    MeetingMinutesService.instance.load();
  }

  List<MeetingMinutesEntry> get _history =>
      MeetingMinutesService.instance.forMeeting(_group.meetingId);

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final entry = await MeetingMinutesService.instance.generate(
        meetingId: _group.meetingId,
        title: _group.title,
        conversationId: _group.conversationId,
      );
      if (!mounted) return;
      setState(() => _generating = false);
      await _showMinutesDialog(entry);
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      showToast('生成纪要失败:$e');
    }
  }

  Future<void> _showMinutesDialog(MeetingMinutesEntry entry) async {
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => material.Dialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.source == 'ai' ? 'AI 会议纪要' : '会议纪要(本地整理)',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface)),
                          const SizedBox(height: 4),
                          Text(
                            '${entry.title} · ${entry.generatedAt.toLocal().month}月${entry.generatedAt.toLocal().day}日 ${entry.generatedAt.toLocal().hour}:${entry.generatedAt.toLocal().minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.5)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    entry.body,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: theme.colorScheme.onSurface),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: entry.body));
                        showToast('已复制');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 17),
                      label: const Text('复制'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: MyTheme.primary),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _shareToMeetingChat(entry.body);
                      },
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: const Text('分享到会议聊天'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareToMeetingChat(String body) async {
    final chatModel = gFFI.chatModel;
    final originalKey = chatModel.currentKey;
    final targetKey = MessageKey(_group.conversationId, ChatModel.clientModeID);
    if (originalKey.peerId != _group.conversationId) {
      chatModel.changeCurrentKey(targetKey);
    }
    // 标题 + 内容作为一条消息,便于在群聊里阅读。
    chatModel.sendText('📋 会议纪要(${_group.title})\n$body');
    if (originalKey.peerId != _group.conversationId) {
      chatModel.changeCurrentKey(originalKey);
    }
    if (mounted) showToast('已分享到会议聊天');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = dark ? MyTheme.surfaceDark : Colors.white;
    final border = dark ? MyTheme.borderDark : MyTheme.borderLight;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      size: 18, color: Color(0xFF1A73E8)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'AI 会议纪要',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '基于本场会议的聊天讨论,一键生成议题、结论与待办的结构化纪要,并回写会议聊天。',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: MyTheme.primary),
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.note_alt_outlined, size: 18),
                label: Text(_generating ? '正在整理…' : '生成 / 重新生成纪要'),
              ),
            ),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '最近纪要',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 4),
              for (final h in _history.take(3))
                InkWell(
                  onTap: () => _showMinutesDialog(h),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(
                          h.source == 'ai'
                              ? Icons.auto_awesome
                              : Icons.notes_rounded,
                          size: 15,
                          color: h.source == 'ai'
                              ? const Color(0xFF1A73E8)
                              : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${h.title} · ${h.generatedAt.toLocal().month}月${h.generatedAt.toLocal().day}日 ${h.generatedAt.toLocal().hour}:${h.generatedAt.toLocal().minute.toString().padLeft(2, '0')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
