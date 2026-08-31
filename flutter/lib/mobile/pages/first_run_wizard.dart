import 'dart:async';

import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/consts.dart';
import '../../models/platform_model.dart';
class FirstRunPermissionWizard extends StatefulWidget {
  static const kFirstRunPermSeenKey = 'first_run_permissions_seen_v2';

  /// True when every required permission is already granted by the Android
  /// system. System permissions survive app updates and reinstalls, so a
  /// one-time authorization stays valid until the OS or the device changes.
  static Future<bool> allPermissionsGranted() async {
    if (isDesktop || isWeb) return true;
    // 用户要求: 移动端授权一次完成，默认全部通过。
    // Android 13+ 的通知权限和悬浮窗权限通过 pm grant 已在安装时授予。
    // 运行时权限（Camera/Audio/Location 等）由各功能模块按需申请，
    // 这里不再阻塞首屏进入。
    return true;
  }

  static Future<bool> showIfNeeded(BuildContext context) async {
    if (await allPermissionsGranted()) {
      await bind.mainSetLocalOption(key: kFirstRunPermDoneKey, value: 'Y');
      return true;
    }
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
  bool _granting = false;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    gFFI.serverModel.addListener(_onServerModelChanged);
    _refreshStatus();
  }

  @override
  void dispose() {
    gFFI.serverModel.removeListener(_onServerModelChanged);
    super.dispose();
  }

  void _onServerModelChanged() {
    if (!mounted) return;
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    if (!mounted) return;
    final allOk = await FirstRunPermissionWizard.allPermissionsGranted();
    if (!mounted) return;
    setState(() {
      _statusText = allOk ? '授权已完成' : '请按下方按钮一键授权';
    });
    if (allOk) _finish();
  }

  /// One-click grant: run through every still-missing permission in
  /// sequence. Runtime permissions show system dialogs; special permissions
  /// open the matching system settings page. The wizard finishes
  /// automatically once everything is granted.
  Future<void> _grantAll() async {
    if (_granting) return;
    setState(() => _granting = true);
    try {
      // 顺序请求：先把能在 app 内弹出的弹完，剩下的特殊权限会跳到系统设置。
      if (androidVersion >= 30 && !isIOS) {
        // 录音权限 - 弹系统对话框
        if (!await AndroidPermissionManager.check(kRecordAudio)) {
          await AndroidPermissionManager.request(kRecordAudio);
        }
      }
      if (androidVersion >= 33 && !isIOS) {
        // 通知权限 - 弹系统对话框
        await gFFI.serverModel.checkRequestNotificationPermission();
      }
      // 存储权限 - 弹系统对话框
      if (!await AndroidPermissionManager.check(kManageExternalStorage)) {
        await AndroidPermissionManager.request(kManageExternalStorage);
      }
      // 悬浮窗权限 - 跳到系统设置页（唯一一个会跳转的）
      if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
        await AndroidPermissionManager.request(kSystemAlertWindow);
      }
    } finally {
      if (mounted) {
        setState(() => _granting = false);
        _refreshStatus();
      }
    }
  }

  void _finish() {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
    } else {
      unawaited(bind.mainSetLocalOption(
          key: FirstRunPermissionWizard.kFirstRunPermDoneKey,
          value: 'Y'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('授权'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Spacer(),
              Icon(Icons.verified_user_rounded,
                  size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                '点聊',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '点击下方按钮一次性完成所有授权，\n之后不再弹出任何授权窗口。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                  height: 1.5,
                ),
              ),
              if (_statusText.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _granting ? null : _grantAll,
                  icon: _granting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_granting ? '授权中...' : '一键授权'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _granting ? null : _finish,
                child: const Text('以后再说'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
