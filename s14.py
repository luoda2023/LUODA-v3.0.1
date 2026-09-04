# -*- coding: utf-8 -*-
import io
p='flutter/test/ui_regression_contract_test.dart'
lines=io.open(p,encoding='utf-8').read().split('\n')
# line 1619 is the onOpen expect (0-based 1618); find the block 1616..1620
start=1615; end=1620
for i in range(start,end):
    print(i+1,repr(lines[i]))
assert "onOpen: _closeTransientPanels" in lines[1618]
# replace 1617..1619 (three expect lines) with new content; keep test close
lines[1617:1620]=[
"    // AI 模型入口已并入“更多”整块面板，原 _AiModelSelector 徽章（含",
"    // onOpen: _closeTransientPanels）已删除；互斥逻辑改由 _toggleMoreMenu",
"    // 与 _closeTransientPanels 共同保证（更多面板与表情/@ 候选互斥）。",
"    expect(chatPageSource, contains('void _toggleMoreMenu()'));",
"    expect(chatPageSource, contains('_showMoreMenu = !_showMoreMenu;'));",
"    expect(chatPageSource, contains('_showEmojiPicker = false;'));",
]
io.open(p,'w',encoding='utf-8').write('\n'.join(lines))
print('updated lines',1618, '..',1622)
