# -*- coding: utf-8 -*-
import io
p='flutter/lib/common/widgets/chat_page.dart'
lines=io.open(p,encoding='utf-8').read().split('\n')
# class _AiModelSelector at 6049 (idx 6048); find its end: line before '/// 会议群聊顶部横幅' 
start=None; end=None
for i,l in enumerate(lines):
    if l.startswith('class _AiModelSelector '):
        start=i
    if l.startswith('/// 会议群聊顶部横幅'):
        end=i; break
assert start is not None and end is not None and end>start
# also delete the leading doc comment '/// AI model selector badge...' lines before start
# walk back from start to capture its contiguous comment block
cstart=start
while cstart>0 and (lines[cstart-1].startswith('///') or lines[cstart-1].strip()==''):
    # only consume immediately preceding comment lines (at least one '///')
    if lines[cstart-1].startswith('///'):
        cstart-=1
    else:
        break
del lines[cstart:end]
io.open(p,'w',encoding='utf-8').write('\n'.join(lines))
print('removed AiModelSelector block lines', cstart+1, '..', end)
