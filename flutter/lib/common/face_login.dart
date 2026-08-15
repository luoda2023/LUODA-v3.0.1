import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:face_recognition_flutter/face_recognition_flutter.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/consts.dart';
import 'package:luoda_flutter/models/platform_model.dart';

/// 本地配置 key：是否开启「登录人脸验证」。
const String kFaceLoginOption = 'face_login_enabled';

/// 本地配置 key：登录密令（SHA-256 十六进制，不存明文）。
const String kFacePasscodeHash = 'face_login_passcode_hash';

/// 本地配置 key：免验证时长（分钟，0 表示关闭）。
const String kFaceGraceMinutes = 'face_login_grace_minutes';

/// 本地配置 key：最近一次验证通过的时间戳（epoch 秒）。
const String kFaceLastOkAt = 'face_login_last_ok_at';

/// 本地配置 key：人脸验证静音（Y/N）。
const String kFaceSilent = 'face_login_silent';

/// 是否开启登录人脸验证。
bool faceLoginEnabled() {
  return bind.mainGetLocalOption(key: kFaceLoginOption) == 'Y';
}

/// 设置登录人脸验证开关。
Future<void> faceLoginSetEnabled(bool value) async {
  await bind.mainSetLocalOption(
    key: kFaceLoginOption,
    value: value ? 'Y' : 'N',
  );
}

String? _cachedFaceId;

/// 人脸验证使用的 faceId：使用设备持久化的稳定 ID，保证录入与每次
/// 启动验证使用同一个 ID。
Future<String> faceLoginFaceId() async {
  final cached = _cachedFaceId;
  if (cached != null && cached.isNotEmpty) return cached;
  try {
    final deviceId = await DirectChatRepository.instance.deviceId;
    if (deviceId.trim().isNotEmpty) {
      _cachedFaceId = deviceId.trim();
      return deviceId.trim();
    }
  } catch (_) {
    // 存储不可用时回退到 me.id
  }
  final id = gFFI.chatModel.me.id.trim();
  return id.isEmpty ? 'dotchat-user' : id;
}

/// 当前设备是否已录入该用户的人脸特征。
Future<bool> faceLoginHasEnrolled() async {
  try {
    final faceId = await faceLoginFaceId();
    return await FaceRecognitionFlutter.isFaceExist(faceId);
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// 密令登录
// ---------------------------------------------------------------------------

/// 计算密令的 SHA-256 哈希（十六进制）。
String passcodeHashOf(String code) {
  return sha256.convert(utf8.encode(code.trim())).toString();
}

/// 校验密令哈希是否匹配（storedHash 非空才认为已设置密令）。
bool passcodeMatches(String storedHash, String code) {
  final hash = storedHash.trim();
  if (hash.isEmpty || code.trim().isEmpty) return false;
  return hash == passcodeHashOf(code);
}

/// 是否处于免验证窗口内。
/// [graceMinutes] 免验证时长（分钟，<=0 表示关闭）；
/// [lastOkAtSec] 最近一次验证通过时间（epoch 秒）；
/// [nowSec] 当前时间（epoch 秒）。
bool faceLoginInGraceWindowOf(int graceMinutes, int lastOkAtSec, int nowSec) {
  if (graceMinutes <= 0 || lastOkAtSec <= 0) return false;
  return nowSec - lastOkAtSec < graceMinutes * 60;
}

String _passcodeHash() {
  return bind.mainGetLocalOption(key: kFacePasscodeHash).trim();
}

/// 是否已设置登录密令。
bool faceLoginPasscodeSet() => _passcodeHash().isNotEmpty;

/// 设置登录密令（存 SHA-256 哈希，不存明文）。
Future<void> faceLoginSetPasscode(String code) async {
  final trimmed = code.trim();
  if (trimmed.isEmpty) {
    await bind.mainSetLocalOption(key: kFacePasscodeHash, value: '');
    return;
  }
  final hash = sha256.convert(utf8.encode(trimmed)).toString();
  await bind.mainSetLocalOption(key: kFacePasscodeHash, value: hash);
}

/// 校验密令是否正确。
bool faceLoginVerifyPasscode(String code) {
  return passcodeMatches(_passcodeHash(), code);
}

/// 弹出密令输入对话框，验证通过返回 true。
Future<bool> faceLoginPromptPasscode(
  BuildContext context, {
  String? title,
  String? hint,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? translate('passcode_login_title')),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        maxLength: 20,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(ctx, v),
        decoration: InputDecoration(
          labelText: hint ?? translate('passcode_enter'),
          prefixIcon: const Icon(Icons.lock_outline_rounded),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, ''),
          child: Text(translate('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(translate('OK')),
        ),
      ],
    ),
  );
  final input = result ?? '';
  return faceLoginVerifyPasscode(input);
}

