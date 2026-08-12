import 'dart:async';

import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/consts.dart';
import '../../models/platform_model.dart';

/// One-time permission wizard shown on first install.
/// Requests ALL required Android permissions at once so the user never
/// sees scattered permission prompts later.
class FirstRunPermissionWizard extends StatefulWidget {
  static const kFirstRunPermSeenKey = 'first_run_permissions_seen_v2';
  static const _remindCooldown = Duration(hours: 24);

  /// True when every required permission is already granted by the Android
  /// system. System permissions survive app updates and reinstalls, so a
  /// one-time authorization stays valid until the OS or the device changes.
  /// Only the essentials gate the wizard: floating window, notifications
  /// and audio are enough for chat / messages to work reliably. File access
  /// and input control are optional and can be granted later from Settings.
  static Future<bool> allPermissionsGranted() async {
    if (isDesktop || isWeb) return true;
    final floating =
        await AndroidPermissionManager.check(kSystemAlertWindow);
    final notification = androidVersion < 33 || isIOS
        ? true
        : await AndroidPermissionManager.check(kAndroid13Notification);
    final audio = androidVersion < 30 || isIOS
        ? true
        : await AndroidPermissionManager.check(kRecordAudio);
    return floating && notification && audio;
  }

  /// Returns true if the wizard completed (all permissions granted or
  /// previously completed), false if the user dismissed it early.
  static Future<bool> showIfNeeded(BuildContext context) async {
    // Already authorized at the system level: never ask again, even after a
    // reinstall. Only a different OS/device loses these grants.
    if (await allPermissionsGranted()) {
      await bind.mainSetLocalOption(key: kFirstRunPermDoneKey, value: 'Y');
      return true;
    }
    final done = await bind.mainGetLocalOption(key: kFirstRunPermDoneKey);
    if (done == 'Y') return true;
    // "Remind me later" must not nag on every single launch; only re-show
    // after the cooldown so the app stays usable between permission prompts.
    final seen = await bind.mainGetLocalOption(key: kFirstRunPermSeenKey);
    final seenTime = DateTime.tryParse(seen);
    if (seenTime != null &&
        DateTime.now().difference(seenTime) < _remindCooldown) {
      return false;
    }
    if (!context.mounted) return false;
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const FirstRunPermissionWizard(),
      ),
    );
    if (completed == true) {
      await bind.mainSetLocalOption(key: kFirstRunPermDoneKey, value: 'Y');
    } else {
      await bind.mainSetLocalOption(
          key: kFirstRunPermSeenKey, value: DateTime.now().toIso8601String());
    }
    return completed == true;
  }

  static const kFirstRunPermDoneKey = 'first_run_permissions_done_v2';

  const FirstRunPermissionWizard({Key? key}) : super(key: key);

  @override
  State<FirstRunPermissionWizard> createState() =>
      _FirstRunPermissionWizardState();
}

class _FirstRunPermissionWizardState extends State<FirstRunPermissionWizard> {
  final Map<String, _PermStatus> _states = {};
  bool _checking = true;
  bool _grantingAll = false;

  static const _kFloating = 'floating';
  static const _kNotification = 'notification';
  static const _kStorage = 'storage';
  static const _kAudio = 'audio';
  static const _kAccessibility = 'accessibility';

  bool _finished = false;

  @override
  void initState() {
    super.initState();
    gFFI.serverModel.addListener(_onServerModelChanged);
    _initChecks();
  }

  @override
  void dispose() {
    gFFI.serverModel.removeListener(_onServerModelChanged);
    super.dispose();
  }

