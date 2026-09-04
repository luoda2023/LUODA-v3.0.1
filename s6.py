# -*- coding: utf-8 -*-
import io
p='flutter/lib/common/widgets/chat_page.dart'
lines=io.open(p,encoding='utf-8').read().split('\n')
# withEmoji block
for i,l in enumerate(lines):
    if l.strip()=='final withEmoji = Column(' and 'if (_showEmojiPicker) _buildEmojiPanel(),' in lines[i+3] if i+3<len(lines) else False:
        pass
# simpler: find the line 'if (_showEmojiPicker) _buildEmojiPanel(),' (desktop, near 5754)
anchor=None
for i,l in enumerate(lines):
    if 'if (_showEmojiPicker) _buildEmojiPanel(),' in l and 5750<i<5900:
        anchor=i; break
assert anchor is not None
lines.insert(anchor, '        if (_showMoreMenu) _buildMorePanel(),')
io.open(p,'w',encoding='utf-8').write('\n'.join(lines))
print('more panel inserted at line', anchor+1)
