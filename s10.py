# -*- coding: utf-8 -*-
import io
p='flutter/lib/common/widgets/chat_page.dart'
lines=io.open(p,encoding='utf-8').read().split('\n')

# Locate the two methods _buildMorePanel and _moreMenuTile start lines
b=None; t=None
for i,l in enumerate(lines):
    if l.startswith('  Widget _buildMorePanel()'): b=i
    if l.startswith('  Widget _moreMenuTile('): t=i
assert b is not None and t is not None and t>b
print('buildMorePanel',b+1,'moreMenuTile',t+1)

new_panel=[
'  Widget _buildMorePanel() {',
'    final items = _moreMenuItems();',
'    if (items.isEmpty) return const SizedBox.shrink();',
'    final bg = dark ? const Color(0xFF1E2024) : const Color(0xFFF5F5F5);',
'    final border = dark ? const Color(0xFF3A3D43) : const Color(0xFFE2E2E2);',
'    final labelColor = dark ? const Color(0xFFB8BBC2) : const Color(0xFF555555);',
'    final textColor = dark ? const Color(0xFF999CA2) : const Color(0xFF777777);',
'    // 整块面板：与表情面板同款背景/圆角/边框，左右贴边、上下按行数铺满，',
'    // 宽度自适应列数（每格约 96px），图标 + 文字说明，可随功能增加自动扩展。',
'    return Container(',
'      margin: const EdgeInsets.fromLTRB(8, 0, 8, 2),',
'      decoration: BoxDecoration(',
'        color: bg,',
'        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),',
'        border: Border.all(color: border),',
'      ),',
'      child: LayoutBuilder(',
'        builder: (context, c) {',
'          final cols = (c.maxWidth / 96).floor().clamp(3, 10);',
'          final rows = (items.length / cols).ceil();',
'          // 期望每行高约 84（图标 48 + 间距 + 文字），面板总高 = 行数*行高 + 上下内边距。',
'          final tileHeight = 84.0;',
'          final gridHeight = rows * tileHeight + 12.0;',
'          return SizedBox(',
'            height: gridHeight,',
'            child: GridView.builder(',
'              shrinkWrap: true,',
'              physics: const NeverScrollableScrollPhysics(),',
'              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),',
'              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(',
'                crossAxisCount: cols,',
'                mainAxisSpacing: 0,',
'                crossAxisSpacing: 0,',
'              ),',
'              itemCount: items.length,',
'              itemBuilder: (_, i) => _moreMenuTile(',
'                  items[i].$1, items[i].$2, items[i].$3, labelColor, textColor),',
'            ),',
'          );',
'        },',
'      ),',
'    );',
'  }',
]
# replace lines b..t-1 (methods content of buildMorePanel only; _moreMenuTile stays as separate method below)
# b is 'Widget _buildMorePanel()' line, t is start of tile method; replace [b, t)
lines[b:t]=new_panel
io.open(p,'w',encoding='utf-8').write('\n'.join(lines))
print('replaced panel, tile method still at', b+len(new_panel)+1)
