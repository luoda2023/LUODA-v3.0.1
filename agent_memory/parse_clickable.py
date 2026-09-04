import sys, re
sys.stdout.reconfigure(encoding='utf-8')
xml = open('agent_memory/ui/emu_conv.xml', encoding='utf-8', errors='ignore').read()
# 找 clickable 节点及其bounds
nodes = re.findall(r'<node[^>]*clickable="true"[^>]*/?>', xml)
print('clickable nodes:', len(nodes))
for n in nodes[:40]:
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    c = re.search(r'class="([^"]*)"', n)
    d = re.search(r'content-desc="([^"]*)"', n)
    t = re.search(r'text="([^"]*)"', n)
    if b:
        print(f"bounds=({b.group(1)},{b.group(2)})-({b.group(3)},{b.group(4)}) class={c.group(1) if c else ''} desc={d.group(1) if d else ''} text={t.group(1) if t else ''}")
