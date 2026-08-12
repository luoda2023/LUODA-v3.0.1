import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:luoda_flutter/desktop/pages/desktop_home_page.dart';
import 'package:luoda_flutter/mobile/widgets/dialog.dart';
import 'package:luoda_flutter/models/chat_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import 'home_page.dart';

/// 本机公网 IPv4 缓存（多页面共享）。
String _cachedPublicIp = '';
DateTime? _lastPublicIpFetchAt;

/// 获取本机公网 IPv4（多个服务轮试），失败返回 null。
Future<String?> _fetchPublicIpv4() async {
  const endpoints = <String>[
    'https://api.ipify.org?format=text',
    'https://4.ipw.cn',
    'https://ifconfig.me/ip',
  ];
  for (final url in endpoints) {
    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final ip = res.body.trim();
        if (_isValidPublicIpv4(ip)) return ip;
      }
    } catch (_) {}
  }
  return null;
}

bool _isValidPublicIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) return false;
    octets.add(octet);
  }
  final first = octets[0];
  if (first <= 0 || first >= 224 || first == 127) return false;
  if (first == 169 && octets[1] == 254) return false;
  if (first == 100 && octets[1] >= 64 && octets[1] <= 127) return false;
  if (first == 192 && octets[1] == 168) return false;
  if (first == 172 && octets[1] >= 16 && octets[1] <= 31) return false;
  return first != 10;
}

class ServerPage extends StatefulWidget implements PageShape {
  @override
  final title = translate("Remote assistance");

  @override
  final icon = const Icon(Icons.desktop_windows_outlined);

  @override
  final appBarActions = (!bind.isDisableSettings() &&
          bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) != 'Y')
      ? [_DropDownAction()]
      : [];

  ServerPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ServerPageState();
}

class _DropDownAction extends StatelessWidget {
  _DropDownAction();

