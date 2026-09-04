import sys, re
sys.stdout.reconfigure(encoding='utf-8')
xml = open('agent_memory/ui/oppo_ldesk2.xml', encoding='utf-8', errors='ignore').read()
for n in re.findall(r'<node[^>]*/?>', xml):
    cls = re.search(r'class="([^"]*)"', n)
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    c = re.search(r'checked="([^"]*)"', n)
    if cls and ('Switch' in cls.group(1)):
        print(f"Switch bounds=({b.group(1)},{b.group(2)}) checked={c.group(1) if c else ''}")
