import 'package:flutter/material.dart';

import '../../common.dart';
import '../../models/meeting_group_model.dart';
import '../../common/widgets/meeting_group_panel.dart' as panel;
import 'home_page.dart';
import 'server_page.dart';

/// DotChat ?????????????? / ???? / ?????????
/// ??????????????????
class RemoteMeetingPage extends StatefulWidget implements PageShape {
  const RemoteMeetingPage({super.key});

  @override
  String get title => translate('Remote meeting');

  @override
  Widget get icon => const Icon(Icons.videocam_outlined);

  @override
  List<Widget> get appBarActions => <Widget>[];

  @override
  State<RemoteMeetingPage> createState() => _RemoteMeetingPageState();
}

class _RemoteMeetingPageState extends State<RemoteMeetingPage> {
  List<MeetingGroup> _meetings = const <MeetingGroup>[];

  @override
  void initState() {
    super.initState();
    MeetingGroupStore.load();
    _reload();
  }

  void _reload() {
    final meetings = MeetingGroupStore.all.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    setState(() => _meetings = meetings);
  }

  Future<void> _startMeeting() async {
    final draft = await showModalBottomSheet<_MeetingDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CreateMeetingSheet(),
    );
    if (draft == null || !mounted) return;
    final group = MeetingGroupStore.create(
      title: draft.title,
      hostPeerId: gFFI.serverModel.id,
      hostDisplayName: gFFI.serverModel.serverId.text,
      startTime: draft.startTime,
      durationMinutes: draft.durationMinutes,
    );
    await MeetingGroupStore.save();
    _reload();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => panel.MeetingGroupPanel(group: group),
      ),
    );
    _reload();
  }

  Future<void> _joinMeeting() async {
    final controller = TextEditingController();
    final theme = Theme.of(context);
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: MyTheme.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.login_rounded,
                  size: 18, color: MyTheme.primary),
            ),
            const SizedBox(width: 10),
            Text(translate('Join meeting'),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface)),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 2),
          decoration: InputDecoration(
            hintText: translate('Enter meeting code'),
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: MyTheme.primary, width: 1.4),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(translate('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MyTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(translate('Join')),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final normalized = code.toLowerCase();
    MeetingGroup? group;
    for (final m in _meetings) {
      if (m.inviteShortCode.toLowerCase() == normalized ||
          m.meetingId.toLowerCase() == normalized) {
        group = m;
        break;
      }
    }
    if (group == null) {
      showToast(translate('Meeting not found'));
      return;
    }
    final target = group;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => panel.MeetingGroupPanel(group: target),
      ),
    );
  }

  void _remoteAssist() {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  translate('Remote assist'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            _sheetItem(
              sheetContext,
              icon: Icons.screen_share_rounded,
              title: translate('Remote assistance'),
              subtitle: translate('Connect to a device by ID or IP'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _connectDialog();
              },
            ),
            _sheetItem(
              sheetContext,
              icon: Icons.settings_suggest_outlined,
              title: translate('Service settings'),
              subtitle: translate('Manage this device\'s assist service'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ServerPage()),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _connectDialog() {
    final controller = TextEditingController();
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: MyTheme.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.screen_share_rounded,
                  size: 18, color: MyTheme.primary),
            ),
            const SizedBox(width: 10),
            Text(translate('Remote assistance'),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface)),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: translate('Enter ID or IP:port'),
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: MyTheme.primary, width: 1.4),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(translate('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MyTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final value = controller.text.trim();
              Navigator.of(dialogContext).pop();
              if (value.isNotEmpty) {
                HomePage.homeKey.currentState?.connectByInput(value);
              }
            },
            child: Text(translate('Connect')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        _buildHero(context),
        const SizedBox(height: 18),
        _buildActions(context),
        const SizedBox(height: 22),
        Row(
          children: <Widget>[
            Text(
              translate('My meetings'),
              style: TextStyle(
                fontSize: MobileText.titleSm,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (_meetings.isNotEmpty)
              IconButton(
                tooltip: translate('New meeting'),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                onPressed: _startMeeting,
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_meetings.isEmpty)
          _buildEmptyMeetings(context, dark)
        else
          for (final meeting in _meetings) _buildMeetingRow(context, meeting),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0FAF57), Color(0xFF07C160)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF07C160).withOpacity(0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.videocam_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      translate('Remote meeting'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      translate('Invite friends to watch & teach together'),
                      style: TextStyle(
                        fontSize: MobileText.caption,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _heroChip(
                icon: Icons.badge_outlined,
                label: 'ID ${gFFI.serverModel.id}',
              ),
              const SizedBox(width: 8),
              _heroChip(
                icon: Icons.qr_code_rounded,
                label: translate('My identity'),
                onTap: () => HomePage.homeKey.currentState?.showMyIdentity(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _actionCard(
            context,
            icon: Icons.video_call_rounded,
            title: translate('Start meeting'),
            subtitle: translate('Invite & teach'),
            primary: true,
            onTap: _startMeeting,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionCard(
            context,
            icon: Icons.login_rounded,
            title: translate('Join meeting'),
            subtitle: translate('Enter code'),
            onTap: _joinMeeting,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionCard(
            context,
            icon: Icons.screen_share_rounded,
            title: translate('Remote assist'),
            subtitle: translate('Connect device'),
            onTap: _remoteAssist,
          ),
        ),
      ],
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final Color bg = primary
        ? const Color(0xFF07C160)
        : dark
            ? MyTheme.surfaceDark
            : Colors.white;
    final Color fg = primary
        ? Colors.white
        : theme.colorScheme.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      elevation: primary ? 4 : 0.5,
      shadowColor: primary
          ? const Color(0xFF07C160).withOpacity(0.3)
          : Colors.black.withOpacity(0.12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Column(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary
                      ? Colors.white.withOpacity(0.18)
                      : const Color(0xFF07C160).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color: primary ? Colors.white : const Color(0xFF07C160),
                    size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: MobileText.bodySm,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: primary
                      ? Colors.white.withOpacity(0.82)
                      : theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyMeetings(BuildContext context, bool dark) {
    final theme = Theme.of(context);
    // ignore: unused_local_variable
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: dark ? MyTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.groups_outlined,
              size: 40, color: theme.colorScheme.onSurface.withOpacity(0.2)),
          const SizedBox(height: 10),
          Text(
            translate('No meetings yet'),
            style: TextStyle(
              fontSize: MobileText.body,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            translate('Start a meeting and invite friends to join'),
            style: TextStyle(
              fontSize: MobileText.caption,
              color: theme.colorScheme.onSurface.withOpacity(0.45),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _startMeeting,
            icon: const Icon(Icons.video_call_rounded, size: 18),
            label: Text(translate('Start meeting')),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingRow(BuildContext context, MeetingGroup meeting) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: dark ? MyTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => panel.MeetingGroupPanel(group: meeting),
              ),
            );
            _reload();
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF07C160).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.groups_rounded,
                      color: Color(0xFF07C160), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        meeting.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: MobileText.bodyLg,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meeting.hasActiveInvite
                            ? '${translate("Meeting code")}: ${meeting.inviteShortCode}'
                            : translate('No invite yet'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: MobileText.caption,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurface.withOpacity(0.25)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Shared bottom-sheet row for the remote-assist sheet.
Widget _sheetItem(
  BuildContext sheetContext, {
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  final theme = Theme.of(sheetContext);
  return ListTile(
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: MyTheme.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 21, color: MyTheme.primary),
    ),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(
        fontSize: 12,
        color: theme.colorScheme.onSurface.withOpacity(0.5),
      ),
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onTap: onTap,
  );
}

/// 新建会议表单数据。
class _MeetingDraft {
  const _MeetingDraft({
    required this.title,
    required this.startTime,
    required this.durationMinutes,
  });

  final String title;
  final DateTime? startTime; // null = 立即开始
  final int durationMinutes; // 0 = 不限时长
}

/// 新建会议底部表单：会议名称 + 开始时间（立即/定时）+ 会议时长。
class _CreateMeetingSheet extends StatefulWidget {
  const _CreateMeetingSheet();

  @override
  State<_CreateMeetingSheet> createState() => _CreateMeetingSheetState();
}

class _CreateMeetingSheetState extends State<_CreateMeetingSheet> {
  final TextEditingController _titleController = TextEditingController();
  bool _startNow = true;
  DateTime? _startTime;
  int _durationMinutes = 60;

  static const List<int> _durationChoices = <int>[30, 60, 120, 0];

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickStartTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime ?? now),
    );
    if (time == null) return;
    setState(() {
      _startTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _startNow = false;
    });
  }

  String _formatStartTime(DateTime dt) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${dt.month}月${dt.day}日 ${two(dt.hour)}:${two(dt.minute)}';
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      showToast(translate('Please enter a meeting name'));
      return;
    }
    Navigator.of(context).pop(
      _MeetingDraft(
        title: title,
        startTime: _startNow ? null : _startTime,
        durationMinutes: _durationMinutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.colorScheme.onSurface.withOpacity(0.5);
    final cardBg =
        dark ? const Color(0xFF2B2D32) : theme.colorScheme.surface;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              translate('Start meeting'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            // 会议名称
            _fieldLabel(theme, translate('Meeting name')),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              autofocus: false,
              maxLength: 32,
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: translate('Enter meeting name'),
                counterText: '',
                filled: true,
                fillColor: cardBg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: MyTheme.primary, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // 开始时间
            _fieldLabel(theme, translate('Start time')),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: _choiceCard(
                    theme,
                    selected: _startNow,
                    icon: Icons.play_circle_outline_rounded,
                    label: translate('Start now'),
                    onTap: () => setState(() => _startNow = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _choiceCard(
                    theme,
                    selected: !_startNow,
                    icon: Icons.schedule_rounded,
                    label: _startTime == null
                        ? translate('Schedule')
                        : _formatStartTime(_startTime!),
                    onTap: () async {
                      await _pickStartTime();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // 会议时长
            _fieldLabel(theme, translate('Meeting duration')),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final minutes in _durationChoices)
                  _durationChip(theme, minutes),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: MyTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _submit,
                child: Text(
                  translate('Create meeting'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(ThemeData theme, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface.withOpacity(0.65),
      ),
    );
  }

  Widget _choiceCard(
    ThemeData theme, {
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final dark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? MyTheme.primary.withOpacity(0.1)
              : (dark ? const Color(0xFF2B2D32) : theme.colorScheme.surface),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? MyTheme.primary : theme.dividerColor,
            width: selected ? 1.4 : 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 17,
              color: selected ? MyTheme.primary : theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? MyTheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _durationChip(ThemeData theme, int minutes) {
    final selected = _durationMinutes == minutes;
    final dark = theme.brightness == Brightness.dark;
    final label = minutes == 0
        ? translate('No limit')
        : minutes >= 60
            ? '${minutes ~/ 60}${translate('hour')}'
            : '$minutes${translate('minute')}';
    return InkWell(
      onTap: () => setState(() => _durationMinutes = minutes),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? MyTheme.primary
              : (dark ? const Color(0xFF2B2D32) : theme.colorScheme.surface),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? MyTheme.primary : theme.dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