// ---------------------------------------------------------------------------
// 免验证时间窗口
// ---------------------------------------------------------------------------

/// 免验证时长（分钟，0 表示关闭）。
int faceLoginGraceMinutes() {
  return int.tryParse(bind.mainGetLocalOption(key: kFaceGraceMinutes)) ?? 0;
}

Future<void> faceLoginSetGraceMinutes(int minutes) async {
  await bind.mainSetLocalOption(
    key: kFaceGraceMinutes,
    value: '$minutes',
  );
}

int _lastOkAt() {
  return int.tryParse(bind.mainGetLocalOption(key: kFaceLastOkAt)) ?? 0;
}

/// 记录一次验证通过的时间（用于免验证窗口）。
Future<void> faceLoginMarkOk() async {
  await bind.mainSetLocalOption(
    key: kFaceLastOkAt,
    value: '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
  );
}

/// 是否处于免验证时间窗口内。
bool faceLoginInGraceWindow() {
  return faceLoginInGraceWindowOf(
    faceLoginGraceMinutes(),
    _lastOkAt(),
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
}

// ---------------------------------------------------------------------------
// 验证静音
// ---------------------------------------------------------------------------

/// 人脸验证是否默认静音。
bool faceLoginSilent() {
  return bind.mainGetLocalOption(key: kFaceSilent) == 'Y';
}

Future<void> faceLoginSetSilent(bool value) async {
  await bind.mainSetLocalOption(key: kFaceSilent, value: value ? 'Y' : 'N');
}

// ---------------------------------------------------------------------------
// USB 调试检测
// ---------------------------------------------------------------------------

/// 是否处于 USB 调试连接（ADB 调试时免验证）。
Future<bool> faceLoginUsbDebugging() async {
  if (!isAndroid) return false;
  try {
    final v = await gFFI.invokeMethod(AndroidChannel.kIsUsbDebugging);
    return v == true;
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// 人脸验证
// ---------------------------------------------------------------------------

/// 引导用户通过摄像头录入人脸（开启人脸验证前调用）。
/// 返回是否录入成功。
Future<bool> faceLoginEnroll() async {
  try {
    final faceId = await faceLoginFaceId();
    final result = await FaceRecognitionFlutter.addFaceBySDKCamera(
      faceId: faceId,
      addFacePerformanceMode: 2, // 精确模式，人脸品质更高
      needShowConfirmDialog: true,
    );
    if (result.isSuccess) return true;
    // 部分版本录入成功返回 code==1（verifySuccess），
    // 保险起见再复查一次本地特征是否存在。
    return await faceLoginHasEnrolled();
  } catch (_) {
    return false;
  }
}

/// 删除本地录入的人脸特征。
Future<void> faceLoginDelete() async {
  try {
    final faceId = await faceLoginFaceId();
    await FaceRecognitionFlutter.deleteFaceFeature(faceId);
  } catch (_) {
    // 忽略：特征不存在或 SDK 不可用时无需处理
  }
}

/// 执行 1:1 人脸核验 + 动作活体。
/// 开启「静音」时验证全程静音，结束后恢复原音量。
/// 返回核验结果（isSuccess 表示通过）。
Future<FaceRecognitionResult> faceLoginVerify() async {
  final silent = faceLoginSilent();
  if (silent && isAndroid) {
    try {
      await gFFI.invokeMethod(AndroidChannel.kMuteMedia);
    } catch (_) {}
  }
  try {
    final faceId = await faceLoginFaceId();
    return await FaceRecognitionFlutter.faceVerify(
      faceId: faceId,
      threshold: 0.84,
      livenessType: 1, // 动作活体（张嘴/微笑/眨眼/摇头/点头）
      motionLivenessTypes: '1,2,3,4,5',
      motionLivenessTimeOut: 7,
      motionLivenessSteps: 2,
      allowMultiFaces: false,
    );
  } finally {
    if (silent && isAndroid) {
      try {
        await gFFI.invokeMethod(AndroidChannel.kUnmuteMedia);
      } catch (_) {}
    }
  }
}

/// 启动人脸验证门：全屏遮罩，验证通过后才允许进入应用。
/// 返回 true 表示验证通过（或用户主动关闭了人脸验证）。
class FaceLoginGate extends StatefulWidget {
  const FaceLoginGate({Key? key}) : super(key: key);

  @override
  State<FaceLoginGate> createState() => _FaceLoginGateState();
}

class _FaceLoginGateState extends State<FaceLoginGate> {
  bool _checking = true;
  bool _verified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final hasEnrolled = await faceLoginHasEnrolled();
      if (!hasEnrolled) {
        if (!mounted) return;
        setState(() {
          _checking = false;
          _error = translate('face_login_not_enrolled');
        });
        return;
      }
      final result = await faceLoginVerify()
          .timeout(
            const Duration(seconds: 30),
            // SDK 相机界面异常时（相机被占用 / 权限丢失 / Activity
            // 未正常显示），Future 可能永不返回，验证门会卡死。
            // 超时后视为失败并给出可退出的入口。
            onTimeout: () => FaceRecognitionResult(
              code: FaceRecognitionResultCode.verifyFailed,
              message: 'face login timeout',
              similarity: 0,
              livenessValue: 0,
              faceBase64: '',
              faceFeature: '',
            ),
          );
      if (!mounted) return;
      if (result.isSuccess) {
        await _pass();
      } else {
        final message = switch (result.code) {
          FaceRecognitionResultCode.cancel =>
            translate('face_login_cancelled'),
          FaceRecognitionResultCode.noFaceMulti =>
            translate('face_login_no_face'),
          FaceRecognitionResultCode.noFaceFeature =>
            translate('face_login_no_face'),
          FaceRecognitionResultCode.noBaseFaceFeature =>
            translate('face_login_not_enrolled'),
          _ => translate('face_login_failed'),
        };
        setState(() {
          _checking = false;
          _error = message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = translate('face_login_sdk_error');
      });
    }
  }

  Future<void> _pass() async {
    await faceLoginMarkOk();
    if (!mounted) return;
    setState(() => _verified = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// 使用密令登录（不依赖人脸）。
  Future<void> _passcodeLogin() async {
    final ok = await faceLoginPromptPasscode(context);
    if (!ok) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = translate('passcode_wrong');
      });
      return;
    }
    await _pass();
  }

  /// 关闭人脸验证。已设置密令时，必须先输入正确密令才能关闭。
  Future<void> _disableAndExit() async {
    if (faceLoginPasscodeSet()) {
      final pass = await faceLoginPromptPasscode(
        context,
        title: translate('passcode_required_to_disable'),
      );
      if (!pass || !mounted) return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(translate('face_login_disable_title')),
        content: Text(translate('face_login_disable_tip')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(translate('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(translate('Disable')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await faceLoginSetEnabled(false);
    await faceLoginDelete();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0E14),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFF07C160).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _verified
                          ? Icons.verified_user_rounded
                          : Icons.face_retouching_natural_rounded,
                      size: 44,
                      color: _verified
                          ? const Color(0xFF07C160)
                          : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    translate('face_login_title'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _error ??
                        (_checking
                            ? translate('face_login_checking')
                            : translate('face_login_title')),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error != null
                          ? const Color(0xFFFF8A80)
                          : Colors.white54,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 36),
                  if (_checking)
                    const CircularProgressIndicator(color: Color(0xFF07C160))
                  else if (_error != null) ...<Widget>[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF07C160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                      ),
                      onPressed: _run,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: Text(translate('Retry')),
                    ),
                    const SizedBox(height: 14),
                    if (faceLoginPasscodeSet())
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _passcodeLogin,
                        icon: const Icon(Icons.password_rounded, size: 18),
                        label: Text(translate('passcode_login')),
                      ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _disableAndExit,
                      child: Text(
                        translate('face_login_disable'),
                        style: const TextStyle(color: Colors.white38),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 应用启动时：若开启了登录人脸验证，弹出全屏验证门。
/// 在首页首帧之后调用，避免阻塞启动动画。
/// 以下情况跳过验证：
///   - USB 调试（ADB）连接中；
///   - 处于免验证时间窗口内（最近一次验证通过后的设定时长内）。
Future<void> faceLoginMaybeShowGate(BuildContext context) async {
  if (!isAndroid || !faceLoginEnabled()) return;
  // USB 调试连接时跳过验证。
  if (await faceLoginUsbDebugging()) return;
  // 免验证时间窗口内跳过验证。
  if (faceLoginInGraceWindow()) return;
  // 已录入人脸或已设置密令才需要验证门（否则直接进入，设置页负责引导录入）。
  final hasEnrolled = await faceLoginHasEnrolled();
  if (!hasEnrolled && !faceLoginPasscodeSet()) return;
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'face-login-gate',
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => const FaceLoginGate(),
  );
}
