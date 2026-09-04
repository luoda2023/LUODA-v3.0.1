import io, re, sys
sys.stdout.reconfigure(encoding="utf-8")
data = io.open(sys.argv[1], encoding="utf-8").read()
for m in re.finditer(r"<node\b([^>]*)>", data):
    attrs = m.group(1)
    cl = re.search(r'class="([^"]*)"', attrs)
    b = re.search(r'bounds="([^"]*)"', attrs)
    cd = re.search(r'content-desc="([^"]*)"', attrs)
    t = re.search(r'text="([^"]*)"', attrs)
    clk = re.search(r'clickable="([^"]*)"', attrs)
    if cl and clk and clk.group(1) == "true":
        label = (t.group(1) if t and t.group(1).strip() else (cd.group(1) if cd else ""))
        print(repr(label)[:70], "|", cl.group(1)[-20:], "|", (b.group(1) if b else ""))
