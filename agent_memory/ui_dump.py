import re, io, sys
sys.stdout.reconfigure(encoding="utf-8")
path = sys.argv[1] if len(sys.argv) > 1 else r"agent_memory/_emu3.xml"
data = io.open(path, encoding="utf-8").read()
pat = re.compile(r"<node\b([^>]*)>")
for m in pat.finditer(data):
    attrs = m.group(1)
    t = re.search(r'text="([^"]*)"', attrs)
    rid = re.search(r'resource-id="([^"]*)"', attrs)
    b = re.search(r'bounds="([^"]*)"', attrs)
    cl = re.search(r'class="([^"]*)"', attrs)
    cd = re.search(r'content-desc="([^"]*)"', attrs)
    has = (t and t.group(1).strip()) or (cd and cd.group(1).strip())
    if has:
        label = (t.group(1) if t and t.group(1).strip() else "") or (cd.group(1) if cd else "")
        print(repr(label), "|", (rid.group(1) if rid else ""), "|", (b.group(1) if b else ""), "|", (cl.group(1) if cl else "")[-30:])
