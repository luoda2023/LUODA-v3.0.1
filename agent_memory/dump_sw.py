import sys, re
sys.stdout.reconfigure(encoding='utf-8')
xml = open('agent_memory/ui/oppo_dc2.xml', encoding='utf-8', errors='ignore').read()
for n in re.findall(r'<node[^>]*/?>', xml):
    cls = re.search(r'class="([^"]*)"', n)
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    c = re.search(r'checked="([^"]*)"', n)
    cl = re.search(r'clickable="([^"]*)"', n)
    t = re.search(r'text="([^"]*)"', n)
    d2 = re.search(r'content-desc="([^"]*)"', n)
    if cls and b:
        x1,x2 = int(b.group(1)), int(b.group(3))
        if (x1 > 700 or 'Switch' in cls.group(1) or 'Button' in cls.group(1)) and (cls.group(1) != 'android.widget.ImageButton'):
            print(f"{cls.group(1)} click={cl.group(1) if cl else ''} checked={c.group(1) if c else ''} text={t.group(1) if t else ''} desc={d2.group(1) if d2 else ''} b={b.group(0)}")
