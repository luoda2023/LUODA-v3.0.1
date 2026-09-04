import sys, re
sys.stdout.reconfigure(encoding='utf-8')
xml = open('agent_memory/ui/oppo_ldesk3.xml', encoding='utf-8', errors='ignore').read()
print('len', len(xml))
for n in re.findall(r'<node[^>]*/?>', xml):
    cls = re.search(r'class="([^"]*)"', n)
    c = re.search(r'checked="([^"]*)"', n)
    t = re.search(r'text="([^"]*)"', n)
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    if cls and ('Switch' in cls.group(1) or 'CheckBox' in cls.group(1)):
        print(f"{cls.group(1)} checked={c.group(1) if c else ''} text={t.group(1) if t else ''} bounds={b.group(0) if b else ''}")
