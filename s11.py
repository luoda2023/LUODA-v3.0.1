# -*- coding: utf-8 -*-
import io
p='flutter/lib/common/widgets/chat_page.dart'
s=io.open(p,encoding='utf-8').read()

old_tile='''  Widget _moreMenuTile(IconData icon, String label, VoidCallback onTap,
      Color iconColor, Color textColor) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xFF25272C)
                    : const Color(0xFFF5F6F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 24, color: iconColor),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
'''
new_tile='''  Widget _moreMenuTile(IconData icon, String label, VoidCallback onTap,
      Color iconColor, Color textColor) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF25272C) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: dark ? const Color(0xFF3A3D43) : const Color(0xFFE2E2E2),
                width: 0.5,
              ),
            ),
            child: Icon(icon, size: 27, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ],
      ),
    );
  }
'''
assert old_tile in s, 'tile block not found'
s=s.replace(old_tile,new_tile)

# Add empty placeholder tiles in _buildMorePanel grid: pad items to full last row? For now keep simple.

io.open(p,'w',encoding='utf-8').write(s)
print('tile replaced OK')
