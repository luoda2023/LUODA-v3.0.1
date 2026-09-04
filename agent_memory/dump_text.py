import sys, re
sys.stdout.reconfigure(encoding='utf-8')
xml = open('agent_memory/ui/oppo_ldesk3.xml', encoding='utf-8', errors='ignore').read()
# 打印所有 text 与 class
for n in re.findall(r'<node[^>]*/?>', xml):
    t = re.search(r'text="([^"]*)"', n)
    cls = re.search(r'class="([^"]*)"', n)
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    txt = t.group(1) if t else ''
    if txt.strip():
        print(f"{txt} | {cls.group(1) if cls else ''} | {b.group(0) if b else ''}")
