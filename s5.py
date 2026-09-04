# -*- coding: utf-8 -*-
import io
p='flutter/lib/common/widgets/chat_page.dart'
lines=io.open(p,encoding='utf-8').read().split('\n')

# --- Find toolbar Row children start (the 'if (onScreenshot != null)' after SizedBox height 42) ---
start=None
for i,l in enumerate(lines):
    if l.strip()=='if (onScreenshot != null)' and i>5600:
        start=i; break
assert start is not None
# walk from start to the end of the toolbar items block: it is a sequence of
#   [screenshot Row..., attach, image, remoteassist, voicecall, favorites, contact, emoji, (AI selector)]
# ending at the line 'const Spacer(),'
end=None
for j in range(start, len(lines)):
    if lines[j].strip()=='const Spacer(),':
        end=j; break
assert end is not None and end>start
print('toolbar item block lines', start+1, '..', end, '=> total', end-start)

replacement = [
'                    if (onScreenshot != null)',
'                      // 截图 + 下拉箭头（保持原组合）……',
'                      Row(',
'                        mainAxisSize: MainAxisSize.min,',
'                        children: <Widget>[',
'                          _ComposerToolButton(',
'                            // PC端截图按钮用剪刀图标（桌面输入栏专用）',
'                            icon: Icons.content_cut_rounded,',
'                            tooltip: translate(\'Screenshot\'),',
'                            enabled: enabled,',
'                            onPressed: () => _runToolAction(onScreenshot!),',
'                          ),',
'                          _ComposerToolButton(',
'                            key: _screenshotArrowKey,',
'                            icon: Icons.arrow_drop_down_rounded,',
'                            tooltip: translate(\'Screenshot options\'),',
'                            enabled: enabled,',
'                            onPressed: () => _showScreenshotOptions(),',
'                          ),',
'                        ],',
'                      ),',
'                    if (_moreMenuItems().isNotEmpty)',
'                      _ComposerToolButton(',
'                        key: _moreMenuButtonKey,',
'                        icon: Icons.more_horiz_rounded,',
'                        tooltip: translate(\'More\'),',
'                        enabled: enabled,',
'                        onPressed: _toggleMoreMenu,',
'                      ),',
]
lines[start:end]=replacement
io.open(p,'w',encoding='utf-8').write('\n'.join(lines))
print('replaced toolbar block')
