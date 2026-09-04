import re
raw = open('agent_memory/shots/emu_acc5.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    tm = re.search(r'text="允许"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    if tm and bm:
        print('allow', bm.group(1))
