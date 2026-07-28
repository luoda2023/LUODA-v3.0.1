import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import '../../models/platform_model.dart';

/// One-time permission wizard shown on first install.
/// Requests ALL required Android permissions at once so the user never
/// sees scattered permission prompts later.
class FirstRunPermissionWizard extends StatefulWidget {
  /// Returns true if the wizard completed (all permissions granted or
  /// previously completed), false if the user dismissed it early.
  static Future<bool> showIfNeeded(BuildContext context) async {
    final done = await bind.mainGetLocalOption(key: kFirstRunPermDoneKey);
    if (done == 'Y') return true;
    if (!context.mounted) return false;
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const FirstRunPermissionWizard(),
      ),
    );
    if (completed == true) {
      await bind.mainSetLocalOption(key: kFirstRunPermDoneKey, value: 'Y');
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

  static const _kFloating = 'floating';
  static const _kNotification = 'notification';
  static const _kStorage = 'storage';
  static const _kAudio = 'audio';
  static const _kAccessibility = 'accessibility';

  @override
  void initState() {
    super.initState();
    _initChecks();
  }

  Future<void> _initChecks() async {
    final floating =
        await AndroidPermissionManager.check(kSystemAlertWindow);
    final notification = androidVersion < 33 || isIOS
        ? true
        : await AndroidPermissionManager.check(kAndroid13Notification);
    final storage =
        await AndroidPermissionManager.check(kManageExternalStorage);
    final audio = androidVersion < 30 || kIsIOS
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
          translate('Required to transfer files between devices'));
      _states[_kAudio] = _PermStatus(
          audio,
          translate('Audio capture'),
          translate('Required to transmit device audio'));
      _states[_kAccessibility] = _PermStatus(
          accessibility,
          translate('Input control'),
          translate(
              'Required for remote mouse/keyboard control of this device'));
      _checking = false;
    });
  }

  bool get _allGranted =>
      _states.values.every((s) => s.granted);

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
                              'Grant these permissions once so LUODA can work smoothly. You will not be asked again.'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 28),

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
                      onPressed:
                          _allGranted ? () => Navigator.of(context).pop(true) : null,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(translate('Continue')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (!_allGranted)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          translate('Grant all permissions above to continue'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
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
                  Text(
                    status.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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

  _PermStatus(this.granted, this.label, this.description);

  _PermStatus copyWith(bool granted) =>
      _PermStatus(granted, label, description);
}
