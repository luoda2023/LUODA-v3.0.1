import re
raw = open('agent_memory/shots/emu_ac3.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
# 找"点聊输入"项 bounds
idx = xml.find('点聊')
print('found at', idx)
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    if '点聊' in tag or 'input' in tag.lower():
        bm = re.search(r'bounds="(\[[^"]*\])"', tag)
        clm = re.search(r'class="([^"]*)"', tag)
        print(tag[:200])
        print('---')