  // should only have one action
  final actions = [
    PopupMenuButton<String>(
        tooltip: "",
        icon: const Icon(Icons.more_vert),
        itemBuilder: (context) {
          listTile(String text, bool checked) {
            return ListTile(
                title: Text(translate(text)),
                trailing: Icon(
                  Icons.check,
                  color: checked ? null : Colors.transparent,
                ));
          }

          final approveMode = gFFI.serverModel.approveMode;
          final verificationMethod = gFFI.serverModel.verificationMethod;
          final showPasswordOption = approveMode != 'click';
          final isApproveModeFixed = isOptionFixed(kOptionApproveMode);
          final isNumericOneTimePasswordFixed =
              isOptionFixed(kOptionAllowNumericOneTimePassword);
          final isAllowNumericOneTimePassword =
              gFFI.serverModel.allowNumericOneTimePassword;
          return [
            if (!isChangeIdDisabled())
              PopupMenuItem(
                enabled: gFFI.serverModel.connectStatus > 0,
                value: "changeID",
                child: Text(translate("Change ID")),
              ),
            if (!isChangeIdDisabled()) const PopupMenuDivider(),
            PopupMenuItem(
              value: 'AcceptSessionsViaPassword',
              child: listTile(
                  'Accept sessions via password', approveMode == 'password'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: 'AcceptSessionsViaClick',
              child:
                  listTile('Accept sessions via click', approveMode == 'click'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: "AcceptSessionsViaBoth",
              child: listTile("Accept sessions via both",
                  approveMode != 'password' && approveMode != 'click'),
              enabled: !isApproveModeFixed,
            ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption &&
                verificationMethod != kUseTemporaryPassword &&
                !isChangePermanentPasswordDisabled())
              PopupMenuItem(
                value: "setPermanentPassword",
                child: Text(translate("Set permanent password")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "setTemporaryPasswordLength",
                child: Text(translate("One-time password length")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "allowNumericOneTimePassword",
                child: listTile(translate("Numeric one-time password"),
                    isAllowNumericOneTimePassword),
                enabled: !isNumericOneTimePasswordFixed,
              ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseTemporaryPassword,
                child: listTile('Use one-time password',
                    verificationMethod == kUseTemporaryPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUsePermanentPassword,
                child: listTile('Use permanent password',
                    verificationMethod == kUsePermanentPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseBothPasswords,
                child: listTile(
                    'Use both passwords',
                    verificationMethod != kUseTemporaryPassword &&
                        verificationMethod != kUsePermanentPassword),
              ),
          ];
        },
        onSelected: (value) async {
          if (value == "changeID") {
            changeIdDialog();
          } else if (value == "setPermanentPassword") {
            setPasswordDialog();
          } else if (value == "setTemporaryPasswordLength") {
            setTemporaryPasswordLengthDialog(gFFI.dialogManager);
          } else if (value == "allowNumericOneTimePassword") {
            gFFI.serverModel.switchAllowNumericOneTimePassword();
            gFFI.serverModel.updatePasswordModel();
          } else if (value == kUsePermanentPassword ||
              value == kUseTemporaryPassword ||
              value == kUseBothPasswords) {
            callback() {
              bind.mainSetOption(key: kOptionVerificationMethod, value: value);
              gFFI.serverModel.updatePasswordModel();
            }

            if (value == kUsePermanentPassword &&
                (await bind.mainGetCommon(key: "permanent-password-set")) !=
                    "true") {
              if (isChangePermanentPasswordDisabled()) {
                callback();
                return;
              }
              setPasswordDialog(notEmptyCallback: callback);
            } else {
              callback();
            }
          } else if (value.startsWith("AcceptSessionsVia")) {
            value = value.substring("AcceptSessionsVia".length);
            if (value == "Password") {
              gFFI.serverModel.setApproveMode('password');
            } else if (value == "Click") {
              gFFI.serverModel.setApproveMode('click');
            } else {
              gFFI.serverModel.setApproveMode(defaultOptionApproveMode);
            }
          }
        })
  ];

  @override
  Widget build(BuildContext context) {
    return actions[0];
  }
}

class _ServerPageState extends State<ServerPage> {
  Timer? _updateTimer;
  // 上次重建时渲染的 ID / 公网 IP：3 秒轮询只在真正变化时才 setState，
  // 避免 ID/IP 不变时每 3 秒整页重建浪费 CPU/电量。
  String _lastRenderedId = '';
  String _lastRenderedIp = '';

  Future<void> _refreshPublicIp() async {
    final now = DateTime.now();
    if (_lastPublicIpFetchAt != null &&
        now.difference(_lastPublicIpFetchAt!) < const Duration(minutes: 2)) {
      return;
    }
    _lastPublicIpFetchAt = now;
    final ip = await _fetchPublicIpv4();
    if (ip != null && mounted && _cachedPublicIp != ip) {
      setState(() => _cachedPublicIp = ip);
    }
  }

  @override
  void initState() {
    super.initState();
    if (isAndroid) {
      unawaited(bind.mainCheckConnectStatus());
    }
    _updateTimer = periodic_immediate(const Duration(seconds: 3), () async {
      await gFFI.serverModel.fetchID();
      await _refreshPublicIp();
      if (isAndroid && mounted) {
        // 只有 ID 或公网 IP 发生变化才重建；其余信息（在线状态、密码、
        // 客户端列表）由 ServerModel 自身的 notifyListeners 驱动刷新。
        final currentId = gFFI.serverModel.serverId.value.text.trim();
        if (currentId != _lastRenderedId ||
            _cachedPublicIp != _lastRenderedIp) {
          _lastRenderedId = currentId;
          _lastRenderedIp = _cachedPublicIp;
          setState(() {});
        }
      }
    });
    gFFI.serverModel.checkAndroidPermission();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  /// 协助页顶部：与会议页一致绿色渐变 hero 卡片。
  Widget _buildAssistHero(BuildContext context) {
    final serverModel = gFFI.serverModel;
    final id = serverModel.serverId.value.text.trim();
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
                child: const Icon(Icons.support_agent_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      translate('Remote assistance'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      translate('Connect and help your devices anytime'),
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
              _assistHeroChip(
                icon: Icons.badge_outlined,
                label: id.isEmpty ? translate('Device ID') : 'ID $id',
                onTap: () {
                  if (id.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: id));
                    showToast(translate('Copied'));
                  }
                },
              ),
              const SizedBox(width: 8),
              // 连接协助：点击弹出 ID/IP 输入框发起远程协助（替代原来的在线状态提示）。
              Expanded(
                child: InkWell(
                  onTap: () => _showAssistConnectDialog(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.screen_share_rounded,
                            color: Colors.white, size: 15),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            translate('Connect assist'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _assistHeroChip({
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

  /// 连接协助：弹出输入框，输入 ID 或 IP:端口 发起远程协助连接。
  void _showAssistConnectDialog(BuildContext context) {
    final controller = TextEditingController();
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: <Widget>[
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
            Text(
              translate('Remote assistance'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.go,
          onSubmitted: (value) {
            final trimmed = value.trim();
            Navigator.of(dialogContext).pop();
            if (trimmed.isNotEmpty) {
              HomePage.homeKey.currentState?.connectByInput(trimmed);
            }
          },
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
                borderRadius: BorderRadius.circular(10),
              ),
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
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    checkService();
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
            builder: (context, serverModel, child) => SingleChildScrollView(
                  controller: gFFI.serverModel.controller,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(
                        // 与会议页一致的页边距
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            _buildAssistHero(context),
                            buildPresetPasswordWarningMobile(),
                            gFFI.serverModel.isStart
                                ? ServerInfo()
                                : ServiceNotRunningNotification(),
                            const ConnectionManager(),
                            const PermissionChecker(),
                            SizedBox.fromSize(size: const Size(0, 15.0)),
                          ],
                        ),
                      ),
                    ),
                  ),
                )));
  }
}

void checkService() async {
  gFFI.invokeMethod("check_service");
  // for Android 10/11, request MANAGE_EXTERNAL_STORAGE permission from system setting page
  if (AndroidPermissionManager.isWaitingFile() && !gFFI.serverModel.fileOk) {
    AndroidPermissionManager.complete(kManageExternalStorage,
        await AndroidPermissionManager.check(kManageExternalStorage));
    debugPrint("file permission finished");
  }
}

class ServiceNotRunningNotification extends StatelessWidget {
  ServiceNotRunningNotification({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);

    return PaddingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      translate('Service is not running'),
                      style: const TextStyle(
                        fontSize: MobileText.bodyLg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      translate('android_start_service_tip'),
                      style: TextStyle(
                        fontSize: MobileText.caption,
                        height: 1.4,
                        color: mobileMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              onPressed: () {
                if (_shouldShowScamWarning()) {
                  showScamWarning(context, serverModel);
                } else {
                  serverModel.toggleService();
                }
              },
              label: Text(translate('Start service')),
            ),
          ),
        ],
      ),
    );
  }
}

bool _shouldShowScamWarning() {
  return gFFI.userModel.userName.value.isEmpty &&
      bind.mainGetLocalOption(key: 'show-scam-warning') != 'N';
}

class ScamWarningDialog extends StatefulWidget {
  const ScamWarningDialog({required this.serverModel, super.key});

  final ServerModel serverModel;

  @override
  State<ScamWarningDialog> createState() => _ScamWarningDialogState();
}

class _ScamWarningDialogState extends State<ScamWarningDialog> {
  int _countdown = bind.isCustomClient() ? 0 : 12;
  bool _dontShowAgain = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_countdown > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          _countdown--;
          if (_countdown <= 0) timer.cancel();
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _countdown > 0;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(translate('Warning'))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Image.asset(
                  'assets/scam.png',
                  width: 160,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                translate('scam_title'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                '${translate('scam_text1')}\n\n${translate('scam_text2')}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _dontShowAgain,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(translate("Don't show again")),
                onChanged: (value) {
                  setState(() => _dontShowAgain = value ?? false);
                },
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translate('Decline')),
        ),
        FilledButton(
          onPressed: locked
              ? null
              : () {
                  Navigator.of(context).pop();
                  if (_dontShowAgain) {
                    bind.mainSetLocalOption(
                      key: 'show-scam-warning',
                      value: 'N',
                    );
                  }
                  widget.serverModel.toggleService();
                },
          child: Text(
            locked
                ? '${translate('I Agree')} (${_countdown}s)'
                : translate('I Agree'),
          ),
        ),
      ],
    );
  }
}

class ServerInfo extends StatelessWidget {
  final model = gFFI.serverModel;
  final emptyController = TextEditingController(text: "-");

  ServerInfo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);

    const Color colorPositive = Colors.green;
    const Color colorNegative = Colors.red;
    const double iconMarginRight = 15;
    const double iconSize = 24;
    final TextStyle textStyleHeading = TextStyle(
      fontSize: MobileText.body,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).brightness == Brightness.dark
          ? MyTheme.mutedDark
          : MyTheme.mutedLight,
    );
    const TextStyle textStyleValue = TextStyle(
      fontSize: MobileText.title,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );

    void copyToClipboard(String value) {
      Clipboard.setData(ClipboardData(text: value));
      showToast(translate('Copied'));
    }

    Widget ConnectionStateNotification() {
      if (serverModel.connectStatus > 0) {
        return Row(children: [
          const Icon(Icons.check, color: colorPositive, size: iconSize)
              .marginOnly(right: iconMarginRight),
          Expanded(child: Text(translate('Online'))),
        ]);
      }
      final directPort =
          bind.mainGetOptionSync(key: kOptionDirectAccessPort).trim();
      if (directPort.isNotEmpty) {
        return Row(children: [
          const Icon(Icons.check, color: colorPositive, size: iconSize)
              .marginOnly(right: iconMarginRight),
          Expanded(child: Text(translate('Direct listening'))),
        ]);
      } else if (serverModel.connectStatus == -1) {
        return Row(children: [
          const Icon(Icons.warning_amber_sharp,
                  color: colorNegative, size: iconSize)
              .marginOnly(right: iconMarginRight),
          Expanded(child: Text(translate('not_ready_status')))
        ]);
      } else if (serverModel.connectStatus == 0) {
        return Row(children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
              .marginOnly(left: 4, right: iconMarginRight),
          Expanded(child: Text(translate('connecting_status')))
        ]);
      } else {
        return Row(children: [
          const Icon(Icons.check, color: colorPositive, size: iconSize)
              .marginOnly(right: iconMarginRight),
          Expanded(child: Text(translate('Ready')))
        ]);
      }
    }

