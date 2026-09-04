import re
raw = open('agent_memory/shots/emu_eas4.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    clm = re.search(r'class="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    ck = re.search(r'checked="([^"]*)"', tag)
    if dm and bm:
        d = dm.group(1).strip()
        if d in ('屏幕录制','输入控制','传输文件','音频录制','允许同步剪贴板','通知','悬浮窗','一键完成必要授权'):
            print(d, bm.group(1), 'checked', ck.group(1) if ck else '?', clm.group(1) if clm else '')
