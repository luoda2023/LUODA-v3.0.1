# -*- coding: utf-8 -*-
import sys
sys.stdout.reconfigure(encoding="utf-8")

def patch_file(path, replacements):
    s = open(path, encoding="utf-8").read()
    for old, new in replacements:
        cnt = s.count(old)
        if cnt == 0:
            print("MISS in", path, repr(old[:80]))
            raise SystemExit(1)
        if cnt > 1:
            print("AMBIG in", path, repr(old[:80]), "x", cnt)
            raise SystemExit(1)
        s = s.replace(old, new)
    open(path, "w", encoding="utf-8", newline="").write(s)
    print("OK", path)

p = r"J:\codex-work\LUODA-v3.0.1\flutter\lib\mobile\pages\first_run_wizard.dart"
patch_file(p, [
    ("""  static const kFirstRunPermSeenKey = 'first_run_permissions_seen_v2';
  static const _remindCooldown = Duration(hours: 24);

  /// Returns true if the wizard completed (all permissions granted or
  /// previously completed), false if the user dismissed it early.
  static Future<bool> showIfNeeded(BuildContext context) async {
    final done = await bind.mainGetLocalOption(key: kFirstRunPermDoneKey);
    if (done == 'Y') return true;""",
     """  static const kFirstRunPermSeenKey = 'first_run_permissions_seen_v2';
  static const _remindCooldown = Duration(hours: 24);

  /// True when every required permission is already granted by the Android
  /// system. System permissions survive app updates and reinstalls, so a
  /// one-time authorization stays valid until the OS or the device changes.
  static Future<bool> allPermissionsGranted() async {
    if (isDesktop || isWeb) return true;
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
    return floating && notification && storage && audio && accessibility;
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
    if (done == 'Y') return true;"""),
])
