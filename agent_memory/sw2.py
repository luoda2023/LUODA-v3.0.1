import re
raw = open('agent_memory/shots/emu_acc2.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
# 打印所有含 bounds 且有开关类的节点
for m in re.finditer(r'<node[^>]*class="([^"]*(?:Switch|CheckBox|Button)[^"]*)"[^>]*>', xml):
    tag = m.group(0)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    tm = re.search(r'text="([^"]*)"', tag)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    ck = re.search(r'checked="([^"]*)"', tag)
    print((tm.group(1) if tm else '') or (dm.group(1) if dm else ''), m.group(1), bm.group(1) if bm else '?', 'checked', ck.group(1) if ck else '?')
