# -*- coding: utf-8 -*-
import io
p='flutter/test/ui_regression_contract_test.dart'
s=io.open(p,encoding='utf-8').read()
old='''    expect(
        chatPageSource, contains('onOpen: _closeTransientPanels'));
  });'''
new='''    // AI 模型入口已并入“更多”整块面板，原 _AiModelSelector 徽章（含
    // onOpen: _closeTransientPanels）已删除；互斥逻辑改由 _toggleMoreMenu
    // 与 _closeTransientPanels 共同保证（更多面板与表情/@ 候选互斥）。
    expect(chatPageSource, contains('void _toggleMoreMenu()'));
    expect(chatPageSource, contains('_showMoreMenu = !_showMoreMenu;'));
    expect(chatPageSource, contains('_showEmojiPicker = false;'));
  });'''
assert old in s, 'assert block not found'
s=s.replace(old,new)
io.open(p,'w',encoding='utf-8').write(s)
print('test updated')