    final showOneTime = serverModel.approveMode != 'click' &&
        serverModel.verificationMethod != kUsePermanentPassword;
    return PaddingCard(
        title: translate('Your Device'),
        titleIcon: const Icon(Icons.devices_rounded, size: 20),
        child: Column(
          // ID
          children: [
            Row(children: [
              const Icon(Icons.perm_identity,
                      color: Colors.grey, size: iconSize)
                  .marginOnly(right: iconMarginRight),
              Text(
                translate('ID'),
                style: textStyleHeading,
              )
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(
                child: Text(
                  model.serverId.value.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyleValue,
                ),
              ),
              IconButton(
                  tooltip: translate('Copy'),
                  icon: Icon(Icons.copy_outlined),
                  onPressed: () {
                    copyToClipboard(model.serverId.value.text.trim());
                  })
            ]).marginOnly(left: 39, bottom: 10),
            // Password
            Row(children: [
              const Icon(Icons.lock_outline, color: Colors.grey, size: iconSize)
                  .marginOnly(right: iconMarginRight),
              Text(
                translate('One-time Password'),
                style: textStyleHeading,
              )
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(
                child: Text(
                  !showOneTime ? '-' : model.serverPasswd.value.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyleValue,
                ),
              ),
              !showOneTime
                  ? SizedBox.shrink()
                  : Row(children: [
                      IconButton(
                          tooltip: translate('Refresh'),
                          icon: const Icon(Icons.refresh),
                          onPressed: () => bind.mainUpdateTemporaryPassword()),
                      IconButton(
                          tooltip: translate('Copy'),
                          icon: Icon(Icons.copy_outlined),
                          onPressed: () {
                            copyToClipboard(
                                model.serverPasswd.value.text.trim());
                          })
                    ])
            ]).marginOnly(left: 40, bottom: 15),
            ConnectionStateNotification(),
            // IP直连信息：公网+内网+UPnP状态，与桌面端对齐
            _buildDirectAccessInfo(context),
          ],
        ));
  }

  /// 显示 IP 直连地址（公网+内网）和 UPnP 映射状态。
  /// 与桌面端 buildDirectAccessBoard 一致，让手机用户也能
  /// 把自己的 IP 告诉对方进行直连。
  Widget _buildDirectAccessInfo(BuildContext context) {
    if (isWeb) return const SizedBox.shrink();
    final publicIP = _cachedPublicIp.isNotEmpty
        ? _cachedPublicIp
        : bind.mainGetOptionSync(key: 'public-ip');
    final lanIP = bind.mainGetOptionSync(key: 'lan-ip');
    final directPort = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    final upnpStatus = bind.mainGetOptionSync(key: 'upnp-status');
    final upnpOk = upnpStatus == 'ok';
    final upnpColor = upnpOk
        ? Colors.green
        : (upnpStatus == 'fail' ? Colors.orange : Colors.grey);
    final upnpTip = upnpStatus == 'unsupported'
        ? 'upnp_mapping_unsupported_tip'
        : upnpStatus == 'disabled'
            ? 'direct_listener_disabled_tip'
            : upnpStatus == 'fail'
                ? 'upnp_mapping_failed_tip'
                : upnpStatus == 'ok'
                    ? 'upnp_mapping_ready_tip'
                    : 'upnp_mapping_unknown_tip';
    String publicAddr = '';
    String lanAddr = '';
    List<int>? ipv4Octets(String value) {
      final parts = value.split('.');
      if (parts.length != 4) return null;
      final octets = parts.map(int.tryParse).toList();
      if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
        return null;
      }
      return octets.cast<int>();
    }

    bool isLanIpv4(List<int> octets) =>
        octets[0] == 10 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168);

    bool isPublicIpv4(List<int> octets) =>
        octets[0] > 0 &&
        octets[0] < 224 &&
        octets[0] != 127 &&
        !(octets[0] == 169 && octets[1] == 254) &&
        !(octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127) &&
        !(octets[0] == 192 && octets[1] == 0 && octets[2] == 2) &&
        !(octets[0] == 198 && octets[1] >= 18 && octets[1] <= 19) &&
        !(octets[0] == 198 && octets[1] == 51 && octets[2] == 100) &&
        !(octets[0] == 203 && octets[1] == 0 && octets[2] == 113) &&
        !isLanIpv4(octets);

    final port = int.tryParse(directPort);
    final publicOctets = ipv4Octets(publicIP);
    final lanOctets = ipv4Octets(lanIP);
    if (port != null && port > 0 && port <= 65535) {
      if (publicOctets != null && isPublicIpv4(publicOctets)) {
        publicAddr = '$publicIP:$port';
      }
      if (lanOctets != null && isLanIpv4(lanOctets)) {
        lanAddr = '$lanIP:$port';
      }
    }
    final hasAny = publicAddr.isNotEmpty || lanAddr.isNotEmpty;
    if (!hasAny) return SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate('Direct IP Access'),
            style: TextStyle(
              fontSize: MobileText.bodySm,
              fontWeight: FontWeight.bold,
              color: mobileMuted(context),
            ),
          ),
          SizedBox(height: 4),
          _mobileIpRow(context, translate('Public network'), publicAddr),
          SizedBox(height: 2),
          if (publicAddr.isNotEmpty && directPort.isNotEmpty)
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: EdgeInsets.only(right: 6, left: 4),
                  decoration: BoxDecoration(
                    color: upnpColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    translate(upnpTip),
                    style: TextStyle(
                        fontSize: MobileText.caption,
                        height: 1.3,
                        color: mobileMuted(context)),
                  ),
                ),
              ],
            ),
          SizedBox(height: 4),
          _mobileIpRow(context, translate('Local network'), lanAddr),
        ],
      ),
    );
  }

  Widget _mobileIpRow(BuildContext context, String label, String addr) {
    final text = addr.isNotEmpty ? addr : translate('Not available');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: MobileText.captionSm,
                fontWeight: FontWeight.w600,
                color: mobileMuted(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: MobileText.bodySm,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: addr.isNotEmpty ? null : mobileMuted(context),
              ),
            ),
          ),
          if (addr.isNotEmpty)
            IconButton(
              tooltip: translate('Copy'),
              constraints: const BoxConstraints.tightFor(
                width: 44,
                height: 44,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: addr));
                showToast(translate('Copied'));
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}

