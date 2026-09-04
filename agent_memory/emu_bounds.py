import re
raw = open('agent_memory/shots/emu_ui3.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
# 找到含特定 desc 的 node bounds
for m in re.finditer(r'content-desc="([^"]*)"[^>]*?bounds="(\[[^\"]+\])"', xml):
    d, b = m.group(1), m.group(2)
    if d.strip():
        print(repr(d.strip()), b)
