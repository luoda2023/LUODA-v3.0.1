import re, io, sys
sys.stdout.reconfigure(encoding="utf-8")
data = io.open(r"agent_memory/_emu3.xml", encoding="utf-8").read()
pat = re.compile(r"<node\b([^>]*)>")
for m in pat.finditer(data):
    attrs = m.group(1)
    t = re.search(r'text="([^"]*)"', attrs)
    rid = re.search(r'resource-id="([^"]*)"', attrs)
    b = re.search(r'bounds="([^"]*)"', attrs)
    cl = re.search(r'class="([^"]*)"', attrs)
    if t and t.group(1).strip():
        print(repr(t.group(1)), "|", (rid.group(1) if rid else ""), "|", (b.group(1) if b else ""), "|", (cl.group(1) if cl else "")[-40:])

