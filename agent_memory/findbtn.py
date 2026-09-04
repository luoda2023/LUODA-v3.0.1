import re
raw = open('agent_memory/shots/emu_id.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
# 打印所有带 content-desc 的node的完整tag前300字符
for m in re.finditer(r'<node[^>]*content-desc="语音通话"[^>]*>', xml):
    print('FULL:', m.group(0)[:400])
    print('---')
