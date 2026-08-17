import re, os, sys

# 1. 收集 cn.rs 已有 key
cn_keys = set()
with open('src/lang/cn.rs', encoding='utf-8') as f:
    for line in f:
        m = re.match(r'\s*\("(.+?)",\s*"(.+?)"\),', line)
        if m:
            cn_keys.add(m.group(1))

# 2. 收集 Flutter 代码里 translate('...') 的静态 key
flutter_keys = set()
for root, dirs, files in os.walk('flutter/lib'):
    for fn in files:
        if not fn.endswith('.dart'):
            continue
        path = os.path.join(root, fn)
        try:
            text = open(path, encoding='utf-8').read()
        except Exception:
            continue
        for m in re.finditer(r"translate\(\s*['\"](.+?)['\"]\s*\)", text):
            flutter_keys.add(m.group(1))

# 3. 收集 Rust 侧 translate("...")
rust_keys = set()
for root, dirs, files in os.walk('src'):
    for fn in files:
        if not fn.endswith('.rs'):
            continue
        path = os.path.join(root, fn)
        norm = path.replace(os.sep, '/')
        if '/lang/' in norm:
            continue
        try:
            text = open(path, encoding='utf-8').read()
        except Exception:
            continue
        for m in re.finditer(r'translate\(\s*[\'\"](.+?)[\'\"]\s*\)', text):
            rust_keys.add(m.group(1))

all_ui_keys = flutter_keys | rust_keys
missing = sorted(k for k in all_ui_keys
                 if k not in cn_keys and not k.startswith('{') and '{}' not in k and len(k) > 1)
print("UI keys total:", len(all_ui_keys))
print("cn.rs keys:", len(cn_keys))
print("missing from cn.rs:", len(missing))
print()
for k in missing:
    print("  MISSING:", k)
