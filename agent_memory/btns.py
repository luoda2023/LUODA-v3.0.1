import re
raw = open('agent_memory/shots/emu_auth.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    clm = re.search(r'class="([^"]*)"', tag)
    if dm and bm:
        d = dm.group(1).strip()
        if d and 'Button' in (clm.group(1) if clm else ''):
            print(d, bm.group(1))
