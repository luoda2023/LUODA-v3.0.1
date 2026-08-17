import re, os

# 匹配 Text('...') / label: '...' / title: '...' 等位置的纯英文字符串
patterns = [
    r"Text\(\s*['\"]([A-Za-z][^'\"]{2,})['\"]",
    r"label:\s*['\"]([A-Za-z][^'\"]{2,})['\"]",
    r"title:\s*['\"]([A-Za-z][^'\"]{2,})['\"]",
    r"hintText:\s*['\"]([A-Za-z][^'\"]{2,})['\"]",
    r"tooltip:\s*['\"]([A-Za-z][^'\"]{2,})['\"]",
    r"message:\s*['\"]([A-Za-z][^'\"]{2,})['\"]",
    r"content:\s*Text\(\s*['\"]([A-Za-z][^'\"]{2,})['\"]",
]

skip_words = {'default', 'center', 'left', 'right', 'start', 'end', 'visible', 'invisible',
              'true', 'false', 'none', 'error', 'warning', 'info', 'Png', 'png', 'jpg',
              'ok', 'Ok', 'OK', 'no', 'yes', 'Unknown', 'null'}

hits = {}
for root, dirs, files in os.walk('flutter/lib'):
    for fn in files:
        if not fn.endswith('.dart'):
            continue
        path = os.path.join(root, fn)
        try:
            text = open(path, encoding='utf-8').read()
        except Exception:
            continue
        for pat in patterns:
            for m in re.finditer(pat, text):
                s = m.group(1).strip()
                # 去掉行内注释
                if '//' in s:
                    s = s.split('//')[0].strip()
                if len(s) < 3:
                    continue
                if s in skip_words:
                    continue
                # 纯英文（含空格/标点）且不含中文字符
                if re.search(r'[\u4e00-\u9fff]', s):
                    continue
                if not re.match(r'^[A-Za-z][A-Za-z0-9 ,.\'!?&/:%+()-]*$', s):
                    continue
                # 排除常见技术串/路径/图标名
                if re.match(r'^[a-z][a-z0-9_-]+$', s):
                    continue
                hits.setdefault(s, set()).add(path)

print("hardcoded english candidates:", len(hits))
for s in sorted(hits):
    files = sorted(hits[s])
    print(f"  {s!r}  <- {files[0]}")
