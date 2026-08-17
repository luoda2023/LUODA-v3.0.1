import re

def load_keys(path):
    keys = set()
    with open(path, encoding='utf-8') as f:
        for line in f:
            m = re.match(r'\s*\("(.+?)",\s*"(.+?)"\),', line)
            if m:
                keys.add(m.group(1))
    return keys

cn = load_keys('src/lang/cn.rs')
en = load_keys('src/lang/en.rs')

diff = sorted(en - cn)
print("keys in en.rs but NOT in cn.rs:", len(diff))
for k in diff:
    print("  ", k)
