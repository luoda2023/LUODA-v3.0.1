# -*- coding: utf-8 -*-
import io
p='flutter/lib/common/widgets/chat_page.dart'
lines=io.open(p,encoding='utf-8').read().split('\n')
# find 'final meeting = chatModel...' line -> end of return list before '];'
for i,l in enumerate(lines):
    if "final meeting = chatModel.currentKey.peerId.startsWith('meeting:');" in l:
        # find the closing '];' after this function - search forward until '  ];' then list ends
        j=i
        while j<len(lines) and lines[j].strip()!='];':
            j+=1
        assert lines[j].strip()=='];'
        # insert before '];'
        insertion=[
'      (Icons.emoji_emotions_outlined, translate(\'Emoji\'), () {',
'        setState(() {',
'          _showMoreMenu = false;',
'          _showEmojiPicker = true;',
'          _atOverlayVisible = false;',
'        });',
'        chatModel.inputNode.unfocus();',
'      }),',
]
        lines[j:j]=insertion
        print('emoji more-menu item inserted before line', j+1)
        break
else:
    raise SystemExit('_moreMenuItems start not found')
io.open(p,'w',encoding='utf-8').write('\n'.join(lines))
