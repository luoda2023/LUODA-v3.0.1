# -*- coding: utf-8 -*-
import io
p = 'flutter/lib/common/widgets/chat_page.dart'
s = io.open(p, encoding='utf-8').read()
lines = s.split('\n')

# ---- 1. Add _showMoreMenu state decl right after _showEmojiPicker decl (line 4905, 0-based 4904)
anchor_decl = '  bool _showEmojiPicker = false;'
idx = None
for i, l in enumerate(lines):
    if l == anchor_decl and 4895 <= i <= 4970:
        idx = i
        break
assert idx is not None, 'decl anchor not found'
lines[idx:idx+1] = [l for l in lines[idx:idx+1]]  # keep

# Insert new state line after the _showEmojiPicker line
insert_after = idx
new_state = ['  bool _showMoreMenu = false;']
lines[insert_after+1:insert_after+1] = new_state
print('inserted state after line', insert_after+1)
io.open(p, 'w', encoding='utf-8').write('\n'.join(lines))
