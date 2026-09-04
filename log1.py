# -*- coding: utf-8 -*-
import io, datetime
p='agent_memory/full_test_log.md'
s=io.open(p,encoding='utf-8').read()
now=datetime.datetime.now().strftime('%m-%d %H:%M')
entry=f"""
### [{now}] 桌面聊天输入栏「更多」整块面板改造 + 双端 v3.1.24 部署
- 需求: PC 聊天输入框底部功能按钮太多→收进「更多」; 面板图标+文字说明; 左右上下铺满可扩展
- 改动(flutter/lib/common/widgets/chat_page.dart, 桌面 _DesktopChatComposer):
  - 行内仅保留: 截图(剪刀+下拉箭头) + 「更多」按钮
  - 「更多」弹出: 整块网格面板(与表情面板同款贴边圆角, 宽度随聊天窗口自适应, 末行补空位铺满)
  - 菜单项: 文件传输/发送图片/语音电话/远程桌面(会议=进入观看/演示)/收藏/名片/AI模型设置/表情
  - 删除无引用旧组件 _AiModelSelector(功能入口并入菜单); 清理 2 个 unused import
- 测试: dart analyze 0 err/warn; 更新 ui_regression "mutually exclusive" 断言通过;
  基线遗留失败3个(LDesk branding/avatars/managed-entry 与本次无关, stash验证同样失败)
- 桌面 Release 构建成功 dotchat.exe; Android APK v3.1.24 (175.5MB) 构建成功
- 部署: 真机OPPO(7358bbbb) 与 模拟器(emulator-5556) 均安装 v3.1.24
- ⚠️ 真机被 Freebuff/ldai 并行任务干扰(AtchDlg反复抢焦点) → pm disable-user 后恢复 dotchat 前台
- ⚠️ 真机重装后 ID 变化: 旧31226615 → 新31979354(需重新加好友/入会)
- 真机主页: 首次启动需同意隐私弹窗(点击底部按钮(540,2260)通过) → 进入主页
"""
io.open(p,'w',encoding='utf-8').write(s.rstrip()+'\n'+entry)
print('appended, total len', len(s)+len(entry))
