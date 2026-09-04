import re
raw = open('agent_memory/shots/emu_eas.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    if dm and bm and dm.group(1).strip() in ('启动服务','一键完成必要授权'):
        print(dm.group(1).strip(), bm.group(1))