class PermissionChecker extends StatefulWidget {
  const PermissionChecker({Key? key}) : super(key: key);

  @override
  State<PermissionChecker> createState() => _PermissionCheckerState();
}

class _PermissionCheckerState extends State<PermissionChecker>
    with WidgetsBindingObserver {
  bool _isCompleting = false;
  bool _notificationOk = androidVersion < 33;
  bool _floatingWindowOk = androidVersion < 23;

  bool get _floatingWindowRequired =>
      bind.mainGetLocalOption(key: kOptionDisableFloatingWindow) != 'Y';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSystemPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    gFFI.serverModel.checkAndroidPermission();
    _refreshSystemPermissions();
  }

  Future<void> _refreshSystemPermissions() async {
    final notificationOk = androidVersion < 33 ||
        await AndroidPermissionManager.check(kAndroid13Notification);
    final floatingWindowOk = !_floatingWindowRequired ||
        androidVersion < 23 ||
        await AndroidPermissionManager.check(kSystemAlertWindow);
    if (!mounted) return;
    setState(() {
      _notificationOk = notificationOk;
      _floatingWindowOk = floatingWindowOk;
    });
  }

  Future<void> _completePermissions(ServerModel serverModel) async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);
    try {
      if (!serverModel.fileOk) {
        await serverModel.toggleFile();
        if (!serverModel.fileOk) return;
      }
      if (androidVersion >= 30 && !serverModel.audioOk) {
        await serverModel.toggleAudio();
        if (!serverModel.audioOk) return;
      }
      if (!_notificationOk) {
        _notificationOk =
            await serverModel.checkRequestNotificationPermission();
        if (!_notificationOk) return;
      }
      if (_floatingWindowRequired && !_floatingWindowOk) {
        _floatingWindowOk = await serverModel.checkFloatingWindowPermission();
        if (!_floatingWindowOk) return;
      }
      if (!serverModel.clipboardOk) {
        await serverModel.toggleClipboard();
      }
      if (!serverModel.inputOk) {
        showToast(translate(
          'Enable input control in system settings, then return to DotChat.',
        ));
        AndroidPermissionManager.startAction(kActionAccessibilitySettings);
        return;
      }
      if (!serverModel.mediaOk) {
        if (_shouldShowScamWarning()) {
          showScamWarning(context, serverModel);
        } else {
          await serverModel.toggleService();
        }
        return;
      }
      showToast(translate('Permission setup complete'));
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
        await _refreshSystemPermissions();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final hasAudioPermission = androidVersion >= 30;
    final hideStopService = isAndroid &&
        bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y';
    final states = <bool>[
      serverModel.mediaOk,
      serverModel.inputOk,
      serverModel.fileOk,
      serverModel.clipboardOk,
      if (hasAudioPermission) serverModel.audioOk,
      if (androidVersion >= 33) _notificationOk,
      if (_floatingWindowRequired) _floatingWindowOk,
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabledCount = states.where((enabled) => enabled).length;
    final allEnabled = enabledCount == states.length;
    return PaddingCard(
        title: translate("Permission center"),
        titleIcon: const Icon(Icons.verified_user_outlined, size: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          SizedBox(
                            width: 52,
                            height: 52,
                            child: CircularProgressIndicator(
                              value: states.isEmpty
                                  ? 0
                                  : enabledCount / states.length,
                              strokeWidth: 5,
                              backgroundColor: dark
                                  ? const Color(0xFF2B2D32)
                                  : const Color(0xFFDCEEDF),
                              color: MyTheme.primary,
                            ),
                          ),
                          Text(
                            '$enabledCount/${states.length}',
                            style: TextStyle(
                              fontSize: MobileText.bodySm,
                              fontWeight: FontWeight.w700,
                              color: MyTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            allEnabled
                                ? translate(
                                    'All required permissions are ready')
                                : translate('Permission center'),
                            style: const TextStyle(
                              fontSize: MobileText.bodyLg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            translate(
                                'Only missing permissions will be requested.'),
                            style: TextStyle(
                              fontSize: MobileText.caption,
                              color: dark
                                  ? MyTheme.mutedDark
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!allEnabled) ...<Widget>[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _isCompleting
                          ? null
                          : () => _completePermissions(serverModel),
                      icon: _isCompleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_user_outlined, size: 19),
                      label: Text(
                        translate('Complete required permissions'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          serverModel.mediaOk && !hideStopService
              ? TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        minimumSize: const Size(0, 48),
                      ),
                      icon: const Icon(Icons.stop_rounded),
                      onPressed: serverModel.toggleService,
                      label: Text(translate("Stop service")))
                  .marginOnly(bottom: 8)
              : SizedBox.shrink(),
          if (!hideStopService || !serverModel.mediaOk)
            PermissionRow(
              translate("Screen Capture"),
              serverModel.mediaOk,
              _shouldShowScamWarning()
                  ? () => showScamWarning(context, serverModel)
                  : serverModel.toggleService,
              icon: Icons.screen_share_rounded,
            ),
          PermissionRow(translate("Input Control"), serverModel.inputOk,
              serverModel.toggleInput,
              icon: Icons.touch_app_rounded),
          PermissionRow(translate("Transfer file"), serverModel.fileOk,
              serverModel.toggleFile,
              icon: Icons.folder_copy_rounded),
          hasAudioPermission
              ? PermissionRow(translate("Audio Capture"), serverModel.audioOk,
                  serverModel.toggleAudio,
                  icon: Icons.mic_rounded)
              : Row(children: [
                  Icon(Icons.info_outline).marginOnly(right: 15),
                  Expanded(
                      child: Text(
                    translate("android_version_audio_tip"),
                    style: const TextStyle(color: MyTheme.darkGray),
                  ))
                ]),
          PermissionRow(translate("Enable clipboard"), serverModel.clipboardOk,
              serverModel.toggleClipboard,
              icon: Icons.content_paste_rounded),
          if (androidVersion >= 33)
            PermissionRow(
              translate('Notifications'),
              _notificationOk,
              () async {
                await serverModel.checkRequestNotificationPermission();
                await _refreshSystemPermissions();
              },
              icon: Icons.notifications_rounded,
            ),
          if (_floatingWindowRequired)
            PermissionRow(
              translate('Floating window'),
              _floatingWindowOk,
              () async {
                await serverModel.checkFloatingWindowPermission();
                await _refreshSystemPermissions();
              },
              icon: Icons.picture_in_picture_alt_rounded,
            ),
        ]));
  }
}

class PermissionRow extends StatelessWidget {
  const PermissionRow(
    this.name,
    this.isOk,
    this.onPressed, {
    this.icon = Icons.check_circle_outline_rounded,
    Key? key,
  }) : super(key: key);

  final String name;
  final bool isOk;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: SwitchListTile(
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
            secondary: SizedBox(
              width: 36,
              child: Icon(
                icon,
                size: 20,
                color: isOk
                    ? MyTheme.primary
                    : dark
                        ? MyTheme.mutedDark
                        : MyTheme.mutedLight,
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(
                fontSize: MobileText.body,
                fontWeight: FontWeight.w500,
              ),
            ),
            value: isOk,
            activeColor: MyTheme.primary,
            onChanged: (_) => onPressed(),
          ),
        ),
        Container(
          height: 0.5,
          margin: const EdgeInsets.only(left: 48),
          color: dark
              ? const Color(0xFF3A3D43)
              : const Color(0x80E5E5E5),
        ),
      ],
    );
  }
}

