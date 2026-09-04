# -*- coding: utf-8 -*-
import io
p='flutter/lib/common/widgets/chat_page.dart'
s=io.open(p,encoding='utf-8').read()

# 1) add placeholders in the grid itemBuilder: pass a nullable? Simpler - pad items list itself before grid.
old='''          final rows = (items.length / cols).ceil();
          // 期望每行高约 84（图标 48 + 间距 + 文字），面板总高 = 行数*行高 + 上下内边距。
          final tileHeight = 84.0;'''
new='''          // 末行不满时补空占位格，保证面板始终“左右上下充满”，
          // 同时为将来新增功能模块预留位置。
          final remainder = items.length % cols;
          final placeholders = remainder == 0 ? 0 : cols - remainder;
          final rows = ((items.length + placeholders) / cols).ceil();
          // 期望每行高约 84（图标 48 + 间距 + 文字），面板总高 = 行数*行高 + 上下内边距。
          final tileHeight = 84.0;'''
assert old in s
s=s.replace(old,new)

# 2) grid itemCount + builder to render padded placeholders
old2='''              itemCount: items.length,
              itemBuilder: (_, i) => _moreMenuTile(
                  items[i].$1, items[i].$2, items[i].$3, labelColor, textColor),'''
new2='''              itemCount: items.length + placeholders,
              itemBuilder: (_, i) {
                if (i < items.length) {
                  return _moreMenuTile(items[i].$1, items[i].$2, items[i].$3,
                      labelColor, textColor);
                }
                return const SizedBox.shrink();
              },'''
assert old2 in s
s=s.replace(old2,new2)
io.open(p,'w',encoding='utf-8').write(s)
print('placeholders added')
