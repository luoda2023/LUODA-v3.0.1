# -*- coding: utf-8 -*-
import io
p = 'flutter/lib/common/widgets/chat_page.dart'
lines = io.open(p, encoding='utf-8').read().split('\n')

def idx_of(needle, lo=0):
    for i in range(lo, len(lines)):
        if needle in lines[i]:
            return i
    raise SystemExit('not found: ' + needle)

# ---- Replace _closeTransientPanels (line 5011-5017, 0-based 5010..5016)
i = 5010
assert '_closeTransientPanels()' in lines[i]
new_close = [
 '  void _closeTransientPanels() {',
 '    if (!_showEmojiPicker && !_showMoreMenu && !_atOverlayVisible) return;',
 '    setState(() {',
 '      _showEmojiPicker = false;',
 '      _showMoreMenu = false;',
 '      _atOverlayVisible = false;',
 '    });',
 '  }',
 '',
]
lines[i:i+8] = new_close

# ---- Replace _runToolAction with the wrapper + menu builder helpers (line after close, now shifted)
i = idx_of('void _runToolAction(VoidCallback action)')
# lines[i] signature; lines[i+1] body close call; lines[i+2] action(); lines[i+3] }
assert '_closeTransientPanels();' in lines[i+1] and lines[i+2].strip() == 'action();'
new_run = [
 '  void _runToolAction(VoidCallback action) {',
 '    _closeTransientPanels();',
 '    action();',
 '  }',
 '',
 '  /// “更多”弹出菜单：返回当前会话可用的功能（图标 + 文字说明）。',
 '  /// 空列表表示没有可放入菜单的功能，此时调用方应隐藏“更多”按钮。',
 '  List<(IconData, String, VoidCallback)> _moreMenuItems() {',
 '    final meeting = chatModel.currentKey.peerId.startsWith(\'meeting:\');',
 '    return <(IconData, String, VoidCallback)>[',
 '      if (onAttachFile != null)',
 '        (Icons.folder_outlined, translate(\'File Transfer\'),',
 '         () => _runToolAction(onAttachFile!)),',
 '      if (onSendImage != null)',
 '        (Icons.image_outlined, translate(\'Send Image\'),',
 '         () => _runToolAction(onSendImage!)),',
 '      if (onVoiceCall != null)',
 '        (Icons.phone_in_talk_outlined, translate(\'Voice call\'),',
 '         () => _runToolAction(onVoiceCall!)),',
 '      if (onRemoteAssist != null)',
 '        (meeting ? Icons.visibility_rounded : Icons.desktop_windows_outlined,',
 '         meeting',
 '             ? (meetingPresenterForChatModel(chatModel)',
 '                 ? translate(\'Enter to Present\')',
 '                 : translate(\'Enter to Watch\'))',
 '             : translate(\'Remote Desktop\'),',
 '         () => _runToolAction(onRemoteAssist!)),',
 '      (Icons.star_rounded, translate(\'Favorites\'),',
 '       () => _runToolAction(() =>',
 '           unawaited(pickFavoriteToSend(context, chatModel, dark: dark)))),',
 '      (Icons.badge_outlined, translate(\'Send Contact Card\'),',
 '       () => _runToolAction(() =>',
 '           unawaited(pickContactToSend(context, chatModel)))),',
 '      if (AiConfig.current.profiles.any((p) =>',
 '          p.enabled && p.profileType == AiProfileType.text))',
 '        (Icons.auto_awesome_rounded, translate(\'AI Model\'),',
 '         () => _runToolAction(_openAiModelConfig)),',
 '    ];',
 '  }',
 '',
 '  /// 打开 AI 设置页（“更多”菜单内模型/智能助手入口）。',
 '  void _openAiModelConfig() {',
 '    Navigator.of(context).push(MaterialPageRoute(',
 '        builder: (_) => const AiConfigPage()));',
 '  }',
 '',
]
lines[i:i+4] = new_run

io.open(p, 'w', encoding='utf-8').write('\n'.join(lines))
print('done close+runToolAction+morse')
