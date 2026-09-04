# -*- coding: utf-8 -*-
import io
p = 'flutter/lib/common/widgets/chat_page.dart'
lines = io.open(p, encoding='utf-8').read().split('\n')

def show(a, b):
    for i in range(a - 1, min(b, len(lines))):
        print(i + 1, repr(lines[i]))

# Locate exact anchors for _closeTransientPanels & state decl in _DesktopChatComposerState
for i, l in enumerate(lines):
    if 'void _closeTransientPanels()' in l:
        print('closeTransientPanels at', i + 1)
    if 'bool _showEmojiPicker = false;' in l and 4895 < i < 4970:
        print('emojiPicker decl at', i + 1)
