import re
raw = open('agent_memory/shots/emu_acc2.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    clm = re.search(r'class="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    tm = re.search(r'text="([^"]*)"', tag)
    ck = re.search(r'checkable="([^"]*)" checked="([^"]*)"', tag)
    if bm and clm and ('Switch' in (clm.group(1) or '') or 'CheckBox' in (clm.group(1) or '')):
        print(clm.group(1), bm.group(1), 'checked=', (ck.group(2) if ck else '?'))
