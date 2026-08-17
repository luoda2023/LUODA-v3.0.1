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

# 1. Wizard: add _grantingAll + _grantAll + button
w = r"J:\codex-work\LUODA-v3.0.1\flutter\lib\mobile\pages\first_run_wizard.dart"
patch_file(w, [
    ("""  final Map<String, _PermStatus> _states = {};
  bool _checking = true;""",
     """  final Map<String, _PermStatus> _states = {};
  bool _checking = true;
  bool _grantingAll = false;"""),
    ("""  bool get _allGranted =>
      _states.values.every((s) => s.granted);""",
     """  bool get _allGranted =>
      _states.values.every((s) => s.granted);

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
    if (mounted && _allGranted) Navigator.of(context).pop(true);
  }"""),
    ("""                    const SizedBox(height: 28),

                    // Permission cards
                    _buildCard(_states[_kAccessibility]!, () =>
                        _grantAccessibility()),""",
     """                    const SizedBox(height: 20),

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
                        _grantAccessibility()),"""),
    ("""                child: Text(translate('Grant')),
              )""",
     """                child: Text(translate('Grant')),
              )
            else if (_grantingAll)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )"""),
])

# 2. Hide raw filehelper ID in mobile conversation rows
h = r"J:\codex-work\LUODA-v3.0.1\flutter\lib\mobile\pages\home_page.dart"
patch_file(h, [
    ("""                                            Text(
                                              formatID(DirectPairingStore
                                                  .realDeviceId(
                                                      entry.key.peerId)),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: MobileText.captionSm,
                                                color: muted.withOpacity(0.8),
                                              ),
                                            ),""",
     """                                            if (entry.key.peerId !=
                                                kFileHelperId)
                                              Text(
                                                formatID(
                                                    DirectPairingStore
                                                        .realDeviceId(entry
                                                            .key.peerId)),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize:
                                                      MobileText.captionSm,
                                                  color: muted
                                                      .withOpacity(0.8),
                                                ),
                                              ),"""),
])
