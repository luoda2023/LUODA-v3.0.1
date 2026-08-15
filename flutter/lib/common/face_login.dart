import 'dart:async';

import 'package:face_recognition_flutter/face_recognition_flutter.dart';
import 'package:flutter/material.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/models/platform_model.dart';

/// 本地配置 key：是否开启「登录人脸验证」。
const String kFaceLoginOption = 'face_login_enabled';

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

/// 人脸验证使用的 faceId：始终绑定当前用户自己的 ID，
/// 换设备 / 换 ID 后需要重新录入。
String faceLoginFaceId() {
  final id = gFFI.chatModel.me.id.trim();
  return id.isEmpty ? 'dotchat-user' : id;
}

/// 当前设备是否已录入该用户的人脸特征。
Future<bool> faceLoginHasEnrolled() async {
  try {
    return await FaceRecognitionFlutter.isFaceExist(faceLoginFaceId());
  } catch (_) {
    return false;
  }
}

/// 引导用户通过摄像头录入人脸（开启人脸验证前调用）。
/// 返回是否录入成功。
Future<bool> faceLoginEnroll() async {
  try {
    final result = await FaceRecognitionFlutter.addFaceBySDKCamera(
      faceId: faceLoginFaceId(),
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
    await FaceRecognitionFlutter.deleteFaceFeature(faceLoginFaceId());
  } catch (_) {
    // 忽略：特征不存在或 SDK 不可用时无需处理
  }
}

/// 执行 1:1 人脸核验 + 动作活体。
/// 返回核验结果（isSuccess 表示通过）。
Future<FaceRecognitionResult> faceLoginVerify() async {
  return FaceRecognitionFlutter.faceVerify(
    faceId: faceLoginFaceId(),
    threshold: 0.84,
    livenessType: 1, // 动作活体（张嘴/微笑/眨眼/摇头/点头）
    motionLivenessTypes: '1,2,3,4,5',
    motionLivenessTimeOut: 7,
    motionLivenessSteps: 2,
    allowMultiFaces: false,
  );
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
      final result = await faceLoginVerify();
      if (!mounted) return;
      if (result.isSuccess) {
        setState(() => _verified = true);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        Navigator.of(context).pop(true);
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

  Future<void> _disableAndExit() async {
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
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
Future<void> faceLoginMaybeShowGate(BuildContext context) async {
  if (!isAndroid || !faceLoginEnabled()) return;
  // 先确认已录入，未录入则直接进入（设置页负责引导录入）。
  if (!await faceLoginHasEnrolled()) return;
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
