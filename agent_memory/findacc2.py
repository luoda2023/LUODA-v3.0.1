import re
raw = open('agent_memory/shots/emu_ac3.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    if '点聊输入' in tag:
        bm = re.search(r'bounds="(\[[^"]*\])"', tag)
        clm = re.search(r'class="([^"]*)"', tag)
        ck = re.search(r'checked="([^"]*)"', tag)
        print('CLASS', clm.group(1) if clm else '?')
        print('BOUNDS', bm.group(1) if bm else '?')
        print('CHECKED', ck.group(1) if ck else '?')
        print(tag[:300])
