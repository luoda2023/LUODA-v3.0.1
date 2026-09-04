import re
raw = open('agent_memory/shots/real_dl.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    tm = re.search(r'text="(连接|取消)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    if tm and bm:
        print(tm.group(1), bm.group(1))
