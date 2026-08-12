import 'package:flutter/material.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';

/// 简约在线状态：小圆点 + 状态文字，不渲染卡片背景。
/// 用于联系人页与点聊页的左上角，风格统一、状态实时刷新。
class OnlineStatusText extends StatelessWidget {
  const OnlineStatusText({super.key, this.fontSize = 13});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gFFI.serverModel,
      builder: (context, _) {
        final status = gFFI.serverModel.connectStatus;
        final directPort =
            bind.mainGetOptionSync(key: kOptionDirectAccessPort).trim();
        // 颜色锁定：全应用只用品牌绿（#07C160 亮绿 / #238A57 深绿）与中性灰。
        final (label, color) = status > 0
            ? (translate('Online'), const Color(0xFF07C160))
            : directPort.isNotEmpty
                ? (translate('Direct listening'), const Color(0xFF238A57))
                : status == 0
                    ? (translate('Connecting'), const Color(0xFF238A57))
                    : (translate('Offline'), const Color(0xFF9AA4B2));
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }
}