  /// Refresh the wizard when the native side reports that the accessibility
  /// service state changed (e.g. the user enabled it in system settings after
  /// the poll window expired), and finish automatically once everything is
  /// granted.
  /// Completes the wizard exactly once. The system permission flow can fire
  /// server-model changes after the route is already gone (e.g. the user
  /// finished via system settings); popping a missing route would leave the
  /// app stuck on a blank screen, so only pop when a route is actually
  /// present and mark the one-time setup done either way.
  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
    } else {
      unawaited(bind.mainSetLocalOption(
          key: FirstRunPermissionWizard.kFirstRunPermDoneKey,
          value: 'Y'));
    }
  }

  void _onServerModelChanged() {
    if (!mounted) return;
    final status = _states[_kAccessibility];
    final inputOk = gFFI.serverModel.inputOk;
    if (status != null && status.granted != inputOk) {
      setState(() => _states[_kAccessibility] = status.copyWith(inputOk));
    }
    if (_requiredGranted) _finish();
  }

  Future<void> _initChecks() async {
    final floating =
        await AndroidPermissionManager.check(kSystemAlertWindow);
    final notification = androidVersion < 33 || isIOS
        ? true
        : await AndroidPermissionManager.check(kAndroid13Notification);
    final storage =
        await AndroidPermissionManager.check(kManageExternalStorage);
    final audio = androidVersion < 30 || isIOS
        ? true
        : await AndroidPermissionManager.check(kRecordAudio);
    final accessibility = gFFI.serverModel.inputOk;
    if (!mounted) return;
    setState(() {
      _states[_kFloating] = _PermStatus(floating, translate('Floating window'),
          translate('Required to show remote control toolbar over other apps'));
      _states[_kNotification] = _PermStatus(
          notification,
          translate('Notifications'),
          translate(
              'Required to receive chat messages and connection alerts'));
      _states[_kStorage] = _PermStatus(
          storage,
          translate('File access'),
          translate('Required to transfer files between devices'),
          optional: true);
      _states[_kAudio] = _PermStatus(
          audio,
          translate('Audio capture'),
          translate('Required to transmit device audio'));
      _states[_kAccessibility] = _PermStatus(
          accessibility,
          translate('Input control'),
          translate(
              'Required for remote mouse/keyboard control of this device'),
          optional: true);
      _checking = false;
    });
  }

  /// Chat only needs these; the rest can be enabled later from Settings.
  bool get _requiredGranted =>
      _states[_kFloating]!.granted &&
      _states[_kNotification]!.granted &&
      _states[_kAudio]!.granted;

  /// One-click flow: request every still-missing permission in order.
  /// Runtime permissions show system dialogs; special permissions open the
  /// matching system settings page. The wizard refreshes after each step and
  /// finishes automatically once everything is granted.
  Future<void> _grantAll() async {
    if (_grantingAll) return;
    setState(() => _grantingAll = true);
    try {
      if (!_states[_kAudio]!.granted) await _grantAudio();
      if (!_states[_kNotification]!.granted) await _grantNotification();
      if (!_states[_kStorage]!.granted) await _grantStorage();
      if (!_states[_kFloating]!.granted) await _grantFloatingWindow();
      if (!_states[_kAccessibility]!.granted) await _grantAccessibility();
    } finally {
      if (mounted) setState(() => _grantingAll = false);
    }
    if (_requiredGranted) _finish();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('Permission setup')),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Header
                    Icon(Icons.shield_outlined,
                        size: 56,
                        color: theme.colorScheme.primary.withOpacity(0.7)),
                    const SizedBox(height: 16),
                    Text(
                      translate('One-time setup'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      translate('first_run_wizard_desc')
                          .replaceAll('first_run_wizard_desc',
                              'Grant these permissions once so DotChat can work smoothly. You will not be asked again.'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // One-click grant all
                    FilledButton.icon(
                      onPressed: _grantingAll ? null : _grantAll,
                      icon: _grantingAll
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_fix_high_rounded),
                      label: Text(translate('Grant all at once')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      translate('grant_all_tip'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Permission cards
                    _buildCard(_states[_kAccessibility]!, () =>
                        _grantAccessibility()),
                    _buildCard(_states[_kFloating]!, () =>
                        _grantFloatingWindow()),
                    _buildCard(
                        _states[_kNotification]!, () => _grantNotification()),
                    _buildCard(_states[_kStorage]!, () => _grantStorage()),
                    _buildCard(_states[_kAudio]!, () => _grantAudio()),

                    const SizedBox(height: 32),

                    // Continue button
                    FilledButton.icon(
                      onPressed: _requiredGranted
                          ? _finish
                          : null,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(translate('Continue')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (!_requiredGranted)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          translate('Grant all permissions above to continue'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          translate('wizard_optional_hint'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.55),
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(translate('Remind me later')),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCard(_PermStatus status, VoidCallback onGrant) {
    final theme = Theme.of(context);
    final granted = status.granted;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: granted
              ? theme.colorScheme.primary.withOpacity(0.3)
              : theme.colorScheme.outline.withOpacity(0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            // Status indicator
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: granted
                    ? theme.colorScheme.primary.withOpacity(0.12)
                    : theme.colorScheme.error.withOpacity(0.08),
              ),
              child: Icon(
                granted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                color: granted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          status.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (status.optional) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            translate('optional'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Grant button
            if (!granted)
              FilledButton.tonal(
                onPressed: onGrant,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(translate('Grant')),
              )
            else if (_grantingAll)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _grantAccessibility() async {
    AndroidPermissionManager.startAction(kActionAccessibilitySettings);
    // The user must manually enable the accessibility service in system settings.
    // We poll every second until it's enabled.
    for (var i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      if (gFFI.serverModel.inputOk) break;
    }
    if (!mounted) return;
    setState(() => _states[_kAccessibility] =
        _states[_kAccessibility]!.copyWith(gFFI.serverModel.inputOk));
  }

  Future<void> _grantFloatingWindow() async {
    final serverModel = gFFI.serverModel;
    final ok = await serverModel.checkFloatingWindowPermission();
    if (!mounted) return;
    setState(() => _states[_kFloating] = _states[_kFloating]!.copyWith(ok));
  }

  Future<void> _grantNotification() async {
    final serverModel = gFFI.serverModel;
    final ok = await serverModel.checkRequestNotificationPermission();
    if (!mounted) return;
    setState(
        () => _states[_kNotification] = _states[_kNotification]!.copyWith(ok));
  }

  Future<void> _grantStorage() async {
    if (!await AndroidPermissionManager.check(kManageExternalStorage)) {
      await AndroidPermissionManager.request(kManageExternalStorage);
    }
    final ok = await AndroidPermissionManager.check(kManageExternalStorage);
    if (!mounted) return;
    setState(() => _states[_kStorage] = _states[_kStorage]!.copyWith(ok));
  }

  Future<void> _grantAudio() async {
    final ok = await AndroidPermissionManager.request(kRecordAudio);
    if (!mounted) return;
    setState(() => _states[_kAudio] = _states[_kAudio]!.copyWith(ok));
  }
}

class _PermStatus {
  final bool granted;
  final String label;
  final String description;
  final bool optional;

  _PermStatus(this.granted, this.label, this.description,
      {this.optional = false});

  _PermStatus copyWith(bool granted) =>
      _PermStatus(granted, label, description, optional: optional);
}
