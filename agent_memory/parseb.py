# -*- coding: utf-8 -*-
import re, sys, io
p = sys.argv[1]
raw = open(p,'rb').read()
xml = raw.decode('utf-8', errors='replace')
out = io.StringIO()
for m in re.finditer(r'<node[^>]*/?>', xml):
    n = m.group(0)
    if 'text=' not in n and 'content-desc=' not in n: continue
    tm = re.search(r'text="([^"]*)"', n)
    dm = re.search(r'content-desc="([^"]*)"', n)
    bm = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    cm = re.search(r'clickable="(true|false)"', n)
    if not bm: continue
    t = (tm.group(1) if tm else '').strip()
    d = (dm.group(1) if dm else '').strip()
    if not t and not d: continue
    x1,y1,x2,y2 = map(int, bm.groups())
    cx, cy = (x1+x2)//2, (y1+y2)//2
    c = cm.group(1) if cm else '?'
    out.write(f'{cx},{cy} [{x1},{y1}][{x2},{y2}] click={c} | T:{t[:30]} | D:{d[:44]}\n')
sys.stdout.buffer.write(out.getvalue().encode('utf-8'))
