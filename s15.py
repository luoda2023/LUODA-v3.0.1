# -*- coding: utf-8 -*-
import io
p='flutter/test/ui_regression_contract_test.dart'
lines=io.open(p,encoding='utf-8').read().split('\n')
# lines 1614..1623 area currently broken; rebuild the whole test body cleanly
# find test start
start=None
for i,l in enumerate(lines):
    if "test('desktop composer transient controls are mutually exclusive'" in l:
        start=i; break
assert start is not None
# find closing "  });" after it (next at col<=4 with exactly 2 spaces then });
end=None
for j in range(start+1,len(lines)):
    if lines[j].strip()==');' and lines[j].startswith('  })') if False else (lines[j]=='  });'):
        end=j; break
print('start',start+1,'end',end+1)
new_block=[
"  test('desktop composer transient controls are mutually exclusive', () {",
"    expect(chatPageSource, contains('void _closeTransientPanels()'));",
"    expect(",
"        chatPageSource, contains('void _runToolAction(VoidCallback action)'));",
"    expect(chatPageSource,",
"        contains('onInteractionStart: _closeTransientPanels'));",
"    // AI 模型入口已并入“更多”整块面板，原 _AiModelSelector 徽章（含",
"    // onOpen: _closeTransientPanels）已删除；互斥逻辑改由 _toggleMoreMenu",
"    // 与 _closeTransientPanels 共同保证（更多面板与表情/@ 候选互斥）。",
"    expect(chatPageSource, contains('void _toggleMoreMenu()'));",
"    expect(chatPageSource, contains('_showMoreMenu = !_showMoreMenu;'));",
"    expect(chatPageSource, contains('_showEmojiPicker = false;'));",
"  });",
]
lines[start:end+1]=new_block
io.open(p,'w',encoding='utf-8').write('\n'.join(lines))
print('test block rewritten')