class ConnectionManager extends StatelessWidget {
  const ConnectionManager({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    return Column(
        children: serverModel.clients
            .map((client) => PaddingCard(
                title: translate(
                    client.isFileTransfer ? "Transfer file" : "Share screen"),
                titleIcon: client.isFileTransfer
                    ? Icon(Icons.folder_outlined)
                    : Icon(Icons.mobile_screen_share),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: ClientInfo(client)),
                      Expanded(
                          flex: -1,
                          child: client.isFileTransfer || !client.authorized
                              ? const SizedBox.shrink()
                              : IconButton(
                                  onPressed: () {
                                    gFFI.chatModel.changeCurrentKey(
                                        MessageKey(client.peerId, client.id));
                                    HomePage.homeKey.currentState
                                        ?.selectChatPage();
                                  },
                                  icon: unreadTopRightBuilder(
                                      client.unreadChatMessageCount)))
                    ],
                  ),
                  client.authorized
                      ? const SizedBox.shrink()
                      : Text(
                          translate("android_new_connection_tip"),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ).marginOnly(bottom: 5),
                  client.authorized
                      ? _buildDisconnectButton(client)
                      : _buildNewConnectionHint(serverModel, client),
                  if (client.incomingVoiceCall && !client.inVoiceCall)
                    ..._buildNewVoiceCallHint(context, serverModel, client),
                ])))
            .toList());
  }

  Widget _buildDisconnectButton(Client client) {
    final disconnectButton = ElevatedButton.icon(
      style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.red)),
      icon: const Icon(Icons.close),
      onPressed: () {
        bind.cmCloseConnection(connId: client.id);
        gFFI.invokeMethod("cancel_notification", client.id);
      },
      label: Text(translate("Disconnect")),
    );
    final buttons = [disconnectButton];
    if (client.inVoiceCall) {
      buttons.insert(
        0,
        ElevatedButton.icon(
          style:
              ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.red)),
          icon: const Icon(Icons.phone),
          label: Text(translate("Stop")),
          onPressed: () {
            bind.cmCloseVoiceCall(id: client.id);
            gFFI.invokeMethod("cancel_notification", client.id);
          },
        ),
      );
    }

    if (buttons.length == 1) {
      return Container(
        alignment: Alignment.centerRight,
        child: disconnectButton,
      );
    } else {
      return Row(
        children: buttons,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
      );
    }
  }

  Widget _buildNewConnectionHint(ServerModel serverModel, Client client) {
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      TextButton(
          child: Text(translate("Dismiss")),
          onPressed: () {
            serverModel.sendLoginResponse(client, false);
          }).marginOnly(right: 15),
      if (serverModel.approveMode != 'password')
        ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: Text(translate("Accept")),
            onPressed: () {
              serverModel.sendLoginResponse(client, true);
            }),
    ]);
  }

  List<Widget> _buildNewVoiceCallHint(
      BuildContext context, ServerModel serverModel, Client client) {
    return [
      Text(
        translate("android_new_voice_call_tip"),
        style: Theme.of(context).textTheme.bodyMedium,
      ).marginOnly(bottom: 5),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(
            child: Text(translate("Dismiss")),
            onPressed: () {
              serverModel.handleVoiceCall(client, false);
            }).marginOnly(right: 15),
        if (serverModel.approveMode != 'password')
          ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: Text(translate("Accept")),
              onPressed: () {
                serverModel.handleVoiceCall(client, true);
              }),
      ])
    ];
  }
}

