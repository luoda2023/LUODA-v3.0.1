import re
raw = open('agent_memory/shots/emu_acc4.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    clm = re.search(r'class="([^"]*)"', tag)
    ck = re.search(r'checked="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    if clm and ck and bm and ('Switch' in (clm.group(1) or '') or 'CheckBox' in (clm.group(1) or '')):
        print(clm.group(1), bm.group(1), 'checked', ck.group(1))
