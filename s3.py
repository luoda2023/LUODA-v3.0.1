# -*- coding: utf-8 -*-
import io
p='flutter/lib/common/widgets/chat_page.dart'
lines=io.open(p,encoding='utf-8').read().split('\n')

# 1) add key field after '_showMoreMenu' state decl
for i,l in enumerate(lines):
    if l=='  bool _showMoreMenu = false;':
        lines[i:i+1]=[l,'  final GlobalKey _moreMenuButtonKey = GlobalKey();']
        print('key field inserted after', i+1)
        break
else:
    raise SystemExit('state decl not found')
io.open(p,'w',encoding='utf-8').write('\n'.join(lines))
print('ok step field')