class PaddingCard extends StatelessWidget {
  const PaddingCard({Key? key, required this.child, this.title, this.titleIcon})
      : super(key: key);

  final String? title;
  final Icon? titleIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final children = [child];
    if (title != null) {
      children.insert(
          0,
          Padding(
              padding: const EdgeInsets.fromLTRB(0, 5, 0, 8),
              child: Row(
                children: [
                  titleIcon?.marginOnly(right: 10) ?? const SizedBox.shrink(),
                  Expanded(
                    child: Text(title ?? '',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.merge(const TextStyle(
                              fontSize: MobileText.bodyLg,
                              fontWeight: FontWeight.w700,
                            ))),
                  )
                ],
              )));
    }
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: dark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class ClientInfo extends StatelessWidget {
  final Client client;
  ClientInfo(this.client);

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Row(
            children: [
              Expanded(
                  flex: -1,
                  child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildAvatar(context))),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(client.name,
                        style: const TextStyle(fontSize: MobileText.titleSm)),
                    const SizedBox(width: 8),
                    Text(client.peerId,
                        style: const TextStyle(fontSize: MobileText.caption))
                  ]))
            ],
          ),
        ]));
  }

  Widget _buildAvatar(BuildContext context) {
    final fallback = CircleAvatar(
      backgroundColor: str2color(client.name,
          Theme.of(context).brightness == Brightness.light ? 255 : 150),
      child: Text(client.name.isNotEmpty ? client.name[0] : '?'),
    );
    return buildAvatarWidget(
          avatar: client.avatar,
          size: 40,
          fallback: fallback,
        ) ??
        fallback;
  }
}

