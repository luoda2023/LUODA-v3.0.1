import sys, re
sys.stdout.reconfigure(encoding='utf-8')
xml = open('agent_memory/ui/oppo_ldesk.xml', encoding='utf-8', errors='ignore').read()
for n in re.findall(r'<node[^>]*/?>', xml):
    cls = re.search(r'class="([^"]*)"', n)
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    c = re.search(r'checked="([^"]*)"', n)
    t = re.search(r'text="([^"]*)"', n)
    if cls and ('Switch' in cls.group(1) or 'Check' in cls.group(1) or cls.group(1).endswith('Button')):
        print(f"class={cls.group(1)} bounds=({b.group(1)},{b.group(2)})-({b.group(3)},{b.group(4)}) checked={c.group(1) if c else ''} text={t.group(1) if t else ''}")
