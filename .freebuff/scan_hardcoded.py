import re, sys, os
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
cn = open('src/lang/cn.rs', encoding='utf-8').read()
cnkeys = set(re.findall(r'\("([^"]+)"\s*,\s*"', cn))

roots = ['flutter/lib']
pat = re.compile(r"\b(title|tooltip|labelText|hintText|helperText|semanticLabel|initialValue|name|subtitle|label)\s*:\s*'([A-Za-z][^']*)'")
found = []
for root in roots:
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if not f.endswith('.dart'):
                continue
            p = os.path.join(dp, f)
            src = open(p, encoding='utf-8', errors='ignore').read()
            for m in pat.finditer(src):
                key = m.group(2)
                line_start = src.rfind('\n', 0, m.start()) + 1
                line_end = src.find('\n', m.start())
                line = src[line_start:line_end]
                if 'translate' in line or 'Tr(' in line:
                    continue
                if key in cnkeys:
                    found.append((p.replace(os.sep, '/'), key, m.group(1)))

for p, k, f in found:
    print(f"{p}:{k} ({f})")
print("---")
print("共", len(found), "处")