void androidChannelInit() {
  gFFI.setMethodCallHandler((method, arguments) {
    debugPrint("flutter got android msg,$method,$arguments");
    try {
      switch (method) {
        case "start_capture":
          {
            gFFI.dialogManager.dismissAll();
            gFFI.serverModel.updateClientState();
            break;
          }
        case "on_state_changed":
          {
            var name = arguments["name"] as String;
            var value = arguments["value"] as String == "true";
            debugPrint("from jvm:on_state_changed,$name:$value");
            gFFI.serverModel.changeStatue(name, value);
            break;
          }
        case "on_android_permission_result":
          {
            var type = arguments["type"] as String;
            var result = arguments["result"] as bool;
            AndroidPermissionManager.complete(type, result);
            break;
          }
        case "on_media_projection_canceled":
          {
            gFFI.serverModel.stopService();
            break;
          }
        case "msgbox":
          {
            var type = arguments["type"] as String;
            var title = arguments["title"] as String;
            var text = arguments["text"] as String;
            var link = (arguments["link"] ?? '') as String;
            msgBox(gFFI.sessionId, type, title, text, link, gFFI.dialogManager);
            break;
          }
        case "stop_service":
          {
            print(
                "stop_service by kotlin, isStart:${gFFI.serverModel.isStart}");
            if (gFFI.serverModel.isStart) {
              gFFI.serverModel.stopService();
            }
            break;
          }
      }
    } catch (e) {
      debugPrintStack(label: "MethodCallHandler err:$e");
    }
    return "";
  });
}

void showScamWarning(BuildContext context, ServerModel serverModel) {
  showDialog<void>(
    context: context,
    builder: (_) => ScamWarningDialog(serverModel: serverModel),
  );
}
